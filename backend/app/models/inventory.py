"""
Module: inventory model
Description: SQLAlchemy ORM model for the inventory table.

Responsibilities:
    - Track stock quantity per product per location
    - Enforce optimistic locking via version column
    - Unique constraint on (product_id, location_id)

Dependencies:
    - app.core.database.Base
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Index,
    Integer,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class InventoryModel(Base):
    """
    ORM model for the inventory table.

    Each row represents the stock level of one product at one location.
    The version column enables optimistic concurrency control —
    updates must include the known version, and the DB rejects stale writes.
    """

    __tablename__ = "inventory"
    __table_args__ = (
        UniqueConstraint("product_id", "location_id", name="uq_inventory_product_location"),
        Index("ix_inventory_product_location", "product_id", "location_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()"),
    )
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("products.id"),
        nullable=False,
    )
    location_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("locations.id"),
        nullable=False,
    )
    quantity: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    min_quantity: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    max_quantity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    version: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=text("NOW()"),
    )

    # ── Relationships ────────────────────────────────────────────
    product: Mapped["ProductModel"] = relationship("ProductModel", lazy="joined")  # noqa: F821
    location: Mapped["LocationModel"] = relationship("LocationModel", lazy="joined")  # noqa: F821
