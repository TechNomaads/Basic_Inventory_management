"""
Module: auth router
Description: API endpoints for authentication (login, refresh, logout).

Responsibilities:
    - POST /auth/login    → authenticate and issue tokens
    - POST /auth/refresh  → exchange refresh token for new pair
    - POST /auth/logout   → invalidate refresh token

Dependencies:
    - app.services.auth_service
    - app.core.dependencies
"""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_current_user, get_db
from app.models.user import UserModel
from app.schemas.auth import LoginRequest, RefreshRequest, TokenResponse
from app.services import auth_service

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])


@router.post("/login", response_model=TokenResponse)
async def login(
    body: LoginRequest,
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    """
    Authenticate with email and password, receive JWT token pair.

    Args:
        body: LoginRequest with email and password.
        db: Async database session.

    Returns:
        TokenResponse with access_token, refresh_token, token_type.

    Raises:
        HTTPException 401: If credentials are invalid.
    """
    return await auth_service.login(db, body.email, body.password)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(
    body: RefreshRequest,
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    """
    Exchange a valid refresh token for a new token pair.

    The old refresh token is invalidated (rotation).

    Args:
        body: RefreshRequest with the refresh_token.
        db: Async database session.

    Returns:
        New TokenResponse.

    Raises:
        HTTPException 401: If the refresh token is invalid or revoked.
    """
    return await auth_service.refresh_tokens(db, body.refresh_token)


@router.post("/logout")
async def logout(
    current_user: UserModel = Depends(get_current_user),
) -> dict:
    """
    Log out the current user by clearing their refresh token.

    Args:
        current_user: The authenticated user (from JWT).

    Returns:
        Confirmation message.
    """
    await auth_service.logout(current_user.id)
    return {"message": "Successfully logged out"}
