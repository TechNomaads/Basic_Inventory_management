"""
Module: user schemas
Description: Pydantic v2 models for user management endpoints.

Responsibilities:
    - Validate user creation and update payloads
    - Shape user response (never includes password_hash)
    - Handle role and location assignment

Dependencies:
    - pydantic
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


class UserCreate(BaseModel):
    """Request body for POST /users."""
    name: str = Field(..., min_length=1, max_length=120)
    email: EmailStr
    password: str = Field(..., min_length=6, max_length=128)
    role: str = Field(default="staff", description="One of: admin, manager, staff, viewer")
    location_ids: list[UUID] = Field(default_factory=list, description="Assigned location UUIDs")


class UserUpdate(BaseModel):
    """Request body for PUT /users/{id}."""
    name: str | None = Field(None, min_length=1, max_length=120)
    email: EmailStr | None = None
    role: str | None = None
    is_active: bool | None = None


class UserLocationUpdate(BaseModel):
    """Request body for PUT /users/{id}/locations."""
    location_ids: list[UUID] = Field(..., description="New list of assigned location UUIDs")


class UserResponse(BaseModel):
    """Response model for user data — never includes password_hash."""
    id: UUID
    name: str
    email: str
    role: str
    is_active: bool
    last_login: datetime | None = None
    created_at: datetime
    location_ids: list[UUID] = Field(default_factory=list)

    model_config = {"from_attributes": True}
