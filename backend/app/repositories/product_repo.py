"""
Module: product_repo
Description: Repository for product database operations.

Responsibilities:
    - Barcode lookup (primary scan endpoint)
    - Search by name, SKU, barcode with filtering
    - Paginated product listing with category/location filters

Dependencies:
    - app.repositories.base.BaseRepository
    - app.models.product
"""

from uuid import UUID

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.product import ProductModel
from app.repositories.base import BaseRepository


class ProductRepository(BaseRepository[ProductModel]):
    """Async repository for Product CRUD and search operations."""

    def __init__(self) -> None:
        super().__init__(ProductModel)

    async def get_by_barcode(self, db: AsyncSession, barcode: str) -> ProductModel | None:
        """
        Find a product by its barcode — the primary scan lookup.

        Args:
            db: Async database session.
            barcode: Barcode string scanned by the mobile app.

        Returns:
            ProductModel if found, None otherwise.
        """
        stmt = select(ProductModel).where(
            ProductModel.barcode == barcode,
            ProductModel.is_active.is_(True),
        )
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    async def search(
        self,
        db: AsyncSession,
        query: str | None = None,
        category_id: UUID | None = None,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[ProductModel], int]:
        """
        Search products with optional text query and category filter.

        The text query is matched against name, SKU, and barcode
        using case-insensitive ILIKE.

        Args:
            db: Async database session.
            query: Optional search text.
            category_id: Optional category UUID filter.
            page: Page number (1-indexed).
            size: Items per page.

        Returns:
            Tuple of (matching products, total count).
        """
        base_stmt = select(ProductModel).where(ProductModel.is_active.is_(True))
        count_base = select(func.count()).select_from(ProductModel).where(
            ProductModel.is_active.is_(True)
        )

        # Apply text search filter
        if query:
            search_filter = or_(
                ProductModel.name.ilike(f"%{query}%"),
                ProductModel.sku.ilike(f"%{query}%"),
                ProductModel.barcode.ilike(f"%{query}%"),
            )
            base_stmt = base_stmt.where(search_filter)
            count_base = count_base.where(search_filter)

        # Apply category filter
        if category_id:
            base_stmt = base_stmt.where(ProductModel.category_id == category_id)
            count_base = count_base.where(ProductModel.category_id == category_id)

        # Count total
        total_result = await db.execute(count_base)
        total = total_result.scalar_one()

        # Fetch page
        offset = (page - 1) * size
        stmt = base_stmt.order_by(ProductModel.name).offset(offset).limit(size)
        result = await db.execute(stmt)
        items = list(result.scalars().all())

        return items, total

    async def get_active_count(self, db: AsyncSession) -> int:
        """
        Count all active products.

        Args:
            db: Async database session.

        Returns:
            Integer count.
        """
        stmt = select(func.count()).select_from(ProductModel).where(
            ProductModel.is_active.is_(True)
        )
        result = await db.execute(stmt)
        return result.scalar_one()


# Singleton instance
product_repo = ProductRepository()
