"""
Module: billing schemas
Description: Pydantic v2 schemas for checkout, customer lookup, and invoice endpoints.

Responsibilities:
    - Validate checkout requests (cart items, payment details, discounts)
    - Validate customer lookup requests
    - Shape invoice listing and detail responses
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from app.models.invoice import PaymentMode


class CustomerLookupResponse(BaseModel):
    id: UUID
    name: str
    phone: str | None = None
    credit_limit: float
    overdue_amount: float

    class Config:
        from_attributes = True


class CustomerCreateRequest(BaseModel):
    name: str = Field(..., max_length=150)
    phone: str = Field(..., max_length=50)


class CheckoutItem(BaseModel):
    product_id: UUID
    quantity: int = Field(..., gt=0, description="Quantity must be greater than zero")
    known_version: int = Field(..., description="Optimistic lock version for this product in inventory")
    unit_price: float | None = Field(default=None, description="Custom unit price override")
    tax_rate: float | None = Field(default=None, description="Custom tax rate override")
    discount_amount: float = Field(default=0.0, ge=0.0, description="Line item discount amount")


class CheckoutRequest(BaseModel):
    location_id: UUID
    payment_mode: PaymentMode = Field(default=PaymentMode.cash)
    discount_amount: float = Field(default=0.0, ge=0.0, description="Bill-level discount")
    amount_paid: float | None = Field(default=None, ge=0.0)
    notes: str | None = Field(default=None, max_length=500)
    customer_name: str | None = Field(default=None, max_length=150)
    customer_phone: str | None = Field(default=None, max_length=50)
    items: list[CheckoutItem] = Field(..., min_items=1, description="Cart must contain at least one item")


class InvoiceItemResponse(BaseModel):
    id: UUID
    product_id: UUID
    product_name: str = Field(..., description="Name of the product")
    product_barcode: str = Field(..., description="Barcode of the product")
    quantity: int
    unit_price: float
    cost_price: float | None = None
    tax_rate: float
    tax_amount: float
    line_total: float

    class Config:
        from_attributes = True

    @field_validator("product_name", mode="before")
    @classmethod
    def get_product_name(cls, v, info):
        # Handle ORM relationship field extraction
        if hasattr(info, "context") and info.context:
            pass
        return v

class InvoiceResponse(BaseModel):
    id: UUID
    invoice_number: str
    location_id: UUID
    location_name: str
    user_id: UUID
    user_name: str
    customer_id: UUID | None = None
    customer_name: str | None = None
    customer_phone: str | None = None
    subtotal: float
    tax_amount: float
    discount_amount: float
    total_amount: float
    amount_paid: float
    amount_due: float
    payment_mode: PaymentMode
    notes: str | None = None
    created_at: datetime
    items: list[InvoiceItemResponse]

    class Config:
        from_attributes = True


class InvoiceSummaryItem(BaseModel):
    id: UUID
    invoice_number: str
    location_name: str
    user_name: str
    customer_name: str | None = None
    customer_phone: str | None = None
    subtotal: float
    tax_amount: float
    discount_amount: float
    total_amount: float
    amount_paid: float
    amount_due: float
    payment_mode: PaymentMode
    created_at: datetime

    class Config:
        from_attributes = True


class SalesSummaryResponse(BaseModel):
    total_sales_today: int
    revenue_today: float
    profit_today: float
