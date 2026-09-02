#!/usr/bin/env python3
"""Content-catalog inventory validator (E12-R21, ADR 0485).

Proves `docs/content/catalog-inventory.yaml` is a TRUE, bidirectional mirror
of the three places learner content actually lives on this tree — the
Practice Engine's built-in catalog (`lib/features/practice/data/
builtin_practice_catalog.dart`), the tutor knowledge pack (`assets/
tutor_knowledge/manifest.json`), and the legacy Learn lessons (`lib/features/
learn/model/lesson.dart`) — plus the `LegacyMappingTable` and `SkillTaxonomy`
reference/skill surfaces those sources feed (ADR 0485 D1-D5).

Standard library ONLY (ADR 0485 R7 / D6): no PyYAML dependency is guaranteed
on the runner, so the inventory is read by this module's own strict,
fail-closed line parser (`_parse_inventory`) rather than a general YAML
library — every non-blank, non-comment line must match an expected pattern
for its current section, or it is an `unparsable_line` finding, never a
silent skip (docs/LESSONS.md L566).

Exit code is 0 iff zero findings were produced; otherwise 1. Every finding is
printed to stdout as one line: `<code>: <detail>`.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

# ---------------------------------------------------------------------------
# The closed set of machine-readable finding codes (ADR 0485 §3.3 / brief
# §3.3). Nothing outside this set is ever emitted — inventing an eleventh
# code would be exactly the "negyedik, egyesített taxonómia" style
# unauthorized-widening the ADR forbids for D4, applied to the code list.
# ---------------------------------------------------------------------------
MISSING_INVENTORY_ENTRY = "missing_inventory_entry"
STALE_INVENTORY_ENTRY = "stale_inventory_entry"
BROKEN_REFERENCE = "broken_reference"
MISSING_LOCALE = "missing_locale"
UNKNOWN_SKILL_TAG = "unknown_skill_tag"
UNUSED_SKILL_TAG = "unused_skill_tag"
UNPARSABLE_LINE = "unparsable_line"
EXCEPTION_MISSING_OWNER = "exception_missing_owner"
EXCEPTION_MISSING_EXPIRY = "exception_missing_expiry"
EXPIRED_EXCEPTION = "expired_exception"

_REQUIRED_LOCALES = ("en", "hu")


@dataclass
class Finding:
    code: str
    detail: str

    def render(self) -> str:
        return f"{self.code}: {self.detail}"


@dataclass
class InventoryItem:
    id: str
    source: str
    fields: dict[str, str] = field(default_factory=dict)


@dataclass
class KnownException:
    id: str
    reason: str | None
    owner: str | None
    expiry: str | None
    suppresses: str | None
    line: int


@dataclass
class ParsedInventory:
    schema_version: str | None
    content_package_version: str | None
    sources: dict[str, str]
    items: list[InventoryItem]
    skill_vocabularies: dict[str, set[str]]
    skill_graph: list[tuple[str, list[str]]]
    known_exceptions: list[KnownException]
    findings: list[Finding]


# ---------------------------------------------------------------------------
# The hand-rolled, fail-closed inventory parser.
#
# Every non-blank, non-comment line MUST match one of the patterns declared
# for the currently open section, or it is `unparsable_line`. There is no
# catch-all "unrecognized line, ignore it" branch anywhere below — that
# silent skip is exactly the L566 fail-open defect this parser exists to
# not repeat.
# ---------------------------------------------------------------------------

_TOP_LEVEL_SCALARS = {"schema_version", "content_package_version"}
_TOP_LEVEL_SECTIONS = {"sources", "items", "skill_vocabularies", "skill_graph", "known_exceptions"}

_TOP_LEVEL_LINE = re.compile(r"^([a-z_]+):(?: (.*))?$")
_SOURCES_LINE = re.compile(r"^  ([a-z_]+): (.+)$")
_ITEM_START = re.compile(r"^  - id: (.+)$")
_ITEM_SCALAR_FIELD = re.compile(r"^    (source|difficulty|version): (.+)$")
_ITEM_LIST_FIELD = re.compile(r"^    (skill_tags|locales): \[(.*)\]$")
_VOCAB_LINE = re.compile(r"^  ([a-z_]+): \[(.*)\]$")
_SKILL_NODE_START = re.compile(r"^  - id: (.+)$")
_SKILL_NODE_PREREQS = re.compile(r"^    prerequisites: \[(.*)\]$")
_EXCEPTION_START = re.compile(r"^  - id: (.+)$")
_EXCEPTION_FIELD = re.compile(r"^    (reason|owner|expiry|suppresses): (.+)$")
_BLANK_OR_COMMENT = re.compile(r"^\s*(#.*)?$")


def _split_bracket_list(raw: str) -> list[str]:
    raw = raw.strip()
    if not raw:
        return []
    return [entry.strip() for entry in raw.split(",") if entry.strip()]


def _unquote(raw: str) -> str:
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        return raw[1:-1]
    return raw


def parse_inventory(text: str) -> ParsedInventory:
    findings: list[Finding] = []
    schema_version: str | None = None
    content_package_version: str | None = None
    sources: dict[str, str] = {}
    items: list[InventoryItem] = []
    skill_vocabularies: dict[str, set[str]] = {}
    skill_graph: list[tuple[str, list[str]]] = []
    known_exceptions: list[KnownException] = []

    section: str | None = None
    current_item: InventoryItem | None = None
    current_node: tuple[str, list[str]] | None = None
    current_exception: KnownException | None = None

    def flush_node() -> None:
        nonlocal current_node
        if current_node is not None:
            skill_graph.append(current_node)
            current_node = None

    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.rstrip("\n")
        if _BLANK_OR_COMMENT.match(line):
            continue

        top_match = _TOP_LEVEL_LINE.match(line) if not line.startswith(" ") else None
        if top_match:
            key, value = top_match.group(1), top_match.group(2)
            current_item = None
            current_node = None
            flush_node()
            current_exception = None
            if key in _TOP_LEVEL_SCALARS:
                if value is None:
                    findings.append(Finding(UNPARSABLE_LINE, f"line {line_number}: {line!r}"))
                    section = None
                    continue
                if key == "schema_version":
                    schema_version = value
                else:
                    content_package_version = _unquote(value)
                section = None
                continue
            if key in _TOP_LEVEL_SECTIONS and value is None:
                section = key
                continue
            findings.append(Finding(UNPARSABLE_LINE, f"line {line_number}: {line!r}"))
            section = None
            continue

        if section == "sources":
            match = _SOURCES_LINE.match(line)
            if match:
                sources[match.group(1)] = match.group(2)
                continue
            findings.append(Finding(UNPARSABLE_LINE, f"line {line_number}: {line!r}"))
            continue

        if section == "items":
            start = _ITEM_START.match(line)
            if start:
                current_item = InventoryItem(id=start.group(1), source="")
                items.append(current_item)
                continue
            scalar = _ITEM_SCALAR_FIELD.match(line)
            if scalar and current_item is not None:
                key, value = scalar.group(1), scalar.group(2)
                if key == "source":
                    current_item.source = value
                else:
                    current_item.fields[key] = value
                continue
            list_field = _ITEM_LIST_FIELD.match(line)
            if list_field and current_item is not None:
                key, value = list_field.group(1), list_field.group(2)
                current_item.fields[key] = value
                continue
            findings.append(Finding(UNPARSABLE_LINE, f"line {line_number}: {line!r}"))
            continue

        if section == "skill_vocabularies":
            match = _VOCAB_LINE.match(line)
            if match:
                skill_vocabularies[match.group(1)] = set(_split_bracket_list(match.group(2)))
                continue
            findings.append(Finding(UNPARSABLE_LINE, f"line {line_number}: {line!r}"))
            continue

        if section == "skill_graph":
            start = _SKILL_NODE_START.match(line)
            if start:
                flush_node()
                current_node = (start.group(1), [])
                continue
            prereqs = _SKILL_NODE_PREREQS.match(line)
            if prereqs and current_node is not None:
                current_node = (current_node[0], _split_bracket_list(prereqs.group(1)))
                continue
            findings.append(Finding(UNPARSABLE_LINE, f"line {line_number}: {line!r}"))
            continue

        if section == "known_exceptions":
            start = _EXCEPTION_START.match(line)
            if start:
                current_exception = KnownException(
                    id=start.group(1),
                    reason=None,
                    owner=None,
                    expiry=None,
                    suppresses=None,
                    line=line_number,
                )
                known_exceptions.append(current_exception)
                continue
            exc_field = _EXCEPTION_FIELD.match(line)
            if exc_field and current_exception is not None:
                key, value = exc_field.group(1), _unquote(exc_field.group(2))
                setattr(current_exception, key, value)
                continue
            findings.append(Finding(UNPARSABLE_LINE, f"line {line_number}: {line!r}"))
            continue

        # No section open at all (e.g. an indented line before the first
        # top-level key) — still unparsable, never silently ignored.
        findings.append(Finding(UNPARSABLE_LINE, f"line {line_number}: {line!r}"))

    flush_node()

    return ParsedInventory(
        schema_version=schema_version,
        content_package_version=content_package_version,
        sources=sources,
        items=items,
        skill_vocabularies=skill_vocabularies,
        skill_graph=skill_graph,
        known_exceptions=known_exceptions,
        findings=findings,
    )


# ---------------------------------------------------------------------------
# Source extraction — every function below is fail-closed: parsing zero
# elements out of a source that is supposed to have some is itself an
# error (ADR 0485 §3.3 / R8), never a silently-empty set.
# ---------------------------------------------------------------------------


class SourceMeasurementError(RuntimeError):
    pass


_PRACTICE_DEFINITION_RE = re.compile(
    r"PracticeDefinition\(\s*"
    r"id:\s*'([^']+)'.*?"
    r"schemaVersion:\s*(\d+).*?"
    r"titleKey:\s*'([^']+)'.*?"
    r"descriptionKey:\s*'([^']+)'.*?"
    r"(?:difficulty:\s*PracticeDifficulty\.(\w+),\s*)?"
    r"skillTags:\s*const\s*\[([^\]]*)\]",
    re.DOTALL,
)


def extract_practice_definitions(source: str, source_label: str) -> list[dict]:
    results = []
    for match in _PRACTICE_DEFINITION_RE.finditer(source):
        (
            definition_id,
            schema_version,
            title_key,
            description_key,
            difficulty,
            tags_blob,
        ) = match.groups()
        tags = re.findall(r"'([^']+)'", tags_blob)
        results.append(
            {
                "id": definition_id,
                "schemaVersion": schema_version,
                "titleKey": title_key,
                "descriptionKey": description_key,
                "difficulty": difficulty or "beginner",
                "skillTags": tags,
            }
        )
    if not results:
        raise SourceMeasurementError(
            f"{source_label}: parsed zero PracticeDefinition entries"
        )
    return results


def extract_knowledge_documents(manifest_path: Path) -> list[dict]:
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SourceMeasurementError(f"{manifest_path}: unreadable manifest ({exc})") from exc
    documents = payload.get("documents") or []
    if not documents:
        raise SourceMeasurementError(f"{manifest_path}: parsed zero knowledge documents")
    return documents


_LESSON_ALL_RE = re.compile(r"static List<Lesson> get all => \[(.*?)\];", re.DOTALL)
_LESSON_GETTER_RE = re.compile(r"static Lesson get (\w+) => Lesson\((.*?)\n  \);", re.DOTALL)
_LESSON_ID_RE = re.compile(r"id:\s*'([^']+)'")
_LESSON_DIFFICULTY_RE = re.compile(r"difficulty:\s*Difficulty\.(\w+)")


def extract_lessons(source: str, source_label: str) -> tuple[list[dict], dict]:
    all_match = _LESSON_ALL_RE.search(source)
    if not all_match:
        raise SourceMeasurementError(f"{source_label}: could not locate `Lessons.all`")
    ordered_names = [n.strip() for n in all_match.group(1).split(",") if n.strip()]
    if not ordered_names:
        raise SourceMeasurementError(f"{source_label}: `Lessons.all` is empty")

    getters: dict[str, dict] = {}
    for getter_match in _LESSON_GETTER_RE.finditer(source):
        name, body = getter_match.groups()
        id_match = _LESSON_ID_RE.search(body)
        if not id_match:
            continue
        difficulty_match = _LESSON_DIFFICULTY_RE.search(body)
        getters[name] = {
            "id": id_match.group(1),
            "difficulty": difficulty_match.group(1) if difficulty_match else "beginner",
        }
    if not getters:
        raise SourceMeasurementError(f"{source_label}: parsed zero `static Lesson get` entries")

    ordered_lessons = []
    for name in ordered_names:
        if name not in getters:
            raise SourceMeasurementError(
                f"{source_label}: `Lessons.all` references undefined getter '{name}'"
            )
        ordered_lessons.append(getters[name])

    first_win = getters.get("firstWin")
    return ordered_lessons, first_win


_LEGACY_MAPPING_RE = re.compile(
    r"LegacySkillMapping\(lessonId:\s*'([^']+)',\s*skillId:\s*'([^']+)'\)"
)


def extract_legacy_mapping(source: str, source_label: str) -> list[dict]:
    results = [
        {"lessonId": lesson_id, "skillId": skill_id}
        for lesson_id, skill_id in _LEGACY_MAPPING_RE.findall(source)
    ]
    if not results:
        raise SourceMeasurementError(f"{source_label}: parsed zero LegacySkillMapping entries")
    return results


_KNOWLEDGE_SKILL_ENUM_RE = re.compile(r"enum KnowledgeSkill \{([^}]*)\}")


def extract_knowledge_skill_enum(source: str, source_label: str) -> set[str]:
    match = _KNOWLEDGE_SKILL_ENUM_RE.search(source)
    if not match:
        raise SourceMeasurementError(f"{source_label}: could not locate `enum KnowledgeSkill`")
    values = {v.strip() for v in match.group(1).split(",") if v.strip()}
    if not values:
        raise SourceMeasurementError(f"{source_label}: `enum KnowledgeSkill` has zero values")
    return values


def extract_arb_keys(arb_path: Path) -> set[str]:
    try:
        payload = json.loads(arb_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SourceMeasurementError(f"{arb_path}: unreadable ARB file ({exc})") from exc
    keys = {k for k in payload if not k.startswith("@")}
    if not keys:
        raise SourceMeasurementError(f"{arb_path}: parsed zero ARB keys")
    return keys


# ---------------------------------------------------------------------------
# Validation passes.
# ---------------------------------------------------------------------------


def _validate_exceptions(
    exceptions: list[KnownException], today: date
) -> tuple[list[Finding], set[str]]:
    findings: list[Finding] = []
    active_suppressions: set[str] = set()
    for exc in exceptions:
        owner_ok = bool(exc.owner and exc.owner.strip())
        if not owner_ok:
            findings.append(Finding(EXCEPTION_MISSING_OWNER, exc.id))

        expiry_ok = False
        if not exc.expiry or exc.expiry.strip().lower() == "unscheduled":
            findings.append(Finding(EXCEPTION_MISSING_EXPIRY, exc.id))
        else:
            try:
                expiry_date = date.fromisoformat(exc.expiry.strip())
                expiry_ok = True
            except ValueError:
                findings.append(Finding(EXCEPTION_MISSING_EXPIRY, exc.id))
                expiry_date = None
            if expiry_ok and expiry_date is not None and expiry_date < today:
                findings.append(Finding(EXPIRED_EXCEPTION, f"{exc.id} (expiry={exc.expiry})"))
                expiry_ok = False

        if owner_ok and expiry_ok and exc.suppresses:
            active_suppressions.add(exc.suppresses.strip())

    return findings, active_suppressions


def _mirror_source(
    findings: list[Finding],
    source_key: str,
    measured_ids: set[str],
    declared: dict[str, InventoryItem],
) -> None:
    declared_ids = {item.id for item in declared.values() if item.source == source_key}
    for missing_id in sorted(measured_ids - declared_ids):
        findings.append(Finding(MISSING_INVENTORY_ENTRY, f"{source_key}:{missing_id}"))
    for stale_id in sorted(declared_ids - measured_ids):
        findings.append(Finding(STALE_INVENTORY_ENTRY, f"{source_key}:{stale_id}"))


# Per-item inventory dimensions that are declared as bracketed lists
# (`skill_tags: [a, b]`, `locales: [en, hu]`) — compared as SORTED sets so
# declaration order in the source never matters. Everything else in
# `_ITEM_FIELDS` is compared as an exact scalar string.
_LIST_FIELDS = {"skill_tags", "locales"}
_ITEM_FIELDS = ("difficulty", "skill_tags", "locales", "version")


def _mirror_fields(
    findings: list[Finding],
    source_key: str,
    measured_fields: dict[str, dict[str, object]],
    declared: dict[str, InventoryItem],
) -> None:
    """Element-level, bidirectional field mirror (ADR 0485 D1, brief MAJOR-1).

    For every measured element that also has a matching declared inventory
    row (an id/source mismatch was already reported by `_mirror_source`),
    every one of `_ITEM_FIELDS` must match exactly — a declared value that
    diverges from the measured one is `stale_inventory_entry` with the field
    name in the detail, never a silent pass.
    """
    for item_id, measured in sorted(measured_fields.items()):
        declared_item = declared.get(item_id)
        if declared_item is None or declared_item.source != source_key:
            continue
        for field_name in _ITEM_FIELDS:
            measured_value = measured[field_name]
            declared_raw = declared_item.fields.get(field_name)
            if field_name in _LIST_FIELDS:
                declared_list = sorted(_split_bracket_list(declared_raw or ""))
                measured_list = sorted(measured_value)
                if declared_list != measured_list:
                    findings.append(
                        Finding(
                            STALE_INVENTORY_ENTRY,
                            f"{source_key}:{item_id}:{field_name} "
                            f"(declared=[{', '.join(declared_list)}], "
                            f"measured=[{', '.join(measured_list)}])",
                        )
                    )
            else:
                measured_str = str(measured_value)
                if declared_raw != measured_str:
                    findings.append(
                        Finding(
                            STALE_INVENTORY_ENTRY,
                            f"{source_key}:{item_id}:{field_name} "
                            f"(declared={declared_raw}, measured={measured_str})",
                        )
                    )


def _vocabulary_check(
    findings: list[Finding],
    vocab_key: str,
    used: set[str],
    declared: set[str],
) -> None:
    for tag in sorted(used - declared):
        findings.append(Finding(UNKNOWN_SKILL_TAG, f"{vocab_key}:{tag}"))
    for tag in sorted(declared - used):
        findings.append(Finding(UNUSED_SKILL_TAG, f"{vocab_key}:{tag}"))


def run_validation(args: argparse.Namespace) -> list[Finding]:
    findings: list[Finding] = []

    inventory_text = Path(args.inventory).read_text(encoding="utf-8")
    parsed = parse_inventory(inventory_text)
    findings.extend(parsed.findings)

    try:
        today = date.fromisoformat(args.today)
    except ValueError:
        raise SystemExit(f"validate_content_catalog.py: invalid --today {args.today!r}")

    exception_findings, active_suppressions = _validate_exceptions(
        parsed.known_exceptions, today
    )
    findings.extend(exception_findings)

    declared_by_id: dict[str, InventoryItem] = {item.id: item for item in parsed.items}

    # --- Practice Engine ---------------------------------------------------
    practice_source = Path(args.practice_catalog).read_text(encoding="utf-8")
    practice_defs = extract_practice_definitions(practice_source, str(args.practice_catalog))
    _mirror_source(
        findings, "practice_engine", {d["id"] for d in practice_defs}, declared_by_id
    )
    used_practice_tags = {tag for d in practice_defs for tag in d["skillTags"]}
    declared_practice_vocab = parsed.skill_vocabularies.get("practice_engine", set())
    _vocabulary_check(findings, "practice_engine", used_practice_tags, declared_practice_vocab)

    en_keys = extract_arb_keys(Path(args.arb_en))
    hu_keys = extract_arb_keys(Path(args.arb_hu))
    description_suppressed = "locale:practice_engine:descriptionKey" in active_suppressions
    # `locales:` (per item field-mirror below) means: the set of locales in
    # which EVERY non-suppressed localization surface of that item resolves.
    # `descriptionKey` is suppressed today (R4/known_exceptions), so only
    # `titleKey` counts toward the measured set while that suppression is
    # active — otherwise a real, unsuppressed regression could hide behind a
    # declared `[en, hu]` that no longer reflects what actually resolves.
    required_surfaces = (
        ("titleKey",) if description_suppressed else ("titleKey", "descriptionKey")
    )
    practice_measured_fields: dict[str, dict[str, object]] = {}
    for d in practice_defs:
        for field_name in ("titleKey", "descriptionKey"):
            if field_name == "descriptionKey" and description_suppressed:
                continue
            for locale, keys in (("en", en_keys), ("hu", hu_keys)):
                if d[field_name] not in keys:
                    findings.append(
                        Finding(
                            MISSING_LOCALE,
                            f"practice_engine:{d['id']}:{field_name}:{locale}",
                        )
                    )
        resolved_locales = [
            locale
            for locale, keys in (("en", en_keys), ("hu", hu_keys))
            if all(d[surface] in keys for surface in required_surfaces)
        ]
        practice_measured_fields[d["id"]] = {
            "difficulty": d["difficulty"],
            "skill_tags": sorted(d["skillTags"]),
            "locales": resolved_locales,
            "version": d["schemaVersion"],
        }
    _mirror_fields(findings, "practice_engine", practice_measured_fields, declared_by_id)

    # --- Tutor knowledge -----------------------------------------------------
    knowledge_docs = extract_knowledge_documents(Path(args.knowledge_manifest))
    _mirror_source(
        findings, "tutor_knowledge", {d["id"] for d in knowledge_docs}, declared_by_id
    )

    knowledge_assets_root = Path(args.knowledge_assets_root)
    for d in knowledge_docs:
        source_path = knowledge_assets_root / d["sourcePath"]
        if not source_path.is_file():
            findings.append(
                Finding(BROKEN_REFERENCE, f"tutor_knowledge:{d['id']}:{d['sourcePath']}")
            )

    topics: dict[str, dict[str, dict]] = {}
    for d in knowledge_docs:
        locale = d.get("locale", "")
        doc_id = d["id"]
        topic = doc_id[: -(len(locale) + 1)] if locale and doc_id.endswith(f"-{locale}") else doc_id
        topics.setdefault(topic, {})[locale] = d
    for topic, by_locale in sorted(topics.items()):
        for locale in _REQUIRED_LOCALES:
            if locale not in by_locale:
                findings.append(Finding(MISSING_LOCALE, f"tutor_knowledge:{topic}:{locale}"))

    knowledge_skill_enum = extract_knowledge_skill_enum(
        Path(args.knowledge_skill_enum_source).read_text(encoding="utf-8"),
        str(args.knowledge_skill_enum_source),
    )
    declared_knowledge_vocab = parsed.skill_vocabularies.get("tutor_knowledge", set())
    _vocabulary_check(findings, "tutor_knowledge", knowledge_skill_enum, declared_knowledge_vocab)

    knowledge_measured_fields = {
        d["id"]: {
            "difficulty": d.get("difficulty", ""),
            "skill_tags": [d.get("skill", "")],
            "locales": [d.get("locale", "")],
            "version": d.get("version", ""),
        }
        for d in knowledge_docs
    }
    _mirror_fields(findings, "tutor_knowledge", knowledge_measured_fields, declared_by_id)

    # --- Legacy Learn lessons ------------------------------------------------
    lessons, first_win = extract_lessons(
        Path(args.lesson_source).read_text(encoding="utf-8"), str(args.lesson_source)
    )
    lesson_ids = {l["id"] for l in lessons}
    if first_win is not None:
        lesson_ids.add(first_win["id"])
    _mirror_source(findings, "learn_lessons", lesson_ids, declared_by_id)

    name_suppressed = "locale:learn_lessons:name" in active_suppressions
    if not name_suppressed:
        for lesson_id in sorted(lesson_ids):
            findings.append(Finding(MISSING_LOCALE, f"learn_lessons:{lesson_id}:name:hu"))

    # `skill_tags`, `locales` and `version` have no dimension in this source
    # (no per-lesson tags, no ARB indirection, no schema bump ever shipped) —
    # ADR 0485's fail-closed sentinel: a FIXED expected value the validator
    # still enforces, so a declared row cannot simply invent a value nothing
    # measures. `difficulty` IS measured, from the source `Difficulty` enum.
    lesson_difficulty_by_id: dict[str, str] = {l["id"]: l["difficulty"] for l in lessons}
    if first_win is not None:
        lesson_difficulty_by_id[first_win["id"]] = first_win["difficulty"]
    learn_measured_fields = {
        lesson_id: {
            "difficulty": difficulty,
            "skill_tags": [],
            "locales": ["en"],
            "version": "1",
        }
        for lesson_id, difficulty in lesson_difficulty_by_id.items()
    }
    _mirror_fields(findings, "learn_lessons", learn_measured_fields, declared_by_id)

    # --- Legacy mapping table (D2 shipped reference set) ----------------------
    mapping_entries = extract_legacy_mapping(
        Path(args.legacy_mapping_source).read_text(encoding="utf-8"),
        str(args.legacy_mapping_source),
    )
    all_lesson_ids = set(lesson_ids)
    used_mapping_tags = set()
    for entry in mapping_entries:
        if entry["lessonId"] not in all_lesson_ids:
            findings.append(
                Finding(BROKEN_REFERENCE, f"legacy_mapping_table:{entry['lessonId']}")
            )
        used_mapping_tags.add(entry["skillId"])
    declared_mapping_vocab = parsed.skill_vocabularies.get("legacy_mapping_table", set())
    _vocabulary_check(findings, "legacy_mapping_table", used_mapping_tags, declared_mapping_vocab)

    return findings


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", required=True, type=Path)
    parser.add_argument("--today", default=None)
    parser.add_argument("--repo-root", default=".", type=Path)
    parser.add_argument("--practice-catalog", default=None)
    parser.add_argument("--knowledge-manifest", default=None)
    parser.add_argument("--knowledge-assets-root", default=None)
    parser.add_argument("--lesson-source", default=None)
    parser.add_argument("--legacy-mapping-source", default=None)
    parser.add_argument("--knowledge-skill-enum-source", default=None)
    parser.add_argument("--arb-en", default=None)
    parser.add_argument("--arb-hu", default=None)
    return parser


def _resolve_defaults(args: argparse.Namespace) -> argparse.Namespace:
    root = Path(args.repo_root)
    defaults = {
        "practice_catalog": root / "lib/features/practice/data/builtin_practice_catalog.dart",
        "knowledge_manifest": root / "assets/tutor_knowledge/manifest.json",
        "knowledge_assets_root": root / "assets/tutor_knowledge",
        "lesson_source": root / "lib/features/learn/model/lesson.dart",
        "legacy_mapping_source": (
            root / "lib/features/practice_generator/data/adapter/legacy_mapping_table.dart"
        ),
        "knowledge_skill_enum_source": (
            root / "lib/features/ai_tutor/data/knowledge/knowledge_document.dart"
        ),
        "arb_en": root / "lib/l10n/app_en.arb",
        "arb_hu": root / "lib/l10n/app_hu.arb",
    }
    for attr, default_value in defaults.items():
        if getattr(args, attr) is None:
            setattr(args, attr, default_value)
    if args.today is None:
        args.today = date.today().isoformat()
    return args


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = _resolve_defaults(parser.parse_args(argv))

    try:
        findings = run_validation(args)
    except SourceMeasurementError as exc:
        print(f"exception: {exc}")
        return 1

    for finding in findings:
        print(finding.render())

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
