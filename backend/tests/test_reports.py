"""
Module: test_reports
Description: Tests for reporting endpoints.

Tests:
    - Summary endpoint returns expected metrics
    - Transaction history returns filtered results
"""

import pytest
from httpx import AsyncClient

from tests.conftest import auth_headers


@pytest.mark.asyncio
async def test_summary_endpoint(client: AsyncClient, admin_user):
    """Summary endpoint returns all expected fields."""
    headers = auth_headers(admin_user)
    response = await client.get("/api/v1/reports/summary", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert "total_products" in data
    assert "low_stock_count" in data
    assert "todays_scans" in data
    assert "pending_adjustments" in data
    assert "total_dispatched" in data
    assert "total_received" in data
    assert "out_of_stock_count" in data
    assert "active_users" in data


@pytest.mark.asyncio
async def test_transactions_endpoint(client: AsyncClient, admin_user):
    """Transaction history endpoint returns paginated results."""
    headers = auth_headers(admin_user)
    response = await client.get(
        "/api/v1/reports/transactions?page=1&size=10",
        headers=headers,
    )
    assert response.status_code == 200
    data = response.json()
    assert "items" in data
    assert "total" in data
    assert "page" in data
    assert "size" in data
    assert "pages" in data


@pytest.mark.asyncio
async def test_health_check(client: AsyncClient):
    """Health check endpoint is public."""
    response = await client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
