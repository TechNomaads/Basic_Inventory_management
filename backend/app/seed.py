"""
Module: seed
Description: Create initial admin user and demo data.

Run via: python -m app.seed

Creates:
    - 1 admin user  (admin@inventory.app / admin123)
    - 2 locations   (Main Warehouse, Store Front)
    - 3 categories  (Electronics, Raw Materials, Packaging)
    - 2 suppliers   (TechSupply Co, PackagePro Ltd)
    - 5 products    (with barcodes ready for scanning)
    - Inventory records for each product at each location
"""

import asyncio
import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings
from app.core.security import hash_password
from app.models.user import UserModel, UserRole, UserLocationModel
from app.models.category import CategoryModel
from app.models.supplier import SupplierModel
from app.models.location import LocationModel
from app.models.product import ProductModel
from app.models.inventory import InventoryModel


async def seed() -> None:
    """Seed the database with initial data if admin doesn't exist."""

    engine = create_async_engine(settings.DATABASE_URL)
    session_factory = async_sessionmaker(
        bind=engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    async with session_factory() as db:
        # ── Check if admin already exists ────────────────────────
        result = await db.execute(
            select(UserModel).where(UserModel.email == "admin@inventory.app")
        )
        if result.scalar_one_or_none():
            print("  ✅ Admin user already exists — skipping seed")
            await engine.dispose()
            return

        print("  📦 Seeding initial data...")

        # ── Create locations ─────────────────────────────────────
        loc_warehouse = LocationModel(
            id=uuid.uuid4(),
            name="Main Warehouse",
            code="WH-001",
            type="warehouse",
        )
        loc_store = LocationModel(
            id=uuid.uuid4(),
            name="Store Front",
            code="SF-001",
            type="store",
        )
        db.add_all([loc_warehouse, loc_store])
        await db.flush()

        # ── Create admin user (assigned to both locations) ───────
        admin = UserModel(
            id=uuid.uuid4(),
            name="Admin User",
            email="admin@inventory.app",
            password_hash=hash_password("admin123"),
            role=UserRole.admin,
            is_active=True,
            created_at=datetime.now(timezone.utc),
        )
        db.add(admin)
        await db.flush()

        # Assign admin to both locations
        db.add(UserLocationModel(user_id=admin.id, location_id=loc_warehouse.id))
        db.add(UserLocationModel(user_id=admin.id, location_id=loc_store.id))

        # ── Create a staff user ──────────────────────────────────
        staff = UserModel(
            id=uuid.uuid4(),
            name="Staff User",
            email="staff@inventory.app",
            password_hash=hash_password("staff123"),
            role=UserRole.staff,
            is_active=True,
            created_at=datetime.now(timezone.utc),
        )
        db.add(staff)
        await db.flush()
        db.add(UserLocationModel(user_id=staff.id, location_id=loc_warehouse.id))

        # ── Create categories ────────────────────────────────────
        cat_electronics = CategoryModel(
            id=uuid.uuid4(),
            name="Electronics",
            description="Electronic components and devices",
        )
        cat_raw = CategoryModel(
            id=uuid.uuid4(),
            name="Raw Materials",
            description="Unprocessed materials for production",
        )
        cat_packaging = CategoryModel(
            id=uuid.uuid4(),
            name="Packaging",
            description="Packaging supplies and materials",
        )
        db.add_all([cat_electronics, cat_raw, cat_packaging])
        await db.flush()

        # ── Create suppliers ─────────────────────────────────────
        sup_tech = SupplierModel(
            id=uuid.uuid4(),
            name="TechSupply Co",
            contact_name="John Smith",
            phone="+1-555-0100",
            email="sales@techsupply.com",
        )
        sup_pack = SupplierModel(
            id=uuid.uuid4(),
            name="PackagePro Ltd",
            contact_name="Sarah Johnson",
            phone="+1-555-0200",
            email="orders@packagepro.com",
        )
        db.add_all([sup_tech, sup_pack])
        await db.flush()

        # ── Create products ──────────────────────────────────────
        products_data = [
            {
                "barcode": "4901234567890",
                "name": "Arduino Uno R3",
                "sku": "ARD-UNO-R3",
                "category_id": cat_electronics.id,
                "supplier_id": sup_tech.id,
                "unit": "pcs",
                "cost_price": 18.50,
                "sell_price": 27.99,
            },
            {
                "barcode": "5901234567891",
                "name": "Raspberry Pi 4 Model B",
                "sku": "RPI-4B-4GB",
                "category_id": cat_electronics.id,
                "supplier_id": sup_tech.id,
                "unit": "pcs",
                "cost_price": 45.00,
                "sell_price": 74.99,
            },
            {
                "barcode": "6901234567892",
                "name": "Copper Wire 22AWG (100m)",
                "sku": "CW-22-100M",
                "category_id": cat_raw.id,
                "supplier_id": sup_tech.id,
                "unit": "rolls",
                "cost_price": 12.00,
                "sell_price": 19.99,
            },
            {
                "barcode": "7901234567893",
                "name": "Cardboard Box 30x30x30cm",
                "sku": "BOX-30CM-STD",
                "category_id": cat_packaging.id,
                "supplier_id": sup_pack.id,
                "unit": "pcs",
                "cost_price": 0.85,
                "sell_price": 1.50,
            },
            {
                "barcode": "8901234567894",
                "name": "Bubble Wrap Roll (50m)",
                "sku": "BW-50M-STD",
                "category_id": cat_packaging.id,
                "supplier_id": sup_pack.id,
                "unit": "rolls",
                "cost_price": 8.50,
                "sell_price": 14.99,
            },
        ]

        product_models = []
        for pd in products_data:
            product = ProductModel(
                id=uuid.uuid4(),
                barcode=pd["barcode"],
                name=pd["name"],
                sku=pd["sku"],
                category_id=pd["category_id"],
                supplier_id=pd["supplier_id"],
                unit=pd["unit"],
                cost_price=pd["cost_price"],
                sell_price=pd["sell_price"],
            )
            db.add(product)
            product_models.append(product)

        await db.flush()

        # ── Create inventory records ─────────────────────────────
        stock_levels = [
            (100, 10, 500),   # Arduino — healthy stock
            (25, 5, 200),     # Raspberry Pi — moderate
            (3, 10, 100),     # Copper Wire — LOW STOCK (below min)
            (500, 50, 2000),  # Boxes — healthy
            (0, 5, 100),      # Bubble Wrap — OUT OF STOCK
        ]

        for i, product in enumerate(product_models):
            qty, min_qty, max_qty = stock_levels[i]

            # Warehouse inventory
            db.add(InventoryModel(
                id=uuid.uuid4(),
                product_id=product.id,
                location_id=loc_warehouse.id,
                quantity=qty,
                min_quantity=min_qty,
                max_quantity=max_qty,
                version=0,
                updated_at=datetime.now(timezone.utc),
            ))

            # Store inventory (half of warehouse stock)
            store_qty = max(0, qty // 2)
            db.add(InventoryModel(
                id=uuid.uuid4(),
                product_id=product.id,
                location_id=loc_store.id,
                quantity=store_qty,
                min_quantity=min_qty // 2,
                max_quantity=max_qty // 2,
                version=0,
                updated_at=datetime.now(timezone.utc),
            ))

        await db.commit()
        print("  ✅ Seed data created successfully!")
        print("  📧 Admin login: admin@inventory.app / admin123")
        print("  📧 Staff login: staff@inventory.app / staff123")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(seed())
