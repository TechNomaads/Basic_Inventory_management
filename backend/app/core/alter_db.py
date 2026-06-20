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
        
        # Add amount_paid to invoices
        await conn.execute(text("ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(12, 2) NOT NULL DEFAULT 0.00"))
        
        print("  ✅ Columns checked and added successfully")
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(alter_tables())
