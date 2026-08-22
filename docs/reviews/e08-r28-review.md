# E08-R28 — Review

Brief: `docs/rounds/e08-r28-ledger-sync-contract-and-merge.md`
Diff: `git diff f055e97e..af7f2264` (pre-flight commit → implementer HEAD)
Reviewer: Claude Sonnet 5 (`--effort high`) · Dátum: 2026-08-22
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 2 · NOTE: 3

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Kétszeri szinkron után az összes XP változatlan | ✅ | `ledger_merge_policy_test.dart` A1 group, mind zöld; **valódi-sértés próba a `LedgerMergePolicy.merge` ELLEN saját kézzel megismételve** (a `_collapseGroup`-lépés eltávolítása → 18 pass/2 fail, pontosan az implementer állítása szerint; visszaállítva → 20/20 zöld) |
| A2 | A szerver elutasítja a kliens összesített XP-jét | ✅ | `backend/tests/test_gamification_ledger.py::test_a2_*` (3 teszt); saját kézzel megismételve pydantic `extra="forbid"` mindkét szinten (receipt + envelope) ELUTASÍTJA a `totalXp`/`profile_total_xp` mezőt |
| A3 | Unió-alapú összefésülés, egyik oldal bejegyzése sem vész el | ✅ | `ledger_merge_policy_test.dart` A3 group + §6.1 mátrix |
| A4 | `unverified`/`verified` megkülönböztethető és auditálható | ✅ | `ledger_merge_policy_test.dart` A4 group — a kliens nem tudja saját magát `verified`-re állítani (kódolt és validált is) |
| A5 | Kikapcsolt szinkron esetén nulla hálózati kérés | ✅ (a kör scope-ján belül — lásd F2) | `ledger_merge_policy_test.dart` A5 group, `_CountingTransport` a SAJÁT sync-transportot méri (L140 megfelelően alkalmazva, nem örökölt probe) |
| A6 | Eltérő policy-verzió megőrzött; superseding explicit hivatkozással | ✅ | `ledger_merge_policy_test.dart` A6 group |
| A7 | Verziózott szerződés; ismeretlen verzió hibát ad | ✅ | Dart: `A7 — versioned contract` group; backend: `test_a7_*` (2 teszt) |
| A8 | Teljes lokális offline működés a szinkron nélkül | ✅ | `ledger_merge_policy_test.dart` A8 group |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e08-r28 --brief docs/rounds/e08-r28-ledger-sync-contract-and-merge.md --base f055e97e4d3e6eb9ec5c7f21db36469a8726a168` → **OK** (8 changed path(s), 0 generated/ignored). A diff pontosan a §4 hét fájlját + a brief saját §10 kitöltését érinti. Engedélyezett fájlokon kívüli változás: **nincs**.

## Megállapítások

### F1 — MAJOR — a Dart-kódoló és a backend-dekódoló NEM interoperábilis wire-alakot termel

- **Fájl:** `lib/features/gamification/data/sync/gamification_sync_contract.dart:58-76` (`_SyncReceiptCodec.toUploadJson`/`envelopeUpload`) vs. `backend/app/gamification/schemas.py:38-82` (`ReceiptUpload`, `LedgerUploadEnvelope`)
- **Probléma:** a Dart `encodeUpload()` minden nyugtát `{'schemaVersion': <envelope-verzió>, 'receipt': {...nyugta mezők, 'status': 'unverified'}}` alakban ágyaz be a `receipts` tömb elemeként — egy PLUSZ `schemaVersion` kulccsal és egy beágyazott `receipt` objektummal. A backend `LedgerUploadEnvelope.receipts` viszont egy LAPOS `ReceiptUpload` lista mezőt vár (`ledgerId`, `sourceEventId`, … közvetlenül a tömb-elem gyökerén, `status` mező NÉLKÜL, `receipt` kulcs NÉLKÜL). **Önállóan lefuttatva** (`LedgerUploadEnvelope.model_validate(<a Dart encodeUpload() pontos kimenete>)`, pydantic 2.13.4): 8 validációs hiba — mind a hét nyugta-mező „Field required", plusz a `receipt` kulcs „Extra inputs are not permitted".
- **Hatás:** ha egy jövőbeli kör a `GamificationSyncContract.encodeUpload()` kimenetét ténylegesen elküldi a `backend/app/gamification/`-nak (amit ez a kör KIFEJEZETTEN elő is készít erre — ADR 0394 „a HTTP-végpont bekötése egy jövőbeli kör dolga"), az MINDEN egyes feltöltés 422-t kap. A kör saját címe „szerződés" — a két oldal ma nem ugyanazt a szerződést beszéli, holott mindkettő EBBEN a körben készült.
- **Miért nem BLOCKER:** a kör explicit NEM köti be a HTTP-réteget (§3 scope, ADR 0394 „Következmények"), és egyik acceptance-cella sem ír elő explicit végpontok-közötti round-trip tesztet — a hiba tehát nem sért egyetlen írott A1–A8 kritériumot sem. De a hűségi mérce (a review nem csak a leírt cellákat nézi) ezt a kör SAJÁT deklarált céljának ("Cél: ... szinkron-szerződés") a megsértéseként kezeli — egy kontraktus, aminek két fele nem egyezik, nem szerződés.
- **Kötelező javítás:** válassz EGY közös wire-alakot, és igazítsd mindkét oldalt hozzá (a legkisebb diff: hagyd el a Dart-oldali extra `schemaVersion`+`receipt` beágyazást — az `envelopeUpload` már hordozza az envelope-szintű `schemaVersion`-t, a per-nyugta `status`-t pedig vagy vedd fel a backend `ReceiptUpload`-ba KLIENS-oldali kényszerített `unverified` értékkel + szerver-oldali eldobással, vagy — egyszerűbb — ne is küldd a wire-en, mert a backend úgyis mindig `unverified`-ként kezel minden feltöltést). Adj hozzá EGY tesztet MINDKÉT oldalon, ami a TÉNYLEGES `encodeUpload()`-nak megfelelő JSON-alakot próbálja dekódolni a backend oldalán (akár csak egy kézzel átírt JSON-fixture, ami a Dart oldal ismert kimenetét tükrözi) — ez lenne a hiányzó „viselkedésváltozásra vonatkozó teszt", ami ezt a hibaosztályt jövőre nézve megfogná.
- **Ellenőrzés:** a fenti fixture-teszt zöld mindkét oldalon; a `tools/round-gate.sh` + `pytest` újra lefut.
- **Státusz:** OPEN

### F2 — MINOR — nincs felső korlát a nyugta-mezők méretén és a nyugta-lista hosszán (látens DoS, be nem drótozott útvonalon)

- **Fájl:** `backend/app/gamification/schemas.py:50-51` (`ledgerId`, `sourceEventId` — csak `min_length=1`, nincs `max_length`), `schemas.py:72` (`receipts: List[ReceiptUpload]` — nincs `max_length`)
- **Probléma:** saját kézzel igazolva (pydantic 2.13.4): egy 1 000 000 karakteres `ledgerId` és egy 100 000 elemű `receipts` lista is elfogadásra kerül.
- **Hatás:** ha a router-kör ezt élesben bedrótozza, egyetlen kérés korlátlan memóriát/CPU-t követelhet — a projekt máshol (pl. a nyugta-lista lapozásánál, `RewardLedgerPage`) következetesen korlátoz, itt nem.
- **Kötelező javítás:** adj `max_length` korlátot a két id-mezőre (pl. 256) és a `receipts` listára (pl. 500) a `schemas.py`-ban.
- **Ellenőrzés:** egy célzott teszt, ami a korlát fölötti bemenetet 422-vel utasítja el.
- **Státusz:** OPEN

## Nem blokkoló (NOTE)

- **N1 — a `verified` ma kizárólag séma-érvényességet jelent, nem policy-újraszámolást.** A `service.py` minden séma-érvényes nyugtát `verified=True`-val materializál (`evaluate_upload`, `_materialise`) — nincs felső korlát a `baseXp`/`bonusXp`-n, és a szerver nem vezeti vissza az XP-t a forrás-eseményből. Az ADR 0394 §5.3 „a szerver a saját policyja szerint validálja" megfogalmazása ezt túlígéri — a mai állapot helyesen „séma-validált", nem „policy-validált". Ez nem sérti egyetlen A1–A8 cellát sem (nincs élő fogyasztó, ami a `verified`-et bizalmi jelzésként olvasná), de a KÖVETKEZŐ, router-kötő körnek explicit gátat kell szabnia: `verified` csak akkor jelenjen meg bizalmi jelzésként egy felületen, ha a szerver ténylegesen újraszámolta az XP-t a forrás-eseményből. Javasolt: az ADR/doc-comment szövegét pontosítani „séma-validált"-ra, amíg ez nincs kész.
- **N2 — `shouldRun`/transport csak doc-commenttel kötve.** Semmi strukturális nem akadályozza meg, hogy egy jövőbeli hívó közvetlenül az `uploadAndPull`-t hívja a `shouldRun` ellenőrzése nélkül — az A5 teszt csak a fegyelmezett hívó útvonalát méri. A jövőbeli router-körnek a gate-et magába a transport-előállításba kellene húznia (pl. a transport provider adjon `NullLedgerSyncTransport`-ot kikapcsolt fiók esetén), nem a hívóra bízni.
- **N3 — `contract.dart:60` holt kifejezés.** `json.remove('totalXp') == null;` — a `.remove()` ténylegesen lefut (ellenőrizve: a `totalXp` hiányzik a végső payloadból), de az `== null` eredménye eldobódik. Stílushiba, nem funkcionális hiba — cseréld `json.remove('totalXp');`-re.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (saját `/tmp/review-e08-r28` klónban megismételve) |
| analyze | zöld | ✅ |
| `ledger_merge_policy_test.dart` | 20/20 zöld | ✅ + saját valódi-sértés próba (18/20 a mutált policy-n, 20/20 visszaállítva) |
| architecture | zöld (12 allowlisted deviation, változatlan) | ✅ |
| secrets | zöld (3246 fájl, 0 lelet) | ✅ |
| l10n | zöld | ✅ |
| backend ruff format/check | zöld | ✅ |
| backend pytest (teljes suite, 166 teszt) | zöld | ✅ |
| `backend/tests/test_gamification_ledger.py` (külön parancs) | 9/9 zöld | ✅ |
| CI — Full Gate (kör-branch) | success | ✅ [run 32562743220](https://github.com/wolfcasaba/strumsight/actions/runs/32562743220), headSha `af7f2264` |
| CI — Router CI (kör-branch) | success | ✅ [run 32562733217](https://github.com/wolfcasaba/strumsight/actions/runs/32562733217), headSha `af7f2264` |
| Biztonsági review (risk=high, `security-reviewer`) | PASS, 0 CRITICAL/BLOCKER, 1 MAJOR (látens, nem blokkoló — lásd N1), 2 MINOR | `docs/reviews/e08-r28-security.md` |
| `gate_shape` jelző | `VIOLATION` a `.codex-round-status`-ban | **Hamis pozitív, kivizsgálva**: a naplóban két `cat tools/round-gate.sh ... \| head -60` hívás (a script FORRÁSÁNAK olvasása, nem egy gate-futtatás csonkítása) illesztette a mintát; a négy tényleges `tools/round-gate.sh ...` hívás mind csonkítatlan (`2>&1`, se `\|`, se `&&`). Ugyanaz az ismert osztály, mint az E08-R03 review NOTE-ja (L340). |

## Merge-döntés

**Merge TILOS**, amíg az F1 (MAJOR) nyitva van (ADR 0052). A javító kör ugyanazzal a motorral (`minimax`) megy, az F1+F2 leletlistával — a lánc normál útja, nem halt-ok (user-döntés 2026-07-31).
