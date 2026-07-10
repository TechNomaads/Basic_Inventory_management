from datetime import datetime
from uuid import UUID
from pydantic import BaseModel, Field


class CompanyResponse(BaseModel):
    id: UUID
    name: str
    address: str | None = None
    logo: str | None = None
    created_at: datetime

    class Config:
        from_attributes = True


class CompanyCreateRequest(BaseModel):
    name: str = Field(..., max_length=150)
    address: str | None = Field(default=None)
    logo: str | None = Field(default=None)


class CompanyUpdateRequest(BaseModel):
    name: str | None = Field(default=None, max_length=150)
    address: str | None = Field(default=None)
    logo: str | None = Field(default=None)
