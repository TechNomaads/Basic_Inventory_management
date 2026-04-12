"""
Module: test_products
Description: Tests for product CRUD and barcode lookup.

Tests:
    - Create product
    - Barcode lookup
    - Search
    - Role enforcement (staff can't create)
"""

import pytest
from httpx import AsyncClient

from tests.conftest import auth_headers


@pytest.mark.asyncio
async def test_create_product(client: AsyncClient, admin_user):
    """Admin can create a product."""
    headers = auth_headers(admin_user)
    response = await client.post(
        "/api/v1/products",
        json={
            "barcode": "PROD-001",
            "name": "Widget Alpha",
            "sku": "WGA-001",
            "unit": "pcs",
            "cost_price": 10.50,
            "sell_price": 15.99,
        },
        headers=headers,
    )
    assert response.status_code == 201
    data = response.json()
    assert data["barcode"] == "PROD-001"
    assert data["name"] == "Widget Alpha"


@pytest.mark.asyncio
async def test_barcode_lookup(client: AsyncClient, admin_user):
    """Look up a product by its barcode."""
    headers = auth_headers(admin_user)

    # First create
    await client.post(
        "/api/v1/products",
        json={
            "barcode": "SCAN-001",
            "name": "Scanner Test Product",
            "sku": "STP-001",
        },
        headers=headers,
    )

    # Then look up
    response = await client.get("/api/v1/products/SCAN-001", headers=headers)
    assert response.status_code == 200
    assert response.json()["barcode"] == "SCAN-001"


@pytest.mark.asyncio
async def test_barcode_not_found(client: AsyncClient, admin_user):
    """Unknown barcode returns 404."""
    headers = auth_headers(admin_user)
    response = await client.get("/api/v1/products/NONEXISTENT", headers=headers)
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_staff_cannot_create_product(client: AsyncClient, staff_user):
    """Staff role is forbidden from creating products."""
    headers = auth_headers(staff_user)
    response = await client.post(
        "/api/v1/products",
        json={
            "barcode": "DENIED-001",
            "name": "Blocked Product",
            "sku": "BLK-001",
        },
        headers=headers,
    )
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_search_products(client: AsyncClient, admin_user):
    """Search returns matching products."""
    headers = auth_headers(admin_user)

    # Create test products
    for i in range(3):
        await client.post(
            "/api/v1/products",
            json={
                "barcode": f"SEARCH-{i:03d}",
                "name": f"Searchable Item {i}",
                "sku": f"SRC-{i:03d}",
            },
            headers=headers,
        )

    # Search
    response = await client.get(
        "/api/v1/products?search=Searchable", headers=headers
    )
    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 3
    assert len(data["items"]) == 3
