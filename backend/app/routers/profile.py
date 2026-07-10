import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_current_user, get_db
from app.core.exceptions import NotFoundException
from app.models.user import UserModel
from app.models.company import CompanyModel
from app.models.audit_log import AuditAction
from app.schemas.company import CompanyCreateRequest, CompanyUpdateRequest, CompanyResponse
from app.services.audit_service import write_audit_log

router = APIRouter(prefix="/api/v1", tags=["Profile & Companies"])


@router.get("/profile")
async def get_profile(
    user: UserModel = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve the current user profile, including active company details."""
    active_company = None
    if user.active_company_id:
        stmt = select(CompanyModel).where(CompanyModel.id == user.active_company_id)
        res = await db.execute(stmt)
        active_company = res.scalar_one_or_none()

    return {
        "id": user.id,
        "name": user.name,
        "full_name": user.name,
        "email": user.email,
        "role": user.role.value,
        "address": user.address,
        "active_company_id": user.active_company_id,
        "signature_stamp_b64": user.signature_stamp_b64,
        "active_company": {
            "id": active_company.id,
            "name": active_company.name,
            "address": active_company.address,
            "logo": active_company.logo,
        } if active_company else None
    }


@router.put("/profile")
async def update_profile(
    body: dict,
    request: Request,
    user: UserModel = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update current user profile name and/or address."""
    old_values = {
        "name": user.name,
        "address": user.address,
        "active_company_id": str(user.active_company_id) if user.active_company_id else None,
        "has_signature": user.signature_stamp_b64 is not None
    }

    name_val = body.get("name") or body.get("full_name")
    if name_val is not None:
        user.name = name_val.strip()
    if "address" in body:
        user.address = body["address"].strip() if body["address"] else None
    if "active_company_id" in body:
        if body["active_company_id"]:
            company_uuid = uuid.UUID(body["active_company_id"])
            # verify exists
            stmt = select(CompanyModel).where(CompanyModel.id == company_uuid)
            res = await db.execute(stmt)
            if not res.scalar_one_or_none():
                raise NotFoundException("Company not found")
            user.active_company_id = company_uuid
        else:
            user.active_company_id = None
    if "signature_stamp_b64" in body:
        user.signature_stamp_b64 = body["signature_stamp_b64"]

    await db.flush()

    # Audit log
    new_values = {
        "name": user.name,
        "address": user.address,
        "active_company_id": str(user.active_company_id) if user.active_company_id else None,
        "has_signature": user.signature_stamp_b64 is not None
    }
    await write_audit_log(
        db=db,
        user_id=user.id,
        table_name="users",
        record_id=user.id,
        action=AuditAction.update,
        old_values=old_values,
        new_values=new_values,
        ip_address=request.client.host if request.client else None
    )

    await db.commit()

    return {"message": "Profile updated successfully"}


@router.get("/companies", response_model=list[CompanyResponse])
async def list_companies(
    db: AsyncSession = Depends(get_db),
    _user: UserModel = Depends(get_current_user),
) -> list[CompanyResponse]:
    """List all companies."""
    stmt = select(CompanyModel).order_by(CompanyModel.created_at.desc())
    res = await db.execute(stmt)
    return res.scalars().all()


@router.post("/companies", response_model=CompanyResponse, status_code=201)
async def create_company(
    body: CompanyCreateRequest,
    request: Request,
    user: UserModel = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CompanyResponse:
    """Create a new company."""
    company = CompanyModel(
        name=body.name.strip(),
        address=body.address.strip() if body.address else None,
        logo=body.logo.strip() if body.logo else None,
        created_at=datetime.now(timezone.utc)
    )
    db.add(company)
    await db.flush()

    # Audit log
    await write_audit_log(
        db=db,
        user_id=user.id,
        table_name="companies",
        record_id=company.id,
        action=AuditAction.insert,
        new_values={
            "name": company.name,
            "address": company.address,
            "has_logo": company.logo is not None
        },
        ip_address=request.client.host if request.client else None
    )

    await db.commit()
    return company


@router.put("/companies/{id}", response_model=CompanyResponse)
async def update_company(
    id: uuid.UUID,
    body: CompanyUpdateRequest,
    request: Request,
    user: UserModel = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CompanyResponse:
    """Update an existing company."""
    stmt = select(CompanyModel).where(CompanyModel.id == id)
    res = await db.execute(stmt)
    company = res.scalar_one_or_none()
    if not company:
        raise NotFoundException(f"Company with ID {id} not found")

    old_values = {
        "name": company.name,
        "address": company.address,
        "has_logo": company.logo is not None
    }

    update_data = body.model_dump(exclude_unset=True)
    if "name" in update_data and update_data["name"] is not None:
        company.name = update_data["name"].strip()
    if "address" in update_data:
        company.address = update_data["address"].strip() if update_data["address"] else None
    if "logo" in update_data:
        company.logo = update_data["logo"].strip() if update_data["logo"] else None

    await db.flush()

    # Audit log
    await write_audit_log(
        db=db,
        user_id=user.id,
        table_name="companies",
        record_id=company.id,
        action=AuditAction.update,
        old_values=old_values,
        new_values={
            "name": company.name,
            "address": company.address,
            "has_logo": company.logo is not None
        },
        ip_address=request.client.host if request.client else None
    )

    await db.commit()
    return company


@router.delete("/companies/{id}", status_code=204)
async def delete_company(
    id: uuid.UUID,
    request: Request,
    user: UserModel = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a company profile."""
    stmt = select(CompanyModel).where(CompanyModel.id == id)
    res = await db.execute(stmt)
    company = res.scalar_one_or_none()
    if not company:
        raise NotFoundException(f"Company with ID {id} not found")

    old_values = {
        "name": company.name,
        "address": company.address,
        "has_logo": company.logo is not None
    }

    await db.delete(company)
    await db.flush()

    # Audit log
    await write_audit_log(
        db=db,
        user_id=user.id,
        table_name="companies",
        record_id=id,
        action=AuditAction.delete,
        old_values=old_values,
        ip_address=request.client.host if request.client else None
    )

    await db.commit()
    return None
