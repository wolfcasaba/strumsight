#!/usr/bin/env python3
"""Deterministic beta release notes from the release manifest (ADR 0486 D5).

The ONLY input is the ADR 0447 release-manifest JSON `tool/generate_release_
manifest.dart` produces — this tool never re-derives a build identifier by
any other means (git, pubspec, environment variable). The manifest keys it
reads are the MEASURED ones (`tool/generate_release_manifest.dart:246-272`):

    schemaVersion
    app.{version,buildNumber,shortSha,channel}
    modelPackage.{schemaVersion,manifestSha256,modelCount}
    knowledgePackage.{schemaVersion,manifestSha256,documentCount}
    artifacts[].{name,path,sha256}

Every one of those is required and type-checked; a missing or wrong-typed
key is a non-zero exit NAMING the key, never a silent `unknown`/empty
field (fail-closed, D5). The note always states the full build identifier
triple — `app.version`, `app.buildNumber`, `app.shortSha` — plus
`app.channel`, so two different builds are never ambiguous from the note
alone.

The output carries no generation timestamp, hostname or non-deterministic
formatting: the SAME manifest input always produces byte-identical output
(D4) — artifacts are listed sorted by name specifically so manifest-array
ordering cannot leak through as spurious note-to-note diff noise.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


class BetaNotesError(Exception):
    """A missing/malformed release-manifest input — always fail-closed."""


def _require_str(container: dict, key: str, *, where: str) -> str:
    value = container.get(key)
    if not isinstance(value, str) or not value:
        raise BetaNotesError(f'"{where}.{key}" must be a non-empty string')
    return value


def _require_int(container: dict, key: str, *, where: str) -> int:
    value = container.get(key)
    # bool is an int subclass in Python — exclude it explicitly so a stray
    # `true`/`false` cannot silently pass as 0/1.
    if isinstance(value, bool) or not isinstance(value, int):
        raise BetaNotesError(f'"{where}.{key}" must be an integer')
    return value


def _require_dict(manifest: dict, key: str) -> dict:
    value = manifest.get(key)
    if not isinstance(value, dict):
        raise BetaNotesError(f'"{key}" must be an object')
    return value


def _require_list(manifest: dict, key: str) -> list:
    value = manifest.get(key)
    if not isinstance(value, list):
        raise BetaNotesError(f'"{key}" must be a list')
    return value


class BetaNotes:
    __slots__ = (
        "app_version",
        "artifacts",
        "build_number",
        "channel",
        "document_count",
        "knowledge_manifest_sha256",
        "knowledge_schema_version",
        "model_count",
        "model_manifest_sha256",
        "model_schema_version",
        "schema_version",
        "short_sha",
    )


def parse_release_manifest(manifest: dict) -> BetaNotes:
    if not isinstance(manifest, dict):
        raise BetaNotesError("release manifest must be a JSON object")

    notes = BetaNotes()
    notes.schema_version = _require_int(manifest, "schemaVersion", where="")

    app = _require_dict(manifest, "app")
    notes.app_version = _require_str(app, "version", where="app")
    notes.build_number = _require_int(app, "buildNumber", where="app")
    notes.short_sha = _require_str(app, "shortSha", where="app")
    notes.channel = _require_str(app, "channel", where="app")

    model_package = _require_dict(manifest, "modelPackage")
    notes.model_schema_version = _require_int(
        model_package, "schemaVersion", where="modelPackage"
    )
    notes.model_manifest_sha256 = _require_str(
        model_package, "manifestSha256", where="modelPackage"
    )
    notes.model_count = _require_int(model_package, "modelCount", where="modelPackage")

    knowledge_package = _require_dict(manifest, "knowledgePackage")
    notes.knowledge_schema_version = _require_int(
        knowledge_package, "schemaVersion", where="knowledgePackage"
    )
    notes.knowledge_manifest_sha256 = _require_str(
        knowledge_package, "manifestSha256", where="knowledgePackage"
    )
    notes.document_count = _require_int(
        knowledge_package, "documentCount", where="knowledgePackage"
    )

    raw_artifacts = _require_list(manifest, "artifacts")
    artifacts = []
    for index, entry in enumerate(raw_artifacts):
        if not isinstance(entry, dict):
            raise BetaNotesError(f'"artifacts[{index}]" must be an object')
        artifacts.append(
            (
                _require_str(entry, "name", where=f"artifacts[{index}]"),
                _require_str(entry, "path", where=f"artifacts[{index}]"),
                _require_str(entry, "sha256", where=f"artifacts[{index}]"),
            )
        )
    notes.artifacts = sorted(artifacts, key=lambda artifact: artifact[0])

    return notes


def render(notes: BetaNotes) -> str:
    lines = [
        "# StrumSight Beta Release Notes",
        "",
        f"- Version: {notes.app_version}",
        f"- Build number: {notes.build_number}",
        f"- Commit: {notes.short_sha}",
        f"- Channel: {notes.channel}",
        f"- Release-manifest schema version: {notes.schema_version}",
        "",
        "## Model package",
        f"- Schema version: {notes.model_schema_version}",
        f"- Manifest sha256: {notes.model_manifest_sha256}",
        f"- Model count: {notes.model_count}",
        "",
        "## Tutor knowledge package",
        f"- Schema version: {notes.knowledge_schema_version}",
        f"- Manifest sha256: {notes.knowledge_manifest_sha256}",
        f"- Document count: {notes.document_count}",
        "",
        "## Artifacts",
    ]
    if notes.artifacts:
        for name, path, sha256 in notes.artifacts:
            lines.append(f"- {name} ({path}): {sha256}")
    else:
        lines.append("- (none)")
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument(
        "--output",
        default=None,
        help="Write the notes here instead of stdout.",
    )
    args = parser.parse_args(argv)

    try:
        try:
            manifest_text = Path(args.manifest).read_text(encoding="utf-8")
        except OSError as error:
            raise BetaNotesError(f"cannot read release manifest: {error}") from error
        try:
            manifest = json.loads(manifest_text)
        except json.JSONDecodeError as error:
            raise BetaNotesError(
                f"release manifest is not valid JSON: {error}"
            ) from error

        notes = parse_release_manifest(manifest)
        text = render(notes)
    except BetaNotesError as error:
        print(f"generate_beta_notes: {error}", file=sys.stderr)
        return 1

    if args.output is not None:
        Path(args.output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
