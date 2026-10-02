"""
Customer receipt links — /recibo/{companyId}-{incomeId}-{signature}.

The link is what the customer gets (WhatsApp / SMS / push). It never exposes
the blob: the route checks the signature, then redirects to a read-only SAS
URL that expires in SAS_MINUTES, so it keeps working once the 'ticketspos'
container is private, and a forwarded blob URL dies on its own.

Stateless on purpose: the signature is an HMAC over (companyId, incomeId)
with RECEIPT_LINK_SECRET, so no table stores tokens and nobody can build a
valid link by counting income IDs. No secret configured → no links are
issued and every link is rejected (fails closed).

Env vars:
  RECEIPT_LINK_SECRET   long random string; rotating it invalidates every link
  BACKEND_PUBLIC_URL    default https://smartloansbackend.azurewebsites.net
"""

import base64
import hashlib
import hmac
import html
import logging
import os
import re
from datetime import datetime, timedelta, timezone
from urllib.parse import unquote, urlparse

from azure.storage.blob import BlobSasPermissions, generate_blob_sas

from modules.ticket_receipts import _blob_service_client

logger = logging.getLogger(__name__)

SAS_MINUTES = 15
_TOKEN_RE = re.compile(r"^(\d+)-(\d+)-([A-Za-z0-9_-]{22})$")


def _secret() -> bytes:
    return os.getenv("RECEIPT_LINK_SECRET", "").encode()


def _signature(company_id: int, income_id: int) -> str:
    digest = hmac.new(_secret(), f"receipt:{company_id}:{income_id}".encode(), hashlib.sha256).digest()
    return base64.urlsafe_b64encode(digest).decode()[:22]


def receipt_link(company_id: int, income_id: int) -> str | None:
    """The customer-facing link for this sale, or None if links are not configured."""
    if not _secret():
        logger.warning("[receiptLinks] RECEIPT_LINK_SECRET not set — no receipt link issued")
        return None
    base = os.getenv("BACKEND_PUBLIC_URL", "https://smartloansbackend.azurewebsites.net").rstrip("/")
    return f"{base}/recibo/{int(company_id)}-{int(income_id)}-{_signature(int(company_id), int(income_id))}"


def verify_token(token: str) -> tuple[int, int] | None:
    """(companyId, incomeId) for a genuine token, else None."""
    if not _secret():
        return None
    match = _TOKEN_RE.match(token or "")
    if not match:
        return None
    company_id, income_id = int(match.group(1)), int(match.group(2))
    if not hmac.compare_digest(match.group(3), _signature(company_id, income_id)):
        return None
    return company_id, income_id


def sas_url(receipt_url: str) -> str:
    """Read-only, short-lived URL for a stored receipt blob URL
    ({account}/{container}/{blob path})."""
    path = unquote(urlparse(receipt_url).path).lstrip("/")
    container, _, blob_path = path.partition("/")
    if not container or not blob_path:
        raise ValueError(f"Not a blob URL: {receipt_url}")
    service = _blob_service_client()
    token = generate_blob_sas(
        account_name=service.account_name,
        container_name=container,
        blob_name=blob_path,
        account_key=service.credential.account_key,
        permission=BlobSasPermissions(read=True),
        expiry=datetime.now(timezone.utc) + timedelta(minutes=SAS_MINUTES),
    )
    return f"{service.url.rstrip('/')}/{container}/{blob_path}?{token}"


def summary_page(income_id: int, total: float | None, discount: float | None) -> str:
    """Shown while the detailed receipt isn't uploaded yet (it is generated
    when the cashier prints the ticket)."""
    rows = [f"<p>Folio: <strong>{income_id}</strong></p>"]
    if isinstance(total, (int, float)):
        rows.append(f"<p>Total: <strong>${total:,.2f} MXN</strong></p>")
    if isinstance(discount, (int, float)) and discount > 0:
        rows.append(f"<p>Descuento aplicado: -${discount:,.2f} MXN</p>")
    body = "\n".join(rows)
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Tu compra</title>
<style>body{{font-family:system-ui,sans-serif;max-width:420px;margin:40px auto;padding:0 16px;color:#222}}
h1{{font-size:20px}}p{{font-size:16px;margin:8px 0}}.note{{color:#666;font-size:14px;margin-top:24px}}</style>
</head><body>
<h1>Gracias por tu compra</h1>
{body}
<p class="note">{html.escape("El recibo detallado estará disponible en cuanto se imprima tu ticket.")}</p>
</body></html>"""
