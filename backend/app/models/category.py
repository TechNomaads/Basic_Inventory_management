"""
Module: category model
Description: SQLAlchemy ORM model for the categories table.

Responsibilities:
    - Self-referencing parent_id for nested category trees
    - Relationship to child categories and products

Dependencies:
    - app.core.database.Base
"""

import uuid

from sqlalchemy import ForeignKey, String, Text, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class CategoryModel(Base):
    """
    ORM model for product categories.

    Supports hierarchical nesting via the self-referencing parent_id.
    """

    __tablename__ = "categories"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()"),
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    parent_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("categories.id"),
        nullable=True,
    )

    # ── Relationships ────────────────────────────────────────────
    children: Mapped[list["CategoryModel"]] = relationship(
        "CategoryModel",
        back_populates="parent",
        lazy="selectin",
    )
    parent: Mapped["CategoryModel | None"] = relationship(
        "CategoryModel",
        back_populates="children",
        remote_side=[id],
        lazy="joined",
    )
