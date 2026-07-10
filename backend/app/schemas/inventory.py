"""
Module: inventory schemas
Description: Pydantic v2 models for inventory and stock transaction endpoints.

Responsibilities:
    - Validate transaction requests (stock in/out)
    - Validate adjustment requests (subject to threshold routing)
    - Shape inventory response with stock status colours
    - Define Socket.io stock update event payload

Dependencies:
    - pydantic
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class TransactionRequest(BaseModel):
    """
    Request body for POST /inventory/transaction.

    The client must include the known version for optimistic locking.
    If the version has changed since the client last fetched, the
    server responds with HTTP 409 and the client must refresh.
    """
    product_id: UUID
    location_id: UUID
    type: str = Field(..., description="receive | dispatch | adjustment | transfer_in | transfer_out | damage")
    quantity_change: int = Field(..., description="Positive for in, negative for out")
    known_version: int = Field(..., description="Optimistic lock version from last read")
    reference_no: str | None = None
    notes: str | None = None


class AdjustmentRequest(BaseModel):
    """
    Request body for POST /inventory/adjustment.

    If abs(quantity_change) > threshold → routed to pending_adjustments.
    Otherwise applied directly like a normal transaction.
    """
    product_id: UUID
    location_id: UUID
    quantity_change: int
    known_version: int
    notes: str | None = None


class InventoryResponse(BaseModel):
    """Response model for inventory data at a specific location."""
    id: UUID
    product_id: UUID
    product_name: str
    product_barcode: str
    product_sku: str
    location_id: UUID
    location_name: str
    quantity: int
    min_quantity: int
    max_quantity: int | None = None
    version: int
    stock_status: str = Field(description="green | amber | red")
    updated_at: datetime

    model_config = {"from_attributes": True}


class StockUpdateEvent(BaseModel):
    """Payload emitted via Socket.io after a successful stock update."""
    product_id: str
    new_quantity: int
    updated_by: str


class PendingAdjustmentResponse(BaseModel):
    """Response model for a pending adjustment."""
    id: UUID
    product_id: UUID
    product_name: str
    location_id: UUID
    location_name: str
    user_id: UUID
    user_name: str
    quantity_change: int
    notes: str | None = None
    status: str
    reviewed_by: UUID | None = None
    reviewer_name: str | None = None
    reviewed_at: datetime | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class CategoryCreateRequest(BaseModel):
    name: str = Field(..., max_length=100)
    description: str | None = Field(default=None)
    parent_id: UUID | None = Field(default=None)


class LocationCreateRequest(BaseModel):
    name: str = Field(..., max_length=150)
    code: str = Field(..., max_length=50)
    type: str | None = Field(default="warehouse", max_length=50)


