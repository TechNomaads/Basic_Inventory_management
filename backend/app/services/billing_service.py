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

    # Validate payment and credit limit
    amount_paid = float(data.amount_paid) if data.amount_paid is not None else total_amount
    
    if customer:
        remaining_balance = total_amount - amount_paid
        new_overdue = float(customer.overdue_amount) + remaining_balance
        if new_overdue > float(customer.credit_limit):
            raise ConflictException(
                f"Checkout rejected: Purchase exceeds credit limit. "
                f"Limit: ₹{customer.credit_limit:.2f}, Current Overdue: ₹{customer.overdue_amount:.2f}, "
                f"New Overdue would be: ₹{new_overdue:.2f}"
            )
        # Adjust overdue amount
        customer.overdue_amount = float(customer.overdue_amount) + remaining_balance
    else:
        if amount_paid < total_amount:
            raise ConflictException(
                "Checkout rejected: Walk-in customers without registered profiles must pay in full."
            )
        amount_paid = total_amount

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
        amount_paid=amount_paid,
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
    Generates a professional A4 invoice HTML styled after the Master of Security System letterhead
    and UTTRAYAN Quotation content.
    """
    import os
    import base64

    def get_hsn_code(product_name: str) -> str:
        name = product_name.lower()
        if "dome" in name or "bullet" in name or "camera" in name or "ip camera" in name:
            return "85365090"
        elif "switch" in name or "poe" in name:
            return "85176290"
        elif "hdd" in name or "seagate" in name or "hard disk" in name or "drive" in name:
            return "84717020"
        elif "ups" in name:
            return "85044030"
        elif "rack" in name:
            return "85381010"
        elif "cable" in name or "cat6" in name:
            return "854449"
        elif "nvr" in name:
            return "85219090"
        return "N/A"

    def num_to_words(num: float) -> str:
        try:
            num = int(round(num))
            if num == 0:
                return "Zero Rupees only"
                
            units = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", 
                     "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"]
            tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]
            
            def helper(n):
                if n < 20:
                    return units[n]
                elif n < 100:
                    return tens[n // 10] + (" " + units[n % 10] if n % 10 != 0 else "")
                elif n < 1000:
                    return units[n // 100] + " Hundred" + (" and " + helper(n % 100) if n % 100 != 0 else "")
                elif n < 100000: # 1 Lakh
                    return helper(n // 1000) + " Thousand" + (" " + helper(n % 1000) if n % 1000 != 0 else "")
                elif n < 10000000: # 1 Crore
                    return helper(n // 100000) + " Lakh" + (" " + helper(n % 100000) if n % 100000 != 0 else "")
                else:
                    return helper(n // 10000000) + " Crore" + (" " + helper(n % 10000000) if n % 10000000 != 0 else "")
            
            words = helper(num).strip()
            return words + " Rupees only"
        except Exception:
            return ""

    # Load logo.png in base64
    logo_base64 = ""
    try:
        current_dir = os.path.dirname(os.path.abspath(__file__))
        logo_path = os.path.abspath(os.path.join(current_dir, "..", "..", "..", "frontend", "logo.png"))
        if os.path.exists(logo_path):
            with open(logo_path, 'rb') as f:
                logo_base64 = base64.b64encode(f.read()).decode('utf-8')
        else:
            fallback_path = "/Users/nikola/Downloads/inventory_management/Basic_Inventory_management/frontend/logo.png"
            if os.path.exists(fallback_path):
                with open(fallback_path, 'rb') as f:
                    logo_base64 = base64.b64encode(f.read()).decode('utf-8')
    except Exception:
        pass

    # Extract customer info
    cust_name = "Anonymous/Walk-in"
    cust_address = "N/A"
    cust_phone = "N/A"
    cust_gstin = "N/A"
    cust_state = "N/A"

    if invoice.customer:
        cust_name = invoice.customer.name
        cust_phone = invoice.customer.phone or "N/A"
        
        # Hardcode Uttrayan details if name matches or phone matches
        if "uttrayan" in cust_name.lower() or cust_phone in ["6292264489", "6293693085"]:
            cust_name = "UTTRAYAN FINANCIAL SERVICES PVT. LTD."
            cust_address = "12th Floor, Unit No. 1202, Plot No. G-1, Infinity Benchmark, EP & GP Block, Salt Lake City, Bidhan Nagar, North Twenty Four Parganas. PIN: 700091"
            cust_phone = "6292264489, 6293693085"
            cust_gstin = "19AABCC0070E1Z6"
            cust_state = "19-West Bengal"
        else:
            cust_state = "19-West Bengal"  # Default state

    # Format timestamp
    date_str = invoice.created_at.astimezone().strftime("%d-%m-%Y")

    # Generate items table HTML
    items_html = ""
    for i, item in enumerate(invoice.items):
        prod_name = item.product.name if item.product else "Unknown Product"
        hsn = get_hsn_code(prod_name)
        qty_val = item.quantity
        rate_val = item.unit_price
        total_val = item.line_total
        
        items_html += f"""
        <tr>
            <td style="text-align: center; border: 1px solid #cbd5e1; padding: 10px 8px;">{i + 1}</td>
            <td style="border: 1px solid #cbd5e1; padding: 10px 8px; font-weight: 600;">{prod_name}</td>
            <td style="text-align: center; border: 1px solid #cbd5e1; padding: 10px 8px;">{hsn}</td>
            <td style="text-align: center; border: 1px solid #cbd5e1; padding: 10px 8px;">{qty_val}</td>
            <td style="text-align: right; border: 1px solid #cbd5e1; padding: 10px 8px;">₹{rate_val:.2f}</td>
            <td style="text-align: right; border: 1px solid #cbd5e1; padding: 10px 8px; font-weight: bold;">₹{total_val:.2f}</td>
        </tr>
        """

    amount_in_words = num_to_words(invoice.total_amount)

    return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Quotation - {invoice.invoice_number}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <!-- Outfit & Inter Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&family=Outfit:wght@500;700;800&display=swap" rel="stylesheet">
    <style>
        @page {{
            size: A4;
            margin: 0;
        }}
        body {{
            font-family: 'Inter', sans-serif;
            background-color: #f1f5f9;
            margin: 0;
            padding: 20px 0;
            color: #1e293b;
        }}
        .invoice-page {{
            background-color: #ffffff;
            width: 210mm;
            min-height: 297mm;
            margin: 0 auto;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.08);
            position: relative;
            box-sizing: border-box;
            display: flex;
            flex-direction: column;
        }}
        .header-banner {{
            background-color: #0f172a;
            color: #ffffff;
            padding: 25px 30px;
            border-bottom: 4px solid #eab308;
            position: relative;
        }}
        .header-container {{
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        .header-left {{
            flex-grow: 1;
        }}
        .header-right {{
            text-align: right;
            margin-left: 20px;
        }}
        .logo-img {{
            height: 65px;
            width: 65px;
            object-fit: contain;
            background: white;
            border-radius: 8px;
            padding: 4px;
            border: 1px solid #eab308;
        }}
        .invoice-body {{
            padding: 30px 40px;
            flex-grow: 1;
        }}
        .info-section {{
            display: flex;
            justify-content: space-between;
            margin-bottom: 30px;
        }}
        .info-col-left {{
            width: 55%;
        }}
        .info-col-right {{
            width: 40%;
            text-align: right;
        }}
        .section-title {{
            font-size: 13px;
            font-weight: 700;
            color: #475569;
            text-transform: uppercase;
            margin-bottom: 8px;
            border-bottom: 2px solid #f1f5f9;
            padding-bottom: 4px;
            letter-spacing: 0.5px;
        }}
        .customer-name {{
            font-size: 16px;
            font-weight: 700;
            color: #0f172a;
            margin-bottom: 6px;
        }}
        .customer-details {{
            font-size: 12px;
            color: #475569;
            line-height: 1.5;
        }}
        .invoice-details-table {{
            width: 100%;
            font-size: 12px;
            margin-top: 5px;
            border-collapse: collapse;
        }}
        .invoice-details-table td {{
            padding: 3px 0;
            vertical-align: top;
        }}
        .invoice-details-table td.label {{
            color: #64748b;
            font-weight: 600;
            text-align: right;
            padding-right: 8px;
            width: 60%;
        }}
        .invoice-details-table td.val {{
            color: #0f172a;
            font-weight: 700;
            text-align: right;
        }}
        .items-table {{
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 30px;
            font-size: 12px;
        }}
        .items-table th {{
            background-color: #f8fafc;
            border: 1px solid #cbd5e1;
            padding: 10px 8px;
            font-weight: 700;
            color: #334155;
            text-transform: uppercase;
            font-size: 11px;
            letter-spacing: 0.5px;
        }}
        .items-table td {{
            border: 1px solid #cbd5e1;
            padding: 10px 8px;
            vertical-align: middle;
        }}
        .summary-section {{
            display: flex;
            justify-content: space-between;
            margin-top: 10px;
        }}
        .summary-left {{
            width: 55%;
        }}
        .summary-right {{
            width: 40%;
        }}
        .totals-table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 12px;
        }}
        .totals-table td {{
            padding: 6px 0;
        }}
        .totals-table td.label {{
            color: #475569;
            text-align: right;
            padding-right: 15px;
        }}
        .totals-table td.val {{
            text-align: right;
            font-weight: 600;
            color: #0f172a;
        }}
        .totals-table tr.grand-total td {{
            border-top: 2px solid #cbd5e1;
            border-bottom: 2px solid #cbd5e1;
            padding: 10px 0;
            font-size: 15px;
            font-weight: 800;
        }}
        .totals-table tr.grand-total td.val {{
            color: #0f172a;
        }}
        .bank-block {{
            background-color: #f8fafc;
            border: 1px solid #e2e8f0;
            border-radius: 6px;
            padding: 12px;
            margin-top: 15px;
            font-size: 11px;
        }}
        .bank-title {{
            font-weight: 700;
            color: #334155;
            text-transform: uppercase;
            margin-bottom: 6px;
            letter-spacing: 0.5px;
            border-bottom: 1px solid #e2e8f0;
            padding-bottom: 4px;
        }}
        .bank-details td {{
            padding: 2px 0;
        }}
        .bank-details td.lbl {{
            color: #64748b;
            width: 35%;
        }}
        .bank-details td.val {{
            font-weight: 600;
            color: #334155;
        }}
        .terms-block {{
            margin-top: 15px;
            font-size: 11px;
            color: #64748b;
            line-height: 1.5;
        }}
        .signatory-block {{
            margin-top: 40px;
            text-align: right;
            font-size: 12px;
        }}
        .footer-banner {{
            background-color: #0f172a;
            color: #ffffff;
            border-top: 3px solid #eab308;
            padding: 15px 30px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-top: auto;
        }}
        .print-bar {{
            text-align: center;
            margin-bottom: 15px;
        }}
        .print-btn {{
            padding: 10px 24px;
            background: #0f172a;
            color: white;
            border: none;
            font-size: 14px;
            font-weight: bold;
            border-radius: 6px;
            cursor: pointer;
            box-shadow: 0 4px 10px rgba(0,0,0,0.15);
            font-family: sans-serif;
            transition: background 0.2s;
        }}
        .print-btn:hover {{
            background: #1e293b;
        }}
        @media print {{
            body {{
                background-color: #ffffff;
                padding: 0;
                margin: 0;
            }}
            .invoice-page {{
                width: 100%;
                min-height: 100%;
                box-shadow: none;
                margin: 0;
                padding-bottom: 0;
            }}
            .print-bar {{
                display: none !important;
            }}
        }}
    </style>
</head>
<body>
    <div class="print-bar">
        <button class="print-btn" onclick="window.print()">Print Invoice / Quotation</button>
    </div>
    
    <div class="invoice-page">
        <div class="header-banner">
            <div class="header-container">
                <div class="header-left">
                    <div style="color: #eab308; font-family: 'Outfit', sans-serif; font-size: 26px; font-weight: 800; text-transform: uppercase; margin-bottom: 4px; letter-spacing: 0.5px;">Master of Security System</div>
                    <div style="color: #fef08a; font-size: 13px; font-weight: 600; font-style: italic; margin-bottom: 4px;">Prop: Rupchand Sk</div>
                    <div style="font-size: 12px; font-weight: 600; color: #ffffff; margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.8px;">Government & General Order Supplier</div>
                    <div style="font-size: 11px; color: #cbd5e1; font-weight: 500;">GST: 19KJEPS3322A1ZA &nbsp;|&nbsp; UDYAM-WB-13-0061558 &nbsp;|&nbsp; PAN: KJEPS3322A</div>
                </div>
                <div class="header-right">
                    {"<img src='data:image/png;base64," + logo_base64 + "' class='logo-img' alt='Logo'>" if logo_base64 else ""}
                </div>
            </div>
        </div>
        
        <div class="invoice-body">
            <div class="info-section">
                <div class="info-col-left">
                    <div class="section-title">Estimate For / Billing To</div>
                    <div class="customer-name">{cust_name}</div>
                    <div class="customer-details">
                        {"<div>" + cust_address + "</div>" if cust_address != "N/A" else ""}
                        <div><strong>Contact:</strong> {cust_phone}</div>
                        {"<div><strong>GSTIN:</strong> " + cust_gstin + "</div>" if cust_gstin != "N/A" else ""}
                        {"<div><strong>State:</strong> " + cust_state + "</div>" if cust_state != "N/A" else ""}
                    </div>
                </div>
                <div class="info-col-right">
                    <div style="color: #0f172a; font-family: 'Outfit', sans-serif; font-size: 20px; font-weight: 800; text-transform: uppercase; margin-bottom: 8px; letter-spacing: 0.5px;">Quotation</div>
                    <table class="invoice-details-table">
                        <tr>
                            <td class="label">Estimate No:</td>
                            <td class="val">{invoice.invoice_number}</td>
                        </tr>
                        <tr>
                            <td class="label">Date:</td>
                            <td class="val">{date_str}</td>
                        </tr>
                        <tr>
                            <td class="label">Prepared By:</td>
                            <td class="val">{invoice.user.name}</td>
                        </tr>
                    </table>
                </div>
            </div>
            
            <table class="items-table">
                <thead>
                    <tr>
                        <th style="width: 6%; text-align: center;">S/N</th>
                        <th style="width: 52%; text-align: left;">Item name</th>
                        <th style="width: 14%; text-align: center;">HSN/SAC</th>
                        <th style="width: 8%; text-align: center;">Qty</th>
                        <th style="width: 10%; text-align: right;">Price/Unit</th>
                        <th style="width: 10%; text-align: right;">Amount</th>
                    </tr>
                </thead>
                <tbody>
                    {items_html}
                </tbody>
            </table>
            
            <div class="summary-section">
                <div class="summary-left">
                    <div style="font-size: 11px; margin-bottom: 12px;">
                        <strong style="color: #475569; text-transform: uppercase; font-size: 10px; display: block; margin-bottom: 4px;">Estimate Amount in Words:</strong>
                        <span style="font-style: italic; font-weight: 700; color: #1e293b; font-size: 12px;">{amount_in_words}</span>
                    </div>
                    
                    <div class="bank-block">
                        <div class="bank-title">Bank Details</div>
                        <table class="bank-details" style="width: 100%; border-collapse: collapse;">
                            <tr>
                                <td class="lbl">Account Name:</td>
                                <td class="val">MASTER OF SECURITY SYSTEM</td>
                            </tr>
                            <tr>
                                <td class="lbl">Bank Name:</td>
                                <td class="val">STATE BANK OF INDIA, CHUNAKHALI</td>
                            </tr>
                            <tr>
                                <td class="lbl">Account No:</td>
                                <td class="val">00000042871592004</td>
                            </tr>
                            <tr>
                                <td class="lbl">IFSC Code:</td>
                                <td class="val">SBIN0015956</td>
                            </tr>
                        </table>
                    </div>
                    
                    <div class="terms-block">
                        <strong style="color: #475569; text-transform: uppercase; font-size: 10px; display: block; margin-bottom: 2px;">Terms and Conditions:</strong>
                        ALL Items under Cover have 1 year warranty from the date of Handover. ESTIMATE VALUES FOR ONE WEEK
                    </div>
                </div>
                
                <div class="summary-right">
                    <table class="totals-table">
                        <tr>
                            <td class="label">Subtotal:</td>
                            <td class="val">₹{invoice.subtotal:.2f}</td>
                        </tr>
                        <tr>
                            <td class="label">Tax (GST):</td>
                            <td class="val">₹{invoice.tax_amount:.2f}</td>
                        </tr>
                        <tr>
                            <td class="label">Discount:</td>
                            <td class="val">-₹{invoice.discount_amount:.2f}</td>
                        </tr>
                        <tr class="grand-total">
                            <td class="label" style="font-weight: 800;">NET TOTAL:</td>
                            <td class="val">₹{invoice.total_amount:.2f}</td>
                        </tr>
                    </table>
                    
                    <div class="signatory-block">
                        <div style="color: #475569; font-weight: 600; font-size: 11px; margin-bottom: 50px;">For Master of Security System:</div>
                        <div style="border-top: 1px solid #cbd5e1; display: inline-block; padding-top: 4px; font-weight: 700; color: #1e293b; width: 150px; text-align: center;">Authorized Signatory</div>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="footer-banner">
            <div style="color: #ffffff; font-size: 11px; display: flex; align-items: center; max-width: 380px;">
                <span style="color: #eab308; font-size: 14px; margin-right: 6px;">📍</span>Chunakhali Nimtala, Berhampore, Murshidabad, Pin-742149, West Bengal, India
            </div>
            <div style="color: #ffffff; font-size: 11px; text-align: right; line-height: 1.5;">
                <div><span style="color: #eab308; font-size: 12px; margin-right: 4px;">📞</span>9064797437, 8436766325</div>
                <div><span style="color: #eab308; font-size: 12px; margin-right: 4px;">✉️</span>mastermail8436@gmail.com</div>
                <div><span style="color: #eab308; font-size: 12px; margin-right: 4px;">🌐</span>https://masterofsecuritysystem.com</div>
            </div>
        </div>
    </div>
</body>
</html>
"""
