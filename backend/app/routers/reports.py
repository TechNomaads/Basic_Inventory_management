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
from app.services import report_service

router = APIRouter(prefix="/api/v1/reports", tags=["Reports"])


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
