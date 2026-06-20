import math
import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy import select, func, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_current_user, get_db
from app.core.exceptions import NotFoundException, ConflictException
from app.models.customer import CustomerModel
from app.models.invoice import InvoiceModel
from app.models.user import UserModel
from app.models.audit_log import AuditAction
from app.services.audit_service import write_audit_log
from app.schemas.customer import (
    CustomerCreateRequest,
    CustomerUpdateRequest,
    CustomerResponse,
    CustomerDetailResponse,
    PaginatedCustomerResponse
)

router = APIRouter(prefix="/api/v1/customers", tags=["Customers"])

@router.get("", response_model=PaginatedCustomerResponse)
async def list_customers(
    search: str | None = Query(None, description="Search by name or phone number"),
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> PaginatedCustomerResponse:
    # Build count query
    count_stmt = select(func.count(CustomerModel.id))
    select_stmt = select(CustomerModel)
    
    if search and search.strip():
        search_term = f"%{search.strip()}%"
        cond = or_(
            CustomerModel.name.ilike(search_term),
            CustomerModel.phone.ilike(search_term)
        )
        count_stmt = count_stmt.where(cond)
        select_stmt = select_stmt.where(cond)
        
    res_count = await db.execute(count_stmt)
    total = res_count.scalar() or 0
    
    # pagination
    offset = (page - 1) * size
    select_stmt = select_stmt.order_by(CustomerModel.created_at.desc()).offset(offset).limit(size)
    res_select = await db.execute(select_stmt)
    items = res_select.scalars().all()
    
    return PaginatedCustomerResponse(
        items=items,
        total=total,
        page=page,
        size=size,
        pages=math.ceil(total / size) if total > 0 else 0
    )

@router.post("", response_model=CustomerResponse, status_code=201)
async def create_customer(
    body: CustomerCreateRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(get_current_user),
) -> CustomerResponse:
    # Check duplicate phone if phone is provided
    if body.phone and body.phone.strip():
        phone_cleaned = body.phone.strip()
        stmt = select(CustomerModel).where(CustomerModel.phone == phone_cleaned)
        res = await db.execute(stmt)
        if res.scalar_one_or_none():
            raise ConflictException(f"Customer with phone number {phone_cleaned} already exists.")
            
    customer = CustomerModel(
        name=body.name.strip(),
        phone=body.phone.strip() if body.phone else None,
        credit_limit=body.credit_limit if body.credit_limit is not None else 10000.00,
        overdue_amount=body.overdue_amount if body.overdue_amount is not None else 0.00,
        created_at=datetime.now(timezone.utc)
    )
    db.add(customer)
    await db.flush()
    
    # Audit log
    await write_audit_log(
        db=db,
        user_id=user.id,
        table_name="customers",
        record_id=customer.id,
        action=AuditAction.insert,
        new_values={
            "name": customer.name,
            "phone": customer.phone,
            "credit_limit": float(customer.credit_limit),
            "overdue_amount": float(customer.overdue_amount)
        },
        ip_address=request.client.host if request.client else None
    )
    await db.commit()
    return customer

@router.get("/kpis")
async def get_customers_kpis(
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
):
    stmt = select(
        func.count(CustomerModel.id),
        func.sum(CustomerModel.overdue_amount),
        func.sum(CustomerModel.credit_limit)
    )
    res = await db.execute(stmt)
    row = res.all()[0]
    return {
        "total_count": row[0] or 0,
        "total_overdue": float(row[1]) if row[1] is not None else 0.0,
        "total_credit": float(row[2]) if row[2] is not None else 0.0
    }

@router.get("/{id}", response_model=CustomerDetailResponse)
async def get_customer(
    id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> CustomerDetailResponse:
    # Fetch customer profile
    stmt = select(CustomerModel).where(CustomerModel.id == id)
    res = await db.execute(stmt)
    customer = res.scalar_one_or_none()
    if not customer:
        raise NotFoundException(f"Customer with ID {id} not found")
        
    # Fetch invoice purchase history
    inv_stmt = (
        select(InvoiceModel)
        .where(InvoiceModel.customer_id == id)
        .order_by(InvoiceModel.created_at.desc())
    )
    inv_res = await db.execute(inv_stmt)
    invoices = inv_res.scalars().all()
    
    return CustomerDetailResponse(
        id=customer.id,
        name=customer.name,
        phone=customer.phone,
        credit_limit=float(customer.credit_limit),
        overdue_amount=float(customer.overdue_amount),
        created_at=customer.created_at,
        invoices=invoices
    )

@router.put("/{id}", response_model=CustomerResponse)
async def update_customer(
    id: uuid.UUID,
    body: CustomerUpdateRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(get_current_user),
) -> CustomerResponse:
    stmt = select(CustomerModel).where(CustomerModel.id == id)
    res = await db.execute(stmt)
    customer = res.scalar_one_or_none()
    if not customer:
        raise NotFoundException(f"Customer with ID {id} not found")
        
    old_values = {
        "name": customer.name,
        "phone": customer.phone,
        "credit_limit": float(customer.credit_limit),
        "overdue_amount": float(customer.overdue_amount)
    }
    
    update_data = body.model_dump(exclude_unset=True)
    
    if "phone" in update_data and update_data["phone"] is not None:
        phone_cleaned = update_data["phone"].strip()
        if phone_cleaned != customer.phone:
            # Check duplicate
            dup_stmt = select(CustomerModel).where(CustomerModel.phone == phone_cleaned)
            dup_res = await db.execute(dup_stmt)
            if dup_res.scalar_one_or_none():
                raise ConflictException(f"Customer with phone number {phone_cleaned} already exists.")
            customer.phone = phone_cleaned
            
    if "name" in update_data and update_data["name"] is not None:
        customer.name = update_data["name"].strip()
    if "credit_limit" in update_data and update_data["credit_limit"] is not None:
        customer.credit_limit = update_data["credit_limit"]
    if "overdue_amount" in update_data and update_data["overdue_amount"] is not None:
        customer.overdue_amount = update_data["overdue_amount"]
        
    await db.flush()
    
    # Audit log
    await write_audit_log(
        db=db,
        user_id=user.id,
        table_name="customers",
        record_id=customer.id,
        action=AuditAction.update,
        old_values=old_values,
        new_values=update_data,
        ip_address=request.client.host if request.client else None
    )
    await db.commit()
    return customer
