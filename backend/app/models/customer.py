"""
Module: customer model
Description: SQLAlchemy ORM model for the customers table.

Responsibilities:
    - Store customer profiles (name, phone)
    - Enable lookups on phone number for customer identification at checkout

Dependencies:
    - app.core.database.Base
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, Index, String, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class CustomerModel(Base):
    """
    ORM model for customer profiles.
    """

    __tablename__ = "customers"
    __table_args__ = (
        Index("ix_customers_phone", "phone"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()"),
    )
    name: Mapped[str] = mapped_column(
        String(150), nullable=False, default="Anonymous/Walk-in", server_default="Anonymous/Walk-in"
    )
    phone: Mapped[str | None] = mapped_column(String(50), unique=True, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=text("NOW()"),
    )
