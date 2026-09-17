"""A K2-kör forrás-őre: a platform-dekóder CSAK audio-sávot választhat.

MÉRT KORLÁT (2026-09-17). A Kotlin-forrás ebben a konténerben nem fordítható
(nincs Android SDK, a `build-apk.yml` CI a fordítás egyetlen bizonyítéka), így
az `AudioDecoderChannel.kt` viselkedésének az a része, ami NEM várhat a CI-ra,
forrás-szinten mérendő. Ez a rész a sávválasztás.

MIÉRT ÉPP EZ. Egy importált MP4 (vagy egy borítóképet cipelő M4A) több sávot
deklarál. Ha a dekóder az ELSŐ sávot venné — vagy bármit, ami nem audio —, a
`MediaCodec.createDecoderByType` egy képsávra indulna el, és a hívó vagy egy
`decoder_failed`-et kapna, vagy — rosszabb esetben — értelmetlen bájtokat
float32 PCM-nek olvasva. Mindkettő NÉMA hiba: a Dart-oldali szerződés-cellák
zöldek maradnának, mert azok a csatornát mockolják.

FALSZIFIKÁCIÓ. Ha a `startsWith("audio/")` szűrő eltűnik a forrásból, ez a
teszt pirosra vált. A Dart-oldali cellák egyike sem venné észre.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
KOTLIN = (
    ROOT
    / "android"
    / "app"
    / "src"
    / "main"
    / "kotlin"
    / "com"
    / "wolfcasaba"
    / "strumsight"
    / "audio"
    / "AudioDecoderChannel.kt"
)
MAIN_ACTIVITY = (
    ROOT
    / "android"
    / "app"
    / "src"
    / "main"
    / "kotlin"
    / "com"
    / "wolfcasaba"
    / "strumsight"
    / "MainActivity.kt"
)

CHANNEL_NAME = "strumsight/audio_decoder"
ERROR_CODES = (
    "no_audio_track",
    "unsupported_container",
    "decoder_failed",
    "file_not_found",
    "too_long",
)


class AudioDecoderTrackFilterTest(unittest.TestCase):
    def setUp(self) -> None:
        self.assertTrue(KOTLIN.is_file(), f"hiányzik a forrás: {KOTLIN}")
        self.source = KOTLIN.read_text(encoding="utf-8")

    def test_only_audio_mime_tracks_are_selected(self) -> None:
        self.assertRegex(
            self.source,
            re.compile(r'startsWith\(\s*"audio/"\s*\)'),
            "a sávválasztásból eltűnt az audio/ MIME-szűrő",
        )

    def test_no_other_media_kind_is_ever_referenced(self) -> None:
        for forbidden in ('"video/', '"image/', '"text/', '"application/'):
            self.assertNotIn(
                forbidden,
                self.source,
                f"a dekóder {forbidden}… sávra hivatkozik — csak audio/ szabad",
            )

    def test_the_track_loop_is_the_only_selection_path(self) -> None:
        # Pontosan egy selectTrack hívás van, és az a szűrt indexet kapja.
        self.assertEqual(
            self.source.count("selectTrack("),
            1,
            "több sáv-kiválasztási út — a szűrő megkerülhető",
        )
        self.assertIn("extractor.selectTrack(track)", self.source)
        self.assertIn("firstAudioTrack(extractor)", self.source)

    def test_the_channel_name_and_error_codes_are_stable(self) -> None:
        self.assertIn(f'"{CHANNEL_NAME}"', self.source)
        for code in ERROR_CODES:
            self.assertIn(f'"{code}"', self.source, f"hiányzó hibakód: {code}")

    def test_the_decoder_and_extractor_are_released(self) -> None:
        self.assertIn("finally", self.source)
        self.assertIn("extractor.release()", self.source)
        self.assertIn(".release()", self.source)

    def test_the_channel_is_registered_from_main_activity(self) -> None:
        self.assertTrue(MAIN_ACTIVITY.is_file())
        activity = MAIN_ACTIVITY.read_text(encoding="utf-8")
        self.assertIn("configureFlutterEngine", activity)
        self.assertIn("AudioDecoderChannel(", activity)

    def test_the_kotlin_stays_small_enough_to_review(self) -> None:
        # A KDoc-blokkok és az üres sorok nem számítanak: a mérce a kód.
        without_kdoc = re.sub(r"/\*\*.*?\*/", "", self.source, flags=re.S)
        code = [
            line
            for line in without_kdoc.splitlines()
            if line.strip() and not line.strip().startswith("//")
        ]
        self.assertLessEqual(
            len(code),
            260,
            "a csatorna túlnőtt a kör keretein — bontani kell",
        )


if __name__ == "__main__":
    unittest.main()
