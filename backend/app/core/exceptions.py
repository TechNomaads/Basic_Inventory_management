"""
Module: exceptions
Description: Custom HTTP exception subclasses for consistent error responses.

Responsibilities:
    - Provide semantically named exceptions for common error cases
    - Map to correct HTTP status codes automatically
    - Keep error messages consistent across the application

Dependencies:
    - fastapi.HTTPException

Usage:
    raise NotFoundException("Product not found")
    raise ForbiddenException("Not assigned to this location")
    raise ConflictException("Version conflict — refresh and retry")
"""

from fastapi import HTTPException, status


class NotFoundException(HTTPException):
    """Raised when a requested resource does not exist (HTTP 404)."""

    def __init__(self, detail: str = "Resource not found") -> None:
        super().__init__(status_code=status.HTTP_404_NOT_FOUND, detail=detail)


class ForbiddenException(HTTPException):
    """Raised when the user lacks permission for the action (HTTP 403)."""

    def __init__(self, detail: str = "Forbidden") -> None:
        super().__init__(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


class UnauthorizedException(HTTPException):
    """Raised when authentication fails or token is invalid (HTTP 401)."""

    def __init__(self, detail: str = "Could not validate credentials") -> None:
        super().__init__(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=detail,
            headers={"WWW-Authenticate": "Bearer"},
        )


class ConflictException(HTTPException):
    """Raised on optimistic lock conflicts or duplicate entries (HTTP 409)."""

    def __init__(self, detail: str = "Conflict — resource has been modified") -> None:
        super().__init__(status_code=status.HTTP_409_CONFLICT, detail=detail)


class BadRequestException(HTTPException):
    """Raised when the request payload is invalid (HTTP 400)."""

    def __init__(self, detail: str = "Bad request") -> None:
        super().__init__(status_code=status.HTTP_400_BAD_REQUEST, detail=detail)
