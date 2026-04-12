"""
Module: report_service
Description: Business logic for reporting and dashboard summaries.

Responsibilities:
    - Aggregate dashboard summary metrics
    - Provide filtered transaction history

Dependencies:
    - app.repositories (product, inventory, transaction, audit)
"""

from datetime import date
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stock_transaction import TransactionType
from app.repositories.inventory_repo import inventory_repo
from app.repositories.product_repo import product_repo
from app.repositories.transaction_repo import transaction_repo
from app.repositories.user_repo import user_repo
from app.schemas.reports import SummaryResponse

# Count pending adjustments
from sqlalchemy import func, select
from app.models.pending_adjustment import AdjustmentStatus, PendingAdjustmentModel


async def get_summary(
    db: AsyncSession,
    from_date: date | None = None,
    to_date: date | None = None,
) -> SummaryResponse:
    """
    Generate dashboard summary metrics.

    Args:
        db: Async database session.
        from_date: Optional start of reporting period.
        to_date: Optional end of reporting period.

    Returns:
        SummaryResponse with all aggregated metrics.
    """
    total_products = await product_repo.get_active_count(db)
    low_stock_count = await inventory_repo.get_low_stock_count(db)
    out_of_stock_count = await inventory_repo.get_out_of_stock_count(db)
    todays_scans = await transaction_repo.count_today(db)
    active_users = await user_repo.get_active_user_count(db)

    total_dispatched = await transaction_repo.count_by_type(
        db, TransactionType.dispatch, from_date, to_date
    )
    total_received = await transaction_repo.count_by_type(
        db, TransactionType.receive, from_date, to_date
    )

    # Count pending adjustments
    pending_stmt = select(func.count()).select_from(PendingAdjustmentModel).where(
        PendingAdjustmentModel.status == AdjustmentStatus.pending
    )
    pending_result = await db.execute(pending_stmt)
    pending_count = pending_result.scalar_one()

    return SummaryResponse(
        total_products=total_products,
        low_stock_count=low_stock_count,
        todays_scans=todays_scans,
        pending_adjustments=pending_count,
        total_dispatched=total_dispatched,
        total_received=total_received,
        out_of_stock_count=out_of_stock_count,
        active_users=active_users,
    )
