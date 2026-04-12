"""
Module: audit_service
Description: Service for recording audit log entries after every data mutation.

Responsibilities:
    - Create audit log entries with old/new values
    - Capture user, table, record, action, and IP address
    - Provide a single function usable from any service

Dependencies:
    - app.models.audit_log
    - app.repositories.audit_repo
"""

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit_log import AuditAction, AuditLogModel
from app.repositories.audit_repo import audit_repo


async def write_audit_log(
    db: AsyncSession,
    user_id: UUID,
    table_name: str,
    record_id: UUID,
    action: AuditAction,
    old_values: dict | None = None,
    new_values: dict | None = None,
    ip_address: str | None = None,
) -> AuditLogModel:
    """
    Write an audit log entry recording a data mutation.

    This function should be called after every successful create,
    update, or delete operation across all services.

    Args:
        db: Async database session.
        user_id: UUID of the user who performed the action.
        table_name: Name of the affected database table.
        record_id: UUID of the affected record.
        action: Type of action (insert, update, delete).
        old_values: Previous state as dict (for updates/deletes).
        new_values: New state as dict (for inserts/updates).
        ip_address: Client IP address (optional).

    Returns:
        The created AuditLogModel instance.
    """
    entry = AuditLogModel(
        user_id=user_id,
        table_name=table_name,
        record_id=record_id,
        action=action,
        old_values=old_values,
        new_values=new_values,
        ip_address=ip_address,
    )
    return await audit_repo.create(db, entry)
