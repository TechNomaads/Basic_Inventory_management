"""
Module: product model
Description: SQLAlchemy ORM model for the products table.

Responsibilities:
    - Store product master data (name, SKU, barcode, prices)
    - Index on barcode and sku for fast scan lookups
    - Foreign keys to categories and suppliers

Dependencies:
    - app.core.database.Base
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Numeric,
    String,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ProductModel(Base):
    """
    ORM model for products — the central entity of the inventory system.

    The barcode field is the primary scan field used by the mobile app.
    Both barcode and sku are uniquely indexed for sub-millisecond lookups.
    """

    __tablename__ = "products"
    __table_args__ = (
        Index("ix_products_barcode", "barcode"),
        Index("ix_products_sku", "sku"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()"),
    )
    barcode: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    sku: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    category_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("categories.id"),
        nullable=True,
    )
    supplier_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("suppliers.id"),
        nullable=True,
    )
    unit: Mapped[str] = mapped_column(String(30), default="pcs", server_default="pcs")
    cost_price: Mapped[float | None] = mapped_column(Numeric(12, 2), nullable=True)
    sell_price: Mapped[float | None] = mapped_column(Numeric(12, 2), nullable=True)
    tax_rate: Mapped[float] = mapped_column(Numeric(5, 2), nullable=False, default=18.0, server_default="18.0")
    image_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=text("NOW()"),
    )

    # ── Relationships ────────────────────────────────────────────
    category: Mapped["CategoryModel | None"] = relationship(  # noqa: F821
        "CategoryModel", lazy="joined"
    )
    supplier: Mapped["SupplierModel | None"] = relationship(  # noqa: F821
        "SupplierModel", lazy="joined"
    )
