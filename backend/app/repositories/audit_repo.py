"""
Module: audit_repo
Description: Repository for audit log database operations.

Responsibilities:
    - Write audit log entries after every mutation
    - Query audit logs with filters for admin review

Dependencies:
    - app.repositories.base.BaseRepository
    - app.models.audit_log
"""

from datetime import date, datetime, time, timezone
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit_log import AuditAction, AuditLogModel
from app.repositories.base import BaseRepository


class AuditRepository(BaseRepository[AuditLogModel]):
    """Async repository for audit log entries."""

    def __init__(self) -> None:
        super().__init__(AuditLogModel)

    async def search_logs(
        self,
        db: AsyncSession,
        user_id: UUID | None = None,
        table_name: str | None = None,
        action: str | None = None,
        from_date: date | None = None,
        to_date: date | None = None,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[AuditLogModel], int]:
        """
        Search audit logs with optional filters.

        Args:
            db: Async database session.
            user_id: Filter by user who performed the action.
            table_name: Filter by affected table name.
            action: Filter by action type (insert, update, delete).
            from_date: Start of date range (inclusive).
            to_date: End of date range (inclusive).
            page: Page number (1-indexed).
            size: Items per page.

        Returns:
            Tuple of (matching audit entries, total count).
        """
        base = select(AuditLogModel)
        count_base = select(func.count()).select_from(AuditLogModel)

        filters = []
        if user_id:
            filters.append(AuditLogModel.user_id == user_id)
        if table_name:
            filters.append(AuditLogModel.table_name == table_name)
        if action:
            filters.append(AuditLogModel.action == AuditAction(action))
        if from_date:
            from_dt = datetime.combine(from_date, time.min, tzinfo=timezone.utc)
            filters.append(AuditLogModel.created_at >= from_dt)
        if to_date:
            to_dt = datetime.combine(to_date, time.max, tzinfo=timezone.utc)
            filters.append(AuditLogModel.created_at <= to_dt)

        for f in filters:
            base = base.where(f)
            count_base = count_base.where(f)

        total_result = await db.execute(count_base)
        total = total_result.scalar_one()

        offset = (page - 1) * size
        stmt = base.order_by(AuditLogModel.created_at.desc()).offset(offset).limit(size)
        result = await db.execute(stmt)
        items = list(result.scalars().all())

        return items, total


# Singleton instance
audit_repo = AuditRepository()
