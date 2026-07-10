"""
Module: config
Description: Application configuration via pydantic-settings.

Responsibilities:
    - Read all environment variables from .env file
    - Provide typed, validated configuration to the entire app
    - Centralise sensitive values (JWT secret, DB URL, etc.)

Dependencies:
    - pydantic-settings

Usage:
    from app.core.config import settings
    print(settings.DATABASE_URL)
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables / .env file."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    # ── App ──────────────────────────────────────────────────────
    APP_NAME: str = "InventoryManager"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    CORS_ORIGINS: list[str] = [
        "http://localhost:3000",
        "http://localhost:8080",
        "http://localhost:5000",
        "http://localhost:5500",
        "http://localhost:*",
    ]

    # ── Database ─────────────────────────────────────────────────
    DATABASE_URL: str = "postgresql+asyncpg://inventory:inventory_secret@db:5432/inventory_db"

    # ── Redis ────────────────────────────────────────────────────
    REDIS_URL: str = "redis://redis:6379/0"

    # ── JWT ──────────────────────────────────────────────────────
    JWT_SECRET_KEY: str = "change-me-to-a-strong-random-secret"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 10080  # 7 days
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30  # 30 days

    # ── Business rules ───────────────────────────────────────────
    ADJUSTMENT_THRESHOLD: int = 10


# Singleton instance — import this everywhere
settings = Settings()
