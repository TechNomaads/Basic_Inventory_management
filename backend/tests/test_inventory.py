"""
Module: test_inventory
Description: Tests for inventory operations including optimistic locking.

Tests:
    - Stock transaction with valid version
    - Optimistic lock conflict (409)
    - Adjustment below threshold (direct apply)
    - Adjustment above threshold (pending)
"""

import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.inventory import InventoryModel
from app.models.location import LocationModel
from app.models.product import ProductModel
from tests.conftest import auth_headers


async def _create_test_product_and_inventory(
    db_session: AsyncSession,
) -> tuple:
    """Helper to create a product, location, and inventory record."""
    location = LocationModel(
        id=uuid.uuid4(),
        name="Warehouse A",
        code="WH-A",
        type="warehouse",
    )
    db_session.add(location)

    product = ProductModel(
        id=uuid.uuid4(),
        barcode="TEST-BARCODE-001",
        name="Test Widget",
        sku="TST-001",
        unit="pcs",
    )
    db_session.add(product)
    await db_session.flush()

    inventory = InventoryModel(
        id=uuid.uuid4(),
        product_id=product.id,
        location_id=location.id,
        quantity=100,
        min_quantity=10,
        version=0,
    )
    db_session.add(inventory)
    await db_session.commit()

    return product, location, inventory


@pytest.mark.asyncio
async def test_stock_transaction_success(
    client: AsyncClient, db_session: AsyncSession, admin_user
):
    """Valid stock transaction updates quantity and increments version."""
    product, location, inventory = await _create_test_product_and_inventory(
        db_session
    )
    headers = auth_headers(admin_user)

    response = await client.post(
        "/api/v1/inventory/transaction",
        json={
            "product_id": str(product.id),
            "location_id": str(location.id),
            "type": "receive",
            "quantity_change": 50,
            "known_version": 0,
            "notes": "Test stock in",
        },
        headers=headers,
    )
    assert response.status_code == 200
    data = response.json()
    assert data["quantity_after"] == 150


@pytest.mark.asyncio
async def test_optimistic_lock_conflict(
    client: AsyncClient, db_session: AsyncSession, admin_user
):
    """Stale version triggers HTTP 409 Conflict."""
    product, location, inventory = await _create_test_product_and_inventory(
        db_session
    )
    headers = auth_headers(admin_user)

    # First transaction succeeds (version 0 → 1)
    await client.post(
        "/api/v1/inventory/transaction",
        json={
            "product_id": str(product.id),
            "location_id": str(location.id),
            "type": "receive",
            "quantity_change": 10,
            "known_version": 0,
        },
        headers=headers,
    )

    # Second transaction with stale version 0 → 409
    response = await client.post(
        "/api/v1/inventory/transaction",
        json={
            "product_id": str(product.id),
            "location_id": str(location.id),
            "type": "dispatch",
            "quantity_change": -5,
            "known_version": 0,  # stale!
        },
        headers=headers,
    )
    assert response.status_code == 409


@pytest.mark.asyncio
async def test_adjustment_below_threshold(
    client: AsyncClient, db_session: AsyncSession, admin_user
):
    """Adjustment ≤ threshold is applied directly."""
    product, location, inventory = await _create_test_product_and_inventory(
        db_session
    )
    headers = auth_headers(admin_user)

    response = await client.post(
        "/api/v1/inventory/adjustment",
        json={
            "product_id": str(product.id),
            "location_id": str(location.id),
            "quantity_change": 5,  # within default threshold of 10
            "known_version": 0,
            "notes": "Minor adjustment",
        },
        headers=headers,
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "applied"


@pytest.mark.asyncio
async def test_adjustment_above_threshold(
    client: AsyncClient, db_session: AsyncSession, admin_user
):
    """Adjustment > threshold goes to pending."""
    product, location, inventory = await _create_test_product_and_inventory(
        db_session
    )
    headers = auth_headers(admin_user)

    response = await client.post(
        "/api/v1/inventory/adjustment",
        json={
            "product_id": str(product.id),
            "location_id": str(location.id),
            "quantity_change": 50,  # exceeds default threshold of 10
            "known_version": 0,
            "notes": "Large adjustment",
        },
        headers=headers,
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "pending"
    assert "pending_id" in data
