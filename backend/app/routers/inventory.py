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
from app.schemas.quick_adjust import QuickAdjustRequest
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


@router.post("/quick-adjust")
async def quick_adjust(
    body: QuickAdjustRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: UserModel = Depends(get_current_user),
) -> dict:
    """
    Rapid stock adjustment from the mobile scanner's Inventory mode.

    Looks up a product by barcode, validates the adjustment won't
    go negative, applies it with optimistic locking, and records
    a stock transaction.

    Args:
        body: QuickAdjustRequest with barcode, location_id, adjustment, reason.

    Returns:
        Dict with product_id, product_name, barcode, new_quantity, new_version.

    Raises:
        HTTPException 404: If product or inventory record not found.
        HTTPException 400: If adjustment would result in negative stock.
    """
    from fastapi import HTTPException
    from app.models.product import ProductModel
    from app.models.inventory import InventoryModel
    from app.models.stock_transaction import StockTransactionModel

    # 1. Look up product by barcode
    product_result = await db.execute(
        select(ProductModel).where(ProductModel.barcode == body.barcode)
    )
    product = product_result.scalar_one_or_none()
    if product is None:
        raise HTTPException(status_code=404, detail=f"No product found with barcode: {body.barcode}")

    # 2. Look up inventory at the specified location
    inv_result = await db.execute(
        select(InventoryModel).where(
            InventoryModel.product_id == product.id,
            InventoryModel.location_id == body.location_id,
        )
    )
    inventory = inv_result.scalar_one_or_none()
    if inventory is None:
        raise HTTPException(
            status_code=404,
            detail=f"No inventory record for '{product.name}' at this location.",
        )

    # 3. Validate: removal must not go negative
    new_qty = inventory.quantity + body.adjustment
    if new_qty < 0:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot adjust by {body.adjustment}. Current stock: {inventory.quantity}.",
        )

    # 4. Apply with version increment (optimistic locking)
    inventory.quantity = new_qty
    inventory.version += 1

    # 5. Record stock transaction
    tx_type = "receipt" if body.adjustment > 0 else "dispatch"
    tx = StockTransactionModel(
        product_id=product.id,
        location_id=body.location_id,
        user_id=current_user.id,
        transaction_type=tx_type,
        quantity_change=body.adjustment,
        quantity_after=new_qty,
        reference=body.reason,
        ip_address=request.client.host if request.client else None,
    )
    db.add(tx)
    await db.commit()

    return {
        "product_id": str(product.id),
        "product_name": product.name,
        "barcode": product.barcode,
        "new_quantity": new_qty,
        "new_version": inventory.version,
    }


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
