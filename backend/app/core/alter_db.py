import asyncio
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy import text
from app.core.config import settings

async def alter_tables():
    print("🔄 Running database alterations...")
    engine = create_async_engine(settings.DATABASE_URL)
    async with engine.begin() as conn:
        # Add credit_limit and overdue_amount to customers
        await conn.execute(text("ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_limit NUMERIC(12, 2) NOT NULL DEFAULT 10000.00"))
        await conn.execute(text("ALTER TABLE customers ADD COLUMN IF NOT EXISTS overdue_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00"))
        await conn.execute(text("ALTER TABLE customers ADD COLUMN IF NOT EXISTS gst_number VARCHAR(50) NULL"))
        await conn.execute(text("ALTER TABLE customers ADD COLUMN IF NOT EXISTS address TEXT NULL"))
        
        # Add address, active_company_id and signature_stamp_b64 to users
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS address TEXT NULL"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS active_company_id UUID NULL REFERENCES companies(id) ON DELETE SET NULL"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS signature_stamp_b64 TEXT NULL"))
        
        # Add amount_paid and prepared_by_signature_b64 to invoices
        await conn.execute(text("ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(12, 2) NOT NULL DEFAULT 0.00"))
        await conn.execute(text("ALTER TABLE invoices ADD COLUMN IF NOT EXISTS invoice_type VARCHAR(50) NOT NULL DEFAULT 'billing'"))
        await conn.execute(text("ALTER TABLE invoices ADD COLUMN IF NOT EXISTS company_id UUID NULL REFERENCES companies(id) ON DELETE SET NULL"))
        await conn.execute(text("ALTER TABLE invoices ADD COLUMN IF NOT EXISTS company_name VARCHAR(150) NULL"))
        await conn.execute(text("ALTER TABLE invoices ADD COLUMN IF NOT EXISTS company_address TEXT NULL"))
        await conn.execute(text("ALTER TABLE invoices ADD COLUMN IF NOT EXISTS company_logo TEXT NULL"))
        await conn.execute(text("ALTER TABLE invoices ADD COLUMN IF NOT EXISTS prepared_by_signature_b64 TEXT NULL"))
        
        print("  ✅ Columns checked and added successfully")
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(alter_tables())
