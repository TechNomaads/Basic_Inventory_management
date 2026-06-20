from datetime import datetime
from uuid import UUID
from pydantic import BaseModel, Field
from app.schemas.billing import InvoiceSummaryItem

class CustomerResponse(BaseModel):
    id: UUID
    name: str
    phone: str | None = None
    credit_limit: float
    overdue_amount: float
    created_at: datetime

    class Config:
        from_attributes = True

class CustomerCreateRequest(BaseModel):
    name: str = Field(..., max_length=150)
    phone: str | None = Field(default=None, max_length=50)
    credit_limit: float | None = Field(default=10000.00, ge=0.0)
    overdue_amount: float | None = Field(default=0.00)

class CustomerUpdateRequest(BaseModel):
    name: str | None = Field(default=None, max_length=150)
    phone: str | None = Field(default=None, max_length=50)
    credit_limit: float | None = Field(default=None, ge=0.0)
    overdue_amount: float | None = Field(default=None)

class CustomerDetailResponse(CustomerResponse):
    invoices: list[InvoiceSummaryItem] = []

class PaginatedCustomerResponse(BaseModel):
    items: list[CustomerResponse]
    total: int
    page: int
    size: int
    pages: int
