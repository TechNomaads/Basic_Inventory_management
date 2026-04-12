"""
Module: auth schemas
Description: Pydantic v2 models for authentication endpoints.

Responsibilities:
    - Validate login request payload
    - Shape token response (access + refresh tokens)
    - Validate refresh token request

Dependencies:
    - pydantic
"""

from pydantic import BaseModel, EmailStr, Field


class LoginRequest(BaseModel):
    """Request body for POST /auth/login."""
    email: EmailStr = Field(..., description="User email address")
    password: str = Field(..., min_length=6, description="Plain-text password")


class TokenResponse(BaseModel):
    """Response body containing JWT access and refresh tokens."""
    access_token: str = Field(..., description="Short-lived JWT access token")
    refresh_token: str = Field(..., description="Long-lived JWT refresh token")
    token_type: str = Field(default="bearer", description="Token type (always 'bearer')")


class RefreshRequest(BaseModel):
    """Request body for POST /auth/refresh."""
    refresh_token: str = Field(..., description="The refresh token to exchange for a new pair")
