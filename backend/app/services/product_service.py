"""
Module: product_service
Description: Business logic for product CRUD operations.

Responsibilities:
    - Create, update, and soft-delete products
    - Write audit log entries for all mutations
    - Barcode lookup for scanner

Dependencies:
    - app.repositories.product_repo
    - app.services.audit_service
"""

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import BadRequestException, NotFoundException
from app.models.audit_log import AuditAction
from app.models.product import ProductModel
from app.repositories.product_repo import product_repo
from app.schemas.product import ProductCreate, ProductUpdate
from app.services.audit_service import write_audit_log


async def create_product(
    db: AsyncSession,
    data: ProductCreate,
    user_id: UUID,
    ip_address: str | None = None,
) -> ProductModel:
    """
    Create a new product and log the action.

    Args:
        db: Async database session.
        data: Validated product creation data.
        user_id: UUID of the user creating the product.
        ip_address: Client IP for audit logging.

    Returns:
        The created ProductModel.

    Raises:
        BadRequestException: If barcode or SKU already exists.
    """
    # Check for duplicate barcode
    existing = await product_repo.get_by_barcode(db, data.barcode)
    if existing:
        raise BadRequestException(f"Barcode '{data.barcode}' already exists")

    product = ProductModel(**data.model_dump())
    product = await product_repo.create(db, product)

    # Audit log
    await write_audit_log(
        db=db,
        user_id=user_id,
        table_name="products",
        record_id=product.id,
        action=AuditAction.insert,
        new_values=data.model_dump(mode="json"),
        ip_address=ip_address,
    )

    return product


async def update_product(
    db: AsyncSession,
    product_id: UUID,
    data: ProductUpdate,
    user_id: UUID,
    ip_address: str | None = None,
) -> ProductModel:
    """
    Update an existing product and log the changes.

    Args:
        db: Async database session.
        product_id: UUID of the product to update.
        data: Validated update data (partial).
        user_id: UUID of the user making the change.
        ip_address: Client IP for audit logging.

    Returns:
        The updated ProductModel.

    Raises:
        NotFoundException: If the product doesn't exist.
    """
    product = await product_repo.get_by_id(db, product_id)
    if product is None:
        raise NotFoundException("Product not found")

    old_values = {
        "name": product.name,
        "sku": product.sku,
        "barcode": product.barcode,
        "category_id": str(product.category_id) if product.category_id else None,
        "supplier_id": str(product.supplier_id) if product.supplier_id else None,
        "unit": product.unit,
        "cost_price": float(product.cost_price) if product.cost_price else None,
        "sell_price": float(product.sell_price) if product.sell_price else None,
        "is_active": product.is_active,
    }

    # Apply updates
    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(product, field, value)

    product = await product_repo.update(db, product)

    # Audit log
    await write_audit_log(
        db=db,
        user_id=user_id,
        table_name="products",
        record_id=product.id,
        action=AuditAction.update,
        old_values=old_values,
        new_values=update_data,
        ip_address=ip_address,
    )

    return product


async def soft_delete_product(
    db: AsyncSession,
    product_id: UUID,
    user_id: UUID,
    ip_address: str | None = None,
) -> ProductModel:
    """
    Soft-delete a product by setting is_active=False.

    Args:
        db: Async database session.
        product_id: UUID of the product to deactivate.
        user_id: UUID of the admin performing the action.
        ip_address: Client IP for audit logging.

    Returns:
        The deactivated ProductModel.

    Raises:
        NotFoundException: If the product doesn't exist.
    """
    product = await product_repo.get_by_id(db, product_id)
    if product is None:
        raise NotFoundException("Product not found")

    product.is_active = False
    product = await product_repo.update(db, product)

    # Audit log
    await write_audit_log(
        db=db,
        user_id=user_id,
        table_name="products",
        record_id=product.id,
        action=AuditAction.delete,
        old_values={"is_active": True},
        new_values={"is_active": False},
        ip_address=ip_address,
    )

    return product
