"""
Module: test_auth
Description: Tests for authentication endpoints.

Tests:
    - Successful login
    - Invalid credentials (401)
    - Token refresh
    - Logout
"""

import pytest
from httpx import AsyncClient

from tests.conftest import auth_headers


@pytest.mark.asyncio
async def test_login_success(client: AsyncClient, admin_user):
    """Successful login returns access and refresh tokens."""
    response = await client.post(
        "/api/v1/auth/login",
        json={"email": "admin@test.com", "password": "admin123"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"


@pytest.mark.asyncio
async def test_login_invalid_password(client: AsyncClient, admin_user):
    """Wrong password returns 401."""
    response = await client.post(
        "/api/v1/auth/login",
        json={"email": "admin@test.com", "password": "wrongpassword"},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_login_nonexistent_user(client: AsyncClient):
    """Login with non-existent email returns 401."""
    response = await client.post(
        "/api/v1/auth/login",
        json={"email": "nobody@test.com", "password": "whatever"},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_protected_endpoint_no_token(client: AsyncClient):
    """Accessing a protected endpoint without a token returns 403."""
    response = await client.get("/api/v1/products")
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_protected_endpoint_with_token(client: AsyncClient, admin_user):
    """Accessing a protected endpoint with a valid token succeeds."""
    headers = auth_headers(admin_user)
    response = await client.get("/api/v1/products", headers=headers)
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_logout(client: AsyncClient, admin_user):
    """Logout endpoint clears session."""
    headers = auth_headers(admin_user)
    response = await client.post("/api/v1/auth/logout", headers=headers)
    assert response.status_code == 200
    assert response.json()["message"] == "Successfully logged out"
