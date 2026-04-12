"""
Module: audit router
Description: API endpoint for querying the audit log (admin only).

Responsibilities:
    - GET /audit → paginated, filtered audit log view

Dependencies:
    - app.repositories.audit_repo
    - app.core.dependencies
"""

import math
from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_db, require_role
from app.models.user import UserModel
from app.repositories.audit_repo import audit_repo
from app.schemas.audit import AuditLogItem, PaginatedAuditResponse

router = APIRouter(prefix="/api/v1/audit", tags=["Audit"])


@router.get("", response_model=PaginatedAuditResponse)
async def list_audit_logs(
    user_id: UUID | None = Query(None),
    table_name: str | None = Query(None),
    action: str | None = Query(None),
    from_date: date | None = Query(None),
    to_date: date | None = Query(None),
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _admin: UserModel = Depends(require_role(["admin"])),
) -> PaginatedAuditResponse:
    """
    Query audit logs with optional filters (admin only).

    Args:
        user_id: Filter by user who performed the action.
        table_name: Filter by affected table.
        action: Filter by action type (insert, update, delete).
        from_date: Start of date range.
        to_date: End of date range.
        page: Page number.
        size: Items per page.

    Returns:
        Paginated list of AuditLogItem.
    """
    logs, total = await audit_repo.search_logs(
        db,
        user_id=user_id,
        table_name=table_name,
        action=action,
        from_date=from_date,
        to_date=to_date,
        page=page,
        size=size,
    )

    items = [
        AuditLogItem(
            id=log.id,
            user_id=log.user_id,
            user_name=log.user.name if log.user else "Unknown",
            table_name=log.table_name,
            record_id=log.record_id,
            action=log.action.value,
            old_values=log.old_values,
            new_values=log.new_values,
            ip_address=log.ip_address,
            created_at=log.created_at,
        )
        for log in logs
    ]

    return PaginatedAuditResponse(
        items=items,
        total=total,
        page=page,
        size=size,
        pages=math.ceil(total / size) if total > 0 else 0,
    )
