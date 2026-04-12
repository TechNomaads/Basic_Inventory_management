"""
Module: pending_adjustment model
Description: SQLAlchemy ORM model for the pending_adjustments table.

Responsibilities:
    - Queue large stock adjustments for manager/admin approval
    - Track approval status, reviewer, and review timestamp

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
    Integer,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class AdjustmentStatus(str, enum.Enum):
    """Status of a pending stock adjustment."""
    pending = "pending"
    approved = "approved"
    rejected = "rejected"


class PendingAdjustmentModel(Base):
    """
    ORM model for pending adjustments.

    When a stock adjustment exceeds the configured threshold,
    it is routed here instead of being applied immediately.
    A manager or admin must approve or reject it.
    """

    __tablename__ = "pending_adjustments"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()"),
    )
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("products.id"), nullable=False
    )
    location_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("locations.id"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    quantity_change: Mapped[int] = mapped_column(Integer, nullable=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[AdjustmentStatus] = mapped_column(
        Enum(AdjustmentStatus, name="adjustment_status_enum", create_type=True),
        nullable=False,
        default=AdjustmentStatus.pending,
        server_default="pending",
    )
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=True
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=text("NOW()"),
    )

    # ── Relationships ────────────────────────────────────────────
    product: Mapped["ProductModel"] = relationship("ProductModel", lazy="joined")  # noqa: F821
    location: Mapped["LocationModel"] = relationship("LocationModel", lazy="joined")  # noqa: F821
    user: Mapped["UserModel"] = relationship(  # noqa: F821
        "UserModel", foreign_keys=[user_id], lazy="joined"
    )
    reviewer: Mapped["UserModel | None"] = relationship(  # noqa: F821
        "UserModel", foreign_keys=[reviewed_by], lazy="joined"
    )
