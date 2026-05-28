from datetime import datetime
import os
from typing import Dict, Any

from azure.storage.blob import BlobServiceClient, ContentSettings


def get_connection_string() -> str:
    return os.getenv("AZURE_STORAGE_CONNECTION_STRING", "")


def get_account_url_fallback() -> str:
    return os.getenv(
        "AZURE_STORAGE_ACCOUNT_URL_FALLBACK",
        "https://imageprofile.blob.core.windows.net"
    )


def get_container_name() -> str:
    return os.getenv("TICKETS_CONTAINER_NAME", "ticketspos")


def _validate_receipt_payload(income_id: int, html: str) -> None:
    if income_id is None:
        raise ValueError("incomeId is required")
    if not isinstance(income_id, int):
        raise ValueError("incomeId must be an integer")
    if income_id <= 0:
        raise ValueError("incomeId must be greater than 0")
    if html is None or not isinstance(html, str) or not html.strip():
        raise ValueError("html is required and must be a non-empty string")


def _blob_service_client() -> BlobServiceClient:
    connection_string = get_connection_string()
    if not connection_string:
        raise RuntimeError(
            "Missing Azure Blob configuration. Set env var: AZURE_STORAGE_CONNECTION_STRING"
        )
    return BlobServiceClient.from_connection_string(connection_string)


def build_receipt_blob_path(income_id: int, file_name: str | None = None, now: datetime | None = None) -> str:
    current = now or datetime.utcnow()
    if file_name and file_name.strip():
        return f"receipts/{current.year}/{current.month:02d}/{file_name.strip()}"
    return f"receipts/{current.year}/{current.month:02d}/receipt_{income_id}.html"


def save_receipt_html(income_id: int, branch_id: int, html: str, file_name: str | None = None) -> Dict[str, Any]:
    _validate_receipt_payload(income_id, html)

    blob_path = build_receipt_blob_path(income_id, file_name=file_name)
    content_settings = ContentSettings(content_type="text/html; charset=utf-8")

    try:
        service_client = _blob_service_client()
        container_name = get_container_name()
        container_client = service_client.get_container_client(container_name)
        blob_client = container_client.get_blob_client(blob_path)

        blob_client.upload_blob(
            html.encode("utf-8"),
            overwrite=True,
            content_settings=content_settings,
            metadata={
                "incomeId": str(income_id),
                "branchId": str(branch_id)
            }
        )

        account_url = getattr(service_client, "url", None) or get_account_url_fallback()
        receipt_url = f"{account_url}/{container_name}/{blob_path}"

        return {
            "success": True,
            "receiptUrl": receipt_url
        }
    except Exception as exc:
        raise RuntimeError(f"Failed to save receipt HTML: {str(exc)}") from exc
