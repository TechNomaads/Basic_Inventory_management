#!/bin/bash
set -e

# Ensure app module is importable
export PYTHONPATH=/app:$PYTHONPATH

echo "🔄 Creating database tables..."
python -c "
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine
from app.core.config import settings
from app.core.database import Base
import app.models  # Import all models so Base.metadata knows about them

async def create_tables():
    engine = create_async_engine(settings.DATABASE_URL)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await engine.dispose()
    print('  ✅ Database tables created successfully')

asyncio.run(create_tables())
"

echo "🔄 Running column migrations..."
python -m app.core.alter_db

echo "🌱 Seeding admin user (if not exists)..."
python -m app.seed

echo "🚀 Starting FastAPI server..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
