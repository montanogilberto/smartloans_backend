from models.supplier import SupplierCreate, SupplierResponse
from typing import List


class SupplierListResponse(BaseModel):
    """Pydantic model for a list of SupplierResponse objects.

    Attributes:
        suppliers (List[SupplierResponse]): A list of supplier objects.
    """
    suppliers: List[SupplierResponse]


__all__ = ["SupplierCreate", "SupplierResponse", "SupplierListResponse"]
