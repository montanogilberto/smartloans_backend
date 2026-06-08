from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class SupplierBase(BaseModel):
    """Base Pydantic model for Supplier data, containing common fields.

    Attributes:
        companyId (int): The ID of the company this supplier is associated with.
        supplierName (str): The name of the supplier. Max length is 200 characters.
        contactName (Optional[str]): The name of the contact person for the supplier. Max length is 100 characters.
        phone (Optional[str]): The phone number of the supplier. Max length is 20 characters.
        email (Optional[str]): The email address of the supplier. Max length is 100 characters.
        address (Optional[str]): The physical address of the supplier.
        active (str): A flag indicating if the supplier is active ('1') or inactive ('0').
    """
    companyId: int = Field(..., description="The ID of the company this supplier is associated with.")
    supplierName: str = Field(..., max_length=200, description="The name of the supplier.")
    contactName: Optional[str] = Field(None, max_length=100, description="The name of the contact person for the supplier.")
    phone: Optional[str] = Field(None, max_length=20, description="The phone number of the supplier.")
    email: Optional[str] = Field(None, max_length=100, description="The email address of the supplier.")
    address: Optional[str] = Field(None, description="The physical address of the supplier.")
    active: str = Field(..., max_length=1, description="A flag indicating if the supplier is active ('1') or inactive ('0').")


class SupplierCreate(SupplierBase):
    """Pydantic model for creating a new Supplier.

    Inherits from SupplierBase and includes all fields required for creation.
    """
    pass


class SupplierResponse(SupplierBase):
    """Pydantic model for responding with Supplier data, including read-only fields.

    Inherits from SupplierBase and adds supplierId, createdAt, and updatedAt.

    Attributes:
        supplierId (int): The unique identifier of the supplier.
        createdAt (datetime): The timestamp when the supplier record was created.
        updatedAt (Optional[datetime]): The timestamp when the supplier record was last updated.
    """
    supplierId: int = Field(..., description="The unique identifier of the supplier.")
    createdAt: datetime = Field(..., description="The timestamp when the supplier record was created.")
    updatedAt: Optional[datetime] = Field(None, description="The timestamp when the supplier record was last updated.")

    class Config:
        from_attributes = True
