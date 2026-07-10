"""
Module: billing router
Description: API endpoints for customer checkout, invoices query, and receipt rendering.

Responsibilities:
    - POST /api/v1/billing/checkout         → process customer sales cart atomically
    - GET /api/v1/billing/invoices         → filter and page invoice logs
    - GET /api/v1/billing/invoices/{id}    → get full invoice details
    - GET /api/v1/billing/invoices/{id}/receipt → render HTML thermal receipt layout
    - GET /api/v1/billing/customers/lookup → look up customer by phone number
"""

import uuid
from datetime import datetime
from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import HTMLResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_current_user, get_db
from app.core.exceptions import NotFoundException
from app.models.customer import CustomerModel
from app.models.user import UserModel
from app.schemas.billing import (
    CheckoutRequest,
    InvoiceResponse,
    InvoiceSummaryItem,
    CustomerLookupResponse,
    SalesSummaryResponse,
    InvoiceUpdateRequest,
)
from app.services import billing_service

router = APIRouter(prefix="/api/v1/billing", tags=["Billing"])


@router.post("/checkout", response_model=InvoiceResponse, status_code=201)
async def checkout(
    request: Request,
    data: CheckoutRequest,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(get_current_user),
) -> InvoiceResponse:
    """
    Process a checkout sale transaction.
    Stock is decremented per item with optimistic concurrency control.
    """
    ip_address = request.client.host if request.client else None
    invoice = await billing_service.process_checkout(
        db=db, data=data, user_id=user.id, ip_address=ip_address
    )
    return invoice


@router.get("/invoices", response_model=list[InvoiceSummaryItem])
async def list_invoices(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    location_id: uuid.UUID | None = Query(None),
    payment_mode: str | None = Query(None),
    start_date: datetime | None = Query(None),
    end_date: datetime | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> list[InvoiceSummaryItem]:
    """
    Retrieve and filter invoice history records.
    """
    invoices, _ = await billing_service.list_invoices(
        db=db,
        skip=skip,
        limit=limit,
        location_id=location_id,
        payment_mode=payment_mode,
        start_date=start_date,
        end_date=end_date,
    )
    return invoices


@router.get("/invoices/{id}", response_model=InvoiceResponse)
async def get_invoice(
    id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> InvoiceResponse:
    """
    Retrieve complete details of a single invoice, including line items.
    """
    invoice = await billing_service.get_invoice_detail(db, id)
    if not invoice:
        raise NotFoundException(f"Invoice with ID {id} not found")
    return invoice


@router.get("/invoices/{id}/receipt", response_class=HTMLResponse)
async def get_receipt(
    id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> HTMLResponse:
    """
    Render a printable, monospaced HTML receipt for thermal paper rolls (58mm/80mm).
    Does not require JWT auth to allow easy printing links and popups.
    """
    invoice = await billing_service.get_invoice_detail(db, id)
    if not invoice:
        raise NotFoundException(f"Invoice with ID {id} not found")
    
    html_content = billing_service.generate_thermal_receipt_html(invoice)
    return HTMLResponse(content=html_content, status_code=200)


@router.get("/customers/lookup", response_model=CustomerLookupResponse)
async def lookup_customer(
    phone: str = Query(..., description="Phone number to lookup"),
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> CustomerLookupResponse:
    """
    Check if a customer profile exists for the given phone number.
    """
    stmt = select(CustomerModel).where(CustomerModel.phone == phone.strip())
    res = await db.execute(stmt)
    customer = res.scalar_one_or_none()
    
    if not customer:
        raise NotFoundException(f"Customer with phone {phone} not found")
        
    return customer


@router.get("/daily-summary", response_model=SalesSummaryResponse)
async def get_daily_summary(
    location_id: uuid.UUID | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> SalesSummaryResponse:
    """
    Get daily counts of sales, revenue, and gross profit.
    """
    summary = await billing_service.get_daily_sales_summary(db, location_id)
    return SalesSummaryResponse(
        total_sales_today=summary["total_sales_today"],
        revenue_today=summary["revenue_today"],
        profit_today=summary["profit_today"]
    )


@router.put("/invoices/{id}", response_model=InvoiceResponse)
async def update_invoice(
    id: uuid.UUID,
    request: Request,
    data: InvoiceUpdateRequest,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(get_current_user),
) -> InvoiceResponse:
    """
    Update details of an existing invoice (customer name/phone, payment mode, discount, notes).
    Adjusts the customer's overdue balance if applicable.
    """
    ip_address = request.client.host if request.client else None
    invoice = await billing_service.update_invoice(
        db=db, invoice_id=id, data=data, user_id=user.id, ip_address=ip_address
    )
    return invoice

