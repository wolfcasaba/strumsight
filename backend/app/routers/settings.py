"""Per-user settings profile — the cloud copy the app syncs to."""

from fastapi import APIRouter

from ..deps import CurrentUser, DbSession
from ..models import UserSettings
from ..schemas import SettingsOut, SettingsUpdate

router = APIRouter(prefix="/settings", tags=["settings"])


def _ensure_settings(user, db) -> UserSettings:
    """Return the user's settings row, creating a default one if missing
    (defensive — every user gets one at registration)."""
    if user.settings is None:
        user.settings = UserSettings()
        db.add(user)
        db.commit()
        db.refresh(user)
    return user.settings


@router.get("", response_model=SettingsOut)
def get_settings(current_user: CurrentUser, db: DbSession) -> UserSettings:
    return _ensure_settings(current_user, db)


@router.put("", response_model=SettingsOut)
def update_settings(
    payload: SettingsUpdate, current_user: CurrentUser, db: DbSession
) -> UserSettings:
    settings = _ensure_settings(current_user, db)
    # Only touch fields the client explicitly sent — so `locale: null` clears
    # it (follow system) while an omitted `locale` leaves it unchanged.
    for field in payload.model_fields_set:
        setattr(settings, field, getattr(payload, field))
    db.add(settings)
    db.commit()
    db.refresh(settings)
    return settings
