"""
Module: reports router
Description: API endpoints for dashboard summaries and transaction history.

Responsibilities:
    - GET /reports/summary       → aggregated dashboard metrics
    - GET /reports/transactions  → filtered, paginated transaction history

Dependencies:
    - app.services.report_service
    - app.repositories.transaction_repo
    - app.core.dependencies
"""

import math
from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_current_user, get_db
from app.models.user import UserModel
from app.repositories.transaction_repo import transaction_repo
from app.schemas.reports import (
    PaginatedTransactionResponse,
    SummaryResponse,
    TransactionHistoryItem,
)
from app.schemas.analytics import SalesTrendItem, CategoryStockItem
from app.services import report_service

router = APIRouter(prefix="/api/v1/reports", tags=["Reports"])


@router.get("/sales-trend", response_model=list[SalesTrendItem])
async def get_sales_trend(
    location_id: UUID | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> list[SalesTrendItem]:
    """
    Get daily sales trend data (revenue and profit) for the last 7 days.
    """
    from datetime import date, timedelta
    from app.models.invoice import InvoiceModel, InvoiceItemModel
    from sqlalchemy import select, func

    today = date.today()
    start_date = today - timedelta(days=6)

    # 1. Fetch all invoice items from invoices created in the last 7 days
    stmt = (
        select(
            func.date(InvoiceModel.created_at).label("invoice_date"),
            InvoiceItemModel.unit_price,
            InvoiceItemModel.cost_price,
            InvoiceItemModel.quantity,
            InvoiceModel.discount_amount,
            InvoiceModel.id.label("invoice_id"),
            InvoiceItemModel.line_total,
            InvoiceItemModel.tax_amount
        )
        .join(InvoiceModel, InvoiceModel.id == InvoiceItemModel.invoice_id)
        .where(InvoiceModel.created_at >= start_date)
    )

    if location_id:
        stmt = stmt.where(InvoiceModel.location_id == location_id)

    res = await db.execute(stmt)
    rows = res.fetchall()

    # 2. Group by date in Python for robust SQLite/PostgreSQL compatibility
    daily_stats = {}
    invoice_discounts = {}  # invoice_id -> discount_amount to avoid double-deducting invoice discount

    for row in rows:
        # row: invoice_date (str or date), unit_price, cost_price, quantity, discount_amount, invoice_id, line_total, tax_amount
        d_val = row[0]
        if isinstance(d_val, str):
            d_date = date.fromisoformat(d_val)
        else:
            d_date = d_val

        unit_p = float(row[1] or 0.0)
        cost_p = float(row[2]) if row[2] is not None else unit_p
        qty = int(row[3] or 0)
        discount = float(row[4] or 0.0)
        inv_id = row[5]
        line_tot = float(row[6] or 0.0)
        tax_amt = float(row[7] or 0.0)

        invoice_discounts[inv_id] = discount

        if d_date not in daily_stats:
            daily_stats[d_date] = {
                "sell_subtotal": 0.0,
                "cost_subtotal": 0.0,
            }

        daily_stats[d_date]["sell_subtotal"] += (line_tot - tax_amt)
        daily_stats[d_date]["cost_subtotal"] += cost_p * qty

    # 3. Sum up total invoice discount per day to subtract from revenue and profit
    daily_discounts = {}
    # Let's query the invoices to get the exact discount and total amount per date
    stmt_invoices = select(
        func.date(InvoiceModel.created_at).label("invoice_date"),
        InvoiceModel.total_amount,
        InvoiceModel.discount_amount
    ).where(InvoiceModel.created_at >= start_date)

    if location_id:
        stmt_invoices = stmt_invoices.where(InvoiceModel.location_id == location_id)

    res_invoices = await db.execute(stmt_invoices)
    invoice_rows = res_invoices.fetchall()

    daily_totals = {}
    for row in invoice_rows:
        d_val = row[0]
        if isinstance(d_val, str):
            d_date = date.fromisoformat(d_val)
        else:
            d_date = d_val

        total_amt = float(row[1] or 0.0)
        discount_amt = float(row[2] or 0.0)

        if d_date not in daily_totals:
            daily_totals[d_date] = 0.0
            daily_discounts[d_date] = 0.0

        daily_totals[d_date] += total_amt
        daily_discounts[d_date] += discount_amt

    # 4. Fill in missing days in the 7-day range with zeros
    trend = []
    for i in range(7):
        target_date = start_date + timedelta(days=i)
        stats = daily_stats.get(target_date, {"sell_subtotal": 0.0, "cost_subtotal": 0.0})
        disc = daily_discounts.get(target_date, 0.0)
        
        revenue = daily_totals.get(target_date, 0.0)
        gross_profit = max(0.0, stats["sell_subtotal"] - stats["cost_subtotal"] - disc)

        trend.append(
            SalesTrendItem(
                date=target_date,
                revenue=revenue,
                profit=gross_profit,
            )
        )

    return trend


@router.get("/category-stock", response_model=list[CategoryStockItem])
async def get_category_stock(
    location_id: UUID | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> list[CategoryStockItem]:
    """
    Get inventory stock distribution aggregated by product category.
    """
    from app.models.category import CategoryModel
    from app.models.product import ProductModel
    from app.models.inventory import InventoryModel
    from sqlalchemy import select, func

    stmt = (
        select(
            CategoryModel.name,
            func.sum(InventoryModel.quantity),
            func.count(ProductModel.id)
        )
        .join(ProductModel, ProductModel.category_id == CategoryModel.id)
        .join(InventoryModel, InventoryModel.product_id == ProductModel.id)
    )

    if location_id:
        stmt = stmt.where(InventoryModel.location_id == location_id)

    stmt = stmt.group_by(CategoryModel.name)

    res = await db.execute(stmt)
    rows = res.fetchall()

    return [
        CategoryStockItem(
            category_name=row[0],
            total_stock=int(row[1] or 0),
            product_count=int(row[2] or 0),
        )
        for row in rows
    ]


@router.get("/summary", response_model=SummaryResponse)
async def get_summary(
    from_date: date | None = Query(None),
    to_date: date | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> SummaryResponse:
    """
    Get dashboard summary metrics.

    Args:
        from_date: Optional start of reporting period.
        to_date: Optional end of reporting period.

    Returns:
        SummaryResponse with aggregated metrics.
    """
    return await report_service.get_summary(db, from_date, to_date)


@router.get("/transactions", response_model=PaginatedTransactionResponse)
async def list_transactions(
    product_id: UUID | None = Query(None),
    user_id: UUID | None = Query(None),
    type: str | None = Query(None, alias="type"),
    from_date: date | None = Query(None),
    to_date: date | None = Query(None),
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> PaginatedTransactionResponse:
    """
    List transaction history with optional filters.

    Args:
        product_id: Filter by product UUID.
        user_id: Filter by user UUID.
        type: Filter by transaction type.
        from_date: Start of date range.
        to_date: End of date range.
        page: Page number.
        size: Items per page.

    Returns:
        Paginated list of TransactionHistoryItem.
    """
    transactions, total = await transaction_repo.search_transactions(
        db,
        product_id=product_id,
        user_id=user_id,
        tx_type=type,
        from_date=from_date,
        to_date=to_date,
        page=page,
        size=size,
    )

    items = [
        TransactionHistoryItem(
            id=tx.id,
            product_id=tx.product_id,
            product_name=tx.product.name if tx.product else "Unknown",
            product_barcode=tx.product.barcode if tx.product else "",
            location_id=tx.location_id,
            location_name=tx.location.name if tx.location else "Unknown",
            user_id=tx.user_id,
            user_name=tx.user.name if tx.user else "Unknown",
            type=tx.type.value,
            quantity_change=tx.quantity_change,
            quantity_before=tx.quantity_before,
            quantity_after=tx.quantity_after,
            reference_no=tx.reference_no,
            notes=tx.notes,
            created_at=tx.created_at,
        )
        for tx in transactions
    ]

    return PaginatedTransactionResponse(
        items=items,
        total=total,
        page=page,
        size=size,
        pages=math.ceil(total / size) if total > 0 else 0,
    )
