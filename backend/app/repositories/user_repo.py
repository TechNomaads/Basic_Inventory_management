"""
Module: user_repo
Description: Repository for user database operations.

Responsibilities:
    - Find user by email for authentication
    - Manage user_locations junction records
    - List users with role filtering

Dependencies:
    - app.repositories.base.BaseRepository
    - app.models.user
"""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.user import UserLocationModel, UserModel
from app.repositories.base import BaseRepository


class UserRepository(BaseRepository[UserModel]):
    """Async repository for User CRUD and lookup operations."""

    def __init__(self) -> None:
        super().__init__(UserModel)

    async def get_by_email(self, db: AsyncSession, email: str) -> UserModel | None:
        """
        Find a user by their email address.

        Args:
            db: Async database session.
            email: Email string to search.

        Returns:
            UserModel if found, None otherwise.
        """
        stmt = (
            select(UserModel)
            .where(UserModel.email == email)
            .options(selectinload(UserModel.user_locations))
        )
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_id_with_locations(
        self, db: AsyncSession, user_id: UUID
    ) -> UserModel | None:
        """
        Fetch a user with their assigned locations eagerly loaded.

        Args:
            db: Async database session.
            user_id: UUID of the user.

        Returns:
            UserModel with user_locations populated, or None.
        """
        stmt = (
            select(UserModel)
            .where(UserModel.id == user_id)
            .options(selectinload(UserModel.user_locations))
        )
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    async def set_user_locations(
        self, db: AsyncSession, user_id: UUID, location_ids: list[UUID]
    ) -> None:
        """
        Replace a user's location assignments.

        Deletes all existing assignments and creates new ones
        for the provided location_ids.

        Args:
            db: Async database session.
            user_id: UUID of the user.
            location_ids: New list of location UUIDs to assign.
        """
        # Remove existing assignments
        user = await self.get_by_id_with_locations(db, user_id)
        if user is None:
            return

        user.user_locations.clear()
        await db.flush()

        # Create new assignments
        for loc_id in location_ids:
            assignment = UserLocationModel(user_id=user_id, location_id=loc_id)
            db.add(assignment)

        await db.commit()

    async def get_active_user_count(self, db: AsyncSession) -> int:
        """
        Count users who have logged in (last_login is not null and is_active).

        Args:
            db: Async database session.

        Returns:
            Count of active users.
        """
        from sqlalchemy import func

        stmt = select(func.count()).select_from(UserModel).where(
            UserModel.is_active.is_(True),
            UserModel.last_login.isnot(None),
        )
        result = await db.execute(stmt)
        return result.scalar_one()


# Singleton instance
user_repo = UserRepository()
