# E04-R06 — Kurált tutor tudásbázis schema és első content pack

- **Státusz:** PLANNING (pre-flight mérve 2026-08-05, kód olvasva: main @ `5180d08`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 6; §35
- **Branch:** `codex/e04-r06-knowledge-schema-and-content-pack`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R01 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "assets/tutor_knowledge/manifest.json",
  "assets/tutor_knowledge/en/",
  "assets/tutor_knowledge/hu/",
  "lib/features/ai_tutor/data/knowledge/knowledge_document.dart",
  "lib/features/ai_tutor/data/knowledge/knowledge_codec.dart",
  "tool/build_tutor_knowledge_manifest.dart",
  "pubspec.yaml",
  "test/features/ai_tutor/data/knowledge_codec_test.dart",
  "test/features/ai_tutor/data/knowledge_manifest_test.dart",
  "docs/rounds/e04-r06-knowledge-schema-and-content-pack.md",
  "docs/adr/0135-tutor-knowledge-governance.md",
]
gate_tests = [
  "test/features/ai_tutor/data",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R01 merge; olvasd újra
> `AGENTS.md` (**§9 DSP-tilalom!**), Chapter 1/5, `HANDOFF.md`. **ADR-reconcile:**
> a batch **0135**-öt oszt (tutor-knowledge-governance); ha E03-R21/R22 vagy a
> korábbi Epic 4 körök eltolták, javítsd. `rg`/`ls`: a `docs/rag/chunks/` mai
> tartalma (**NEM másolható** ide), a `pubspec.yaml` `assets:` szekciója.
> PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Mérve az orchestrátor pre-flightban, `main` @ `5180d08` (2026-08-05).** Előre
kiosztott ADR: **0135** (tutor-knowledge-governance) — az orchestrátor írta meg
(`docs/adr/0135-tutor-knowledge-governance.md`), NEM implementer-diff, NEM TOML
`allowed_paths`.

**Mért baseline (grep/ls a kódban, nem a tábla):**

1. **ADR-reconcile:** a legmagasabb létező ADR `0134`; `docs/adr/0135*` nem
   létezett → **0135 szabad**, reconcile nem kellett. Az ADR ebben a
   pre-flightban megíródott és az engedélyezett listára került.
2. **E04-R01 merge** megvan (`814388a`, PR #124); Epic 3/E04-R05 lezárva
   (`main` @ `5180d08`). Előfeltételek teljesülnek.
3. **`assets/tutor_knowledge/` NEM létezik** (greenfield); a `pubspec.yaml`
   `assets:` szekció létezik (58. sor) → additív bővítés.
4. **`lib/features/ai_tutor/data/`** ma csak a `local/` codeceket tartalmazza
   (`tutor_profile_codec.dart`, `tutor_conversation_codec.dart`); a
   `data/knowledge/` **új**. A `test/features/ai_tutor/data/` könyvtár
   **létezik** (codec-tesztek); az új tesztek oda kerülnek.

**REVÍZIÓ — engedélyezett-lista SZŰKÍTÉS (ADR 0087 §2, autonóm):**
`lib/features/ai_tutor/public.dart` **eltávolítva** az engedélyezett listáról
és **ÜRES MARAD**. Mért indok: a lezárt `test/features/ai_tutor/ai_tutor_boundary_test.dart`
egy **nulla-export invariánst** kényszerít a `public.dart`-ra (E04-R02..R05
precedens, ADR 0131 §2) — bármely `import`/`export` direktíva PIROSRA váltja a
boundary tesztet. A brief eredeti „additív export" cellája hamis feltételezés
volt; ez a kör greenfield schema + content + build-tool + teszt, hívó nélkül, a
fogyasztók a retrieval-körben (R07) jönnek. A `public.dart` érintetlen marad.

**§1 mérési szabályok:**

- **(1) Elérhetetlen cél-státusz — approval lifecycle.** Az acceptance
  „approved-only build" cellája egy státuszt (`approved`) ír elő. Ez NEM
  reducer/állapotgép-átmenet: az `approved`/`reviewNeeded`/`rejected` státusz a
  **dokumentum-forrásfájl saját, szerző által írt mezője**, a build-tool pedig
  erős egyenlőséggel (`status == approved`) szűr a production manifestbe. Az
  input, amely az `approved`-ot produkálja, tehát a review után `approved`
  státuszúra állított content-fájl — a mutációs próba (egy `reviewNeeded`
  átcsúszik) RED-re vált.
- **(2) Erőforrás-tulajdonlás.** A kör nem rendel lease/lock/handle/subscription
  erőforrást egyetlen réteghez sem (tiszta build-tool + immutable value object +
  asset-fájlok) → **N/A**.

**AGENTS.md §9 megerősítve:** a `docs/rag` fejlesztői DSP/ML anyag, NEM másolható;
a tutor-tartalom saját/jogtiszta, `license` + `hash` mezővel (ADR 0135 §1–§2).

## 1. Cél

Felhasználói célú, **review-zott, verziózott** gitároktatási tudásbázis
létrehozása, a fejlesztői DSP RAG-től **szigorúan elkülönítve**.

## 2. Jelenlegi állapot

- Nincs user-célú tutor knowledge pack (SDD §3.2/6/7); a `docs/rag/chunks/`
  **fejlesztői DSP-anyag** (AGENTS.md §9), NEM tanulói tartalom → nem másolható.
- `assets/` és `pubspec.yaml` `assets:` szekció létezik — additív bővítés.
- Nincs approval-lifecycle vagy manifest-hash konvenció tutor-tartalomra.

## 3. Scope

**Benne:** `KnowledgeDocument`/`KnowledgeChunk` schema, approved/reviewNeeded/
rejected lifecycle, első jogtiszta en+hu dokumentumok (rhythm/chord/technique/
practice/safety), locale+skill+difficulty+license+hash minden dokumhoz,
determinisztikus build-tool, **approved-only** production manifest, content review
checklist, CI hash-ellenőrzés.

**Kívül — TILOS:** `docs/rag` automatikus másolása, retrieval/index (R07), UI,
jogvédett/harmadik-fél tartalom.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `assets/tutor_knowledge/manifest.json` | ÚJ | approved-only manifest |
| `assets/tutor_knowledge/en/`, `.../hu/` | ÚJ | jogtiszta en/hu dokumentumok |
| `.../data/knowledge/knowledge_document.dart` | ÚJ | document/chunk schema |
| `.../data/knowledge/knowledge_codec.dart` | ÚJ | determinisztikus codec |
| `tool/build_tutor_knowledge_manifest.dart` | ÚJ | reprodukálható build |
| `pubspec.yaml` | meglévő | assets-bejegyzés (csak additív) |
| `test/features/ai_tutor/data/*` | ÚJ | schema/hash/approved-only tesztek |
| `docs/rounds/e04-r06-*.md` | meglévő | §10 handoff + review checklist |
| `docs/adr/0135-tutor-knowledge-governance.md` | ÚJ (pre-flight, **orchestrátor**) | governance döntés |

**Tilos zóna:** `docs/rag` (olvasható precedensként, de NEM másolható),
minden más fájl, más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **ADR 0135:** a user tutor knowledge pack **külön** a `docs/rag` DSP-anyagtól;
   automatikus másolás TILOS; a production manifest **kizárólag approved** dokumentumot
   tartalmaz. **NEM elfogadható:** reviewNeeded/rejected dokumentum a production buildben.
2. Minden dokumentum locale+skill+difficulty+license+**hash**-t hordoz; determinisztikus
   chunking → reprodukálható build.
3. CI ellenőrzi a manifest+chunk hash-eket.

## 6. Acceptance criteria

- [ ] Manifest schema-validált; **duplicate ID**, **missing license**, **hash
      mismatch**, **corrupt content** külön hibakóddal elutasított (mind a 4 eset).
- [ ] **Approved-only build:** reviewNeeded/rejected dokumentum kizárva a production
      manifestből — teszt bizonyítja; **NEM elfogadható** enyhébb szűrés.
- [ ] Locale coverage: rhythm/chord/technique/practice/safety mind en+hu.
- [ ] A build **reprodukálható** (kétszeri futtatás bit-azonos manifest/chunk).

A reviewer az approved-only szűrőt eldobható mutációval (egy reviewNeeded átcsúszik)
pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/data
```

Külön processzek, nincs `&&`/pipe/`tail`. A `pubspec.yaml` assets-változás CI-ben
asset-gate alatt is fut. CI = orchestrátor exact-SHA dispatch.

## 8. Implementációs sorrend

1. Schema + codec + RED hash/approved-only tesztek.
2. Első en+hu dokumentumok + license/hash.
3. Determinisztikus build-tool + manifest.
4. `pubspec.yaml` assets; gate.

Javasolt commit: `feat(ai-tutor-knowledge): add curated versioned tutor knowledge pack`.

## 9. Kockázatok

- **Jogtisztaság:** csak saját/engedélyezett tartalom, license-mezővel — jogvédett
  tab/lyrics TILOS.
- A `docs/rag` másolásának kísértése (AGENTS.md §9) → `stopped`, nem néma átemelés.

**STOP:** `docs/rag` másolás, approved-only gyengítés vagy licenc-hiányos dokumentum
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

### Szállított változtatás

- `KnowledgeDocument` és `KnowledgeChunk` immutable value schema: verzió,
  locale, skill, difficulty, license, approval-status és SHA-256 content hash
  validációval; a codec stabil hibakódokkal utasítja el a hibás JSON-t és a
  hibás enum/mezőértékeket.
- Determinisztikus, kanonikus UTF-8 JSON codec és bekezdés-alapú chunker;
  a manifest-builder a forrásokat lexikálisan rendezi, a dokumentum-content
  hash-t újraszámolja, és kizárólag `status == approved` dokumentumot ír ki.
- Tíz saját szerzésű, CC0-1.0 license-mezővel ellátott documentum az en+hu
  packban: rhythm, chord, technique, practice és safety témánként egy-egy.
  A generált `manifest.json` document- és chunk-hash-eket, valamint source
  pathot tartalmaz.
- Additív Flutter asset-bejegyzés a `tutor_knowledge/` könyvtárhoz.

### Content review checklist — alkalmazva mind a 10 dokumentumra

- [x] Saját, rövid oktatási szöveg; nincs átvétel a `docs/rag`-ból, tab-ból,
  dalszövegből vagy harmadik fél oktatási anyagából.
- [x] `CC0-1.0` license, schema version, document version és SHA-256 content
  hash jelen van.
- [x] A safety szöveg megállást és képzett egészségügyi szakember felkeresését
  kéri tartós vagy visszatérő tünetnél; nem ad diagnózist.
- [x] Nincs mérési, DSP- vagy kameraeredményre vonatkozó bizonyítatlan állítás.
- [x] Mindkét locale mind az öt kötelező topicot fedi.

### Futott ellenőrzések

- RED: `flutter test test/features/ai_tutor/data/knowledge_codec_test.dart test/features/ai_tutor/data/knowledge_manifest_test.dart`
  a hiányzó schema/codec/builder fájlok miatt várt compile hibával állt meg.
- ZÖLD: ugyanez a célzott tesztcsomag — **12 teszt passed**. A tesztek a négy
  külön manifest-hibakódot, approved-only filtert, en+hu coverage-et,
  reprodukálhatóságot, document- és chunk-hash manifest-lockot fedik.
- ZÖLD: `dart analyze lib/features/ai_tutor/data/knowledge/knowledge_document.dart lib/features/ai_tutor/data/knowledge/knowledge_codec.dart tool/build_tutor_knowledge_manifest.dart test/features/ai_tutor/data/knowledge_codec_test.dart test/features/ai_tutor/data/knowledge_manifest_test.dart`
  — `No issues found!`
- A review mutációs próba a `rhythm-counting-en` státuszát ideiglenesen
  `reviewNeeded`-re állította; a committed-manifest lock teszt RED lett, majd
  visszaállítás és manifest-újragenerálás után a 12 teszt ismét zöld.
- PIROS (scope-on kívüli környezeti előfeltétel):
  `tools/round-gate.sh test/features/ai_tutor/data` — format zöld
  (`913 files, 0 changed`), analyze piros (`752 issues`), első hiba:
  `lib/l10n/app_localizations.dart` nem létezik. A generált localization fájl
  nincs az allowed pathson, ezért a gate nem jutott test/architecture lépésig.
  `stopped` kör-jelzés elküldve; nem módosítottam listán kívüli fájlt.

### Nem futtatott ellenőrzések

- CI full suite, property gate és APK: orchestrátor-felelősség, és a lokális
  round gate piros analyze előfeltétele miatt nem indítható érvényes CI-evidencia.
- A round-gate test/architecture lépése: az analyze előfeltétel piros volta
  miatt nem indult el.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r06-knowledge-schema-and-content-pack-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
