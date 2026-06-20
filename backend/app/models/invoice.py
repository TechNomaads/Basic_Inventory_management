"""
Module: invoice model
Description: SQLAlchemy ORM models for invoices and invoice_items tables.

Responsibilities:
    - Record total sales, payments, discounts, and customer links
    - Keep dynamic, snapshotted line items with price/tax data
    - Establish foreign keys to locations, users, customers, and products

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
    Numeric,
    String,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class PaymentMode(str, enum.Enum):
    """Payment mode choices."""
    cash = "cash"
    upi = "upi"
    card = "card"


class InvoiceModel(Base):
    """
    ORM model for customer invoices.
    """

    __tablename__ = "invoices"
    __table_args__ = (
        Index("ix_invoices_invoice_number", "invoice_number"),
        Index("ix_invoices_location_created", "location_id", "created_at"),
        Index("ix_invoices_customer_created", "customer_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()"),
    )
    invoice_number: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    location_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("locations.id"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    customer_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("customers.id", ondelete="SET NULL"), nullable=True
    )
    subtotal: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0.0)
    tax_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0.0)
    discount_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0.0)
    total_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0.0)
    amount_paid: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0.00, server_default="0.00")
    payment_mode: Mapped[PaymentMode] = mapped_column(
        Enum(PaymentMode, name="payment_mode_enum", create_type=True),
        nullable=False,
        default=PaymentMode.cash,
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=text("NOW()"),
    )

    # ── Relationships ────────────────────────────────────────────
    location: Mapped["LocationModel"] = relationship("LocationModel", lazy="joined")  # noqa: F821
    user: Mapped["UserModel"] = relationship("UserModel", lazy="joined")  # noqa: F821
    customer: Mapped["CustomerModel | None"] = relationship("CustomerModel", lazy="joined")  # noqa: F821
    items: Mapped[list["InvoiceItemModel"]] = relationship(
        "InvoiceItemModel",
        back_populates="invoice",
        cascade="all, delete-orphan",
        lazy="selectin",
    )

    @property
    def location_name(self) -> str:
        return self.location.name if self.location else ""

    @property
    def user_name(self) -> str:
        return self.user.name if self.user else ""

    @property
    def customer_name(self) -> str | None:
        return self.customer.name if self.customer else None

    @property
    def customer_phone(self) -> str | None:
        return self.customer.phone if self.customer else None

    @property
    def amount_due(self) -> float:
        return float(self.total_amount or 0.0) - float(self.amount_paid or 0.0)


class InvoiceItemModel(Base):
    """
    ORM model for individual items within an invoice.
    Snapshot fields prevent changes to master data from modifying historic transactions.
    """

    __tablename__ = "invoice_items"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()"),
    )
    invoice_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("invoices.id", ondelete="CASCADE"), nullable=False
    )
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("products.id"), nullable=False
    )
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    unit_price: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    cost_price: Mapped[float | None] = mapped_column(Numeric(12, 2), nullable=True)
    tax_rate: Mapped[float] = mapped_column(Numeric(5, 2), nullable=False, default=18.0)
    tax_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    line_total: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)

    # ── Relationships ────────────────────────────────────────────
    invoice: Mapped[InvoiceModel] = relationship("InvoiceModel", back_populates="items")
    product: Mapped["ProductModel"] = relationship("ProductModel", lazy="joined")  # noqa: F821

    @property
    def product_name(self) -> str:
        return self.product.name if self.product else ""

    @property
    def product_barcode(self) -> str:
        return self.product.barcode if self.product else ""
