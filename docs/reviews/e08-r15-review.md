# E08-R15 — Review

Brief: `docs/rounds/e08-r15-achievement-ui-and-evidence.md`
Diff: `a1547d45...86e12fc3`
Reviewer: Codex / `gpt-5.6-sol` · Dátum: 2026-08-21
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 nyitott (4 javítva) · MINOR: 0 · NOTE: 0

A Terra javítókör a commitált végállapot analyzer-hibáit, a detail action
hiányát, az audit-only kategória UI-szivárgását és a numerikus evidence-rést
lezárta. A végleges diff friss, izolált klónban scope-tiszta és a kötelező
kör-gate minden lépése zöld. Két eldobható valódi-sértés pirosra vitte a
hozzájuk tartozó őrtesztet, restore után a klón tiszta és a cellák zöldek.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | all / unlocked / in-progress / category helyes halmaz | ✅ | valós kategória pozitív, `accessibilityNeutral` és hidden negatív cellák |
| A2 | locked hidden részlet a semantics fában sincs | ✅ | screen + detail negatív cella; `Opacity(0)` mutáció piros, restore zöld |
| A3 | progress és completion dátum | ✅ | A3 widget-cella, locale-formázott dátum |
| A4 | zárt, privacy-safe evidence | ✅ | zárt reason enum, aggregate-only contract, invalid numerikus mátrix |
| A5 | lokalizált empty state | ✅ | A5 widget-cella |
| A6 | exact unknown ID safe state | ✅ | A6 widget-cella |
| A7 | minden copy ARB | ✅ | feature-szegmens + aggregate parity |
| A8 | nagy text scale + teljes semantics | ✅ | 1.99/2.0/2.01/3.0 mátrix; exact-ID button action |

## Scope-audit

```text
Legacy scope audit OK (34076d249b0e..86e12fc3d24c, 5 changed path(s), 0 generated/ignored)
```

Az első implementáció 10 útvonala és a javítókör 5 útvonala is kizárólag a
brief tételes allowlistjén belül van.

## Megállapítások lezárása

### F1 — MAJOR — FIXED (`86e12fc3`)

A két szükségtelen non-null assertion eltűnt, a publikus
`AchievementContent` és lookup dokumentált. A végső analyzer 0 leletet ad.

### F2 — MAJOR — FIXED (`86e12fc3`)

A caller-fed `ValueChanged<String>` callback a visible/revealed tile exact
achievement ID-ját adja át egy button semantics action és egy `InkWell`
útvonalon. A locked hidden placeholder nem tappable és nem ad valódi ID-t.

### F3 — MAJOR — FIXED (`86e12fc3`)

Az explicit `_filterableCategories` lista kizárja az audit-only
`accessibilityNeutral` értéket. Tartós pozitív és negatív widget-cellák
védik a szerződést.

### F4 — MAJOR — FIXED (`86e12fc3`)

Az `AchievementEvidence` runtime őre csak véges, nem negatív current és
véges, pozitív target értéket enged. A NaN/infinity/negatív/0 mátrix tartós;
az őr kikapcsolásakor piros, restore után zöld.

## Gate-bizonyíték

| Gate | Eredmény |
|---|---|
| scope-audit | OK, 5 javítókör-path, 0 generated/ignored |
| format | zöld, 1739 fájl, 0 változás |
| analyze | zöld, 0 lelet |
| célzott suite | zöld, 16/16 |
| architecture | zöld, 12 allowlisted eltérés |
| secrets | zöld, 3123 fájl, 0 lelet |
| l10n | zöld, 1532 en/hu üzenet |
| A2 mutáció | `Opacity(0)` hidden cím → piros; restore → zöld |
| A4 mutáció | current-validáció kikapcsolása → piros; restore → zöld |
| review-klón végállapot | `git diff --check` zöld, munkafa tiszta |
| CI | az APPROVED review után exact-SHA-n dispatchelendő |

## Merge-döntés

A kód- és privacy-review APPROVED. Merge csak a végleges head exact-SHA
Full Gate/Build APK terve, Router CI és a merge-lockos landoló zöld eredménye
után engedélyezett.
