"""
Module: analytics schemas
Description: Pydantic schemas for reports and charting API responses.
"""

from datetime import date as d_date
from pydantic import BaseModel, Field


class SalesTrendItem(BaseModel):
    """Single date sales summary item."""
    date: d_date = Field(description="Calendar date of the trend item")
    revenue: float = Field(description="Total revenue generated")
    profit: float = Field(description="Gross profit margin generated")


class CategoryStockItem(BaseModel):
    """Stock level summary aggregated by product category."""
    category_name: str = Field(description="Name of the product category")
    total_stock: int = Field(description="Total unit quantity in stock across selected store")
    product_count: int = Field(description="Number of distinct products in this category")
