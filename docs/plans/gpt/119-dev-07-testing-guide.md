---
id: 119
topic: Testing Guide — Flutter gate külön parancsokkal, property seed, backend pytest+Ruff, ML parity, device gate, flaky policy
tags: [development, testing, gates, property]
status: active
depends_on: []
canonical_target: docs/development/07-testing.md
verify: CI a leírt gate-eket futtatja
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, 58-file manifest)
---

# Testing Guide

## Flutter standard gate

Külön parancsok:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze lib/ test/ tool/
flutter test
flutter test test/property
```

Ha `tool/` még nem létezik, a kör dokumentálhatja a szűkebb parancsot.

## Property tests

- Lokális default seed determinisztikus.
- CI friss `PROPERTY_SEED` értéket használ.
- Invariáns legyen százalékos/toleranciás, ne flaky időzítés.
- DSP/reducer/idempotency változásnál preferált.

## Backend

```bash
cd backend
python -m pytest -q
```

A Chapter 2 után Ruff és Alembic gate is kötelező.

## ML

- gyors unit/parity teszt minden változásnál;
- nehéz training/evaluation manuális vagy nightly workflow;
- shipping assethez model card és checksum;
- Python és Dart output tolerancia dokumentált.

## Device testing

Kötelező, ha a kör érinti:

- mikrofon vagy camera lifecycle;
- audio latency;
- thermal/memory;
- notification;
- secure storage;
- release signing;
- offline AI runtime.

## Tesztbizonyíték

PR-ben pontos parancs és eredmény. „Tests passed” önmagában nem elég. Nem futott gate-et külön jelöld.

## Flaky test

- ne kapcsold ki;
- rögzíts seedet/logot;
- izoláld clock/network/plugin függést;
- külön issue, owner és határidő;
- required gate-ből kivétel csak időkorlátos waiverrel.

---
