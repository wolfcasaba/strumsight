import json
import stat
import tempfile
import unittest
from contextlib import ExitStack
from datetime import datetime, timezone
from pathlib import Path

from tools.ai_router.state import StateError, StateLockError, StateStore, TerraBudgetError


NOW = datetime(2026, 8, 1, 12, 0, tzinfo=timezone.utc)


class StateStoreTest(unittest.TestCase):
    def store(self, root: Path) -> StateStore:
        ids = iter(("reservation-1", "reservation-2", "reservation-3"))
        return StateStore(root, clock=lambda: NOW, id_factory=lambda: next(ids))

    def test_task_state_is_atomic_private_and_round_trips(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "state"
            store = self.store(root)
            payload = {"schema_version": 1, "task_id": "E03-R01", "phase": "PRECHECK"}

            store.save_task("E03-R01", payload)

            self.assertEqual(store.load_task("E03-R01"), payload)
            self.assertEqual(stat.S_IMODE(root.stat().st_mode), 0o700)
            self.assertEqual(
                stat.S_IMODE((root / "tasks" / "E03-R01.json").stat().st_mode), 0o600
            )
            self.assertEqual(list((root / "tasks").glob("*.tmp")), [])

    def test_task_lock_is_exclusive_across_store_instances(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "state"
            first = self.store(root)
            second = self.store(root)

            with first.task_lock("E03-R01"):
                with self.assertRaises(StateLockError):
                    with second.task_lock("E03-R01", blocking=False):
                        pass

    def test_reserved_or_started_terra_call_consumes_budget_after_crash(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = self.store(Path(directory) / "state")

            reservation = store.reserve_terra("E03-R01", daily_limit=3, task_limit=1)
            self.assertEqual(reservation.status, "reserved")
            with self.assertRaises(TerraBudgetError):
                store.reserve_terra("E03-R01", daily_limit=3, task_limit=1)
            store.mark_terra_started(reservation.reservation_id)
            with self.assertRaises(TerraBudgetError):
                store.reserve_terra("E03-R01", daily_limit=3, task_limit=1)

    def test_daily_limit_is_global_and_transitions_are_persisted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = self.store(Path(directory) / "state")
            first = store.reserve_terra("E03-R01", daily_limit=2)
            store.mark_terra_started(first.reservation_id)
            store.mark_terra_finished(first.reservation_id, "ready_for_review")
            store.reserve_terra("E03-R02", daily_limit=2)

            with self.assertRaises(TerraBudgetError):
                store.reserve_terra("E03-R03", daily_limit=2)
            ledger = json.loads((store.root / "terra-ledger.json").read_text())
            self.assertEqual(ledger["reservations"][0]["status"], "finished")
            self.assertEqual(ledger["reservations"][0]["outcome"], "ready_for_review")

    def test_finishing_a_terra_reservation_is_crash_safe_and_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = self.store(Path(directory) / "state")
            reservation = store.reserve_terra("E03-R01", daily_limit=3)

            # A crash can leave the task in TERRA_CALL before the provider call is
            # durably marked as started. Fail closed and consume that reservation.
            store.mark_terra_finished(reservation.reservation_id, "STOPPED")
            store.mark_terra_finished(reservation.reservation_id, "STOPPED")

            ledger = json.loads((store.root / "terra-ledger.json").read_text())
            self.assertEqual(ledger["reservations"][0]["status"], "finished")
            self.assertEqual(ledger["reservations"][0]["outcome"], "STOPPED")
            with self.assertRaises(StateError):
                store.mark_terra_finished(reservation.reservation_id, "READY_FOR_REVIEW")

    def test_corrupt_state_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = self.store(Path(directory) / "state")
            path = store.root / "tasks" / "E03-R01.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("not-json")

            with self.assertRaises(StateError):
                store.load_task("E03-R01")


if __name__ == "__main__":
    unittest.main()
