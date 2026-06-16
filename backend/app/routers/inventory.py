"""
Module: inventory router
Description: API endpoints for inventory operations and stock transactions.

Responsibilities:
    - GET /inventory/{location_id}   → list inventory for a location
    - POST /inventory/transaction    → process stock in/out
    - POST /inventory/adjustment     → process adjustment (threshold routing)

Dependencies:
    - app.services.inventory_service
    - app.repositories.inventory_repo
    - app.core.dependencies
"""

from uuid import UUID

from fastapi import APIRouter, Depends, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_current_user, get_db
from app.models.user import UserModel
from app.models.location import LocationModel
from app.models.category import CategoryModel
from app.models.supplier import SupplierModel
from app.repositories.inventory_repo import inventory_repo
from app.schemas.inventory import (
    AdjustmentRequest,
    InventoryResponse,
    TransactionRequest,
)
from app.services import inventory_service

router = APIRouter(prefix="/api/v1/inventory", tags=["Inventory"])


def _determine_stock_status(quantity: int, min_quantity: int) -> str:
    """
    Determine the stock status colour based on quantity vs threshold.

    Returns:
        "green" (ok), "amber" (low), or "red" (critical/out).
    """
    if quantity <= 0:
        return "red"
    if min_quantity > 0 and quantity < min_quantity:
        return "amber"
    return "green"


@router.get("/{location_id}", response_model=list[InventoryResponse])
async def list_inventory_by_location(
    location_id: UUID,
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> list[InventoryResponse]:
    """
    List all inventory items at a specific location.

    Args:
        location_id: UUID of the location.

    Returns:
        List of InventoryResponse with stock status colours.
    """
    items = await inventory_repo.list_by_location(db, location_id)
    return [
        InventoryResponse(
            id=inv.id,
            product_id=inv.product_id,
            product_name=inv.product.name if inv.product else "Unknown",
            product_barcode=inv.product.barcode if inv.product else "",
            product_sku=inv.product.sku if inv.product else "",
            location_id=inv.location_id,
            location_name=inv.location.name if inv.location else "Unknown",
            quantity=inv.quantity,
            min_quantity=inv.min_quantity,
            max_quantity=inv.max_quantity,
            version=inv.version,
            stock_status=_determine_stock_status(inv.quantity, inv.min_quantity),
            updated_at=inv.updated_at,
        )
        for inv in items
    ]


@router.post("/transaction")
async def create_transaction(
    body: TransactionRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: UserModel = Depends(get_current_user),
) -> dict:
    """
    Process a stock transaction with optimistic locking.

    The client must send the known version. If it conflicts,
    the server responds with HTTP 409.

    Args:
        body: TransactionRequest with product, location, delta, version.

    Returns:
        Confirmation dict with transaction ID.

    Raises:
        HTTPException 404: If inventory record not found.
        HTTPException 409: On optimistic lock version conflict.
    """
    tx = await inventory_service.process_transaction(
        db, body, current_user.id,
        request.client.host if request.client else None,
    )
    return {
        "message": "Transaction recorded successfully",
        "transaction_id": str(tx.id),
        "quantity_after": tx.quantity_after,
    }


@router.post("/adjustment")
async def create_adjustment(
    body: AdjustmentRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: UserModel = Depends(get_current_user),
) -> dict:
    """
    Process a stock adjustment.

    If abs(quantity_change) <= threshold → apply directly.
    If abs(quantity_change) > threshold → route to pending queue.

    Args:
        body: AdjustmentRequest with product, location, delta, version.

    Returns:
        Dict with status ("applied" or "pending").
    """
    return await inventory_service.process_adjustment(
        db, body, current_user.id,
        request.client.host if request.client else None,
    )


@router.get("/meta/locations", response_model=list[dict])
async def list_locations(
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> list[dict]:
    """List all locations in the database."""
    result = await db.execute(select(LocationModel))
    locations = result.scalars().all()
    return [{"id": str(loc.id), "name": loc.name, "code": loc.code, "type": loc.type} for loc in locations]


@router.get("/meta/categories", response_model=list[dict])
async def list_categories(
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> list[dict]:
    """List all categories in the database."""
    result = await db.execute(select(CategoryModel))
    categories = result.scalars().all()
    return [{"id": str(cat.id), "name": cat.name, "description": cat.description} for cat in categories]


@router.get("/meta/suppliers", response_model=list[dict])
async def list_suppliers(
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> list[dict]:
    """List all suppliers in the database."""
    result = await db.execute(select(SupplierModel))
    suppliers = result.scalars().all()
    return [{"id": str(sup.id), "name": sup.name, "contact_name": sup.contact_name} for sup in suppliers]
