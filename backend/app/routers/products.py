"""
Module: products router
Description: API endpoints for product CRUD and barcode lookup.

Responsibilities:
    - GET /products            → paginated search with filters
    - GET /products/{barcode}  → barcode lookup (primary scan endpoint)
    - POST /products           → create product (admin/manager)
    - PUT /products/{id}       → update product (admin/manager)
    - DELETE /products/{id}    → soft delete (admin only)

Dependencies:
    - app.services.product_service
    - app.repositories.product_repo
    - app.core.dependencies
"""

import math
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_current_user, get_db, require_role
from app.core.exceptions import NotFoundException
from app.models.user import UserModel
from app.repositories.product_repo import product_repo
from app.schemas.product import (
    PaginatedProductResponse,
    ProductCreate,
    ProductResponse,
    ProductUpdate,
)
from app.services import product_service

router = APIRouter(prefix="/api/v1/products", tags=["Products"])


def _product_to_response(product) -> ProductResponse:
    """Convert a ProductModel to ProductResponse, resolving relationships."""
    return ProductResponse(
        id=product.id,
        barcode=product.barcode,
        name=product.name,
        sku=product.sku,
        category_id=product.category_id,
        category_name=product.category.name if product.category else None,
        supplier_id=product.supplier_id,
        supplier_name=product.supplier.name if product.supplier else None,
        unit=product.unit,
        cost_price=float(product.cost_price) if product.cost_price else None,
        sell_price=float(product.sell_price) if product.sell_price else None,
        image_url=product.image_url,
        is_active=product.is_active,
        created_at=product.created_at,
    )


@router.get("", response_model=PaginatedProductResponse)
async def list_products(
    search: str | None = Query(None, description="Search by name, SKU, or barcode"),
    category_id: UUID | None = Query(None),
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> PaginatedProductResponse:
    """
    List products with optional search and category filter.

    Args:
        search: Optional text to match against name, SKU, barcode.
        category_id: Optional category UUID filter.
        page: Page number (1-indexed).
        size: Items per page (max 100).

    Returns:
        Paginated list of ProductResponse.
    """
    products, total = await product_repo.search(db, search, category_id, page, size)
    return PaginatedProductResponse(
        items=[_product_to_response(p) for p in products],
        total=total,
        page=page,
        size=size,
        pages=math.ceil(total / size) if total > 0 else 0,
    )


@router.get("/{barcode}", response_model=ProductResponse)
async def get_product_by_barcode(
    barcode: str,
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> ProductResponse:
    """
    Look up a product by its barcode — called on every scan.

    Args:
        barcode: The barcode string from the scanner.

    Returns:
        ProductResponse if found.

    Raises:
        HTTPException 404: If no product matches the barcode.
    """
    product = await product_repo.get_by_barcode(db, barcode)
    if product is None:
        raise NotFoundException(f"No product found with barcode: {barcode}")
    return _product_to_response(product)


@router.post("", response_model=ProductResponse, status_code=201)
async def create_product(
    body: ProductCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: UserModel = Depends(require_role(["admin", "manager"])),
) -> ProductResponse:
    """
    Create a new product (admin/manager only).

    Args:
        body: ProductCreate with all required fields.

    Returns:
        The created ProductResponse.

    Raises:
        HTTPException 400: If barcode or SKU already exists.
    """
    product = await product_service.create_product(
        db, body, current_user.id, request.client.host if request.client else None
    )
    return _product_to_response(product)


@router.put("/{product_id}", response_model=ProductResponse)
async def update_product(
    product_id: UUID,
    body: ProductUpdate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: UserModel = Depends(require_role(["admin", "manager"])),
) -> ProductResponse:
    """
    Update an existing product (admin/manager only).

    Args:
        product_id: UUID of the product to update.
        body: Partial update data.

    Returns:
        The updated ProductResponse.

    Raises:
        HTTPException 404: If product doesn't exist.
    """
    product = await product_service.update_product(
        db, product_id, body, current_user.id,
        request.client.host if request.client else None,
    )
    return _product_to_response(product)


@router.delete("/{product_id}", response_model=ProductResponse)
async def delete_product(
    product_id: UUID,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: UserModel = Depends(require_role(["admin"])),
) -> ProductResponse:
    """
    Soft-delete a product (admin only) — sets is_active=False.

    Args:
        product_id: UUID of the product to deactivate.

    Returns:
        The deactivated ProductResponse.

    Raises:
        HTTPException 404: If product doesn't exist.
    """
    product = await product_service.soft_delete_product(
        db, product_id, current_user.id,
        request.client.host if request.client else None,
    )
    return _product_to_response(product)
