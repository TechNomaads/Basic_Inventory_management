"""
Module: product schemas
Description: Pydantic v2 models for product endpoints.

Responsibilities:
    - Validate product creation and update payloads
    - Shape product response including category and supplier names
    - Provide barcode lookup response

Dependencies:
    - pydantic
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class ProductCreate(BaseModel):
    """Request body for POST /products."""
    barcode: str = Field(..., max_length=100, description="Unique barcode for scanning")
    name: str = Field(..., max_length=200)
    sku: str = Field(..., max_length=100, description="Unique stock-keeping unit code")
    category_id: UUID | None = None
    supplier_id: UUID | None = None
    unit: str = Field(default="pcs", max_length=30)
    cost_price: float | None = None
    sell_price: float | None = None
    image_url: str | None = None


class ProductUpdate(BaseModel):
    """Request body for PUT /products/{id}."""
    name: str | None = Field(None, max_length=200)
    sku: str | None = Field(None, max_length=100)
    barcode: str | None = Field(None, max_length=100)
    category_id: UUID | None = None
    supplier_id: UUID | None = None
    unit: str | None = Field(None, max_length=30)
    cost_price: float | None = None
    sell_price: float | None = None
    image_url: str | None = None
    is_active: bool | None = None


class ProductResponse(BaseModel):
    """Response model for product data."""
    id: UUID
    barcode: str
    name: str
    sku: str
    category_id: UUID | None = None
    category_name: str | None = None
    supplier_id: UUID | None = None
    supplier_name: str | None = None
    unit: str
    cost_price: float | None = None
    sell_price: float | None = None
    image_url: str | None = None
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class PaginatedProductResponse(BaseModel):
    """Paginated list of products."""
    items: list[ProductResponse]
    total: int
    page: int
    size: int
    pages: int
