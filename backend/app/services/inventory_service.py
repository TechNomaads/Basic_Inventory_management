"""
Module: inventory_service
Description: Business logic for stock transactions and adjustments.

Responsibilities:
    - Execute stock in/out with optimistic locking
    - Route large adjustments to pending queue
    - Emit Socket.io events after successful updates
    - Record stock transactions and audit logs

Dependencies:
    - app.repositories.inventory_repo
    - app.repositories.transaction_repo
    - app.services.audit_service
    - app.sockets.events (Socket.io emit)
"""

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.exceptions import ConflictException, NotFoundException
from app.models.audit_log import AuditAction
from app.models.pending_adjustment import AdjustmentStatus, PendingAdjustmentModel
from app.models.stock_transaction import StockTransactionModel, TransactionType
from app.repositories.inventory_repo import inventory_repo
from app.repositories.transaction_repo import transaction_repo
from app.schemas.inventory import AdjustmentRequest, TransactionRequest
from app.services.audit_service import write_audit_log


async def process_transaction(
    db: AsyncSession,
    data: TransactionRequest,
    user_id: UUID,
    ip_address: str | None = None,
) -> StockTransactionModel:
    """
    Process a stock transaction with optimistic locking.

    Steps:
        1. Fetch current inventory to get quantity_before
        2. Attempt optimistic-lock update
        3. On conflict → raise HTTP 409
        4. Record the transaction
        5. Write audit log
        6. Emit Socket.io event to location room

    Args:
        db: Async database session.
        data: Validated transaction request.
        user_id: UUID of the user performing the action.
        ip_address: Client IP for audit logging.

    Returns:
        The created StockTransactionModel.

    Raises:
        NotFoundException: If the inventory record doesn't exist.
        ConflictException: If the optimistic lock version conflicts.
    """
    # Fetch current inventory
    inv = await inventory_repo.get_by_product_location(
        db, data.product_id, data.location_id
    )
    if inv is None:
        raise NotFoundException(
            "Inventory record not found for this product at this location"
        )

    quantity_before = inv.quantity

    # Attempt optimistic-lock update
    updated_inv = await inventory_repo.update_stock(
        db=db,
        product_id=data.product_id,
        location_id=data.location_id,
        delta=data.quantity_change,
        known_version=data.known_version,
    )

    if updated_inv is None:
        raise ConflictException(
            "Stock has been modified by another user. "
            "Please refresh and try again."
        )

    quantity_after = quantity_before + data.quantity_change

    # Record the transaction
    tx = StockTransactionModel(
        product_id=data.product_id,
        location_id=data.location_id,
        user_id=user_id,
        type=TransactionType(data.type),
        quantity_change=data.quantity_change,
        quantity_before=quantity_before,
        quantity_after=quantity_after,
        reference_no=data.reference_no,
        notes=data.notes,
    )
    db.add(tx)
    await db.commit()
    await db.refresh(tx)

    # Audit log
    await write_audit_log(
        db=db,
        user_id=user_id,
        table_name="stock_transactions",
        record_id=tx.id,
        action=AuditAction.insert,
        new_values={
            "product_id": str(data.product_id),
            "location_id": str(data.location_id),
            "type": data.type,
            "quantity_change": data.quantity_change,
            "quantity_before": quantity_before,
            "quantity_after": quantity_after,
        },
        ip_address=ip_address,
    )

    # Emit Socket.io event to notify other clients
    await _emit_stock_update(
        location_id=str(data.location_id),
        product_id=str(data.product_id),
        new_quantity=quantity_after,
        updated_by=str(user_id),
    )

    return tx


async def process_adjustment(
    db: AsyncSession,
    data: AdjustmentRequest,
    user_id: UUID,
    ip_address: str | None = None,
) -> dict:
    """
    Process a stock adjustment — routes to pending if delta exceeds threshold.

    If abs(quantity_change) <= ADJUSTMENT_THRESHOLD:
        Apply directly as a normal transaction.
    If abs(quantity_change) > ADJUSTMENT_THRESHOLD:
        Create a pending_adjustment for manager/admin approval.

    Args:
        db: Async database session.
        data: Validated adjustment request.
        user_id: UUID of the user.
        ip_address: Client IP for audit logging.

    Returns:
        Dict with "status" key: "applied" or "pending".
    """
    if abs(data.quantity_change) <= settings.ADJUSTMENT_THRESHOLD:
        # Apply directly
        tx_data = TransactionRequest(
            product_id=data.product_id,
            location_id=data.location_id,
            type="adjustment",
            quantity_change=data.quantity_change,
            known_version=data.known_version,
            notes=data.notes,
        )
        await process_transaction(db, tx_data, user_id, ip_address)
        return {"status": "applied", "message": "Adjustment applied directly"}
    else:
        # Route to pending
        pending = PendingAdjustmentModel(
            product_id=data.product_id,
            location_id=data.location_id,
            user_id=user_id,
            quantity_change=data.quantity_change,
            notes=data.notes,
        )
        db.add(pending)
        await db.commit()
        await db.refresh(pending)

        # Audit log
        await write_audit_log(
            db=db,
            user_id=user_id,
            table_name="pending_adjustments",
            record_id=pending.id,
            action=AuditAction.insert,
            new_values={
                "product_id": str(data.product_id),
                "location_id": str(data.location_id),
                "quantity_change": data.quantity_change,
                "status": "pending",
            },
            ip_address=ip_address,
        )

        return {
            "status": "pending",
            "message": f"Adjustment exceeds threshold ({settings.ADJUSTMENT_THRESHOLD}). Sent for approval.",
            "pending_id": str(pending.id),
        }


async def approve_adjustment(
    db: AsyncSession,
    adjustment_id: UUID,
    reviewer_id: UUID,
    ip_address: str | None = None,
) -> dict:
    """
    Approve a pending adjustment and apply the stock change.

    Args:
        db: Async database session.
        adjustment_id: UUID of the pending adjustment.
        reviewer_id: UUID of the approving manager/admin.
        ip_address: Client IP for audit logging.

    Returns:
        Dict with approval confirmation.

    Raises:
        NotFoundException: If the adjustment doesn't exist.
    """
    from datetime import datetime, timezone
    from sqlalchemy import select

    stmt = select(PendingAdjustmentModel).where(
        PendingAdjustmentModel.id == adjustment_id
    )
    result = await db.execute(stmt)
    pending = result.scalar_one_or_none()

    if pending is None:
        raise NotFoundException("Pending adjustment not found")

    if pending.status != AdjustmentStatus.pending:
        from app.core.exceptions import BadRequestException
        raise BadRequestException(f"Adjustment is already {pending.status.value}")

    # Get current inventory for version
    inv = await inventory_repo.get_by_product_location(
        db, pending.product_id, pending.location_id
    )
    if inv is None:
        raise NotFoundException("Inventory record not found")

    # Apply the stock change
    tx_data = TransactionRequest(
        product_id=pending.product_id,
        location_id=pending.location_id,
        type="adjustment",
        quantity_change=pending.quantity_change,
        known_version=inv.version,
        notes=f"Approved adjustment: {pending.notes or ''}",
    )
    await process_transaction(db, tx_data, reviewer_id, ip_address)

    # Update the pending record
    pending.status = AdjustmentStatus.approved
    pending.reviewed_by = reviewer_id
    pending.reviewed_at = datetime.now(timezone.utc)
    await db.commit()

    # Audit log
    await write_audit_log(
        db=db,
        user_id=reviewer_id,
        table_name="pending_adjustments",
        record_id=pending.id,
        action=AuditAction.update,
        old_values={"status": "pending"},
        new_values={"status": "approved", "reviewed_by": str(reviewer_id)},
        ip_address=ip_address,
    )

    return {"status": "approved", "adjustment_id": str(adjustment_id)}


async def reject_adjustment(
    db: AsyncSession,
    adjustment_id: UUID,
    reviewer_id: UUID,
    ip_address: str | None = None,
) -> dict:
    """
    Reject a pending adjustment without applying stock changes.

    Args:
        db: Async database session.
        adjustment_id: UUID of the pending adjustment.
        reviewer_id: UUID of the rejecting manager/admin.
        ip_address: Client IP for audit logging.

    Returns:
        Dict with rejection confirmation.
    """
    from datetime import datetime, timezone
    from sqlalchemy import select

    stmt = select(PendingAdjustmentModel).where(
        PendingAdjustmentModel.id == adjustment_id
    )
    result = await db.execute(stmt)
    pending = result.scalar_one_or_none()

    if pending is None:
        raise NotFoundException("Pending adjustment not found")

    if pending.status != AdjustmentStatus.pending:
        from app.core.exceptions import BadRequestException
        raise BadRequestException(f"Adjustment is already {pending.status.value}")

    pending.status = AdjustmentStatus.rejected
    pending.reviewed_by = reviewer_id
    pending.reviewed_at = datetime.now(timezone.utc)
    await db.commit()

    # Audit log
    await write_audit_log(
        db=db,
        user_id=reviewer_id,
        table_name="pending_adjustments",
        record_id=pending.id,
        action=AuditAction.update,
        old_values={"status": "pending"},
        new_values={"status": "rejected", "reviewed_by": str(reviewer_id)},
        ip_address=ip_address,
    )

    return {"status": "rejected", "adjustment_id": str(adjustment_id)}


async def _emit_stock_update(
    location_id: str,
    product_id: str,
    new_quantity: int,
    updated_by: str,
) -> None:
    """
    Broadcast stock change to all clients in the location room via Socket.io.

    Flutter app listens for 'stock_updated' event and updates
    Riverpod state immediately for real-time UI sync.

    Args:
        location_id: Room identifier (location UUID string).
        product_id: UUID string of the affected product.
        new_quantity: Updated stock count.
        updated_by: UUID string of the user who made the change.
    """
    try:
        from app.sockets.events import sio

        await sio.emit(
            "stock_updated",
            {
                "productId": product_id,
                "newQuantity": new_quantity,
                "updatedBy": updated_by,
            },
            room=location_id,
        )
    except Exception:
        # Socket.io emit failures should not block the transaction
        pass
