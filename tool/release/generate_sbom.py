#!/usr/bin/env python3
"""Software bill of materials + third-party notices generator.

ADR 0447 D3 / D5. Standard library only — PyYAML and any other third-party
Python package are FORBIDDEN here: the CI runner image does not guarantee
they are installed, and a gate cell that only goes green because a package
happens to be present locally is exactly the boxed-green/CI-red trap
L110 measured. `pubspec.lock` is read with a small line-based parser
tailored to the shape `dart pub` actually emits (see `_parse_pubspec_lock`)
rather than a general YAML parser.

`pubspec.lock` carries no `license` field for any of its 160 packages
(measured: `grep -ci license pubspec.lock` -> 0), and neither do
`backend/requirements.txt` / `backend/requirements-dev.txt`. So every
package's license is resolved from one of two MEASURED sources, in order:

  1. Hosted Dart package: the resolved package version's own `LICENSE` file
     in the local pub cache. The SBOM entry records the file's path RELATIVE
     TO THE PUB CACHE ROOT (`hosted/pub.dev/<pkg>-<ver>/LICENSE`) — never the
     resolved absolute cache path, which differs by machine/CI runner and
     would make the committed notices bundle non-reproducible — plus its
     sha256 and its first non-empty line. It does NOT infer an SPDX
     identifier from that free-form text (SPDX-from-text inference is
     explicitly forbidden by ADR 0447 D3).
  2. SDK-bundled / non-hosted Dart package, or a Python pin: the
     hand-curated `_CURATED_LICENSES` registry below (SPDX identifier +
     provenance per entry), in the spirit of
     `tool/ci/check_song_fixture_licenses.dart`'s in-file provenance table.

A package resolved by neither source is a hard failure: this tool exits
non-zero and names the package. Writing "unknown"/null/empty and continuing
is exactly the weakening ADR 0447 D3 forbids.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

SBOM_SCHEMA_VERSION = 1


class SbomError(Exception):
    """A package's license could not be resolved from either measured source."""


@dataclass(frozen=True)
class LockedPackage:
    name: str
    source: str  # "hosted" | "sdk" | ...
    version: str


@dataclass(frozen=True)
class CuratedLicense:
    spdx: str
    provenance: str


# ---------------------------------------------------------------------------
# Hand-curated license registry (ADR 0447 D3, second resolution source).
#
# Keyed by (ecosystem, package name). Covers exactly the packages that
# CANNOT be resolved from a pub cache LICENSE file: the 5 Dart SDK-bundled
# packages in pubspec.lock (source: sdk, not hosted) and every backend
# Python pin. Extending this registry requires a written SPDX identifier and
# a provenance string — never a bare guess.
# ---------------------------------------------------------------------------
_CURATED_LICENSES: dict[tuple[str, str], CuratedLicense] = {
    ("dart-sdk", "flutter"): CuratedLicense(
        spdx="BSD-3-Clause",
        provenance=(
            "Flutter SDK LICENSE file, bundled with the SDK "
            "($FLUTTER_ROOT/LICENSE) rather than resolved via pub.dev "
            "(https://github.com/flutter/flutter/blob/main/LICENSE)."
        ),
    ),
    ("dart-sdk", "flutter_localizations"): CuratedLicense(
        spdx="BSD-3-Clause",
        provenance=(
            "Flutter SDK LICENSE file, bundled with the SDK "
            "($FLUTTER_ROOT/LICENSE) rather than resolved via pub.dev."
        ),
    ),
    ("dart-sdk", "flutter_test"): CuratedLicense(
        spdx="BSD-3-Clause",
        provenance=(
            "Flutter SDK LICENSE file, bundled with the SDK "
            "($FLUTTER_ROOT/LICENSE) rather than resolved via pub.dev."
        ),
    ),
    ("dart-sdk", "flutter_web_plugins"): CuratedLicense(
        spdx="BSD-3-Clause",
        provenance=(
            "Flutter SDK LICENSE file, bundled with the SDK "
            "($FLUTTER_ROOT/LICENSE) rather than resolved via pub.dev."
        ),
    ),
    ("dart-sdk", "sky_engine"): CuratedLicense(
        spdx="BSD-3-Clause",
        provenance=(
            "Flutter engine LICENSE file, bundled with the SDK "
            "($FLUTTER_ROOT/bin/cache/pkg/sky_engine/LICENSE) rather than "
            "resolved via pub.dev."
        ),
    ),
    ("python", "fastapi"): CuratedLicense(
        spdx="MIT",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/fastapi/).",
    ),
    ("python", "uvicorn"): CuratedLicense(
        spdx="BSD-3-Clause",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/uvicorn/).",
    ),
    ("python", "sqlalchemy"): CuratedLicense(
        spdx="MIT",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/SQLAlchemy/).",
    ),
    ("python", "alembic"): CuratedLicense(
        spdx="MIT",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/alembic/).",
    ),
    ("python", "pydantic"): CuratedLicense(
        spdx="MIT",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/pydantic/).",
    ),
    ("python", "pydantic-settings"): CuratedLicense(
        spdx="MIT",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/pydantic-settings/).",
    ),
    ("python", "email-validator"): CuratedLicense(
        spdx="Unlicense",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/email-validator/).",
    ),
    ("python", "pyjwt"): CuratedLicense(
        spdx="MIT",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/PyJWT/).",
    ),
    ("python", "bcrypt"): CuratedLicense(
        spdx="Apache-2.0",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/bcrypt/).",
    ),
    ("python", "python-multipart"): CuratedLicense(
        spdx="Apache-2.0",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/python-multipart/).",
    ),
    ("python", "httpx"): CuratedLicense(
        spdx="BSD-3-Clause",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/httpx/).",
    ),
    ("python", "pytest"): CuratedLicense(
        spdx="MIT",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/pytest/).",
    ),
    ("python", "ruff"): CuratedLicense(
        spdx="MIT",
        provenance="PyPI project metadata License classifier (https://pypi.org/project/ruff/).",
    ),
}


def _parse_pubspec_lock(text: str) -> list[LockedPackage]:
    """Reads the `packages:` map `dart pub` emits into `pubspec.lock`.

    Deliberately NOT a general YAML parser (ADR 0447 D5): only understands
    the exact two-space/four-space indented shape this repository's
    lockfile uses — a top-level `<name>:` key followed by an indented
    `source:` / `version:` scalar pair.
    """
    packages: list[LockedPackage] = []
    lines = text.split("\n")
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if (
            line.startswith("  ")
            and not line.startswith("   ")
            and line.rstrip().endswith(":")
            and line.strip() != "packages:"
        ):
            name = line.strip()[:-1]
            j = i + 1
            source: str | None = None
            version: str | None = None
            while j < n and (lines[j].startswith("    ") or lines[j].strip() == ""):
                stripped = lines[j].strip()
                if stripped.startswith("source:"):
                    source = stripped.split(":", 1)[1].strip()
                if stripped.startswith("version:"):
                    version = stripped.split(":", 1)[1].strip().strip('"')
                j += 1
            if source and version:
                packages.append(LockedPackage(name=name, source=source, version=version))
            i = j
        else:
            i += 1
    return packages


_REQUIREMENT_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*")


def _parse_requirements(text: str) -> list[str]:
    """Extracts bare package names from a `requirements.txt`-style file.

    Strips extras (`uvicorn[standard]` -> `uvicorn`) and version specifiers
    (`fastapi>=0.115,<0.116` -> `fastapi`); ignores comments and blanks.
    """
    names: list[str] = []
    for raw_line in text.split("\n"):
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        bracket_index = line.find("[")
        name_part = line[:bracket_index] if bracket_index != -1 else line
        match = _REQUIREMENT_NAME.match(name_part.strip())
        if match:
            names.append(match.group(0))
    return names


def _first_non_empty_line(data: bytes) -> str:
    for raw_line in data.decode("utf-8", errors="replace").split("\n"):
        stripped = raw_line.strip()
        if stripped:
            return stripped
    return ""


def _resolve_dart_license(pkg: LockedPackage, pub_cache: Path) -> dict:
    if pkg.source == "hosted":
        relative_license_path = Path("hosted") / "pub.dev" / f"{pkg.name}-{pkg.version}" / "LICENSE"
        license_path = pub_cache / relative_license_path
        if license_path.is_file():
            data = license_path.read_bytes()
            return {
                "kind": "pub-cache-license-file",
                "licensePath": relative_license_path.as_posix(),
                "sha256": hashlib.sha256(data).hexdigest(),
                "firstLine": _first_non_empty_line(data),
            }
    curated = _CURATED_LICENSES.get(("dart-sdk", pkg.name))
    if curated is not None:
        return {
            "kind": "curated",
            "spdx": curated.spdx,
            "provenance": curated.provenance,
        }
    raise SbomError(
        f"no license source for Dart package {pkg.name}@{pkg.version} "
        f"(source={pkg.source}): no pub cache LICENSE file and no "
        "_CURATED_LICENSES entry"
    )


def _resolve_python_license(name: str) -> dict:
    curated = _CURATED_LICENSES.get(("python", name.lower()))
    if curated is not None:
        return {
            "kind": "curated",
            "spdx": curated.spdx,
            "provenance": curated.provenance,
        }
    raise SbomError(f"no license source for Python package {name}: no _CURATED_LICENSES entry")


def build_sbom(
    *,
    pubspec_lock_text: str,
    requirements_texts: dict[str, str],
    pub_cache: Path,
) -> dict:
    """Builds the SBOM document. Raises [SbomError] on the first
    unresolvable license — fail-closed, not a best-effort partial report."""
    components = []

    for pkg in sorted(_parse_pubspec_lock(pubspec_lock_text), key=lambda p: p.name):
        license_entry = _resolve_dart_license(pkg, pub_cache)
        components.append(
            {
                "ecosystem": "dart",
                "name": pkg.name,
                "version": pkg.version,
                "lockSource": pkg.source,
                "license": license_entry,
            }
        )

    seen_python: set[str] = set()
    for requirements_path in sorted(requirements_texts):
        for name in _parse_requirements(requirements_texts[requirements_path]):
            key = name.lower()
            if key in seen_python:
                continue
            seen_python.add(key)
            license_entry = _resolve_python_license(name)
            components.append(
                {
                    "ecosystem": "python",
                    "name": name,
                    "version": None,
                    "lockSource": requirements_path,
                    "license": license_entry,
                }
            )

    components.sort(key=lambda c: (c["ecosystem"], c["name"]))
    return {
        "schemaVersion": SBOM_SCHEMA_VERSION,
        "componentCount": len(components),
        "components": components,
    }


def render_notices(sbom: dict) -> str:
    lines = [
        "# Third-party notices",
        "",
        "Generated by `tool/release/generate_sbom.py` from `pubspec.lock` and the",
        "backend `requirements*.txt` pins. Do not hand-edit — regenerate instead.",
        "",
    ]
    for component in sbom["components"]:
        license_entry = component["license"]
        version = component["version"] or "(unpinned)"
        lines.append(f"## {component['ecosystem']} / {component['name']} {version}")
        lines.append("")
        if license_entry["kind"] == "curated":
            lines.append(f"- License (SPDX): {license_entry['spdx']}")
            lines.append(f"- Provenance: {license_entry['provenance']}")
        else:
            lines.append(f"- License text: {license_entry['licensePath']}")
            lines.append(f"- License file sha256: {license_entry['sha256']}")
            lines.append(f"- First line: {license_entry['firstLine']}")
        lines.append("")
    return "\n".join(lines).rstrip("\n") + "\n"


def _resolve_pub_cache(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit)
    env_value = os.environ.get("PUB_CACHE")
    if env_value:
        return Path(env_value)
    return Path.home() / ".pub-cache"


def _default_requirements_paths(profile: str) -> list[str]:
    if profile == "production":
        return ["backend/requirements.txt"]
    return ["backend/requirements.txt", "backend/requirements-dev.txt"]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=["production", "development"], default="production")
    parser.add_argument("--pubspec-lock", default="pubspec.lock")
    parser.add_argument("--pub-cache", default=None)
    parser.add_argument(
        "--requirements",
        action="append",
        default=None,
        help="Repeatable. Overrides the profile's default requirements*.txt set.",
    )
    parser.add_argument("--output-sbom", default="build/sbom.json")
    parser.add_argument("--output-notices", default="THIRD_PARTY_NOTICES.md")
    args = parser.parse_args(argv)

    pubspec_lock_path = Path(args.pubspec_lock)
    if not pubspec_lock_path.is_file():
        print(f"generate_sbom: pubspec.lock not found: {pubspec_lock_path}", file=sys.stderr)
        return 2

    requirements_paths = args.requirements or _default_requirements_paths(args.profile)
    requirements_texts: dict[str, str] = {}
    for requirements_path in requirements_paths:
        path = Path(requirements_path)
        if not path.is_file():
            print(f"generate_sbom: requirements file not found: {path}", file=sys.stderr)
            return 2
        requirements_texts[requirements_path] = path.read_text(encoding="utf-8")

    pub_cache = _resolve_pub_cache(args.pub_cache)

    try:
        sbom = build_sbom(
            pubspec_lock_text=pubspec_lock_path.read_text(encoding="utf-8"),
            requirements_texts=requirements_texts,
            pub_cache=pub_cache,
        )
    except SbomError as error:
        print(f"generate_sbom: {error}", file=sys.stderr)
        return 1

    output_sbom_path = Path(args.output_sbom)
    output_sbom_path.parent.mkdir(parents=True, exist_ok=True)
    output_sbom_path.write_text(json.dumps(sbom, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    notices_path = Path(args.output_notices)
    notices_path.parent.mkdir(parents=True, exist_ok=True)
    notices_path.write_text(render_notices(sbom), encoding="utf-8")

    print(
        f"SBOM written: {output_sbom_path} ({sbom['componentCount']} components). "
        f"Notices written: {notices_path}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
