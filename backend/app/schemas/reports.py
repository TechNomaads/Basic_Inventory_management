"""
Module: reports schemas
Description: Pydantic v2 models for reporting endpoints.

Responsibilities:
    - Shape dashboard summary response
    - Shape transaction history items with filtering metadata

Dependencies:
    - pydantic
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class SummaryResponse(BaseModel):
    """Dashboard summary metrics."""
    total_products: int = Field(description="Count of active products")
    low_stock_count: int = Field(description="Products below min_quantity")
    todays_scans: int = Field(description="Transactions created today")
    pending_adjustments: int = Field(description="Adjustments awaiting approval")
    total_dispatched: int = Field(description="Total dispatch transactions in period")
    total_received: int = Field(description="Total receive transactions in period")
    out_of_stock_count: int = Field(description="Products with zero stock")
    active_users: int = Field(description="Users who logged in during period")


class TransactionHistoryItem(BaseModel):
    """A single transaction in the history list."""
    id: UUID
    product_id: UUID
    product_name: str
    product_barcode: str
    location_id: UUID
    location_name: str
    user_id: UUID
    user_name: str
    type: str
    quantity_change: int
    quantity_before: int
    quantity_after: int
    reference_no: str | None = None
    notes: str | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class PaginatedTransactionResponse(BaseModel):
    """Paginated list of transaction history items."""
    items: list[TransactionHistoryItem]
    total: int
    page: int
    size: int
    pages: int
