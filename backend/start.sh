#!/bin/bash
set -e

# Ensure app module is importable
export PYTHONPATH=/app:$PYTHONPATH

echo "🔄 Creating database tables..."
python -c "
import asyncio, time
from sqlalchemy.ext.asyncio import create_async_engine
from app.core.config import settings
from app.core.database import Base
import app.models

async def create_tables():
    for i in range(15):
        try:
            engine = create_async_engine(settings.DATABASE_URL)
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
            await engine.dispose()
            print('  ✅ Database tables created successfully')
            return
        except Exception as e:
            print(f'  ⏳ Database connection attempt {i+1} failed. Retrying in 2s...')
            await asyncio.sleep(2)
    raise Exception('Could not connect to database after 15 attempts')

asyncio.run(create_tables())
"

echo "🔄 Running column migrations..."
python -m app.core.alter_db

echo "🌱 Seeding admin user (if not exists)..."
python -m app.seed

echo "🚀 Starting FastAPI server..."
if [ "$DEBUG" = "True" ] || [ "$DEBUG" = "true" ] || [ "$DEBUG" = "1" ]; then
    echo "  -> Running in DEVELOPMENT mode with hot-reload"
    exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
else
    echo "  -> Running in PRODUCTION mode"
    exec uvicorn app.main:app --host 0.0.0.0 --port 8000
fi
