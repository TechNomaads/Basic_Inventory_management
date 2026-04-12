"""
Module: dependencies
Description: FastAPI dependency injection functions for auth and access control.

Responsibilities:
    - get_db: yield an async database session
    - get_current_user: extract and validate JWT from Authorization header
    - require_role: factory that returns a dependency enforcing role membership
    - location_guard: factory that checks user is assigned to a location

Dependencies:
    - fastapi, sqlalchemy
    - app.core.security, app.core.database
    - app.models.user

Usage:
    @router.get("/items")
    async def list_items(user = Depends(get_current_user)):
        ...

    @router.post("/admin")
    async def admin_action(user = Depends(require_role(["admin"]))):
        ...
"""

from uuid import UUID

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_async_session
from app.core.exceptions import ForbiddenException, UnauthorizedException
from app.core.security import decode_token
from app.models.user import UserModel, UserRole

# Bearer token scheme for Swagger UI
bearer_scheme = HTTPBearer()


async def get_db() -> AsyncSession:  # type: ignore[misc]
    """
    Yield an async database session from the pool.

    This is the primary database dependency — inject it
    into any endpoint or service that needs DB access.
    """
    async for session in get_async_session():
        yield session


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> UserModel:
    """
    Extract the JWT from the Authorization header, validate it,
    and return the corresponding UserModel.

    Args:
        credentials: Bearer token extracted by HTTPBearer.
        db: Async database session.

    Returns:
        The authenticated UserModel with user_locations eagerly loaded.

    Raises:
        UnauthorizedException: If the token is invalid, expired, or
            the user does not exist / is deactivated.
    """
    try:
        payload = decode_token(credentials.credentials)
        user_id_str: str | None = payload.get("sub")
        token_type: str | None = payload.get("type")

        if user_id_str is None or token_type != "access":
            raise UnauthorizedException("Invalid token payload")

        user_id = UUID(user_id_str)

    except (JWTError, ValueError) as exc:
        raise UnauthorizedException(f"Token validation failed: {exc}")

    # Fetch the user with their assigned locations in one query
    stmt = (
        select(UserModel)
        .where(UserModel.id == user_id, UserModel.is_active.is_(True))
        .options(selectinload(UserModel.user_locations))
    )
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if user is None:
        raise UnauthorizedException("User not found or deactivated")

    return user


def require_role(allowed_roles: list[str]):
    """
    Factory that creates a FastAPI dependency enforcing role membership.

    Args:
        allowed_roles: List of role name strings (e.g. ["admin", "manager"]).

    Returns:
        A dependency function that raises ForbiddenException
        if the current user's role is not in the allowed list.

    Usage:
        @router.post("/users", dependencies=[Depends(require_role(["admin"]))])
        async def create_user(...): ...
    """

    async def _role_check(
        current_user: UserModel = Depends(get_current_user),
    ) -> UserModel:
        if current_user.role.value not in allowed_roles:
            raise ForbiddenException(
                f"Role '{current_user.role.value}' is not allowed. "
                f"Required: {allowed_roles}"
            )
        return current_user

    return _role_check


def location_guard(location_id: UUID):
    """
    Factory that creates a FastAPI dependency verifying the user
    is assigned to the requested location.

    Admins and managers bypass the check (unrestricted access).
    Staff and viewers must have the location in their assignments.

    Args:
        location_id: The UUID of the location to guard.

    Returns:
        A dependency function that raises ForbiddenException
        if the user is not assigned to the location.

    Raises:
        ForbiddenException: If a non-admin/manager user tries to
            access a location they are not assigned to.
    """

    async def _guard(
        current_user: UserModel = Depends(get_current_user),
    ) -> None:
        # Admins and managers have unrestricted location access
        if current_user.role in (UserRole.admin, UserRole.manager):
            return

        assigned_ids = [ul.location_id for ul in current_user.user_locations]
        if location_id not in assigned_ids:
            raise ForbiddenException("Not assigned to this location")

    return _guard
