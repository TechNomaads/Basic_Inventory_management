"""
Module: location model
Description: SQLAlchemy ORM model for the locations table.

Responsibilities:
    - Define warehouse, shelf, and bin locations
    - Self-referencing parent_id for location hierarchy
    - Unique code constraint for quick lookup

Dependencies:
    - app.core.database.Base
"""

import uuid

from sqlalchemy import ForeignKey, String, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class LocationModel(Base):
    """
    ORM model for physical locations (warehouses, shelves, bins).

    Supports hierarchical nesting — a bin belongs to a shelf,
    which belongs to a warehouse.
    """

    __tablename__ = "locations"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()"),
    )
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    code: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    type: Mapped[str | None] = mapped_column(String(50), nullable=True)
    parent_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("locations.id"),
        nullable=True,
    )

    # ── Relationships ────────────────────────────────────────────
    children: Mapped[list["LocationModel"]] = relationship(
        "LocationModel",
        back_populates="parent",
        lazy="selectin",
    )
    parent: Mapped["LocationModel | None"] = relationship(
        "LocationModel",
        back_populates="children",
        remote_side=[id],
        lazy="joined",
    )
