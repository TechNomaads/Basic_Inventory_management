"""
Module: test_billing
Description: Integration tests for the billing system.

Tests:
    - Successful checkout (creates invoice, deductions stock, logs audit/transactions)
    - Checkout with insufficient stock (409 Conflict)
    - Checkout with version mismatch/optimistic lock failure (409 Conflict)
    - Price snapshotting (invoice prices remain unchanged if product prices update)
    - List and filter invoices
    - Get single invoice detail
    - Retrieve thermal receipt without authorization
    - Customer profile lookup
"""

import uuid
from datetime import datetime, timezone
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.inventory import InventoryModel
from app.models.location import LocationModel
from app.models.product import ProductModel
from app.models.invoice import InvoiceModel, InvoiceItemModel, PaymentMode
from app.models.customer import CustomerModel
from app.models.stock_transaction import StockTransactionModel
from tests.conftest import auth_headers


async def _create_billing_test_data(
    db_session: AsyncSession,
) -> tuple[ProductModel, LocationModel, InventoryModel]:
    """Helper to seed basic product, location, and inventory records."""
    location = LocationModel(
        id=uuid.uuid4(),
        name="Main Store",
        code="MS-01",
        type="store",
    )
    db_session.add(location)

    product = ProductModel(
        id=uuid.uuid4(),
        barcode="8901234567890",
        name="Premium Wireless Mouse",
        sku="MS-PREM-WRLS",
        unit="pcs",
        cost_price=400.00,
        sell_price=799.00,
        tax_rate=18.00,
    )
    db_session.add(product)
    await db_session.flush()

    inventory = InventoryModel(
        id=uuid.uuid4(),
        product_id=product.id,
        location_id=location.id,
        quantity=50,
        min_quantity=5,
        version=0,
    )
    db_session.add(inventory)
    await db_session.commit()

    return product, location, inventory


@pytest.mark.asyncio
async def test_checkout_success(
    client: AsyncClient, db_session: AsyncSession, admin_user
):
    """Processes a valid checkout cart, checks DB and return payload."""
    product, location, inventory = await _create_billing_test_data(db_session)
    headers = auth_headers(admin_user)

    response = await client.post(
        "/api/v1/billing/checkout",
        json={
            "location_id": str(location.id),
            "payment_mode": "upi",
            "discount_amount": 50.00,
            "customer_name": "John Doe",
            "customer_phone": "9876543210",
            "notes": "Test checkout transaction",
            "items": [
                {
                    "product_id": str(product.id),
                    "quantity": 2,
                    "known_version": 0,
                }
            ],
        },
        headers=headers,
    )
    assert response.status_code == 201
    data = response.json()

    # Verify response schema fields
    assert "id" in data
    assert "invoice_number" in data
    assert data["location_name"] == "Main Store"
    assert data["user_name"] == "Test Admin"
    assert data["customer_name"] == "John Doe"
    assert data["customer_phone"] == "9876543210"
    
    # Subtotal = 2 * 799 = 1598
    # Tax = 1598 * 18% = 287.64
    # Total = 1598 + 287.64 - 50 = 1835.64
    assert round(data["subtotal"], 2) == 1598.00
    assert round(data["tax_amount"], 2) == 287.64
    assert round(data["discount_amount"], 2) == 50.00
    assert round(data["total_amount"], 2) == 1835.64
    assert data["payment_mode"] == "upi"
    assert len(data["items"]) == 1
    assert data["items"][0]["product_name"] == "Premium Wireless Mouse"

    # Verify inventory was updated (use fresh session to bypass cache)
    from tests.conftest import test_session_factory
    async with test_session_factory() as fresh_session:
        res = await fresh_session.execute(
            select(InventoryModel).where(
                InventoryModel.product_id == product.id,
                InventoryModel.location_id == location.id
            )
        )
        inv_after = res.scalar_one()
        assert inv_after.quantity == 48
        assert inv_after.version == 1

        # Verify invoice was persisted in the DB
        invoice_id = uuid.UUID(data["id"])
        res_inv = await fresh_session.execute(
            select(InvoiceModel).where(InvoiceModel.id == invoice_id)
        )
        db_invoice = res_inv.scalar_one_or_none()
        assert db_invoice is not None
        assert db_invoice.invoice_number.startswith("INV-")

        # Verify Stock Transaction was logged
        res_tx = await fresh_session.execute(
            select(StockTransactionModel).where(StockTransactionModel.reference_no == db_invoice.invoice_number)
        )
        db_tx = res_tx.scalar_one_or_none()
        assert db_tx is not None
        assert db_tx.quantity_change == -2
        assert db_tx.quantity_before == 50
        assert db_tx.quantity_after == 48


@pytest.mark.asyncio
async def test_checkout_out_of_stock(
    client: AsyncClient, db_session: AsyncSession, admin_user
):
    """Attempting checkout with quantity exceeding stock raises 409 Conflict."""
    product, location, inventory = await _create_billing_test_data(db_session)
    headers = auth_headers(admin_user)

    response = await client.post(
        "/api/v1/billing/checkout",
        json={
            "location_id": str(location.id),
            "payment_mode": "cash",
            "items": [
                {
                    "product_id": str(product.id),
                    "quantity": 100,  # exceeds available 50
                    "known_version": 0,
                }
            ],
        },
        headers=headers,
    )
    assert response.status_code == 409
    assert "Insufficient stock" in response.json()["detail"]


@pytest.mark.asyncio
async def test_checkout_optimistic_lock_mismatch(
    client: AsyncClient, db_session: AsyncSession, admin_user
):
    """Attempting checkout with an outdated version raises 409 Conflict."""
    product, location, inventory = await _create_billing_test_data(db_session)
    headers = auth_headers(admin_user)

    response = await client.post(
        "/api/v1/billing/checkout",
        json={
            "location_id": str(location.id),
            "payment_mode": "cash",
            "items": [
                {
                    "product_id": str(product.id),
                    "quantity": 1,
                    "known_version": 99,  # incorrect version
                }
            ],
        },
        headers=headers,
    )
    assert response.status_code == 409
    assert "Concurrency conflict" in response.json()["detail"]


@pytest.mark.asyncio
async def test_checkout_price_snapshotting(
    client: AsyncClient, db_session: AsyncSession, admin_user
):
    """Subsequent changes to product selling/cost price should not alter historical invoices."""
    product, location, inventory = await _create_billing_test_data(db_session)
    headers = auth_headers(admin_user)

    # 1. Checkout mouse at original price (799.00)
    checkout_response = await client.post(
        "/api/v1/billing/checkout",
        json={
            "location_id": str(location.id),
            "payment_mode": "card",
            "items": [
                {
                    "product_id": str(product.id),
                    "quantity": 1,
                    "known_version": 0,
                }
            ],
        },
        headers=headers,
    )
    assert checkout_response.status_code == 201
    invoice_data = checkout_response.json()
    invoice_id = uuid.UUID(invoice_data["id"])

    # 2. Update product master price
    res_prod = await db_session.execute(
        select(ProductModel).where(ProductModel.id == product.id)
    )
    db_product = res_prod.scalar_one()
    db_product.sell_price = 1299.00
    db_product.cost_price = 600.00
    await db_session.commit()

    # 3. Retrieve historical invoice details and check that prices match the snapshot
    invoice_response = await client.get(
        f"/api/v1/billing/invoices/{invoice_id}",
        headers=headers,
    )
    assert invoice_response.status_code == 200
    invoice_details = invoice_response.json()
    
    assert invoice_details["items"][0]["unit_price"] == 799.00
    assert invoice_details["items"][0]["cost_price"] == 400.00
    assert round(invoice_details["items"][0]["line_total"], 2) == round(799.00 * 1.18, 2)


@pytest.mark.asyncio
async def test_list_invoices_filtering(
    client: AsyncClient, db_session: AsyncSession, admin_user
):
    """Lists invoices and validates filters by location/payment mode."""
    product, location, inventory = await _create_billing_test_data(db_session)
    headers = auth_headers(admin_user)

    # Create two invoices with different properties
    # Invoice 1
    await client.post(
        "/api/v1/billing/checkout",
        json={
            "location_id": str(location.id),
            "payment_mode": "cash",
            "items": [{"product_id": str(product.id), "quantity": 1, "known_version": 0}],
        },
        headers=headers,
    )
    # Invoice 2
    await client.post(
        "/api/v1/billing/checkout",
        json={
            "location_id": str(location.id),
            "payment_mode": "upi",
            "items": [{"product_id": str(product.id), "quantity": 1, "known_version": 1}],
        },
        headers=headers,
    )

    # Filter by Payment Mode: cash
    response_cash = await client.get(
        f"/api/v1/billing/invoices?payment_mode=cash",
        headers=headers,
    )
    assert response_cash.status_code == 200
    invoices_cash = response_cash.json()
    assert len(invoices_cash) == 1
    assert invoices_cash[0]["payment_mode"] == "cash"

    # Filter by Location
    response_loc = await client.get(
        f"/api/v1/billing/invoices?location_id={location.id}",
        headers=headers,
    )
    assert response_loc.status_code == 200
    assert len(response_loc.json()) == 2


@pytest.mark.asyncio
async def test_thermal_receipt_unauthenticated(
    client: AsyncClient, db_session: AsyncSession, admin_user
):
    """The thermal receipt endpoint renders printable HTML and bypasses token check."""
    product, location, inventory = await _create_billing_test_data(db_session)
    headers = auth_headers(admin_user)

    checkout_response = await client.post(
        "/api/v1/billing/checkout",
        json={
            "location_id": str(location.id),
            "payment_mode": "card",
            "items": [{"product_id": str(product.id), "quantity": 1, "known_version": 0}],
        },
        headers=headers,
    )
    invoice_id = checkout_response.json()["id"]

    # Retrieve receipt without auth headers
    receipt_response = await client.get(f"/api/v1/billing/invoices/{invoice_id}/receipt")
    assert receipt_response.status_code == 200
    assert "text/html" in receipt_response.headers["content-type"]
    html_content = receipt_response.text
    assert "Main Store" in html_content
    assert "NET TOTAL" in html_content
    assert "Print Receipt" in html_content


@pytest.mark.asyncio
async def test_customer_lookup(
    client: AsyncClient, db_session: AsyncSession, admin_user
):
    """Checks looking up an existing customer via phone number."""
    headers = auth_headers(admin_user)

    # 1. Create a customer directly
    customer = CustomerModel(
        id=uuid.uuid4(),
        name="Jane Smith",
        phone="9999988888",
    )
    db_session.add(customer)
    await db_session.commit()

    # 2. Lookup phone number
    response = await client.get(
        "/api/v1/billing/customers/lookup?phone=9999988888",
        headers=headers,
    )
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Jane Smith"
    assert data["phone"] == "9999988888"

    # 3. Lookup non-existent customer
    response_404 = await client.get(
        "/api/v1/billing/customers/lookup?phone=1111111111",
        headers=headers,
    )
    assert response_404.status_code == 404
