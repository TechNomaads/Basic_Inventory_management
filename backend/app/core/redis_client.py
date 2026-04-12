"""
Module: redis_client
Description: Redis connection manager for refresh token storage.

Responsibilities:
    - Create and manage the Redis connection pool
    - Store, retrieve, and delete refresh tokens keyed by user_id
    - Set TTL matching the refresh token expiry

Dependencies:
    - redis[hiredis]
    - app.core.config.settings

Usage:
    await store_refresh_token(user_id, token)
    stored = await get_refresh_token(user_id)
    await delete_refresh_token(user_id)
"""

from uuid import UUID

import redis.asyncio as aioredis

from app.core.config import settings

# ── Redis connection pool ────────────────────────────────────────
redis_pool = aioredis.ConnectionPool.from_url(
    settings.REDIS_URL,
    decode_responses=True,
)
redis_client = aioredis.Redis(connection_pool=redis_pool)

# TTL for refresh tokens in seconds (7 days default)
REFRESH_TOKEN_TTL = settings.REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60


async def store_refresh_token(user_id: UUID, token: str) -> None:
    """
    Store a refresh token in Redis, keyed by user_id.

    Any previous token for the same user is overwritten,
    effectively limiting each user to one active refresh token.

    Args:
        user_id: The user's UUID.
        token: The JWT refresh token string.
    """
    key = f"refresh_token:{user_id}"
    await redis_client.setex(key, REFRESH_TOKEN_TTL, token)


async def get_refresh_token(user_id: UUID) -> str | None:
    """
    Retrieve the stored refresh token for a user.

    Args:
        user_id: The user's UUID.

    Returns:
        The token string if found, None otherwise.
    """
    key = f"refresh_token:{user_id}"
    return await redis_client.get(key)


async def delete_refresh_token(user_id: UUID) -> None:
    """
    Delete a user's refresh token from Redis (logout).

    Args:
        user_id: The user's UUID.
    """
    key = f"refresh_token:{user_id}"
    await redis_client.delete(key)
