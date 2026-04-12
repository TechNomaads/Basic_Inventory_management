"""
Module: auth_service
Description: Authentication business logic — login, token management, logout.

Responsibilities:
    - Validate credentials and issue JWT token pair
    - Refresh access tokens using stored refresh tokens
    - Logout by clearing Redis-stored refresh token
    - Update last_login timestamp on successful authentication

Dependencies:
    - app.core.security (JWT, password hashing)
    - app.core.redis_client (refresh token storage)
    - app.repositories.user_repo
"""

from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import BadRequestException, UnauthorizedException
from app.core.redis_client import (
    delete_refresh_token,
    get_refresh_token,
    store_refresh_token,
)
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    verify_password,
)
from app.repositories.user_repo import user_repo
from app.schemas.auth import TokenResponse


async def login(db: AsyncSession, email: str, password: str) -> TokenResponse:
    """
    Authenticate a user and return a JWT token pair.

    Args:
        db: Async database session.
        email: User's email address.
        password: Plain-text password to verify.

    Returns:
        TokenResponse with access and refresh tokens.

    Raises:
        UnauthorizedException: If credentials are invalid or user is deactivated.
    """
    user = await user_repo.get_by_email(db, email)

    if user is None or not verify_password(password, user.password_hash):
        raise UnauthorizedException("Invalid email or password")

    if not user.is_active:
        raise UnauthorizedException("Account is deactivated")

    # Issue tokens
    access_token = create_access_token(
        data={"sub": str(user.id), "role": user.role.value}
    )
    refresh_token = create_refresh_token(user.id)

    # Store refresh token in Redis
    await store_refresh_token(user.id, refresh_token)

    # Update last login
    user.last_login = datetime.now(timezone.utc)
    await db.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
    )


async def refresh_tokens(db: AsyncSession, refresh_token_str: str) -> TokenResponse:
    """
    Exchange a valid refresh token for a new token pair.

    Args:
        db: Async database session.
        refresh_token_str: The JWT refresh token string.

    Returns:
        New TokenResponse with fresh access and refresh tokens.

    Raises:
        UnauthorizedException: If the refresh token is invalid, expired,
            or doesn't match the stored token.
    """
    try:
        payload = decode_token(refresh_token_str)
        user_id_str = payload.get("sub")
        token_type = payload.get("type")

        if not user_id_str or token_type != "refresh":
            raise UnauthorizedException("Invalid refresh token")

    except Exception:
        raise UnauthorizedException("Invalid or expired refresh token")

    from uuid import UUID
    user_id = UUID(user_id_str)

    # Verify the token matches what's stored in Redis
    stored_token = await get_refresh_token(user_id)
    if stored_token != refresh_token_str:
        raise UnauthorizedException("Refresh token has been revoked")

    # Fetch user to ensure they still exist and are active
    user = await user_repo.get_by_id_with_locations(db, user_id)
    if user is None or not user.is_active:
        raise UnauthorizedException("User not found or deactivated")

    # Issue new token pair
    new_access = create_access_token(
        data={"sub": str(user.id), "role": user.role.value}
    )
    new_refresh = create_refresh_token(user.id)

    # Replace stored refresh token (rotation)
    await store_refresh_token(user.id, new_refresh)

    return TokenResponse(
        access_token=new_access,
        refresh_token=new_refresh,
    )


async def logout(user_id) -> None:
    """
    Log out a user by deleting their refresh token from Redis.

    Args:
        user_id: UUID of the user to log out.
    """
    await delete_refresh_token(user_id)
