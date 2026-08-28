# E12-R09 — független review (ADR 0055 / ADR 0138)

- **Kör:** `E12-R09` — Domain event catalog és schema registry
- **Branch:** `sonnet-impl/e12-r09-domain-event-catalog-and-schema-registry`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5, orchestrátor-session), READ-ONLY — a review során production-fájl nem módosult
- **Reviewelt HEAD:** `eedf4ac6`
- **Dátum:** 2026-08-28

## 1. Mit mértem (nem bemondás)

| Mérés | Parancs | Eredmény |
|---|---|---|
| Scope-audit a brief `allowed_paths` ellen | `python3 tools/scope-audit.py --repo … --brief … --base e2462f8a` | `Legacy scope audit OK (e2462f8a..eedf4ac6, 9 changed path(s), 0 generated/ignored)` |
| Munkafa tisztaság | `git status --short` | üres (a `dirty_files=1` a jelzés pillanatában a gitignore-olt jelzésfájl volt) |
| Célzott teszt IZOLÁLT `/tmp` klónban | `flutter test test/core/events/event_schema_compatibility_test.dart` | **22/22 zöld** |
| CI-terv | `tools/round-ci-plan.py --brief … --base origin/main --head HEAD` | `dispatch: ["full-gate.yml"]`, `router_ci_expected: true`, `apk_required: false` |

A célzott tesztet **nem** az implementer munkapéldányában futtattam: friss `/tmp` klón + `tools/prepare-flutter-generated.sh`, hogy a zöld ne a helyi állapot mellékhatása legyen.

## 2. Valódi-sértés próbák (a cella BUKÁSI KÉPESSÉGE — L477, L443)

Mindhárom próba az izolált klónban futott, utána visszaállítva (`git status --short` üres).

| Próba | Beavatkozás | Mért eredmény |
|---|---|---|
| **P1** — hamis producer | a katalógus `analysis` producer-cellája létező, de NEM termelő fájlra átírva (`streak_service.dart:56`) | **PIROS** — `A5: … streak_service.dart is listed as a producer for analysis but does not contain a AnalysisActivityEvent(...) constructor call` |
| **P2** — a „nincs producer" állítás hazuggá tétele | ÚJ `lib/features/ai_tutor/application/probe_tutor_producer.dart` valódi `TutorActivityEvent(...)` hívással | **PIROS** — `A8: a TutorActivityEvent producer appeared on the tree — the catalog row must be updated: [lib/features/ai_tutor/application/probe_tutor_producer.dart]` |
| **P3** — nem kanonikus fixture | `occurredAt` ezredmásodperc nélkülire írva (`…T09:00:00Z`) | **PIROS** — `A7: practice_session_completed_v1.json must be byte-canonical …` (3 bukott cella) |

A P2 azért fontos, mert az A8 az egyetlen cella, ami egy **hiányt** állít: a próba bizonyítja, hogy a „NO PRODUCER (mért)" jelölés nem szabad szöveg, hanem mért állítás. A P1 pedig azt fogja meg, amit a naiv „létezik-e a fájl" ellenőrzés nem: a létező, de rossz hivatkozást.

## 3. Acceptance-mátrix — cellánként

| # | Kritérium | Hol méri | Verdikt |
|---|---|---|---|
| A1 | round-trip mind a hat fixture-re | `A1/A2/A7 …` csoport, `$typeCode fixture is canonical and round-trips` | ✅ |
| A2 | ismeretlen extra mező tolerált, a mezők változatlanok | `… unknown extra field still decodes …` (6 cella) | ✅ |
| A3 | hiányzó `schemaVersion` → kontrollált hiba | `missing schemaVersion throws ArgumentError` | ✅ |
| A4 | ismeretlen `type` → kontrollált hiba | `unknown type discriminator throws ArgumentError` | ✅ |
| A5 | producer/consumer hivatkozás létezik ÉS termel | `A5: every producer reference …` + `every consumer reference …` | ✅ (P1 bizonyítja a bukási képességet) |
| A6 | owner Chapter + idempotencia-kulcs minden soron, mind a hat `type` | `the catalog has a row for every fixture type and no others`, `every row carries a non-empty owner Chapter and idempotency key` | ✅ |
| A7 | kanonikus fixture (`jsonDecode == toJson()`) | ugyanaz a cella, mint A1 | ✅ (P3) |
| A8 | a „nincs producer" állítás igaz a fán | `A8: the tutor row claims no producer …` | ✅ (P2) |
| Küszöb-hármas | `0` piros · `1` zöld · `2` piros | `Schema-version threshold …` csoport, 3 cella | ✅ — mindhárom a VALÓDI `LearningActivityEvent.fromJson`-t hívja, nem tesztbeli segéd-predikátumot (L443) |

**A tiltott gyengítések ellenőrzése:** `lib/**` diff **nincs** (a scope-audit 9 útvonala kizárólag a §4 lista); új envelope-típus **nincs**; a katalógus a `< V` esetre kimondja a kontrollált hibát (nem „best-effort olvasás"), és sehol nem tartalmaz `lib/core/events/` hivatkozást.

## 4. Igazmondás-ellenőrzés (a §10 handoff állításai)

- A hivatkozott consumer-sorok MÉRVE valósak: `streak_service.dart:56`, `default_streak_policy.dart:55`, `activity_outbox_repository.dart:31`, `local_activity_outbox_repository.dart:219`, `activity_event_ingestor.dart:53` mind `LearningActivityEvent`-et említő sor.
- A `tutor` sor indoklása (`gamification_tutor_adapter.dart:164–170`) a fájl saját szövegével egyezik („do NOT build a `TutorActivityEvent`"), és az ott hivatkozott ADR 0289 + §5.1 + chat-farming indoklás szintén a forrásfájl kommentjéből származik, nem találgatás.
- A §10-ben leírt két javítás (escape-elt `\|` a saját doksi-táblában → hamis katalógus-sor; a Dart 3 objektum-minta `TutorActivityEvent()` hamis pozitívja) a diffben visszakereshető (`ecf17b85`), és a `_containsConstructorCall` megoldás mérten helyes (P1/P2).

## 5. Leletek

| # | Súly | Lelet |
|---|---|---|
| F1 | **NOTE** | A §6 kötelező valódi-sértés próbája az **A3** cella pirosra váltását írta elő; a MÉRT hatás az A1/A7 és a küszöb-„rajta" cellákon jelentkezett, mert az A3 cella memóriabeli másolaton dolgozik (a fixture-fájl sérülése nem éri el). Az implementer ezt **kimondta és megindokolta** a §10-ben, nem takarta el — a próba célja (a gate valódi séma-sértésre pirosra vált) teljesült, ugyanazon a `_requireInt` kódágon. A brief szövege volt pontatlan, nem a szállítmány. |
| F2 | **NOTE** | A katalógus-parszoló (`_parseCatalogRows`) az üres cellákat kiszűri (`where(isNotEmpty)`), ezért egy üresen hagyott oszlop csendes index-csúszást okozhatna. A gyakorlatban ez nem rejt hibát: a hiányzó cella a sort 7 alá viszi → a sor kimarad → a „row for every fixture type" cella PIROSRA vált (mérve a P-sorozat mellett a cella logikájából). Egy későbbi kör explicit cella-számláló ellenőrzéssel szigoríthatja. |
| F3 | **NOTE** | Elgépelés a §10 handoffban: „a küszöb-hármas »rajta« ccustomáján" (helyesen: cellájában). Kizárólag szöveg, mérce nem érinti. |

**BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 3**

## 6. VÉGSŐ DÖNTÉS

**APPROVED.** A szállítmány a brief §4 listáján belül marad, mind a nyolc acceptance-cella + a kétirányú küszöb-hármas valódi belépőn mér, és három független sértés-próba bizonyította, hogy a cellák pirosra tudnak váltani. A merge feltétele a változatlan zöld kapu a merge SHA-n (`full-gate.yml` + `router-ci.yml`).
