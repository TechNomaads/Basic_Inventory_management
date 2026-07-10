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
from app.models.user import UserModel
from app.models.invoice import InvoiceModel, InvoiceItemModel, PaymentMode
from app.models.company import CompanyModel
from app.models.product import ProductModel
from app.models.inventory import InventoryModel
from app.models.stock_transaction import StockTransactionModel, TransactionType
from app.models.audit_log import AuditAction
from app.schemas.billing import CheckoutRequest, CheckoutItem, InvoiceUpdateRequest
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


async def generate_invoice_number(db: AsyncSession, prefix: str = "INV") -> str:
    """
    Generate the next sequential invoice number for the current year.
    Format: PREFIX-YYYY-XXXXX (e.g., INV-2026-00001)
    Locks the matching rows using SELECT ... FOR UPDATE to avoid concurrency duplication.
    """
    year = datetime.now(timezone.utc).year
    full_prefix = f"{prefix}-{year}-"

    # Query the highest invoice number for this year, locking it
    stmt = (
        select(InvoiceModel.invoice_number)
        .where(InvoiceModel.invoice_number.like(f"{full_prefix}%"))
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

    return f"{full_prefix}{next_seq:05d}"


async def process_checkout(
    db: AsyncSession,
    data: CheckoutRequest,
    user_id: uuid.UUID,
    ip_address: str | None = None,
) -> InvoiceModel:
    """
    Atomic checkout within a database transaction.
    """
    is_quote = (data.invoice_type == "quotation")

    # 1. Retrieve or Create Customer
    customer = await get_or_create_customer(db, data.customer_phone, data.customer_name)
    if customer:
        if data.customer_gst and data.customer_gst.strip():
            gst_val = data.customer_gst.strip()
            customer.gst_number = gst_val
            if not customer.address:
                gst = gst_val.upper()
                state_code = gst[:2]
                states = {
                    "01": "Jammu & Kashmir", "02": "Himachal Pradesh", "03": "Punjab", "04": "Chandigarh", 
                    "05": "Uttarakhand", "06": "Haryana", "07": "Delhi", "08": "Rajasthan", "09": "Uttar Pradesh", 
                    "10": "Bihar", "11": "Sikkim", "12": "Arunachal Pradesh", "13": "Nagaland", "14": "Manipur", 
                    "15": "Mizoram", "16": "Tripura", "17": "Meghalaya", "18": "Assam", "19": "West Bengal", 
                    "20": "Jharkhand", "21": "Odisha", "22": "Chhattisgarh", "23": "Madhya Pradesh", "24": "Gujarat", 
                    "26": "Dadra and Nagar Haveli and Daman and Diu", "27": "Maharashtra", "29": "Karnataka", 
                    "30": "Goa", "31": "Lakshadweep", "32": "Kerala", "33": "Tamil Nadu", "34": "Puducherry", 
                    "35": "Andaman & Nicobar Islands", "36": "Telangana", "37": "Andhra Pradesh", "38": "Ladakh"
                }
                state_name = states.get(state_code, "India")
                if len(gst) == 15:
                    customer.address = f"Plot {gst[3:6]}, Sector {gst[6:8]}, Industrial Area, {state_name} - {gst[9:12]}001"
                else:
                    customer.address = "India"
            await db.flush()
    customer_id = customer.id if customer else None

    # Fetch company details if provided
    company_name = None
    company_address = None
    company_logo = None
    if data.company_id:
        stmt_comp = select(CompanyModel).where(CompanyModel.id == data.company_id)
        comp_res = await db.execute(stmt_comp)
        company = comp_res.scalar_one_or_none()
        if company:
            company_name = company.name
            company_address = company.address
            company_logo = company.logo

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

        if not is_quote and inv.quantity < item.quantity:
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
    
    if not is_quote:
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
    else:
        # Quotations do not charge customer overdue amounts
        pass

    # 3. Generate Invoice Number (locks sequence)
    prefix = "QTN" if is_quote else "INV"
    invoice_number = await generate_invoice_number(db, prefix=prefix)

    # Fetch user's signature stamp if not overridden in checkout data
    prepared_by_sig = None
    if hasattr(data, 'prepared_by_signature_b64') and data.prepared_by_signature_b64:
        prepared_by_sig = data.prepared_by_signature_b64
    else:
        stmt_user = select(UserModel).where(UserModel.id == user_id)
        user_res = await db.execute(stmt_user)
        user_record = user_res.scalar_one_or_none()
        if user_record:
            prepared_by_sig = user_record.signature_stamp_b64

    # 4. Create Invoice Record
    invoice = InvoiceModel(
        id=uuid.uuid4(),
        invoice_number=invoice_number,
        location_id=data.location_id,
        user_id=user_id,
        customer_id=customer_id,
        invoice_type=data.invoice_type,
        company_id=data.company_id,
        company_name=company_name,
        company_address=company_address,
        company_logo=company_logo,
        prepared_by_signature_b64=prepared_by_sig,
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

    # 5. Process inventory deductions with optimistic lock checks & insert stock ledger logs (only if not quote)
    for idx, (item_model, qty_before, known_ver) in enumerate(invoice_items):
        item_model.invoice_id = invoice.id
        db.add(item_model)

        if not is_quote:
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
                raise ConflictException(
                    f"Concurrency conflict: Stock for product ID {update_data['product_id']} was modified by another transaction. Please refresh."
                )

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
            "invoice_type": data.invoice_type,
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
        logo_path = os.path.abspath(os.path.join(current_dir, "..", "assets", "logo.png"))
        if os.path.exists(logo_path):
            with open(logo_path, 'rb') as f:
                logo_base64 = base64.b64encode(f.read()).decode('utf-8')
    except Exception:
        pass

    # Load gem_logo.png in base64
    gem_logo_base64 = ""
    try:
        current_dir = os.path.dirname(os.path.abspath(__file__))
        gem_logo_path = os.path.abspath(os.path.join(current_dir, "..", "assets", "gem_logo.png"))
        if os.path.exists(gem_logo_path):
            with open(gem_logo_path, 'rb') as f:
                gem_logo_base64 = base64.b64encode(f.read()).decode('utf-8')
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
        cust_gstin = invoice.customer.gst_number or "N/A"
        cust_address = invoice.customer.address or "N/A"
        
        # Hardcode Uttrayan details if name matches or phone matches
        if "uttrayan" in cust_name.lower() or cust_phone in ["6292264489", "6293693085"]:
            cust_name = "UTTRAYAN FINANCIAL SERVICES PVT. LTD."
            cust_address = "12th Floor, Unit No. 1202, Plot No. G-1, Infinity Benchmark, EP & GP Block, Salt Lake City, Bidhan Nagar, North Twenty Four Parganas. PIN: 700091"
            cust_phone = "6292264489, 6293693085"
            cust_gstin = "19AABCC0070E1Z6"
            cust_state = "19-West Bengal"
        else:
            if cust_gstin != "N/A" and len(cust_gstin) >= 2:
                state_code = cust_gstin[:2]
                cust_state = f"{state_code}-State"
            else:
                cust_state = "19-West Bengal"

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

    comp_name = invoice.company_name or "Master of Security System"
    comp_address = invoice.company_address or "Government & General Order Supplier"
    comp_logo_base64 = logo_base64
    if invoice.company_logo:
        if "base64," in invoice.company_logo:
            comp_logo_base64 = invoice.company_logo.split("base64,")[1]
        else:
            comp_logo_base64 = invoice.company_logo

    if invoice.company_name:
        subtitle_html = f'<div style="font-size: 12px; color: #cbd5e1; font-weight: 500; margin-top: 4px;">{comp_address}</div>'
    else:
        subtitle_html = """
        <div style="font-size: 12px; font-weight: 600; color: #ffffff; margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.8px;">Government & General Order Supplier</div>
        <div style="font-size: 11px; color: #cbd5e1; font-weight: 500;">GST: 19KJEPS3322A1ZA &nbsp;|&nbsp; UDYAM-WB-13-0061558 &nbsp;|&nbsp; PAN: KJEPS3322A</div>
        """

    is_quote = (getattr(invoice, "invoice_type", "billing") == "quotation")
    title_label = "Quotation" if is_quote else "Tax Invoice"
    estimate_to_label = "Estimate For" if is_quote else "Billing To"
    no_label = "Estimate No:" if is_quote else "Invoice No:"
    words_label = "Estimate Amount in Words:" if is_quote else "Invoice Amount in Words:"
    signatory_label = f"For {comp_name}:"

    if invoice.company_name:
        footer_html = f"""
        <div class="footer-banner" style="background: #1e293b; color: #ffffff; padding: 15px 30px; display: flex; justify-content: space-between; align-items: center; border-radius: 0 0 8px 8px; margin-top: 30px; border-top: 3px solid #eab308;">
            <div style="font-size: 11px; max-width: 500px;">
                <span style="color: #eab308; font-size: 14px; margin-right: 6px;">📍</span>{comp_address}
            </div>
            <div style="font-size: 11px; text-align: right; line-height: 1.5;">
                <div>{comp_name}</div>
            </div>
        </div>
        """
    else:
        footer_html = """
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
        """

    return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{title_label} - {invoice.invoice_number}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
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
            -webkit-print-color-adjust: exact;
        }}
        .invoice-page {{
            width: 210mm;
            min-height: 297mm;
            margin: 0 auto;
            background-color: #ffffff;
            box-shadow: 0 10px 25px rgba(0,0,0,0.05);
            border-radius: 8px;
            display: flex;
            flex-direction: column;
        }}
        .header-banner {{
            background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
            padding: 25px 30px;
            color: #ffffff;
            border-radius: 8px 8px 0 0;
            border-bottom: 4px solid #eab308;
        }}
        .header-container {{
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        .header-left {{
            flex: 1;
        }}
        .header-right {{
            text-align: right;
            margin-left: 20px;
        }}
        .logo-img {{
            max-height: 65px;
            width: auto;
            filter: drop-shadow(0 2px 4px rgba(0,0,0,0.15));
        }}
        .invoice-body {{
            padding: 30px;
            flex-grow: 1;
            display: flex;
            flex-direction: column;
        }}
        .info-section {{
            display: flex;
            justify-content: space-between;
            margin-bottom: 30px;
            gap: 20px;
        }}
        .info-col-left {{
            flex: 1.2;
        }}
        .info-col-right {{
            flex: 0.8;
            text-align: right;
            display: flex;
            flex-direction: column;
            align-items: flex-end;
        }}
        .section-title {{
            font-family: 'Outfit', sans-serif;
            font-size: 10px;
            font-weight: 800;
            text-transform: uppercase;
            color: #64748b;
            letter-spacing: 1.5px;
            margin-bottom: 8px;
            border-bottom: 1px solid #e2e8f0;
            padding-bottom: 4px;
        }}
        .customer-name {{
            font-size: 15px;
            font-weight: 700;
            color: #0f172a;
            margin-bottom: 6px;
        }}
        .customer-details {{
            font-size: 11px;
            color: #475569;
            line-height: 1.5;
        }}
        .invoice-details-table {{
            border-collapse: collapse;
            font-size: 11px;
            margin-top: 4px;
        }}
        .invoice-details-table td {{
            padding: 3px 0;
        }}
        .invoice-details-table .label {{
            color: #64748b;
            font-weight: 600;
            padding-right: 15px;
            text-align: right;
        }}
        .invoice-details-table .val {{
            color: #0f172a;
            font-weight: 700;
            text-align: left;
        }}
        .items-table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 11px;
            margin-bottom: 25px;
        }}
        .items-table th {{
            background-color: #f8fafc;
            color: #475569;
            font-family: 'Outfit', sans-serif;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            border: 1px solid #cbd5e1;
            padding: 12px 8px;
        }}
        .items-table td {{
            border: 1px solid #cbd5e1;
            padding: 12px 8px;
            color: #334155;
            vertical-align: middle;
        }}
        .summary-section {{
            display: flex;
            justify-content: space-between;
            margin-top: auto;
            padding-top: 20px;
            border-top: 2px solid #e2e8f0;
            gap: 40px;
        }}
        .summary-left {{
            flex: 1.2;
        }}
        .summary-right {{
            flex: 0.8;
            display: flex;
            flex-direction: column;
            align-items: flex-end;
        }}
        .totals-table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 11px;
            margin-bottom: 20px;
        }}
        .totals-table td {{
            padding: 8px 12px;
            border: 1px solid #cbd5e1;
            color: #334155;
            vertical-align: middle;
        }}
        .bank-block {{
            background-color: #f8fafc;
            border: 1px solid #e2e8f0;
            border-radius: 6px;
            padding: 12px;
            margin-bottom: 15px;
        }}
        .bank-title {{
            font-family: 'Outfit', sans-serif;
            font-size: 9px;
            font-weight: 800;
            text-transform: uppercase;
            color: #475569;
            letter-spacing: 1px;
            margin-bottom: 6px;
            border-bottom: 1px dashed #cbd5e1;
            padding-bottom: 4px;
        }}
        .bank-details td {{
            padding: 2px 0;
            font-size: 10px;
        }}
        .bank-details .lbl {{
            color: #64748b;
            font-weight: 600;
            width: 90px;
        }}
        .bank-details .val {{
            color: #334155;
            font-weight: 700;
        }}
        .terms-block {{
            font-size: 9px;
            color: #64748b;
            line-height: 1.4;
        }}
        .signatory-block {{
            text-align: center;
            margin-top: 20px;
        }}
        .footer-banner {{
            background-color: #0f172a;
            color: #ffffff;
            border-top: 3px solid #eab308;
            padding: 15px 30px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        @media print {{
            body {{ background: white; padding: 0; }}
            .invoice-page {{ box-shadow: none; }}
        }}
    </style>
</head>
<body>
    <div class="invoice-page">
        <div class="header-banner">
            <div style="display: flex; align-items: center; justify-content: space-between; gap: 20px;">
                <!-- Left: GeM Logo -->
                <div style="width: 120px; flex-shrink: 0; text-align: left;">
                    {"<img src='data:image/png;base64," + gem_logo_base64 + "' style='max-height: 60px; width: auto; filter: drop-shadow(0 2px 4px rgba(0,0,0,0.15));' alt='GeM Logo'>" if gem_logo_base64 else ""}
                </div>
                <!-- Middle: Company Title & Details -->
                <div style="flex: 1; text-align: center;">
                    <div style="color: #eab308; font-family: 'Outfit', sans-serif; font-size: 24px; font-weight: 800; text-transform: uppercase; margin-bottom: 4px; letter-spacing: 0.5px;">{comp_name}</div>
                    {subtitle_html}
                </div>
                <!-- Right spacer to balance center alignment -->
                <div style="width: 120px; flex-shrink: 0;"></div>
            </div>
        </div>
        
        <div class="invoice-body">
            <div class="info-section">
                <div class="info-col-left">
                    <div class="section-title">{estimate_to_label}</div>
                    <div class="customer-name">{cust_name}</div>
                    <div class="customer-details">
                        {"<div>" + cust_address + "</div>" if cust_address != "N/A" else ""}
                        <div><strong>Contact:</strong> {cust_phone}</div>
                        {"<div><strong>GSTIN:</strong> " + cust_gstin + "</div>" if cust_gstin != "N/A" else ""}
                        {"<div><strong>State:</strong> " + cust_state + "</div>" if cust_state != "N/A" else ""}
                    </div>
                </div>
                <div class="info-col-right">
                    <div style="color: #0f172a; font-family: 'Outfit', sans-serif; font-size: 20px; font-weight: 800; text-transform: uppercase; margin-bottom: 8px; letter-spacing: 0.5px;">{title_label}</div>
                    <table class="invoice-details-table">
                        <tr>
                            <td class="label">{no_label}</td>
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
                        <strong style="color: #475569; text-transform: uppercase; font-size: 10px; display: block; margin-bottom: 4px;">{words_label}</strong>
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
                            <td class="label" style="background-color: #f8fafc; font-weight: 600; text-align: left; width: 110px;">Subtotal:</td>
                            <td class="val" style="font-weight: 700; text-align: right;">₹{invoice.subtotal:.2f}</td>
                        </tr>
                        <tr>
                            <td class="label" style="background-color: #f8fafc; font-weight: 600; text-align: left;">Tax (GST):</td>
                            <td class="val" style="font-weight: 700; text-align: right;">₹{invoice.tax_amount:.2f}</td>
                        </tr>
                        <tr>
                            <td class="label" style="background-color: #f8fafc; font-weight: 600; text-align: left;">Discount:</td>
                            <td class="val" style="font-weight: 700; text-align: right; color: #ef4444;">-₹{invoice.discount_amount:.2f}</td>
                        </tr>
                        <tr style="background-color: #f8fafc;">
                            <td class="label" style="font-weight: 800; font-family: 'Outfit', sans-serif; color: #0f172a; text-align: left; text-transform: uppercase;">Net Total:</td>
                            <td class="val" style="font-weight: 800; font-family: 'Outfit', sans-serif; color: #0f172a; text-align: right; font-size: 13px;">₹{invoice.total_amount:.2f}</td>
                        </tr>
                    </table>
                    
                    <div class="signatory-block" style="display: flex; flex-direction: column; align-items: center; margin-top: 15px; min-width: 180px;">
                        <div style="color: #475569; font-weight: 600; font-size: 11px; margin-bottom: 5px;">{signatory_label}</div>
                        <!-- Signature/Stamp space -->
                        <div style="height: 60px; display: flex; align-items: center; justify-content: center; margin-bottom: 5px;">
                            {"<img src='data:image/png;base64," + invoice.prepared_by_signature_b64 + "' style='max-height: 55px; width: auto; object-fit: contain; mix-blend-mode: multiply;' alt='Signature Stamp'>" if getattr(invoice, 'prepared_by_signature_b64', None) else ""}
                        </div>
                        <div style="border-top: 1px solid #cbd5e1; display: inline-block; padding-top: 4px; font-weight: 700; color: #1e293b; width: 150px; text-align: center;">Authorized Signatory</div>
                    </div>
                </div>
            </div>
        </div>
        
        {footer_html}
    </div>
</body>
</html>
"""


async def update_invoice(
    db: AsyncSession,
    invoice_id: uuid.UUID,
    data: InvoiceUpdateRequest,
    user_id: uuid.UUID,
    ip_address: str | None = None,
) -> InvoiceModel:
    """Update existing invoice customer details, payment mode, discount, and notes."""
    stmt = select(InvoiceModel).where(InvoiceModel.id == invoice_id).options(
        joinedload(InvoiceModel.customer)
    )
    res = await db.execute(stmt)
    invoice = res.scalar_one_or_none()
    if not invoice:
        raise NotFoundException(f"Invoice with ID {invoice_id} not found")

    old_values = {
        "customer_name": invoice.customer.name if invoice.customer else None,
        "customer_phone": invoice.customer.phone if invoice.customer else None,
        "payment_mode": invoice.payment_mode.value,
        "discount_amount": float(invoice.discount_amount),
        "total_amount": float(invoice.total_amount),
        "notes": invoice.notes,
    }

    is_quote = (getattr(invoice, "invoice_type", "billing") == "quotation")

    # 1. Revert old customer overdue if not a quote and customer existed
    if not is_quote and invoice.customer:
        old_remaining = float(invoice.total_amount) - float(invoice.amount_paid)
        invoice.customer.overdue_amount = float(invoice.customer.overdue_amount) - old_remaining

    # 2. Update customer if phone/name changed
    new_customer = invoice.customer
    if data.customer_phone is not None or data.customer_name is not None:
        phone = data.customer_phone if data.customer_phone is not None else (invoice.customer.phone if invoice.customer else None)
        name = data.customer_name if data.customer_name is not None else (invoice.customer.name if invoice.customer else None)
        if phone or name:
            new_customer = await get_or_create_customer(db, phone, name)
            invoice.customer_id = new_customer.id if new_customer else None

    # 3. Update discount & totals
    if data.discount_amount is not None:
        invoice.discount_amount = float(data.discount_amount)
        
    invoice.total_amount = max(0.0, float(invoice.subtotal) + float(invoice.tax_amount) - float(invoice.discount_amount))
    
    # If payment was full, keep it full
    if old_values["total_amount"] == float(invoice.amount_paid):
        invoice.amount_paid = invoice.total_amount
    else:
        # Cap amount_paid to total_amount
        invoice.amount_paid = min(float(invoice.amount_paid), float(invoice.total_amount))

    # 4. Apply new customer overdue if not a quote and new customer exists
    if not is_quote and new_customer:
        new_remaining = float(invoice.total_amount) - float(invoice.amount_paid)
        new_customer.overdue_amount = float(new_customer.overdue_amount) + new_remaining

    # 5. Update other fields
    if data.payment_mode is not None:
        invoice.payment_mode = PaymentMode(data.payment_mode)
    if data.notes is not None:
        invoice.notes = data.notes

    await db.flush()

    # Audit log
    new_values = {
        "customer_name": new_customer.name if new_customer else None,
        "customer_phone": new_customer.phone if new_customer else None,
        "payment_mode": invoice.payment_mode.value,
        "discount_amount": float(invoice.discount_amount),
        "total_amount": float(invoice.total_amount),
        "notes": invoice.notes,
    }
    await write_audit_log(
        db=db,
        user_id=user_id,
        table_name="invoices",
        record_id=invoice.id,
        action=AuditAction.update,
        old_values=old_values,
        new_values=new_values,
        ip_address=ip_address,
    )

    await db.commit()

    # Reload with relations
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

