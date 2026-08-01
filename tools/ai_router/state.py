"""Crash-safe authoritative router state and global Terra budget ledger."""

from __future__ import annotations

import fcntl
import json
import os
import re
import tempfile
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterator


class StateError(RuntimeError):
    pass


class StateLockError(StateError):
    pass


class TerraBudgetError(StateError):
    pass


TASK_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


@dataclass(frozen=True)
class TerraReservation:
    reservation_id: str
    task_id: str
    utc_day: str
    status: str


class StateStore:
    def __init__(
        self,
        root: Path,
        *,
        clock: Callable[[], datetime] | None = None,
        id_factory: Callable[[], str] | None = None,
    ) -> None:
        self.root = root
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        self.id_factory = id_factory or (lambda: uuid.uuid4().hex)
        self._held_tasks: set[str] = set()
        for directory in (self.root, self.root / "tasks", self.root / "locks"):
            directory.mkdir(parents=True, exist_ok=True)
            directory.chmod(0o700)

    @staticmethod
    def _validate_task_id(task_id: str) -> None:
        if not TASK_ID.fullmatch(task_id):
            raise StateError("invalid task id")

    @staticmethod
    def _read_json(path: Path, default: dict[str, object] | None = None) -> dict[str, object]:
        if not path.exists():
            return dict(default) if default is not None else {}
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise StateError(f"state file is invalid: {path.name}") from error
        if not isinstance(value, dict):
            raise StateError(f"state file root must be an object: {path.name}")
        return value

    @staticmethod
    def _write_json(path: Path, value: dict[str, object]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        encoded = (json.dumps(value, ensure_ascii=False, sort_keys=True) + "\n").encode()
        fd, temporary = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(encoded)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, path)
        except BaseException:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass
            raise

    @contextmanager
    def task_lock(self, task_id: str, *, blocking: bool = True) -> Iterator[None]:
        self._validate_task_id(task_id)
        if task_id in self._held_tasks:
            raise StateLockError(f"task lock is already held: {task_id}")
        path = self.root / "locks" / f"{task_id}.lock"
        descriptor = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
        os.chmod(path, 0o600)
        operation = fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB)
        try:
            try:
                fcntl.flock(descriptor, operation)
            except BlockingIOError as error:
                raise StateLockError(f"task lock is busy: {task_id}") from error
            self._held_tasks.add(task_id)
            yield
        finally:
            self._held_tasks.discard(task_id)
            try:
                fcntl.flock(descriptor, fcntl.LOCK_UN)
            finally:
                os.close(descriptor)

    def load_task(self, task_id: str) -> dict[str, object]:
        self._validate_task_id(task_id)
        return self._read_json(self.root / "tasks" / f"{task_id}.json")

    def save_task(self, task_id: str, state: dict[str, object]) -> None:
        self._validate_task_id(task_id)
        if not isinstance(state, dict) or state.get("task_id") not in (None, task_id):
            raise StateError("task state has a mismatched task_id")
        path = self.root / "tasks" / f"{task_id}.json"
        if task_id in self._held_tasks:
            self._write_json(path, state)
        else:
            with self.task_lock(task_id):
                self._write_json(path, state)

    @contextmanager
    def _ledger_lock(self) -> Iterator[None]:
        path = self.root / "terra-ledger.lock"
        descriptor = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
        os.chmod(path, 0o600)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX)
            yield
        finally:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
            os.close(descriptor)

    def _load_ledger(self) -> dict[str, object]:
        ledger = self._read_json(
            self.root / "terra-ledger.json",
            {"schema_version": 1, "reservations": []},
        )
        if ledger.get("schema_version") != 1 or not isinstance(ledger.get("reservations"), list):
            raise StateError("Terra ledger schema is invalid")
        return ledger

    def reserve_terra(
        self, task_id: str, *, daily_limit: int, task_limit: int = 1
    ) -> TerraReservation:
        self._validate_task_id(task_id)
        if daily_limit < 1 or task_limit < 1:
            raise StateError("Terra limits must be positive")
        now = self.clock().astimezone(timezone.utc)
        day = now.date().isoformat()
        with self._ledger_lock():
            ledger = self._load_ledger()
            reservations = ledger["reservations"]
            active = {"reserved", "started", "finished"}
            daily_count = sum(
                1
                for row in reservations
                if isinstance(row, dict) and row.get("utc_day") == day and row.get("status") in active
            )
            task_count = sum(
                1
                for row in reservations
                if isinstance(row, dict) and row.get("task_id") == task_id and row.get("status") in active
            )
            if daily_count >= daily_limit:
                raise TerraBudgetError("automatic Terra daily budget is exhausted")
            if task_count >= task_limit:
                raise TerraBudgetError("task Terra budget is exhausted")
            reservation_id = self.id_factory()
            row = {
                "reservation_id": reservation_id,
                "task_id": task_id,
                "utc_day": day,
                "status": "reserved",
                "reserved_at": now.isoformat(),
            }
            reservations.append(row)
            self._write_json(self.root / "terra-ledger.json", ledger)
        return TerraReservation(reservation_id, task_id, day, "reserved")

    def _transition_reservation(
        self,
        reservation_id: str,
        *,
        expected: str | tuple[str, ...],
        status: str,
        outcome: str | None = None,
        idempotent: bool = False,
    ) -> None:
        now = self.clock().astimezone(timezone.utc).isoformat()
        with self._ledger_lock():
            ledger = self._load_ledger()
            matches = [
                row
                for row in ledger["reservations"]
                if isinstance(row, dict) and row.get("reservation_id") == reservation_id
            ]
            if len(matches) != 1:
                raise StateError("Terra reservation was not found uniquely")
            row = matches[0]
            current = row.get("status")
            if current == status and idempotent and row.get("outcome") == outcome:
                return
            expected_statuses = (expected,) if isinstance(expected, str) else expected
            if current not in expected_statuses:
                raise StateError(f"invalid Terra transition from {current} to {status}")
            row["status"] = status
            row[f"{status}_at"] = now
            if outcome is not None:
                row["outcome"] = outcome
            self._write_json(self.root / "terra-ledger.json", ledger)

    def mark_terra_started(self, reservation_id: str) -> None:
        self._transition_reservation(reservation_id, expected="reserved", status="started")

    def mark_terra_finished(self, reservation_id: str, outcome: str) -> None:
        if not outcome:
            raise StateError("Terra outcome is required")
        self._transition_reservation(
            reservation_id,
            expected=("reserved", "started"),
            status="finished",
            outcome=outcome,
            idempotent=True,
        )
