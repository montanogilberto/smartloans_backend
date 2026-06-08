from fastapi import APIRouter, HTTPException, status
from typing import List, Optional
import json

from database import get_connection
from schemas.supplier import SupplierCreate, SupplierResponse, SupplierListResponse

router = APIRouter(prefix="/suppliers", tags=["Supplier"])


@router.post("/", response_model=SupplierResponse, status_code=status.HTTP_201_CREATED)
async def create_supplier(
    supplier: SupplierCreate,
) -> SupplierResponse:
    """Creates a new supplier in the database.

    Args:
        supplier (SupplierCreate): The supplier data to create.

    Returns:
        SupplierResponse: The created supplier's data, including its generated ID and timestamps.

    Raises:
        HTTPException: If there's a database error or the creation fails.
    """
    try:
        with get_connection() as connection:
            cursor = connection.cursor()
            payload = {"action": "INSERT", **supplier.model_dump()}
            cursor.execute("EXEC sp_supplier @pjsonfile=?", json.dumps(payload))
            row = cursor.fetchone()
            if row:
                return SupplierResponse(**json.loads(row[0]))
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to create supplier.")
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.put("/{supplierId}", response_model=SupplierResponse)
async def update_supplier(
    supplierId: int,
    supplier: SupplierCreate,
) -> SupplierResponse:
    """Updates an existing supplier's information.

    Args:
        supplierId (int): The ID of the supplier to update.
        supplier (SupplierCreate): The updated supplier data.

    Returns:
        SupplierResponse: The updated supplier's data.

    Raises:
        HTTPException: If the supplier is not found, or if there's a database error.
    """
    try:
        with get_connection() as connection:
            cursor = connection.cursor()
            payload = {"action": "UPDATE", "supplierId": supplierId, **supplier.model_dump()}
            cursor.execute("EXEC sp_supplier @pjsonfile=?", json.dumps(payload))
            row = cursor.fetchone()
            if row:
                updated_supplier = json.loads(row[0])
                if updated_supplier:
                    return SupplierResponse(**updated_supplier)
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Supplier with ID {supplierId} not found.")
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Supplier with ID {supplierId} not found or no changes made.")
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.delete("/{supplierId}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_supplier(
    supplierId: int,
    companyId: int # Assuming companyId is required for deletion context
):
    """Deletes a supplier from the database.

    Args:
        supplierId (int): The ID of the supplier to delete.
        companyId (int): The ID of the company the supplier belongs to.

    Returns:
        None: Responds with a 204 No Content status on successful deletion.

    Raises:
        HTTPException: If the supplier is not found or if there's a database error.
    """
    try:
        with get_connection() as connection:
            cursor = connection.cursor()
            payload_check_existence = {"action": "GET_ONE", "supplierId": supplierId, "companyId": companyId}
            cursor.execute("EXEC sp_supplier_one @pjsonfile=?", json.dumps(payload_check_existence))
            existing_supplier_row = cursor.fetchone()
            if not existing_supplier_row:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Supplier with ID {supplierId} not found.")
            cursor.nextset() # Clear previous results for the next execution

            # Proceed with deletion if found
            payload = {"action": "DELETE", "supplierId": supplierId, "companyId": companyId}
            cursor.execute("EXEC sp_supplier @pjsonfile=?", json.dumps(payload))

    except HTTPException as he:
        raise he
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.get("/", response_model=SupplierListResponse)
async def get_all_suppliers(companyId: int) -> SupplierListResponse:
    """Retrieves a list of all suppliers for a given company.

    Args:
        companyId (int): The ID of the company to retrieve suppliers for.

    Returns:
        SupplierListResponse: A list of supplier objects.

    Raises:
        HTTPException: If there's a database error or no suppliers are found.
    """
    try:
        with get_connection() as connection:
            cursor = connection.cursor()
            payload = {"companyId": companyId}
            cursor.execute("EXEC sp_supplier_all @pjsonfile=?", json.dumps(payload))
            rows = cursor.fetchone()
            if rows and rows[0]:
                suppliers_data = json.loads(rows[0])
                return SupplierListResponse(suppliers=[
                    SupplierResponse(**supplier) for supplier in suppliers_data
                ])
            return SupplierListResponse(suppliers=[])
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.get("/{supplierId}", response_model=SupplierResponse)
async def get_supplier_by_id(
    supplierId: int,
    companyId: int
) -> SupplierResponse:
    """Retrieves a single supplier by its ID.

    Args:
        supplierId (int): The ID of the supplier to retrieve.
        companyId (int): The ID of the company the supplier belongs to.

    Returns:
        SupplierResponse: The supplier's data.

    Raises:
        HTTPException: If the supplier is not found or if there's a database error.
    """
    try:
        with get_connection() as connection:
            cursor = connection.cursor()
            payload = {"supplierId": supplierId, "companyId": companyId}
            cursor.execute("EXEC sp_supplier_one @pjsonfile=?", json.dumps(payload))
            row = cursor.fetchone()
            if row and row[0]:
                return SupplierResponse(**json.loads(row[0]))
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Supplier with ID {supplierId} not found.")
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
