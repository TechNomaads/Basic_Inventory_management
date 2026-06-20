"""
Module: billing_service
Description: Business logic for customer profile lookups, atomic checkouts, invoice searches, and thermal receipt rendering.

Responsibilities:
    - Process transactions atomically (stock validation + optimistic lock update + invoice logging)
    - Generate unique, annual, sequential invoice numbers
    - Calculate tax-exclusive invoice totals and discounts
    - Support daily summary stats (sales, revenue, profit)
    - Generate printer-friendly HTML receipt previews
"""

import uuid
from datetime import datetime, timezone
from sqlalchemy import func, select, update
from sqlalchemy.orm import joinedload, selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException

from app.core.exceptions import ConflictException, NotFoundException
from app.models.customer import CustomerModel
from app.models.invoice import InvoiceModel, InvoiceItemModel, PaymentMode
from app.models.product import ProductModel
from app.models.inventory import InventoryModel
from app.models.stock_transaction import StockTransactionModel, TransactionType
from app.models.audit_log import AuditAction
from app.schemas.billing import CheckoutRequest, CheckoutItem
from app.services.audit_service import write_audit_log


async def get_or_create_customer(
    db: AsyncSession, phone: str | None, name: str | None
) -> CustomerModel | None:
    """
    Look up customer by phone. If not found, create a new one.
    If no phone is provided, return None (Anonymous/Walk-in).
    """
    if not phone or not phone.strip():
        if name and name.strip() and name != "Anonymous/Walk-in":
            # If name is provided without phone, create an anonymous-style named customer
            cust = CustomerModel(name=name.strip(), phone=None)
            db.add(cust)
            await db.flush()
            return cust
        return None

    cleaned_phone = phone.strip()
    stmt = select(CustomerModel).where(CustomerModel.phone == cleaned_phone)
    res = await db.execute(stmt)
    customer = res.scalar_one_or_none()

    if not customer:
        customer = CustomerModel(
            name=name.strip() if name and name.strip() else "Anonymous/Walk-in",
            phone=cleaned_phone,
        )
        db.add(customer)
        await db.flush()
    elif name and name.strip() and name != "Anonymous/Walk-in":
        # Update name if a new one is provided
        customer.name = name.strip()
        await db.flush()

    return customer


async def generate_invoice_number(db: AsyncSession) -> str:
    """
    Generate the next sequential invoice number for the current year.
    Format: INV-YYYY-XXXXX (e.g., INV-2026-00001)
    Locks the matching rows using SELECT ... FOR UPDATE to avoid concurrency duplication.
    """
    year = datetime.now(timezone.utc).year
    prefix = f"INV-{year}-"

    # Query the highest invoice number for this year, locking it
    stmt = (
        select(InvoiceModel.invoice_number)
        .where(InvoiceModel.invoice_number.like(f"{prefix}%"))
        .order_by(InvoiceModel.invoice_number.desc())
        .limit(1)
        .with_for_update()
    )
    result = await db.execute(stmt)
    last_invoice = result.scalar_one_or_none()

    if last_invoice:
        try:
            parts = last_invoice.split("-")
            last_seq = int(parts[2])
            next_seq = last_seq + 1
        except (IndexError, ValueError):
            next_seq = 1
    else:
        next_seq = 1

    return f"{prefix}{next_seq:05d}"


async def process_checkout(
    db: AsyncSession,
    data: CheckoutRequest,
    user_id: uuid.UUID,
    ip_address: str | None = None,
) -> InvoiceModel:
    """
    Atomic checkout within a database transaction.
    """
    # 1. Retrieve or Create Customer
    customer = await get_or_create_customer(db, data.customer_phone, data.customer_name)
    customer_id = customer.id if customer else None

    # 2. Pre-fetch products to snapshot prices/tax and perform inventory validations
    subtotal = 0.0
    total_tax = 0.0
    invoice_items = []
    stock_updates = []

    # Map to track inventory lock mismatches or missing stock
    for item in data.items:
        # Get product master details
        stmt_prod = select(ProductModel).where(ProductModel.id == item.product_id)
        prod_res = await db.execute(stmt_prod)
        product = prod_res.scalar_one_or_none()
        if not product:
            raise NotFoundException(f"Product with ID {item.product_id} not found")

        # Get inventory level at checkout location
        stmt_inv = select(InventoryModel).where(
            InventoryModel.product_id == item.product_id,
            InventoryModel.location_id == data.location_id,
        )
        inv_res = await db.execute(stmt_inv)
        inv = inv_res.scalar_one_or_none()

        if not inv:
            raise NotFoundException(
                f"No inventory record found for product '{product.name}' at this location"
            )

        if inv.quantity < item.quantity:
            raise ConflictException(
                f"Insufficient stock for '{product.name}'. Requested: {item.quantity}, Available: {inv.quantity}"
            )

        # Base calculations (Tax-exclusive added on top)
        unit_price = float(item.unit_price if item.unit_price is not None else (product.sell_price or 0.0))
        cost_price = float(product.cost_price or 0.0) if product.cost_price else None
        tax_rate = float(item.tax_rate if item.tax_rate is not None else product.tax_rate)

        raw_subtotal = unit_price * item.quantity
        item_subtotal = max(0.0, raw_subtotal - float(item.discount_amount))
        item_tax = item_subtotal * (tax_rate / 100.0)
        line_total = item_subtotal + item_tax

        subtotal += item_subtotal
        total_tax += item_tax

        # Build line item record
        invoice_item = InvoiceItemModel(
            id=uuid.uuid4(),
            product_id=product.id,
            quantity=item.quantity,
            unit_price=unit_price,
            cost_price=cost_price,
            tax_rate=tax_rate,
            tax_amount=item_tax,
            line_total=line_total,
        )
        invoice_items.append((invoice_item, inv.quantity, item.known_version))

        # Store parameters for bulk update
        stock_updates.append({
            "product_id": item.product_id,
            "quantity_change": -item.quantity,
            "quantity_before": inv.quantity,
            "known_version": item.known_version
        })

    # Calculate final invoice totals
    discount_amount = float(data.discount_amount)
    total_amount = max(0.0, subtotal + total_tax - discount_amount)

    # 3. Generate Invoice Number (locks sequence)
    invoice_number = await generate_invoice_number(db)

    # 4. Create Invoice Record
    invoice = InvoiceModel(
        id=uuid.uuid4(),
        invoice_number=invoice_number,
        location_id=data.location_id,
        user_id=user_id,
        customer_id=customer_id,
        subtotal=subtotal,
        tax_amount=total_tax,
        discount_amount=discount_amount,
        total_amount=total_amount,
        payment_mode=data.payment_mode,
        notes=data.notes,
        created_at=datetime.now(timezone.utc),
    )
    db.add(invoice)
    await db.flush()

    # 5. Process inventory deductions with optimistic lock checks & insert stock ledger logs
    for idx, (item_model, qty_before, known_ver) in enumerate(invoice_items):
        update_data = stock_updates[idx]
        
        # Deduct stock and increment version
        stmt_update = (
            update(InventoryModel)
            .where(
                InventoryModel.product_id == update_data["product_id"],
                InventoryModel.location_id == data.location_id,
                InventoryModel.version == known_ver,
            )
            .values(
                quantity=InventoryModel.quantity + update_data["quantity_change"],
                version=InventoryModel.version + 1,
                updated_at=func.now(),
            )
            .returning(InventoryModel)
        )
        res_up = await db.execute(stmt_update)
        updated_inv = res_up.scalar_one_or_none()

        if not updated_inv:
            # Rollback automatically occurs when exception is raised inside controller/session handler
            raise ConflictException(
                f"Concurrency conflict: Stock for product ID {update_data['product_id']} was modified by another transaction. Please refresh."
            )

        # Complete invoice item link
        item_model.invoice_id = invoice.id
        db.add(item_model)

        # Log stock transaction audit ledger
        qty_after = qty_before + update_data["quantity_change"]
        stock_tx = StockTransactionModel(
            id=uuid.uuid4(),
            product_id=update_data["product_id"],
            location_id=data.location_id,
            user_id=user_id,
            type=TransactionType.sale,
            quantity_change=update_data["quantity_change"],
            quantity_before=qty_before,
            quantity_after=qty_after,
            reference_no=invoice_number,
            notes=f"Checkout sale. Invoice: {invoice_number}",
            created_at=datetime.now(timezone.utc),
        )
        db.add(stock_tx)

    # 6. Audit Log
    await write_audit_log(
        db=db,
        user_id=user_id,
        table_name="invoices",
        record_id=invoice.id,
        action=AuditAction.insert,
        new_values={
            "invoice_number": invoice_number,
            "total_amount": total_amount,
            "customer_id": str(customer_id) if customer_id else None,
        },
        ip_address=ip_address,
    )

    await db.commit()

    # Re-query with eager-loaded relationships for Pydantic serialization
    stmt_reload = (
        select(InvoiceModel)
        .where(InvoiceModel.id == invoice.id)
        .options(
            joinedload(InvoiceModel.location),
            joinedload(InvoiceModel.user),
            joinedload(InvoiceModel.customer),
            selectinload(InvoiceModel.items).joinedload(InvoiceItemModel.product),
        )
    )
    res_reload = await db.execute(stmt_reload)
    return res_reload.unique().scalar_one()


async def get_invoice_detail(db: AsyncSession, invoice_id: uuid.UUID) -> InvoiceModel | None:
    """Fetch invoice by UUID with pre-fetched relations."""
    stmt = (
        select(InvoiceModel)
        .where(InvoiceModel.id == invoice_id)
        .options(
            joinedload(InvoiceModel.location),
            joinedload(InvoiceModel.user),
            joinedload(InvoiceModel.customer),
            selectinload(InvoiceModel.items).joinedload(InvoiceItemModel.product),
        )
    )
    res = await db.execute(stmt)
    return res.unique().scalar_one_or_none()


async def list_invoices(
    db: AsyncSession,
    skip: int = 0,
    limit: int = 50,
    location_id: uuid.UUID | None = None,
    payment_mode: PaymentMode | None = None,
    start_date: datetime | None = None,
    end_date: datetime | None = None,
) -> tuple[list[InvoiceModel], int]:
    """List and filter invoices with a total count."""
    stmt = select(InvoiceModel).options(
        joinedload(InvoiceModel.location),
        joinedload(InvoiceModel.user),
        joinedload(InvoiceModel.customer),
        selectinload(InvoiceModel.items).joinedload(InvoiceItemModel.product),
    )
    count_stmt = select(func.count(InvoiceModel.id))

    if location_id:
        stmt = stmt.where(InvoiceModel.location_id == location_id)
        count_stmt = count_stmt.where(InvoiceModel.location_id == location_id)
    if payment_mode:
        stmt = stmt.where(InvoiceModel.payment_mode == payment_mode)
        count_stmt = count_stmt.where(InvoiceModel.payment_mode == payment_mode)
    if start_date:
        stmt = stmt.where(InvoiceModel.created_at >= start_date)
        count_stmt = count_stmt.where(InvoiceModel.created_at >= start_date)
    if end_date:
        stmt = stmt.where(InvoiceModel.created_at <= end_date)
        count_stmt = count_stmt.where(InvoiceModel.created_at <= end_date)

    # Order by date descending
    stmt = stmt.order_by(InvoiceModel.created_at.desc()).offset(skip).limit(limit)

    res_items = await db.execute(stmt)
    res_count = await db.execute(count_stmt)

    return list(res_items.unique().scalars().all()), res_count.scalar() or 0


async def get_daily_sales_summary(db: AsyncSession, location_id: uuid.UUID | None = None) -> dict:
    """
    Calculate sales count, total revenue, and profit for today.
    """
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)

    # Total invoices count & revenue
    stmt_sales = select(
        func.count(InvoiceModel.id),
        func.sum(InvoiceModel.total_amount),
        func.sum(InvoiceModel.discount_amount)
    ).where(InvoiceModel.created_at >= today_start)

    if location_id:
        stmt_sales = stmt_sales.where(InvoiceModel.location_id == location_id)

    res_sales = await db.execute(stmt_sales)
    count, revenue, total_discount = res_sales.fetchone() or (0, 0.0, 0.0)

    count = count or 0
    revenue = float(revenue or 0.0)
    total_discount = float(total_discount or 0.0)

    # Profit calculation: SUM((line_total - tax_amount) - (cost_price * quantity)) - invoice.discount_amount
    stmt_items = select(
        InvoiceItemModel.line_total,
        InvoiceItemModel.tax_amount,
        InvoiceItemModel.unit_price,
        InvoiceItemModel.cost_price,
        InvoiceItemModel.quantity
    ).join(InvoiceModel).where(InvoiceModel.created_at >= today_start)

    if location_id:
        stmt_items = stmt_items.where(InvoiceModel.location_id == location_id)

    res_items = await db.execute(stmt_items)
    items = res_items.fetchall()

    total_cost_subtotal = 0.0
    total_sell_subtotal = 0.0

    for line_tot, tax_amt, unit_p, cost_p, qty in items:
        # Use snapshotted cost price, fall back to unit sell price if cost price is null (margin = 0)
        c_price = float(cost_p) if cost_p is not None else float(unit_p)
        total_cost_subtotal += c_price * qty
        # Use actual discounted item subtotal (before tax)
        total_sell_subtotal += float(line_tot) - float(tax_amt)

    # Gross profit = sell subtotal - cost subtotal - discount
    profit = max(0.0, total_sell_subtotal - total_cost_subtotal - total_discount)

    return {
        "total_sales_today": count,
        "revenue_today": revenue,
        "profit_today": profit
    }


def generate_thermal_receipt_html(invoice: InvoiceModel) -> str:
    """
    Generates a thermal printer-friendly HTML document.
    Sized for 58mm/80mm rolls. Clean, monospaced layout with minimal borders.
    """
    items_html = ""
    for item in invoice.items:
        prod_name = item.product.name if item.product else "Unknown Product"
        # truncate name to fit line
        display_name = prod_name[:18] + ".." if len(prod_name) > 18 else prod_name
        qty_price = f"{item.quantity} x ₹{item.unit_price:.2f}"
        total_str = f"₹{item.line_total:.2f}"
        
        items_html += f"""
        <tr>
            <td colspan="2" style="font-weight: bold;">{display_name}</td>
        </tr>
        <tr>
            <td style="padding-left: 10px; color: #555;">{qty_price} (GST {item.tax_rate}%)</td>
            <td style="text-align: right; font-weight: bold;">{total_str}</td>
        </tr>
        """

    cust_html = ""
    if invoice.customer:
        cust_name = invoice.customer.name
        cust_phone = invoice.customer.phone or "N/A"
        cust_html = f"""
        <div class="info-block">
            <strong>Customer:</strong> {cust_name}<br/>
            <strong>Phone:</strong> {cust_phone}
        </div>
        <div class="separator">- - - - - - - - - - - - - - - -</div>
        """

    # Format timestamp
    date_str = invoice.created_at.astimezone().strftime("%Y-%m-%d %I:%M %p")

    return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Receipt - {invoice.invoice_number}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        @page {{
            size: 80mm auto;
            margin: 0;
        }}
        body {{
            font-family: 'Courier New', Courier, monospace;
            font-size: 12px;
            line-height: 1.4;
            color: #000;
            background: #fff;
            width: 76mm;
            margin: 0 auto;
            padding: 10px 4px;
            box-sizing: border-box;
        }}
        .text-center {{
            text-align: center;
        }}
        .header {{
            margin-bottom: 12px;
        }}
        .store-title {{
            font-size: 16px;
            font-weight: bold;
            text-transform: uppercase;
        }}
        .separator {{
            text-align: center;
            margin: 8px 0;
            letter-spacing: 2px;
        }}
        .info-block {{
            margin-bottom: 6px;
            font-size: 11px;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 10px;
        }}
        td {{
            padding: 3px 0;
            vertical-align: top;
        }}
        .totals-table {{
            width: 100%;
            margin-top: 8px;
        }}
        .totals-table td {{
            padding: 2px 0;
        }}
        .totals-title {{
            text-align: right;
            padding-right: 15px;
        }}
        .totals-val {{
            text-align: right;
            font-weight: bold;
        }}
        .footer {{
            margin-top: 20px;
            font-size: 11px;
        }}
        .print-btn {{
            display: block;
            width: 100%;
            padding: 10px;
            background: #000;
            color: #fff;
            text-align: center;
            border: none;
            font-weight: bold;
            cursor: pointer;
            margin-top: 20px;
            border-radius: 4px;
        }}
        @media print {{
            .print-btn {{
                display: none;
            }}
            body {{
                width: 100%;
                padding: 0;
            }}
        }}
    </style>
</head>
<body>
    <div class="text-center header">
        <div class="store-title">{invoice.location.name}</div>
        <div style="font-size: 10px;">POS Receipt</div>
    </div>
    
    <div class="separator">- - - - - - - - - - - - - - - -</div>
    
    <div class="info-block">
        <strong>Inv No:</strong> {invoice.invoice_number}<br/>
        <strong>Date:</strong> {date_str}<br/>
        <strong>Cashier:</strong> {invoice.user.name}
    </div>
    
    <div class="separator">- - - - - - - - - - - - - - - -</div>
    
    {cust_html}
    
    <table>
        <tbody>
            {items_html}
        </tbody>
    </table>
    
    <div class="separator">- - - - - - - - - - - - - - - -</div>
    
    <table class="totals-table">
        <tr>
            <td class="totals-title">Subtotal:</td>
            <td class="totals-val">₹{invoice.subtotal:.2f}</td>
        </tr>
        <tr>
            <td class="totals-title">Tax (GST):</td>
            <td class="totals-val">₹{invoice.tax_amount:.2f}</td>
        </tr>
        <tr>
            <td class="totals-title">Discount:</td>
            <td class="totals-val">-₹{invoice.discount_amount:.2f}</td>
        </tr>
        <tr style="font-size: 14px; font-weight: bold;">
            <td class="totals-title">NET TOTAL:</td>
            <td class="totals-val">₹{invoice.total_amount:.2f}</td>
        </tr>
    </table>
    
    <div class="separator">- - - - - - - - - - - - - - - -</div>
    
    <div class="info-block">
        <strong>Payment Mode:</strong> {invoice.payment_mode.upper()}
    </div>
    
    <div class="text-center footer">
        Thank You for Your Visit!<br/>
        Please Come Again.
    </div>

    <button class="print-btn" onclick="window.print()">Print Receipt</button>
</body>
</html>
"""
