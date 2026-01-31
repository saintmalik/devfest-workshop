"""
Module containing environment configurations
"""

import os


class Development:
    """
    Development environment configuration
    """

    DEBUG = True
    TESTING = False
    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY")
    SQLALCHEMY_DATABASE_URI = os.getenv("DATABASE_URL")
    ENABLE_METRICS = os.getenv("ENABLE_METRICS", "true").lower() == "true"
    ENABLE_TRACING = os.getenv("ENABLE_TRACING", "true").lower() == "true"


class Production:
    """
    Production environment configuration
    """

    DEBUG = False
    TESTING = False
    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY")
    SQLALCHEMY_DATABASE_URI = os.getenv("DATABASE_URL")
    ENABLE_METRICS = os.getenv("ENABLE_METRICS", "true").lower() == "true"
    ENABLE_TRACING = os.getenv("ENABLE_TRACING", "true").lower() == "true"


class Testing:
    """
    Testing environment configuration (uses SQLite for fast unit tests)
    """

    DEBUG = True
    TESTING = True
    # Must be provided by CI/CD pipeline
    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY")

    # Prefer constructing from components to ensure safe encoding
    # Otherwise fall back to pre-defined DATABASE_URL
    _db_user = os.getenv("DB_USER")
    _db_password = os.getenv("DB_PASSWORD")
    _db_host = os.getenv("DB_HOST")
    _db_port = os.getenv("DB_PORT")
    _db_name = os.getenv("DB_NAME")

    if _db_user and _db_password and _db_host:
        from urllib.parse import quote_plus

        password = quote_plus(_db_password)
        _db_url = (
            f"postgresql+psycopg2://{_db_user}:{password}@{_db_host}:{_db_port}/{_db_name}"
        )
    else:
        _db_url = os.getenv("DATABASE_URL", "sqlite:///:memory:")

    SQLALCHEMY_DATABASE_URI = _db_url
    ENABLE_METRICS = False
    ENABLE_TRACING = False


app_config = {
    "development": Development,
    "production": Production,
    "testing": Testing,
}
