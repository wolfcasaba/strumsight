# E04-R02 — Tutor azonosítók, conversation és message domain

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-04, kód **újramérve**: main @ `dd7712d`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 2; §35
- **Branch:** `codex/e04-r02-conversation-and-message-domain`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R01 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/models/tutor_ids.dart",
  "lib/features/ai_tutor/domain/models/tutor_conversation.dart",
  "lib/features/ai_tutor/domain/models/tutor_message.dart",
  "lib/features/ai_tutor/domain/models/tutor_content_block.dart",
  "lib/features/ai_tutor/domain/models/tutor_turn.dart",
  "lib/features/ai_tutor/domain/models/tutor_response_mode.dart",
  "lib/features/ai_tutor/data/local/tutor_conversation_codec.dart",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/domain/tutor_conversation_test.dart",
  "test/features/ai_tutor/domain/tutor_message_test.dart",
  "test/features/ai_tutor/data/tutor_conversation_codec_test.dart",
  "docs/rounds/e04-r02-conversation-and-message-domain.md",
]
gate_tests = [
  "test/features/ai_tutor/domain",
  "test/features/ai_tutor/data",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** `origin/main` + E04-R01 merge
> ellenőrzése; olvasd újra az `AGENTS.md`-t, Chapter 1/5-öt, `HANDOFF.md`-t.
> **ADR-reconcile:** nincs ÚJ ADR ebben a körben; a §5 a R01 0131–0134-re
> hivatkozik — igazold a végleges számokat. `rg`-vel mérd a `tool/check_architecture.dart`
> domain-purity szabályát és az R01 `ai_tutor/public.dart` mai alakját.
> PREPARED→PLANNING, brief commit a kör-branchre az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl, hiányzó contract,
ellentmondó acceptance vagy megkülönböztetésre alkalmatlan teszt esetén `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

Pre-flight lezárva 2026-08-04, orchestrátor Claude (Opus 4.8). Baseline **újramérve**:
`main` @ `dd7712d` (E04-R01 merge `814388a` beleértve). Az alábbi mért feloldások
**KÖTÖTTEK** — az implementer ezeket ne írja felül.

**(1) ADR-reconcile — nincs ÚJ ADR.** A `docs/adr/0131`–`0134` fájlok léteznek és
elfogadottak (mérve: `ls docs/adr/013{1,2,3,4}-*.md` → provider-boundary /
privacy-and-consent / tool-confirmation / memory-policy). Ez a kör **greenfield
domain-modell**, nem hoz új keresztmetsző normatív döntést: a §5 döntései a
**0131 provider-boundary** (Flutter-/SDK-mentes domain) és a **0132/0134**
(nincs system-prompt / rejtett reasoning tárolás) **kiterjesztései**. Ezért új
ADR-számot nem osztunk. (A pipeline-prompt „te írod meg az ADR-t" pontja arra a
körre vonatkozik, amelyik új döntést hoz; itt a mért helyzet szerint nincs.)

**(2) MÉRT DRIFT — a domain-purity gépi őr NEM fedi az `ai_tutor/domain`-t
(§1 mérési szabály).** A §2/§5.1/§6 szövege azt sugallja, hogy egy meglévő
`tool/check_architecture.dart` őr „a `lib/features/*/domain/` alatt" automatikusan
tiltja a framework-importot, és a „purity-őr zöld" acceptance egy meglévő guard
kizöldülése. **Ez mérve hamis:**

- `tool/check_architecture.dart` `_isSharedDomain` (232. sor) **csak** ezt a hármat
  fedi: `lib/core/music/`, `lib/core/audio/codec/`, `lib/features/practice/domain/`.
  `ai_tutor` **nincs benne**.
- `test/features/practice/domain/domain_purity_test.dart` a `Directory('lib/features/practice/domain')`-ra van **beégetve** (18. sor).

**KÖTÖTT FELOLDÁS — a song_trainer (E03-R02) precedens:** a feature-domain
purity-mércéje **kör-lokális teszt-scanner**, NEM a `tool/check_architecture.dart`.
Lásd `test/features/song_trainer/domain/song_document_test.dart:292`
(`group('Domain purity')` → `Directory('lib/features/song_trainer/domain')` +
`_forbiddenPatterns`). Ezt a kör **pontosan ugyanígy** teszi: az `ai_tutor/domain`
purity-t egy `group('Domain purity')` blokk méri a
`test/features/ai_tutor/domain/tutor_conversation_test.dart`-ban (a §4 glob
`test/features/ai_tutor/domain/*` engedi), `Directory('lib/features/ai_tutor/domain')`
rekurzív szkennelésével és a song_trainer/practice-szel azonos tiltott mintakészlettel:
framework/riverpod/dio/shared_preferences import, `l10n` import, `DateTime.now(`,
`Stopwatch(`, `Random(`, `print(`. **A `tool/check_architecture.dart` TILOS ZÓNA**
(gate/tool-fájl, nincs az engedélyezett listán) — az implementer NEM szerkeszti,
és NEM az őt mérő guardra hivatkozik a §6 „purity-őr zöld" teljesítésekor.

**(3) Erőforrás-tulajdonlás (§1 mérési szabály 2) — N/A.** Ez tiszta domain-modell
kör; nincs lease/lock/handle/subscription réteghez rendelve (`grep -rn "\.acquire("`
az `ai_tutor` alatt üres — greenfield). A mérési szabály 2 nem alkalmazandó.

**(4) Greenfield igazolva.** `lib/features/ai_tutor/` ma csak az R01 üres
`public.dart`-ot tartalmazza (+ a `test/features/ai_tutor/ai_tutor_boundary_test.dart`
R01 boundary-teszt, amely NINCS az engedélyezett listán → érintetlen marad).
A brief-beli enum-készletek (role user/tutor/tool/systemNotice; delivery-state
pending/streaming/complete/failed/cancelled) ÚJ definíciók — nincs meglévő
reducer/állapotgép, így „elérhetetlen cél-státusz" kockázat nincs; a §6 megköveteli,
hogy `cancelled` ÉS `failed` külön reprezentálható legyen és round-trippeljen.

**(5) MÉRT ÜTKÖZÉS — `public.dart` export HALASZTVA (implementer STOP feloldása,
2026-08-04T23:36Z).** Az implementer a kód előtt helyesen `stopped`-ot jelzett:
a **lezárt E04-R01** `test/features/ai_tutor/ai_tutor_boundary_test.dart`
tesztje azt méri, hogy a `public.dart` **NULLA** `import`/`export` direktívát
tartalmaz („empty baseline boundary"), és ez a teszt-fájl **tilos zóna** (nincs
az engedélyezett listán). Így a §4/§8.4 additív `public.dart` export a listán
belül nem tehető zölddé.

**KÖTÖTT FELOLDÁS (scope-SZŰKÍTÉS, nem tágítás — ADR 0087 §2 orchestrátor-autonómia):**
a `public.dart` ebben a körben **üres marad** (az R01 boundary-invariáns
sérthetetlen, a teszt zöld marad — nem nyúlunk lezárt kör artefaktumához). Az
additív feature-export az **első valódi fogyasztó köréig halasztva** (UI/gateway/
repository = R13/R17+, a §3 „Kívül" szerint amúgy is ezen körön kívül). Ez semmit
nem veszít mérhetőt: a §6 acceptance mind a modelleken + codecen + azok **közvetlen**
tesztjein mérendő (a tesztek közvetlenül importálják a `domain/models/*` és
`data/local/*` fájlokat, nem a `public.dart`-on át). A `public.dart` boundary-export
egy külön, R13/R17+ körben lesz additív, amikor lesz keresztfeature-fogyasztó és a
boundary-teszt is a fogyasztói szerződéshez igazítható.

## 1. Cél

A beszélgetés és üzenetek immutable, verziózott, **providerfüggetlen** domain
alapjának létrehozása — Flutter- és model-SDK-mentesen.

## 2. Jelenlegi állapot

- `lib/features/ai_tutor/` ma csak az R01 üres `public.dart`-ot tartalmazza —
  domain-model nincs (greenfield).
- A domain-purity gépi őr (`tool/check_architecture.dart`) tiltja a
  Flutter/Riverpod/provider-SDK importot a `lib/features/*/domain/` alatt — ez a kör
  ennek hatálya alá esik.
- A `SongDocument`/Practice V2 domain a verziózott, determinisztikus kulcssorrendű
  JSON-codec precedense (E03-R02 / E02-R03) — ugyanezt a mintát követi.

## 3. Scope

**Benne:** typed ID-k (conversation/message/turn/request/action), `TutorConversation`,
`TutorMessage`, sealed content-block hierarchia, role-készlet (user/tutor/tool/
systemNotice), delivery-state (pending/streaming/complete/failed/cancelled),
verziózott JSON-codec, immutable + stable-sequence rendezett listák, forward-compat
unknown-block policy.

**Kívül — TILOS:** provider-SDK típus, system-prompt vagy rejtett reasoning
tárolása, UI/gateway/repository (R13/R17+), bármely storage-írás.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/models/tutor_ids.dart` | ÚJ | typed ID-k + validáció |
| `.../domain/models/tutor_conversation.dart` | ÚJ | conversation modell |
| `.../domain/models/tutor_message.dart` | ÚJ | message modell |
| `.../domain/models/tutor_content_block.dart` | ÚJ | sealed content-block |
| `.../domain/models/tutor_turn.dart` | ÚJ | turn modell |
| `.../domain/models/tutor_response_mode.dart` | ÚJ | response mode enum |
| `.../data/local/tutor_conversation_codec.dart` | ÚJ | verziózott JSON-codec |
| `lib/features/ai_tutor/public.dart` | **ÜRES MARAD (§0.0 (5))** | additív export **HALASZTVA** az első fogyasztó köréig (R13/R17+) — a R01 boundary-teszt zölden tartása |
| `test/features/ai_tutor/domain/*` , `.../data/tutor_conversation_codec_test.dart` | ÚJ | domain + codec tesztek |
| `docs/rounds/e04-r02-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A domain **Flutter- és provider-SDK-mentes** (ADR 0131 provider-boundary + a
   domain-purity őr).
2. A codec **determinisztikus** (kulcssorrend, UTC ISO-8601), ismeretlen block-type
   esetén **forward-compatible placeholder VAGY dokumentált failure** (nem néma dobás).
3. Listák immutable-ök, **stable sequence** szerint rendezettek.
4. Conversationben **nincs** system-prompt / rejtett reasoning (ADR 0132/0134).

## 6. Acceptance criteria

- [ ] Typed ID validáció (trim/nem-üres/max hossz) — literálisan tesztelt kódkészlet.
- [ ] Conversation + message JSON **round-trip** bit-stabil; message-ordering stable.
- [ ] Unknown-block policy: **mátrix** — ismert block → dekódol; ismeretlen block →
      placeholder-VAGY-dokumentált-failure (a választott ág tesztelt); **NEM
      elfogadható:** néma eldobás vagy csendes crash.
- [ ] Cancelled és failed delivery-state külön reprezentálható és round-tripel.
- [ ] UTC timestamp policy; nagy Unicode szöveg round-trip.
- [ ] Domain Flutter-független — a **kör-lokális** `group('Domain purity')` scanner zöld
      (§0.0 (2): a song_trainer precedens, a `tool/check_architecture.dart` NEM fedi az
      `ai_tutor/domain`-t és tilos zóna); **≥90% line coverage** az új domainen.

A reviewer a codec egy központi invariánsát (kulcssorrend VAGY unknown-block ág)
eldobható mutációval pirosra vált.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/data
```

Egyetlen lokális gate, külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. Typed ID-k + RED validációs tesztek.
2. Content-block + message + conversation + turn modellek.
3. Verziózott codec + round-trip / unknown-block tesztek.
4. **`public.dart` ÜRES MARAD** (§0.0 (5) — export halasztva, R01 boundary-teszt zöld); gate.

Javasolt commit: `feat(ai-tutor-domain): add versioned conversations and messages`.

## 9. Kockázatok

- A sealed hierarchia Dart-verzió/`sealed` mintázata — igazold a `switch`-exhaustivitást.
- Coverage-cél: a ritka ágakhoz (cancelled/failed, unknown-block) is kell teszt.

**STOP:** provider-SDK import, néma unknown-block eldobás vagy mércegyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

- **Megvalósítás:**
  - `domain/models/tutor_ids.dart`: trim/üres/max-hossz validált, típusos
    conversation/message/turn/request/action ID-k.
  - `domain/models/tutor_conversation.dart`, `tutor_message.dart`,
    `tutor_turn.dart`, `tutor_response_mode.dart`: immutable, UTC-normalizált
    value-modellek; a conversation a message-eket sequence szerint stabilan
    rendezi.
  - `domain/models/tutor_content_block.dart`: sealed, strukturált block-készlet;
    ismeretlen type teljes JSON-objektumát immutable placeholderként megőrzi.
  - `data/local/tutor_conversation_codec.dart`: schema v1, fix kulcssorrendű
    UTF-8 JSON, UTC timestamp, ismert-block round-trip és ismeretlen-block
    megőrzés.
  - A `public.dart` változatlanul csak `library;`; a R01 boundary-teszt
    változatlan maradt (§0.0 (5)).
- **Tesztbizonyíték:**
  - RED: `flutter test test/features/ai_tutor/domain test/features/ai_tutor/data`
    a még hiányzó domain/codec importokra fordítási hibával állt meg.
  - GREEN: ugyanaz a célzott tesztfuttatás 39/39 teszttel zöld.
  - Lefedettség: `flutter test --coverage test/features/ai_tutor/domain
    test/features/ai_tutor/data`, majd az `coverage/lcov.info` AI Tutor domain
    szűrése: **246/253, 97,23%**.
  - Kötelező gate: `tools/round-gate.sh test/features/ai_tutor/domain
    test/features/ai_tutor/data` → format, analyze, mindkét célzott teszt és
    architecture: zöld.
- **Eltérés:** nincs; a §0.0 (5) szerinti public-boundary halasztás változatlan.
- **Nem futtatott ellenőrzések:** teljes Flutter suite, randomizált property gate
  és APK/CI dispatch — az orchestrátor feladata; `gh`-t nem hívtam.
- **Follow-up:** az additív feature-export az első valódi fogyasztó R13/R17+
  körében esedékes a §0.0 (5) szerint.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r02-conversation-and-message-domain-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
