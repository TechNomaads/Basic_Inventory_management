# Inventory Management System — Backend

## Overview
Production-ready REST API for inventory management built with FastAPI, PostgreSQL, Redis, and Socket.IO.

## Quick Start

### Prerequisites
- Docker & Docker Compose
- Python 3.11+ (for local development)

### Using Docker (recommended)
```bash
# Copy environment file
cp backend/.env.example backend/.env

# Start all services
docker-compose up --build

# API available at http://localhost:8000
# Docs at http://localhost:8000/docs
```

### Local Development
```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run Alembic migrations
alembic upgrade head

# Start server
uvicorn app.main:app --reload --port 8000
```

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/auth/login | Public | Login with email/password |
| POST | /api/v1/auth/refresh | Public | Refresh JWT tokens |
| POST | /api/v1/auth/logout | Bearer | Invalidate refresh token |
| GET | /api/v1/products | Bearer | List/search products |
| GET | /api/v1/products/{barcode} | Bearer | Barcode lookup |
| POST | /api/v1/products | Admin/Manager | Create product |
| PUT | /api/v1/products/{id} | Admin/Manager | Update product |
| DELETE | /api/v1/products/{id} | Admin | Soft delete product |
| GET | /api/v1/inventory/{location_id} | Bearer | Location inventory |
| POST | /api/v1/inventory/transaction | Bearer | Stock in/out |
| POST | /api/v1/inventory/adjustment | Bearer | Stock adjustment |
| GET | /api/v1/pending | Manager/Admin | Pending adjustments |
| POST | /api/v1/pending/{id}/approve | Manager/Admin | Approve adjustment |
| POST | /api/v1/pending/{id}/reject | Manager/Admin | Reject adjustment |
| GET | /api/v1/reports/summary | Bearer | Dashboard metrics |
| GET | /api/v1/reports/transactions | Bearer | Transaction history |
| GET | /api/v1/users | Admin | List users |
| POST | /api/v1/users | Admin | Create user |
| GET | /api/v1/audit | Admin | Audit log |

## Architecture
- **Repositories**: Async database query layer with generic CRUD base
- **Services**: Business logic with audit logging
- **Routers**: FastAPI endpoints with role guards
- **Socket.IO**: Real-time stock updates via location-based rooms
- **Optimistic Locking**: Version-based concurrency control on inventory

## Running Tests
```bash
pip install aiosqlite  # SQLite async driver for tests
pytest tests/ -v
```
