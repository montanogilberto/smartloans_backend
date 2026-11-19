"""
Core push between the parties of a loan (borrower <-> lender; juridical next).
RFC-014: push via send_azure_push is THE channel for the conversation of a
loan — every step one party takes notifies the other with a fixed template.
WhatsApp/SMS tickets (modules/loanTickets.py) only complement it for people
without the app.

Each push:
  1. resolves the CLIENT id to its app USER id (hub tags are user_{userId};
     a clientId targets an empty tag and the hub still answers 2xx),
  2. is stored with sp_pushNotifications so it shows in "Mis notificaciones",
  3. goes out with send_azure_push (data.navigationRoute for tap deep-linking),
  4. records the delivery for that user (NotificationDeliveries).

Best-effort: callers run it in the background (push_in_background); a failed
push is logged and never changes the response of the flow that triggered it.
Logs carry ids and template names only — never message text or phones.
"""
import asyncio
import json
import logging
import threading

from databases import connection
from modules.azure_notifications import send_azure_push
from modules.pushNotifications import resolve_push_user_ids, _record_delivery

logger = logging.getLogger(__name__)


def _money(amount) -> str:
    try:
        return f"${float(amount):,.2f}"
    except (TypeError, ValueError):
        return "$—"


# template -> (notificationType, title, message, navigationRoute). Formatted with
# the params each caller passes ({amount}, {rate}, {term}, {name}, {loanId}...).
TEMPLATES: dict[str, tuple[str, str, str, str]] = {
    # Borrower asks a lender for a loan.
    "loan_requested": (
        "Info", "📋 Nueva solicitud de {name}",
        "{name} solicita {amount} a una tasa del {rate}% anual a {term} meses. Toca para revisar.",
        "/p2p-lending"),
    # Lender approves the request (non-custodial: the lender funds by SPEI next).
    "loan_approved_borrower": (
        "Success", "✅ ¡Solicitud aprobada!",
        "Tu préstamo de {amount} a {rate}% anual fue aprobado. Te avisaremos cuando el prestamista "
        "declare el fondeo para que confirmes la recepción.",
        "/my-loans"),
    "loan_approved_lender": (
        "Info", "💸 Realiza el fondeo",
        "Aprobaste el préstamo de {amount}. Transfiere desde tu banco a la CLABE del acreditado y "
        "declara la transferencia en la app.",
        "/p2p-lending"),
    "loan_rejected": (
        "Warning", "❌ Solicitud no aprobada",
        "Tu solicitud de {amount} no fue aprobada en este momento. Puedes intentar con otros prestamistas.",
        "/p2p-lending"),
    # Single-cycle negotiation: lender counters, borrower accepts or rejects.
    "loan_countered": (
        "Info", "🔄 Nuevos términos propuestos",
        "El prestamista propone {amount} a {rate}% anual por {term} meses. Revisa y responde.",
        "/p2p-lending"),
    "loan_counter_accepted": (
        "Success", "✅ Términos aceptados",
        "El acreditado aceptó tus nuevos términos ({amount} · {rate}% · {term} m). Apruébalo para fondear.",
        "/p2p-lending"),
    "loan_counter_rejected": (
        "Warning", "❌ Contraoferta rechazada",
        "El acreditado rechazó tus nuevos términos.",
        "/p2p-lending"),
    # Funding (RFC-002): lender declared the SPEI; the borrower must confirm.
    "funding_declared": (
        "Info", "💸 Confirma tu fondeo",
        "Tu prestamista declaró que te transfirió {amount} (préstamo #{loanId}). Revisa tu banco y "
        "confirma en la app si llegó.",
        "/loan-detail/{loanId}"),
    # The AI check of the receipt didn't pass: the borrower should look before confirming.
    "funding_evidence_review": (
        "Warning", "🔎 Revisa el comprobante de fondeo",
        "El comprobante del préstamo de {amount} necesita revisión antes de confirmar la recepción.",
        "/loan-detail/{loanId}"),
}


def render(template: str, **params) -> tuple[str, str, str, str]:
    """(notificationType, title, message, navigationRoute) for a template."""
    kind, title, message, route = TEMPLATES[template]
    values = {k: v for k, v in params.items()}
    if "amount" in values:
        values["amount"] = _money(values["amount"])
    return kind, title.format(**values), message.format(**values), route.format(**values)


async def push_to_client(company_id, client_id, template: str, **params) -> bool:
    """Push one template to one client's app user. True if the hub accepted it."""
    if not client_id:
        return False
    kind, title, message, route = render(template, **params)
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        user_id = resolve_push_user_ids(cursor, [client_id]).get(int(client_id))
        if not user_id:
            logger.info("[loanPush] %s skipped: clientId=%s has no app user", template, client_id)
            return False

        # Inbox row ("Mis notificaciones") — the same SP the app used.
        cursor.execute("EXEC [dbo].[sp_pushNotifications] @pjsonfile = %s", (json.dumps({"pushNotifications": [{
            "action": 1, "companyId": company_id, "title": title, "message": message,
            "notificationType": kind, "priority": "High", "targetType": "User",
            "targetUserId": user_id, "navigationRoute": route,
            "payloadJson": json.dumps({"type": template, "clientId": int(client_id),
                                       **{k: v for k, v in params.items() if k in ("loanId", "proposalId", "fundingTransactionId")}}),
        }]}),))
        row = cursor.fetchone()
        stored = json.loads(row[0]) if row and row[0] else {}
        push_notification_id = int(stored["pushNotificationId"]) if stored.get("pushNotificationId") else None

        result = await send_azure_push(title, message, user_id, data={"navigationRoute": route})
        sent = bool(isinstance(result, dict) and result.get("sent") is True)
        if push_notification_id:
            _record_delivery(cursor, push_notification_id, user_id, sent)
        logger.info("[loanPush] %s -> clientId=%s userId=%s sent=%s", template, client_id, user_id, sent)
        return sent
    except Exception as e:
        logger.error("[loanPush] %s -> clientId=%s failed: %s", template, client_id, e)
        return False
    finally:
        if conn:
            conn.close()


def push_in_background(company_id, client_id, template: str, **params) -> None:
    """Fire-and-forget push for sync or async callers (D7: never inline in the flow)."""
    def run():
        asyncio.run(push_to_client(company_id, client_id, template, **params))
    threading.Thread(target=run, daemon=True).start()
