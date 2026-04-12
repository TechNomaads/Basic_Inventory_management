"""
Module: transaction_repo
Description: Repository for stock transaction database operations.

Responsibilities:
    - Create stock transaction records
    - Query transaction history with filters
    - Count today's transactions

Dependencies:
    - app.repositories.base.BaseRepository
    - app.models.stock_transaction
"""

from datetime import date, datetime, time, timezone
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stock_transaction import StockTransactionModel, TransactionType
from app.repositories.base import BaseRepository


class TransactionRepository(BaseRepository[StockTransactionModel]):
    """Async repository for stock transaction records."""

    def __init__(self) -> None:
        super().__init__(StockTransactionModel)

    async def get_by_product(
        self,
        db: AsyncSession,
        product_id: UUID,
        limit: int = 5,
    ) -> list[StockTransactionModel]:
        """
        Get the most recent transactions for a product.

        Args:
            db: Async database session.
            product_id: UUID of the product.
            limit: Maximum number of records to return.

        Returns:
            List of recent StockTransactionModel instances.
        """
        stmt = (
            select(StockTransactionModel)
            .where(StockTransactionModel.product_id == product_id)
            .order_by(StockTransactionModel.created_at.desc())
            .limit(limit)
        )
        result = await db.execute(stmt)
        return list(result.scalars().all())

    async def get_by_user(
        self,
        db: AsyncSession,
        user_id: UUID,
        limit: int = 5,
    ) -> list[StockTransactionModel]:
        """
        Get the most recent transactions by a specific user.

        Args:
            db: Async database session.
            user_id: UUID of the user.
            limit: Maximum number of records.

        Returns:
            List of recent StockTransactionModel instances.
        """
        stmt = (
            select(StockTransactionModel)
            .where(StockTransactionModel.user_id == user_id)
            .order_by(StockTransactionModel.created_at.desc())
            .limit(limit)
        )
        result = await db.execute(stmt)
        return list(result.scalars().all())

    async def search_transactions(
        self,
        db: AsyncSession,
        product_id: UUID | None = None,
        user_id: UUID | None = None,
        tx_type: str | None = None,
        from_date: date | None = None,
        to_date: date | None = None,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[StockTransactionModel], int]:
        """
        Search transactions with multiple optional filters.

        Args:
            db: Async database session.
            product_id: Optional product filter.
            user_id: Optional user filter.
            tx_type: Optional transaction type filter.
            from_date: Optional start date (inclusive).
            to_date: Optional end date (inclusive).
            page: Page number (1-indexed).
            size: Items per page.

        Returns:
            Tuple of (matching transactions, total count).
        """
        base = select(StockTransactionModel)
        count_base = select(func.count()).select_from(StockTransactionModel)

        filters = []
        if product_id:
            filters.append(StockTransactionModel.product_id == product_id)
        if user_id:
            filters.append(StockTransactionModel.user_id == user_id)
        if tx_type:
            filters.append(StockTransactionModel.type == TransactionType(tx_type))
        if from_date:
            from_dt = datetime.combine(from_date, time.min, tzinfo=timezone.utc)
            filters.append(StockTransactionModel.created_at >= from_dt)
        if to_date:
            to_dt = datetime.combine(to_date, time.max, tzinfo=timezone.utc)
            filters.append(StockTransactionModel.created_at <= to_dt)

        for f in filters:
            base = base.where(f)
            count_base = count_base.where(f)

        total_result = await db.execute(count_base)
        total = total_result.scalar_one()

        offset = (page - 1) * size
        stmt = base.order_by(StockTransactionModel.created_at.desc()).offset(offset).limit(size)
        result = await db.execute(stmt)
        items = list(result.scalars().all())

        return items, total

    async def count_today(self, db: AsyncSession) -> int:
        """
        Count transactions created today (UTC).

        Args:
            db: Async database session.

        Returns:
            Integer count.
        """
        today_start = datetime.combine(date.today(), time.min, tzinfo=timezone.utc)
        stmt = select(func.count()).select_from(StockTransactionModel).where(
            StockTransactionModel.created_at >= today_start
        )
        result = await db.execute(stmt)
        return result.scalar_one()

    async def count_by_type(
        self,
        db: AsyncSession,
        tx_type: TransactionType,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> int:
        """
        Count transactions of a specific type within an optional date range.

        Args:
            db: Async database session.
            tx_type: The transaction type to count.
            from_date: Optional start date.
            to_date: Optional end date.

        Returns:
            Integer count.
        """
        stmt = select(func.count()).select_from(StockTransactionModel).where(
            StockTransactionModel.type == tx_type
        )
        if from_date:
            from_dt = datetime.combine(from_date, time.min, tzinfo=timezone.utc)
            stmt = stmt.where(StockTransactionModel.created_at >= from_dt)
        if to_date:
            to_dt = datetime.combine(to_date, time.max, tzinfo=timezone.utc)
            stmt = stmt.where(StockTransactionModel.created_at <= to_dt)

        result = await db.execute(stmt)
        return result.scalar_one()


# Singleton instance
transaction_repo = TransactionRepository()
