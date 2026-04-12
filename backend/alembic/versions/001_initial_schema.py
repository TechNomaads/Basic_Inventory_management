"""001 — Initial schema: all tables, enums, indexes, constraints.

Revision ID: 001_initial_schema
Revises: None
Create Date: 2024-01-01 00:00:00.000000

This migration creates the complete database schema for the
Inventory Management System, including:
    - 3 enum types (user_role, transaction_type, adjustment_status, audit_action)
    - 9 tables (users, user_locations, categories, suppliers, locations,
      products, inventory, stock_transactions, pending_adjustments, audit_log)
    - All foreign keys, unique constraints, and indexes
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB, UUID

# revision identifiers
revision: str = "001_initial_schema"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# ── Enum type definitions ────────────────────────────────────────
# create_type=False: we handle creation ourselves in the DO block
user_role_enum = sa.Enum(
    "admin", "manager", "staff", "viewer",
    name="user_role_enum",
    create_type=False,
)
transaction_type_enum = sa.Enum(
    "receive", "dispatch", "adjustment",
    "transfer_in", "transfer_out", "damage",
    name="transaction_type_enum",
    create_type=False,
)
adjustment_status_enum = sa.Enum(
    "pending", "approved", "rejected",
    name="adjustment_status_enum",
    create_type=False,
)
audit_action_enum = sa.Enum(
    "insert", "update", "delete",
    name="audit_action_enum",
    create_type=False,
)


def upgrade() -> None:
    """Create all tables and indexes."""

    # ── Create enum types (idempotent via DO block) ────────────────
    op.execute("""
        DO $$ BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role_enum') THEN
                CREATE TYPE user_role_enum AS ENUM ('admin', 'manager', 'staff', 'viewer');
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transaction_type_enum') THEN
                CREATE TYPE transaction_type_enum AS ENUM ('receive', 'dispatch', 'adjustment', 'transfer_in', 'transfer_out', 'damage');
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'adjustment_status_enum') THEN
                CREATE TYPE adjustment_status_enum AS ENUM ('pending', 'approved', 'rejected');
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audit_action_enum') THEN
                CREATE TYPE audit_action_enum AS ENUM ('insert', 'update', 'delete');
            END IF;
        END $$;
    """)

    # ── users ────────────────────────────────────────────────────
    op.create_table(
        "users",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("email", sa.String(255), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("role", user_role_enum, nullable=False, server_default="staff"),
        sa.Column("is_active", sa.Boolean, server_default="true"),
        sa.Column("last_login", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("NOW()")),
    )

    # ── categories ───────────────────────────────────────────────
    op.create_table(
        "categories",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("parent_id", UUID(as_uuid=True), sa.ForeignKey("categories.id"), nullable=True),
    )

    # ── suppliers ────────────────────────────────────────────────
    op.create_table(
        "suppliers",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("name", sa.String(150), nullable=False),
        sa.Column("contact_name", sa.String(120), nullable=True),
        sa.Column("phone", sa.String(30), nullable=True),
        sa.Column("email", sa.String(255), nullable=True),
        sa.Column("address", sa.Text, nullable=True),
    )

    # ── locations ────────────────────────────────────────────────
    op.create_table(
        "locations",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("name", sa.String(150), nullable=False),
        sa.Column("code", sa.String(50), nullable=False, unique=True),
        sa.Column("type", sa.String(50), nullable=True),
        sa.Column("parent_id", UUID(as_uuid=True), sa.ForeignKey("locations.id"), nullable=True),
    )

    # ── user_locations (junction) ────────────────────────────────
    op.create_table(
        "user_locations",
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("location_id", UUID(as_uuid=True), sa.ForeignKey("locations.id", ondelete="CASCADE"), primary_key=True),
    )

    # ── products ─────────────────────────────────────────────────
    op.create_table(
        "products",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("barcode", sa.String(100), nullable=False, unique=True),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("sku", sa.String(100), nullable=False, unique=True),
        sa.Column("category_id", UUID(as_uuid=True), sa.ForeignKey("categories.id"), nullable=True),
        sa.Column("supplier_id", UUID(as_uuid=True), sa.ForeignKey("suppliers.id"), nullable=True),
        sa.Column("unit", sa.String(30), server_default="pcs"),
        sa.Column("cost_price", sa.Numeric(12, 2), nullable=True),
        sa.Column("sell_price", sa.Numeric(12, 2), nullable=True),
        sa.Column("image_url", sa.Text, nullable=True),
        sa.Column("is_active", sa.Boolean, server_default="true"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("NOW()")),
    )
    op.create_index("ix_products_barcode", "products", ["barcode"])
    op.create_index("ix_products_sku", "products", ["sku"])

    # ── inventory ────────────────────────────────────────────────
    op.create_table(
        "inventory",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("product_id", UUID(as_uuid=True), sa.ForeignKey("products.id"), nullable=False),
        sa.Column("location_id", UUID(as_uuid=True), sa.ForeignKey("locations.id"), nullable=False),
        sa.Column("quantity", sa.Integer, nullable=False, server_default="0"),
        sa.Column("min_quantity", sa.Integer, server_default="0"),
        sa.Column("max_quantity", sa.Integer, nullable=True),
        sa.Column("version", sa.Integer, nullable=False, server_default="0"),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("NOW()")),
        sa.UniqueConstraint("product_id", "location_id", name="uq_inventory_product_location"),
    )
    op.create_index("ix_inventory_product_location", "inventory", ["product_id", "location_id"])

    # ── stock_transactions ───────────────────────────────────────
    op.create_table(
        "stock_transactions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("product_id", UUID(as_uuid=True), sa.ForeignKey("products.id"), nullable=False),
        sa.Column("location_id", UUID(as_uuid=True), sa.ForeignKey("locations.id"), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("type", transaction_type_enum, nullable=False),
        sa.Column("quantity_change", sa.Integer, nullable=False),
        sa.Column("quantity_before", sa.Integer, nullable=False),
        sa.Column("quantity_after", sa.Integer, nullable=False),
        sa.Column("reference_no", sa.String(100), nullable=True),
        sa.Column("notes", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("NOW()")),
    )
    op.create_index("ix_stock_tx_product_created", "stock_transactions", ["product_id", sa.text("created_at DESC")])
    op.create_index("ix_stock_tx_user_created", "stock_transactions", ["user_id", sa.text("created_at DESC")])

    # ── pending_adjustments ──────────────────────────────────────
    op.create_table(
        "pending_adjustments",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("product_id", UUID(as_uuid=True), sa.ForeignKey("products.id"), nullable=False),
        sa.Column("location_id", UUID(as_uuid=True), sa.ForeignKey("locations.id"), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("quantity_change", sa.Integer, nullable=False),
        sa.Column("notes", sa.Text, nullable=True),
        sa.Column("status", adjustment_status_enum, nullable=False, server_default="pending"),
        sa.Column("reviewed_by", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("NOW()")),
    )

    # ── audit_log ────────────────────────────────────────────────
    op.create_table(
        "audit_log",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("table_name", sa.String(100), nullable=False),
        sa.Column("record_id", UUID(as_uuid=True), nullable=False),
        sa.Column("action", audit_action_enum, nullable=False),
        sa.Column("old_values", JSONB, nullable=True),
        sa.Column("new_values", JSONB, nullable=True),
        sa.Column("ip_address", sa.String(45), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("NOW()")),
    )
    op.create_index("ix_audit_user_created", "audit_log", ["user_id", sa.text("created_at DESC")])


def downgrade() -> None:
    """Drop all tables and enum types in reverse order."""
    op.drop_table("audit_log")
    op.drop_table("pending_adjustments")
    op.drop_table("stock_transactions")
    op.drop_table("inventory")
    op.drop_table("products")
    op.drop_table("user_locations")
    op.drop_table("locations")
    op.drop_table("suppliers")
    op.drop_table("categories")
    op.drop_table("users")

    audit_action_enum.drop(op.get_bind(), checkfirst=True)
    adjustment_status_enum.drop(op.get_bind(), checkfirst=True)
    transaction_type_enum.drop(op.get_bind(), checkfirst=True)
    user_role_enum.drop(op.get_bind(), checkfirst=True)
