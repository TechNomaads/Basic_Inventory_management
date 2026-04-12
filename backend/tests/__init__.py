"""
Module: conftest
Description: Pytest fixtures for backend test suite.

Responsibilities:
    - Set up test database with SQLite (async)
    - Provide authenticated test client with JWT headers
    - Create test users, products, locations, and inventory fixtures

Dependencies:
    - pytest, pytest-asyncio, httpx
"""

import asyncio
import uuid
from datetime import datetime, timezone

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.database import Base, get_async_session
from app.core.security import create_access_token, hash_password
from app.main import app
from app.models.user import UserModel, UserRole

# ── Test database engine (SQLite async) ──────────────────────────
TEST_DATABASE_URL = "sqlite+aiosqlite:///./test.db"

test_engine = create_async_engine(TEST_DATABASE_URL, echo=False)
test_session_factory = async_sessionmaker(
    bind=test_engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


@pytest_asyncio.fixture(scope="session")
def event_loop():
    """Create a single event loop for the entire test session."""
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest_asyncio.fixture(autouse=True)
async def setup_database():
    """Create all tables before each test and drop them after."""
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


async def _get_test_session() -> AsyncSession:  # type: ignore[misc]
    """Override database dependency with test session."""
    async with test_session_factory() as session:
        yield session


@pytest_asyncio.fixture
async def db_session() -> AsyncSession:
    """Provide a test database session."""
    async with test_session_factory() as session:
        yield session


@pytest_asyncio.fixture
async def client() -> AsyncClient:
    """Provide an async HTTP client bound to the test app."""
    app.dependency_overrides[get_async_session] = _get_test_session
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def admin_user(db_session: AsyncSession) -> UserModel:
    """Create and return a test admin user."""
    user = UserModel(
        id=uuid.uuid4(),
        name="Test Admin",
        email="admin@test.com",
        password_hash=hash_password("admin123"),
        role=UserRole.admin,
        is_active=True,
        created_at=datetime.now(timezone.utc),
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


@pytest_asyncio.fixture
async def staff_user(db_session: AsyncSession) -> UserModel:
    """Create and return a test staff user."""
    user = UserModel(
        id=uuid.uuid4(),
        name="Test Staff",
        email="staff@test.com",
        password_hash=hash_password("staff123"),
        role=UserRole.staff,
        is_active=True,
        created_at=datetime.now(timezone.utc),
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


def auth_headers(user: UserModel) -> dict[str, str]:
    """Generate Bearer auth headers for a given user."""
    token = create_access_token(
        data={"sub": str(user.id), "role": user.role.value}
    )
    return {"Authorization": f"Bearer {token}"}
