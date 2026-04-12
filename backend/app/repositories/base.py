"""
Module: base repository
Description: Generic async CRUD base class for SQLAlchemy models.

Responsibilities:
    - Provide reusable get, list, create, update, delete methods
    - Handle pagination logic
    - Serve as parent class for all domain repositories

Dependencies:
    - sqlalchemy.ext.asyncio.AsyncSession

Usage:
    class ProductRepo(BaseRepository[ProductModel]):
        def __init__(self):
            super().__init__(ProductModel)
"""

from typing import Generic, TypeVar
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import Base

ModelType = TypeVar("ModelType", bound=Base)


class BaseRepository(Generic[ModelType]):
    """
    Generic async CRUD repository.

    Provides standard database operations that can be inherited
    and extended by domain-specific repositories.
    """

    def __init__(self, model: type[ModelType]) -> None:
        self.model = model

    async def get_by_id(self, db: AsyncSession, record_id: UUID) -> ModelType | None:
        """
        Fetch a single record by its primary key.

        Args:
            db: Async database session.
            record_id: UUID primary key.

        Returns:
            The model instance, or None if not found.
        """
        stmt = select(self.model).where(self.model.id == record_id)
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_all(
        self,
        db: AsyncSession,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[ModelType], int]:
        """
        Fetch a paginated list of all records.

        Args:
            db: Async database session.
            page: Page number (1-indexed).
            size: Items per page.

        Returns:
            Tuple of (list of model instances, total count).
        """
        # Count total
        count_stmt = select(func.count()).select_from(self.model)
        total_result = await db.execute(count_stmt)
        total = total_result.scalar_one()

        # Fetch page
        offset = (page - 1) * size
        stmt = select(self.model).offset(offset).limit(size)
        result = await db.execute(stmt)
        items = list(result.scalars().all())

        return items, total

    async def create(self, db: AsyncSession, obj: ModelType) -> ModelType:
        """
        Insert a new record into the database.

        Args:
            db: Async database session.
            obj: The model instance to persist.

        Returns:
            The persisted model instance with generated fields (id, timestamps).
        """
        db.add(obj)
        await db.commit()
        await db.refresh(obj)
        return obj

    async def update(self, db: AsyncSession, obj: ModelType) -> ModelType:
        """
        Persist changes to an existing record.

        Args:
            db: Async database session.
            obj: The modified model instance.

        Returns:
            The updated model instance.
        """
        await db.commit()
        await db.refresh(obj)
        return obj

    async def delete(self, db: AsyncSession, obj: ModelType) -> None:
        """
        Delete a record from the database.

        Args:
            db: Async database session.
            obj: The model instance to delete.
        """
        await db.delete(obj)
        await db.commit()
