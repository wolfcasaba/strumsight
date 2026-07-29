"""SQLAlchemy engine/session construction and the request-scoped DB dependency."""

from collections.abc import Generator

from fastapi import Request
from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker


class Base(DeclarativeBase):
    """Declarative base for all ORM models."""


def create_database_engine(database_url: str) -> Engine:
    """Build an engine without opening a connection or mutating the schema."""
    connect_args = (
        {"check_same_thread": False}
        if database_url.startswith("sqlite")
        else {}
    )
    engine = create_engine(database_url, connect_args=connect_args)
    enable_sqlite_foreign_keys(engine)
    return engine


def enable_sqlite_foreign_keys(engine: Engine) -> None:
    """Enforce declared foreign keys on every SQLite DBAPI connection."""
    if engine.dialect.name != "sqlite":
        return

    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, _connection_record) -> None:
        previous_autocommit = getattr(dbapi_connection, "autocommit", None)
        try:
            if previous_autocommit is not None:
                dbapi_connection.autocommit = True
            cursor = dbapi_connection.cursor()
            try:
                cursor.execute("PRAGMA foreign_keys=ON")
            finally:
                cursor.close()
        finally:
            if previous_autocommit is not None:
                dbapi_connection.autocommit = previous_autocommit


def create_session_factory(engine: Engine) -> sessionmaker[Session]:
    """Bind the request-session factory to one application-owned engine."""
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


def get_db(request: Request) -> Generator[Session, None, None]:
    """Yield a request-scoped session, always closed afterwards."""
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()
