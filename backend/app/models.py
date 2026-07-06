"""ORM models: a User and their one-to-one settings profile."""

from datetime import datetime, timezone

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String, unique=True, index=True, nullable=False)
    hashed_password: Mapped[str] = mapped_column(String, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    settings: Mapped["UserSettings"] = relationship(
        back_populates="user",
        uselist=False,
        cascade="all, delete-orphan",
    )


class UserSettings(Base):
    """The per-user profile synced from the app's local settings.

    Defaults mirror the Flutter client (theme=system, locale=system/null,
    confidence threshold 0.45, tuning A4=440).
    """

    __tablename__ = "user_settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )

    theme_mode: Mapped[str] = mapped_column(String, default="system", nullable=False)
    # null => follow the system language.
    locale: Mapped[str | None] = mapped_column(String, nullable=True)
    confidence_threshold: Mapped[float] = mapped_column(
        Float, default=0.45, nullable=False
    )
    tuning_a4: Mapped[int] = mapped_column(Integer, default=440, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False
    )

    user: Mapped[User] = relationship(back_populates="settings")
