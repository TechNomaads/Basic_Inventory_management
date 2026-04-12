"""
Module: audit_log model
Description: SQLAlchemy ORM model for the audit_log table.

Responsibilities:
    - Record every data mutation (insert, update, delete)
    - Store old and new values as JSONB for full traceability
    - Index on (user_id, created_at) for efficient audit queries

Dependencies:
    - app.core.database.Base
"""

import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    DateTime,
    Enum,
    ForeignKey,
    Index,
    String,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class AuditAction(str, enum.Enum):
    """Types of auditable actions."""
    insert = "insert"
    update = "update"
    delete = "delete"


class AuditLogModel(Base):
    """
    ORM model for the audit log — immutable record of every
    data mutation performed through the API.

    old_values and new_values are stored as JSONB, allowing
    flexible querying without schema migration for new fields.
    """

    __tablename__ = "audit_log"
    __table_args__ = (
        Index("ix_audit_user_created", "user_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()"),
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    table_name: Mapped[str] = mapped_column(String(100), nullable=False)
    record_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    action: Mapped[AuditAction] = mapped_column(
        Enum(AuditAction, name="audit_action_enum", create_type=True),
        nullable=False,
    )
    old_values: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    new_values: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    ip_address: Mapped[str | None] = mapped_column(String(45), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=text("NOW()"),
    )

    # ── Relationships ────────────────────────────────────────────
    user: Mapped["UserModel"] = relationship("UserModel", lazy="joined")  # noqa: F821
