"""
Module: inventory_repo
Description: Repository for inventory database operations with optimistic locking.

Responsibilities:
    - Fetch inventory by product+location
    - Optimistic lock stock update (version check)
    - List inventory for a location with low stock detection
    - Count low stock and out-of-stock items

Dependencies:
    - app.repositories.base.BaseRepository
    - app.models.inventory
"""

from uuid import UUID

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.inventory import InventoryModel
from app.repositories.base import BaseRepository


class InventoryRepository(BaseRepository[InventoryModel]):
    """Async repository for Inventory with optimistic concurrency control."""

    def __init__(self) -> None:
        super().__init__(InventoryModel)

    async def get_by_product_location(
        self, db: AsyncSession, product_id: UUID, location_id: UUID
    ) -> InventoryModel | None:
        """
        Fetch the inventory record for a specific product at a specific location.

        Args:
            db: Async database session.
            product_id: UUID of the product.
            location_id: UUID of the location.

        Returns:
            InventoryModel if found, None otherwise.
        """
        stmt = select(InventoryModel).where(
            InventoryModel.product_id == product_id,
            InventoryModel.location_id == location_id,
        )
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    async def update_stock(
        self,
        db: AsyncSession,
        product_id: UUID,
        location_id: UUID,
        delta: int,
        known_version: int,
    ) -> InventoryModel | None:
        """
        Attempt an optimistic-lock stock update.

        The update only succeeds if the current version in the database
        matches known_version. On success, the version is incremented.
        Returns None on version conflict — caller must raise HTTP 409.

        Args:
            db: Async database session.
            product_id: UUID of the product.
            location_id: UUID of the location.
            delta: Quantity change (positive for in, negative for out).
            known_version: The version the client last saw.

        Returns:
            Updated InventoryModel on success, None on version conflict.
        """
        stmt = (
            update(InventoryModel)
            .where(
                InventoryModel.product_id == product_id,
                InventoryModel.location_id == location_id,
                InventoryModel.version == known_version,
            )
            .values(
                quantity=InventoryModel.quantity + delta,
                version=InventoryModel.version + 1,
                updated_at=func.now(),
            )
            .returning(InventoryModel)
        )
        result = await db.execute(stmt)
        await db.commit()
        return result.scalar_one_or_none()

    async def list_by_location(
        self, db: AsyncSession, location_id: UUID
    ) -> list[InventoryModel]:
        """
        List all inventory records for a given location.

        Args:
            db: Async database session.
            location_id: UUID of the location.

        Returns:
            List of InventoryModel instances.
        """
        stmt = select(InventoryModel).where(
            InventoryModel.location_id == location_id
        )
        result = await db.execute(stmt)
        return list(result.scalars().all())

    async def get_low_stock_count(self, db: AsyncSession) -> int:
        """
        Count inventory items where quantity < min_quantity.

        Args:
            db: Async database session.

        Returns:
            Integer count of low-stock items.
        """
        stmt = select(func.count()).select_from(InventoryModel).where(
            InventoryModel.quantity < InventoryModel.min_quantity,
            InventoryModel.min_quantity > 0,
        )
        result = await db.execute(stmt)
        return result.scalar_one()

    async def get_out_of_stock_count(self, db: AsyncSession) -> int:
        """
        Count inventory items where quantity is zero.

        Args:
            db: Async database session.

        Returns:
            Integer count of out-of-stock items.
        """
        stmt = select(func.count()).select_from(InventoryModel).where(
            InventoryModel.quantity <= 0
        )
        result = await db.execute(stmt)
        return result.scalar_one()


# Singleton instance
inventory_repo = InventoryRepository()
