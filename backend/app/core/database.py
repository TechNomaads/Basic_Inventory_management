"""
Module: database
Description: Async SQLAlchemy engine and session factory for PostgreSQL.

Responsibilities:
    - Create the async engine from DATABASE_URL
    - Provide an async session factory for dependency injection
    - Declare the ORM Base class for all models

Dependencies:
    - sqlalchemy[asyncio], asyncpg
    - app.core.config.settings

Usage:
    async with get_async_session() as session:
        result = await session.execute(select(User))
"""

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.core.config import settings

# ── Async engine ─────────────────────────────────────────────────
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    pool_size=20,
    max_overflow=10,
    pool_pre_ping=True,
)

# ── Session factory ──────────────────────────────────────────────
async_session_factory = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


# ── Declarative base for all ORM models ─────────────────────────
class Base(DeclarativeBase):
    """Base class for all SQLAlchemy ORM models."""
    pass


async def get_async_session() -> AsyncSession:  # type: ignore[misc]
    """
    FastAPI dependency that yields an async database session.

    The session is automatically closed after the request completes.
    Callers should commit explicitly when mutations succeed.
    """
    async with async_session_factory() as session:
        yield session
