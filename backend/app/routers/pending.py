"""
Module: pending router
Description: API endpoints for managing pending stock adjustments.

Responsibilities:
    - GET /pending           → list pending adjustments (manager/admin)
    - POST /pending/{id}/approve → approve a pending adjustment
    - POST /pending/{id}/reject  → reject a pending adjustment

Dependencies:
    - app.services.inventory_service
    - app.core.dependencies
"""

from uuid import UUID

from fastapi import APIRouter, Depends, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_db, require_role
from app.models.pending_adjustment import AdjustmentStatus, PendingAdjustmentModel
from app.models.user import UserModel
from app.schemas.inventory import PendingAdjustmentResponse
from app.services import inventory_service

router = APIRouter(prefix="/api/v1/pending", tags=["Pending Adjustments"])


@router.get("", response_model=list[PendingAdjustmentResponse])
async def list_pending(
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(require_role(["admin", "manager"])),
) -> list[PendingAdjustmentResponse]:
    """
    List all pending adjustments awaiting approval.

    Only accessible by managers and admins.

    Returns:
        List of PendingAdjustmentResponse.
    """
    stmt = (
        select(PendingAdjustmentModel)
        .where(PendingAdjustmentModel.status == AdjustmentStatus.pending)
        .order_by(PendingAdjustmentModel.created_at.desc())
    )
    result = await db.execute(stmt)
    items = result.scalars().all()

    return [
        PendingAdjustmentResponse(
            id=item.id,
            product_id=item.product_id,
            product_name=item.product.name if item.product else "Unknown",
            location_id=item.location_id,
            location_name=item.location.name if item.location else "Unknown",
            user_id=item.user_id,
            user_name=item.user.name if item.user else "Unknown",
            quantity_change=item.quantity_change,
            notes=item.notes,
            status=item.status.value,
            reviewed_by=item.reviewed_by,
            reviewer_name=item.reviewer.name if item.reviewer else None,
            reviewed_at=item.reviewed_at,
            created_at=item.created_at,
        )
        for item in items
    ]


@router.post("/{adjustment_id}/approve")
async def approve_adjustment(
    adjustment_id: UUID,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: UserModel = Depends(require_role(["admin", "manager"])),
) -> dict:
    """
    Approve a pending adjustment and apply the stock change.

    Args:
        adjustment_id: UUID of the pending adjustment.

    Returns:
        Confirmation dict.

    Raises:
        HTTPException 404: If adjustment not found.
        HTTPException 400: If already processed.
    """
    return await inventory_service.approve_adjustment(
        db, adjustment_id, current_user.id,
        request.client.host if request.client else None,
    )


@router.post("/{adjustment_id}/reject")
async def reject_adjustment(
    adjustment_id: UUID,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: UserModel = Depends(require_role(["admin", "manager"])),
) -> dict:
    """
    Reject a pending adjustment without applying stock changes.

    Args:
        adjustment_id: UUID of the pending adjustment.

    Returns:
        Confirmation dict.

    Raises:
        HTTPException 404: If adjustment not found.
        HTTPException 400: If already processed.
    """
    return await inventory_service.reject_adjustment(
        db, adjustment_id, current_user.id,
        request.client.host if request.client else None,
    )
