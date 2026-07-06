"""Pydantic request/response schemas — the API contract with the Flutter app."""

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field

ThemeMode = Literal["light", "dark", "system"]
Locale = Literal["en", "hu"]


# ---- auth ----------------------------------------------------------------


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=72)  # bcrypt caps at 72 bytes


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: EmailStr
    created_at: datetime


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


# ---- settings ------------------------------------------------------------


class SettingsOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    theme_mode: ThemeMode
    locale: Optional[Locale]
    confidence_threshold: float
    tuning_a4: int
    updated_at: datetime


class SettingsUpdate(BaseModel):
    """Partial update — every field optional so the client can PUT just what
    changed. `locale=null` is a meaningful value (follow system language), so
    callers distinguish "clear" from "leave unchanged" by omitting the key."""

    model_config = ConfigDict(extra="forbid")

    theme_mode: Optional[ThemeMode] = None
    locale: Optional[Locale] = None
    confidence_threshold: Optional[float] = Field(default=None, ge=0.0, le=1.0)
    tuning_a4: Optional[int] = Field(default=None, ge=400, le=480)
