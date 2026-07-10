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
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_current_user, get_db
from app.models.user import UserModel
from app.models.location import LocationModel
from app.models.category import CategoryModel
from app.models.supplier import SupplierModel
from app.models.product import ProductModel
from app.models.inventory import InventoryModel
from app.repositories.inventory_repo import inventory_repo
from app.schemas.inventory import (
    AdjustmentRequest,
    InventoryResponse,
    TransactionRequest,
    CategoryCreateRequest,
    LocationCreateRequest,
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


@router.post("/meta/categories", status_code=201)
async def create_category(
    body: CategoryCreateRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(get_current_user),
):
    """Create a new category in the database."""
    category = CategoryModel(
        name=body.name.strip(),
        description=body.description.strip() if body.description else None,
        parent_id=body.parent_id
    )
    db.add(category)
    await db.flush()
    
    # Audit log
    from app.models.audit_log import AuditAction
    from app.services.audit_service import write_audit_log
    await write_audit_log(
        db=db,
        user_id=user.id,
        table_name="categories",
        record_id=category.id,
        action=AuditAction.insert,
        new_values={"name": category.name, "description": category.description},
        ip_address=request.client.host if request.client else None
    )
    await db.commit()
    return {"id": str(category.id), "name": category.name, "description": category.description}


@router.delete("/meta/categories/{id}", status_code=204)
async def delete_category(
    id: UUID,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(get_current_user),
):
    """Delete a category from the database."""
    stmt = select(CategoryModel).where(CategoryModel.id == id)
    res = await db.execute(stmt)
    category = res.scalar_one_or_none()
    if not category:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail=f"Category with ID {id} not found")
        
    old_values = {"name": category.name, "description": category.description}
    
    # Set parent_id of subcategories to None
    await db.execute(
        update(CategoryModel)
        .where(CategoryModel.parent_id == id)
        .values(parent_id=None)
    )
    # Set category_id of products to None
    await db.execute(
        update(ProductModel)
        .where(ProductModel.category_id == id)
        .values(category_id=None)
    )
    
    await db.delete(category)
    await db.flush()
    
    # Audit log
    from app.models.audit_log import AuditAction
    from app.services.audit_service import write_audit_log
    await write_audit_log(
        db=db,
        user_id=user.id,
        table_name="categories",
        record_id=id,
        action=AuditAction.delete,
        old_values=old_values,
        ip_address=request.client.host if request.client else None
    )
    await db.commit()
    return None


@router.get("/meta/suppliers", response_model=list[dict])
async def list_suppliers(
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> list[dict]:
    """List all suppliers in the database."""
    result = await db.execute(select(SupplierModel))
    suppliers = result.scalars().all()
    return [{"id": str(sup.id), "name": sup.name, "contact_name": sup.contact_name} for sup in suppliers]


@router.post("/meta/locations", status_code=201)
async def create_location(
    body: LocationCreateRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(get_current_user),
):
    """Create a new location (warehouse/store) in the database."""
    # Check code uniqueness
    existing_stmt = select(LocationModel).where(LocationModel.code == body.code.strip())
    existing_res = await db.execute(existing_stmt)
    if existing_res.scalar_one_or_none():
        from fastapi import HTTPException
        raise HTTPException(status_code=400, detail=f"Location with code '{body.code}' already exists")

    location = LocationModel(
        name=body.name.strip(),
        code=body.code.strip(),
        type=body.type.strip() if body.type else "warehouse"
    )
    db.add(location)
    await db.flush()

    # Seed initial inventory as 0 for all existing products at this new location
    products_res = await db.execute(select(ProductModel))
    products = products_res.scalars().all()
    for prod in products:
        db.add(InventoryModel(
            product_id=prod.id,
            location_id=location.id,
            quantity=0,
            min_quantity=0,
            max_quantity=None,
            version=0
        ))
    await db.flush()

    # Audit log
    from app.models.audit_log import AuditAction
    from app.services.audit_service import write_audit_log
    await write_audit_log(
        db=db,
        user_id=user.id,
        table_name="locations",
        record_id=location.id,
        action=AuditAction.insert,
        new_values={"name": location.name, "code": location.code, "type": location.type},
        ip_address=request.client.host if request.client else None
    )
    await db.commit()
    return {"id": str(location.id), "name": location.name, "code": location.code, "type": location.type}


@router.delete("/meta/locations/{id}", status_code=204)
async def delete_location(
    id: UUID,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(get_current_user),
):
    """Delete a location from the database after running safety checks."""
    stmt = select(LocationModel).where(LocationModel.id == id)
    res = await db.execute(stmt)
    location = res.scalar_one_or_none()
    if not location:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail=f"Location with ID {id} not found")

    # 1. Check for historic invoices
    from app.models.invoice import InvoiceModel
    invoice_stmt = select(InvoiceModel).where(InvoiceModel.location_id == id).limit(1)
    invoice_res = await db.execute(invoice_stmt)
    if invoice_res.scalar_one_or_none():
        from fastapi import HTTPException
        raise HTTPException(
            status_code=400,
            detail="Cannot delete location: historic invoice transactions exist at this location. Please rename it or mark it inactive instead."
        )

    # 2. Check for active stock items (> 0 qty)
    from app.models.inventory import InventoryModel
    stock_stmt = select(InventoryModel).where(InventoryModel.location_id == id, InventoryModel.quantity > 0).limit(1)
    stock_res = await db.execute(stock_stmt)
    if stock_res.scalar_one_or_none():
        from fastapi import HTTPException
        raise HTTPException(
            status_code=400,
            detail="Cannot delete location: it still has products in stock. Please transfer or adjust the quantities to 0 first."
        )

    old_values = {"name": location.name, "code": location.code, "type": location.type}

    # 3. Clean up the 0 qty inventory records at this location first
    from sqlalchemy import delete
    await db.execute(delete(InventoryModel).where(InventoryModel.location_id == id))
    
    # 4. Delete the location
    await db.delete(location)
    await db.flush()

    # Audit log
    from app.models.audit_log import AuditAction
    from app.services.audit_service import write_audit_log
    await write_audit_log(
        db=db,
        user_id=user.id,
        table_name="locations",
        record_id=id,
        action=AuditAction.delete,
        old_values=old_values,
        ip_address=request.client.host if request.client else None
    )
    await db.commit()
    return None

