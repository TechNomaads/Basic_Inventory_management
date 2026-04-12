"""
Module: audit schemas
Description: Pydantic v2 models for audit log endpoints.

Responsibilities:
    - Shape audit log response items
    - Support paginated audit queries

Dependencies:
    - pydantic
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class AuditLogItem(BaseModel):
    """A single audit log entry."""
    id: UUID
    user_id: UUID
    user_name: str
    table_name: str
    record_id: UUID
    action: str
    old_values: dict | None = None
    new_values: dict | None = None
    ip_address: str | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class PaginatedAuditResponse(BaseModel):
    """Paginated list of audit log entries."""
    items: list[AuditLogItem]
    total: int
    page: int
    size: int
    pages: int
