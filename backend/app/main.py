"""
Module: main
Description: FastAPI application factory — assembles all components.

Responsibilities:
    - Create the FastAPI app instance
    - Include all API routers
    - Mount Socket.io ASGI app
    - Configure CORS middleware
    - Provide /health endpoint

Dependencies:
    - All routers, Socket.io app, config
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.routers import auth, audit, inventory, pending, products, reports, users, billing, customers
from app.sockets.events import socket_app


def create_app() -> FastAPI:
    """
    Application factory — creates and configures the FastAPI instance.

    Returns:
        Fully configured FastAPI application.
    """
    application = FastAPI(
        title=settings.APP_NAME,
        version=settings.APP_VERSION,
        description="Inventory Management System API",
        docs_url="/docs",
        redoc_url="/redoc",
    )

    # ── CORS middleware ──────────────────────────────────────────
    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ── Include routers ──────────────────────────────────────────
    application.include_router(auth.router)
    application.include_router(products.router)
    application.include_router(inventory.router)
    application.include_router(pending.router)
    application.include_router(reports.router)
    application.include_router(users.router)
    application.include_router(audit.router)
    application.include_router(billing.router)
    application.include_router(customers.router)


    # ── Mount Socket.IO ──────────────────────────────────────────
    class SocketIOPathMiddleware:
        """
        Middleware to strip the '/ws' prefix from the scope path for Socket.IO.
        This is necessary because newer Starlette/FastAPI versions do not mutate scope['path']
        when routing requests to mounted applications.
        """
        def __init__(self, app):
            self.app = app

        async def __call__(self, scope, receive, send):
            if scope["type"] in ("http", "websocket") and scope.get("path", "").startswith("/ws"):
                scope = dict(scope)  # shallow copy
                scope["path"] = scope["path"][3:]  # Strip '/ws'
                if not scope["path"].startswith("/"):
                    scope["path"] = "/" + scope["path"]
            await self.app(scope, receive, send)

    application.mount("/ws", SocketIOPathMiddleware(socket_app))

    # ── Health check ─────────────────────────────────────────────
    @application.get("/health", tags=["Health"])
    async def health_check() -> dict:
        """Simple health check for Docker and load balancers."""
        return {"status": "healthy", "version": settings.APP_VERSION}

    return application


# Create the app instance — Uvicorn targets this
app = create_app()
