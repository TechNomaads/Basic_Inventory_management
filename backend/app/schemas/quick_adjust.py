"""
Module: quick_adjust schemas
Description: Pydantic schemas for the inventory quick-adjust endpoint.

Used by the scanner's Inventory mode to rapidly adjust stock
quantities without a full stock transaction form.
"""

from pydantic import BaseModel, Field
from uuid import UUID


class QuickAdjustRequest(BaseModel):
    """Request body for POST /api/v1/inventory/quick-adjust."""

    barcode: str = Field(..., description="Product barcode scanned by the device")
    location_id: UUID = Field(..., description="Store location UUID")
    adjustment: int = Field(
        ...,
        description="Stock adjustment: positive to add, negative to subtract",
    )
    reason: str = Field(
        default="Scanner quick-adjust",
        description="Reason for the stock adjustment",
    )


class QuickAdjustResponse(BaseModel):
    """Response body for a successful quick-adjust."""

    product_id: UUID
    product_name: str
    barcode: str
    new_quantity: int
    new_version: int
