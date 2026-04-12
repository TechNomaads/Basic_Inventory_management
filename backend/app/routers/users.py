"""
Module: users router
Description: API endpoints for user management (admin only).

Responsibilities:
    - GET /users           → list all users
    - POST /users          → create a new user
    - PUT /users/{id}/role → update user role
    - PUT /users/{id}/locations → update location assignments
    - DELETE /users/{id}   → soft delete (deactivate)

Dependencies:
    - app.repositories.user_repo
    - app.core.dependencies
    - app.services.audit_service
"""

from uuid import UUID

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_db, require_role
from app.core.exceptions import NotFoundException
from app.core.security import hash_password
from app.models.audit_log import AuditAction
from app.models.user import UserLocationModel, UserModel, UserRole
from app.repositories.user_repo import user_repo
from app.schemas.user import UserCreate, UserLocationUpdate, UserResponse, UserUpdate
from app.services.audit_service import write_audit_log

router = APIRouter(prefix="/api/v1/users", tags=["Users"])


def _user_to_response(user: UserModel) -> UserResponse:
    """Convert UserModel to UserResponse."""
    return UserResponse(
        id=user.id,
        name=user.name,
        email=user.email,
        role=user.role.value,
        is_active=user.is_active,
        last_login=user.last_login,
        created_at=user.created_at,
        location_ids=[ul.location_id for ul in (user.user_locations or [])],
    )


@router.get("", response_model=list[UserResponse])
async def list_users(
    db: AsyncSession = Depends(get_db),
    _admin: UserModel = Depends(require_role(["admin"])),
) -> list[UserResponse]:
    """
    List all users (admin only).

    Returns:
        List of UserResponse (password hashes are never included).
    """
    users, _ = await user_repo.get_all(db, page=1, size=1000)
    return [_user_to_response(u) for u in users]


@router.post("", response_model=UserResponse, status_code=201)
async def create_user(
    body: UserCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    admin: UserModel = Depends(require_role(["admin"])),
) -> UserResponse:
    """
    Create a new user (admin only).

    Args:
        body: UserCreate with name, email, password, role, location_ids.

    Returns:
        The created UserResponse.
    """
    user = UserModel(
        name=body.name,
        email=body.email,
        password_hash=hash_password(body.password),
        role=UserRole(body.role),
    )
    user = await user_repo.create(db, user)

    # Assign locations
    if body.location_ids:
        await user_repo.set_user_locations(db, user.id, body.location_ids)
        user = await user_repo.get_by_id_with_locations(db, user.id)

    # Audit log
    await write_audit_log(
        db=db,
        user_id=admin.id,
        table_name="users",
        record_id=user.id,
        action=AuditAction.insert,
        new_values={"name": body.name, "email": body.email, "role": body.role},
        ip_address=request.client.host if request.client else None,
    )

    return _user_to_response(user)


@router.put("/{user_id}/role", response_model=UserResponse)
async def update_user_role(
    user_id: UUID,
    body: UserUpdate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    admin: UserModel = Depends(require_role(["admin"])),
) -> UserResponse:
    """
    Update a user's role and/or profile (admin only).

    Args:
        user_id: UUID of the user to update.
        body: Partial update data.

    Returns:
        Updated UserResponse.

    Raises:
        HTTPException 404: If user not found.
    """
    user = await user_repo.get_by_id_with_locations(db, user_id)
    if user is None:
        raise NotFoundException("User not found")

    old_role = user.role.value
    update_data = body.model_dump(exclude_unset=True)

    if "role" in update_data:
        user.role = UserRole(update_data["role"])
    if "name" in update_data:
        user.name = update_data["name"]
    if "email" in update_data:
        user.email = update_data["email"]
    if "is_active" in update_data:
        user.is_active = update_data["is_active"]

    user = await user_repo.update(db, user)

    # Audit log
    await write_audit_log(
        db=db,
        user_id=admin.id,
        table_name="users",
        record_id=user.id,
        action=AuditAction.update,
        old_values={"role": old_role},
        new_values=update_data,
        ip_address=request.client.host if request.client else None,
    )

    return _user_to_response(user)


@router.put("/{user_id}/locations", response_model=UserResponse)
async def update_user_locations(
    user_id: UUID,
    body: UserLocationUpdate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    admin: UserModel = Depends(require_role(["admin"])),
) -> UserResponse:
    """
    Replace a user's location assignments (admin only).

    Args:
        user_id: UUID of the user.
        body: New list of location UUIDs.

    Returns:
        Updated UserResponse with new location_ids.

    Raises:
        HTTPException 404: If user not found.
    """
    user = await user_repo.get_by_id_with_locations(db, user_id)
    if user is None:
        raise NotFoundException("User not found")

    old_locs = [str(ul.location_id) for ul in user.user_locations]
    await user_repo.set_user_locations(db, user_id, body.location_ids)
    user = await user_repo.get_by_id_with_locations(db, user_id)

    # Audit log
    await write_audit_log(
        db=db,
        user_id=admin.id,
        table_name="user_locations",
        record_id=user_id,
        action=AuditAction.update,
        old_values={"location_ids": old_locs},
        new_values={"location_ids": [str(lid) for lid in body.location_ids]},
        ip_address=request.client.host if request.client else None,
    )

    return _user_to_response(user)


@router.delete("/{user_id}", response_model=UserResponse)
async def delete_user(
    user_id: UUID,
    request: Request,
    db: AsyncSession = Depends(get_db),
    admin: UserModel = Depends(require_role(["admin"])),
) -> UserResponse:
    """
    Soft-delete a user by setting is_active=False (admin only).

    Args:
        user_id: UUID of the user to deactivate.

    Returns:
        Deactivated UserResponse.

    Raises:
        HTTPException 404: If user not found.
    """
    user = await user_repo.get_by_id_with_locations(db, user_id)
    if user is None:
        raise NotFoundException("User not found")

    user.is_active = False
    user = await user_repo.update(db, user)

    # Audit log
    await write_audit_log(
        db=db,
        user_id=admin.id,
        table_name="users",
        record_id=user.id,
        action=AuditAction.delete,
        old_values={"is_active": True},
        new_values={"is_active": False},
        ip_address=request.client.host if request.client else None,
    )

    return _user_to_response(user)
