"""
Module: user model
Description: SQLAlchemy ORM model for the users table and user_locations junction.

Responsibilities:
    - Define UserRole enum (admin, manager, staff, viewer)
    - Map users table with all columns, defaults, and constraints
    - Map user_locations junction table for location scoping
    - Provide relationships for eager/lazy loading

Dependencies:
    - app.core.database.Base
"""

import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    String,
    text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class UserRole(str, enum.Enum):
    """Enumeration of user roles for role-based access control."""
    admin = "admin"
    manager = "manager"
    staff = "staff"
    viewer = "viewer"


class UserLocationModel(Base):
    """
    Junction table mapping users to their assigned locations.

    Staff and viewer roles are scoped to specific locations;
    admin and manager roles bypass location restrictions.
    """

    __tablename__ = "user_locations"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    location_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("locations.id", ondelete="CASCADE"),
        primary_key=True,
    )


class UserModel(Base):
    """
    ORM model for the users table.

    Stores authentication credentials and role assignment.
    Passwords are always stored as bcrypt hashes — the plain-text
    password is never persisted or returned in API responses.
    """

    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()"),
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[UserRole] = mapped_column(
        Enum(UserRole, name="user_role_enum", create_type=True),
        nullable=False,
        default=UserRole.staff,
        server_default="staff",
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    last_login: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=text("NOW()"),
    )

    # ── Relationships ────────────────────────────────────────────
    user_locations: Mapped[list["UserLocationModel"]] = relationship(
        "UserLocationModel",
        lazy="selectin",
        cascade="all, delete-orphan",
    )
