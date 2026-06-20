"""
Module: stock_transaction model
Description: SQLAlchemy ORM model for the stock_transactions table.

Responsibilities:
    - Record every stock movement with before/after quantities
    - Support transaction types: receive, dispatch, adjustment, transfer, damage
    - Indexes for fast lookups by product and user

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
    Integer,
    String,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class TransactionType(str, enum.Enum):
    """Types of stock transactions."""
    receive = "receive"
    dispatch = "dispatch"
    adjustment = "adjustment"
    transfer_in = "transfer_in"
    transfer_out = "transfer_out"
    damage = "damage"
    sale = "sale"


class StockTransactionModel(Base):
    """
    ORM model for stock transactions — the immutable audit trail
    of every stock movement in the system.

    quantity_before and quantity_after are captured at transaction time
    to provide a full history even if aggregated counts drift.
    """

    __tablename__ = "stock_transactions"
    __table_args__ = (
        Index("ix_stock_tx_product_created", "product_id", "created_at"),
        Index("ix_stock_tx_user_created", "user_id", "created_at"),
    )

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
    type: Mapped[TransactionType] = mapped_column(
        Enum(TransactionType, name="transaction_type_enum", create_type=True),
        nullable=False,
    )
    quantity_change: Mapped[int] = mapped_column(Integer, nullable=False)
    quantity_before: Mapped[int] = mapped_column(Integer, nullable=False)
    quantity_after: Mapped[int] = mapped_column(Integer, nullable=False)
    reference_no: Mapped[str | None] = mapped_column(String(100), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=text("NOW()"),
    )

    # ── Relationships ────────────────────────────────────────────
    product: Mapped["ProductModel"] = relationship("ProductModel", lazy="joined")  # noqa: F821
    location: Mapped["LocationModel"] = relationship("LocationModel", lazy="joined")  # noqa: F821
    user: Mapped["UserModel"] = relationship("UserModel", lazy="joined")  # noqa: F821
