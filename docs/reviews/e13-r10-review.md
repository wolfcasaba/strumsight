# E13-R10 — Kör-review (Aszinkron állapotkomponensek)

- **Kör:** `E13-R10` · **Branch:** `sonnet-impl/e13-r10-async-state-components`
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`), commit `0f338e77` + `138621d4`
- **Reviewer:** Claude Opus 5 (orchestrátor), READ-ONLY — production kódot nem írtam
- **Review-alap:** `de1167c6..138621d4` (a pre-flight commit óta)
- **Verdikt:** **CHANGES REQUESTED** — 1 MAJOR nyitva

---

## 1. Jelzés és handoff

`.codex-round-status`: `implementer_status=done`, `head=138621d4`,
`gate_shape=ok`. A wrapper `status=stopped`-ra váltott
`scope_audit=VIOLATION`-nel, **egyetlen** sértéssel:
`path outside allowed scope: .pipeline-prompt-e13-r10.md`.

**Ez NEM az implementer diffje**, hanem az orchestrátor (én) által a
munkapéldány gyökerébe írt prompt-fájl — untracked, egyetlen commitban sem
szerepel. Kimozgattam a repóból, és a hiteles eszközzel újramértem:

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r10 \
    --brief docs/rounds/e13-r10-async-state-components.md --base de1167c6…
Legacy scope audit OK (de1167c65ad2..138621d4a356, 15 changed path(s), 0 generated/ignored)
```

A 15 módosult útvonal mind a brief `allowed_paths` listáján van. **Scope: OK.**
A `dirty_files=2` ugyanennek a fájlnak (+ a jelzésfájlnak) a számlálója volt.

A brief §10 handoffja **őszinte**: a katalógus-demó szűkítését, az `Expanded`
korlátot és a valódi-sértés próbát is dokumentálja, mérésekkel.

## 2. Gate — SAJÁT kézzel újrafuttatva

Izolált klón (`/tmp/review-e13-r10`, `138621d4`), csonkítatlan kimenet:

```
format                     zöld     analyze                    zöld
test failure_presentation  zöld (12/12)   test async_state     zöld (9/9)
architecture               zöld (12 allowlisted deviation)
secrets                    zöld (3558 fájl, 0 lelet)
l10n                       zöld — aggregate freshness OK (en, hu), parity 1811 üzenet
MINDEN GATE ZÖLD
```

Az `l10n` lépés zöldje igazolja a §0.0/D3 útvonalat: a fragmentum a forrás, az
aggregátum regenerálva, a paritás megvan.

## 3. Acceptance criteria — tételesen

| # | Kritérium | Verdikt | Bizonyíték |
|---|---|---|---|
| A1 | Nyers kivétel/`toString()` sehol | ✅ | `failure_presentation_test.dart` „A1" csoport: ismeretlen kódra a modell nem tartalmazza a kódot, `Exception`-t, `#0 `-t, `retryable:`-t, és ≠ `failure.toString()`. A §5.1 cella külön bizonyítja, hogy `cause`+`stackTrace` jelenléte NEM változtat a kimeneten (a `secret-path` szivárgás mérve nem jelenik meg). |
| A2 | Offline nem hiba-stílus, cached tartalom marad | ✅ | `async_state_test.dart`: a banner `dy`-ja kisebb a content `dy`-jánál (tehát fölötte van, nem helyette), és `find.byType(SsFailureState) findsNothing`. `syncPending`/`degraded` szintén mountolva tartja. |
| A3 | Retry csak újrapróbálható hibánál | ✅ | Két irányban mérve (`retryable:false` × 4 típus → nincs retry; `retryable:true` × 4 → van). **A döntő cella:** azonos `code`, ellentétes `retryable` → ellentétes retry-döntés — ez a kód-only implementációt megöli. |
| A4 | Véglegesen megtagadott engedély → beállítás-akció | ✅ | `MicrophonePermissionState.permanentlyDenied.failure!` valódi bemenetből: `retry` nincs, `openSettings` van. |
| A5 | Üres állapot értelmes akciót kínál | ✅ | `SsEmptyState.onAction` **nem nullable** (típusszintű garancia) + tap-teszt. |
| A6 | Skeleton nem olvasható, tartja a geometriát | ✅ | Pontos `Size(120,40)`; `ExcludeSemantics` (a külső probe-címke marad az egyetlen); a loading-régió EGYSZER hangzik el. |
| A7 | Minden új szöveg ARB-n át (en+hu) | ✅ | A §6.2 gépi őre teljesül: ugyanaz a failure `hu` ≠ `en`, és a `hu` érték a fragmentum kipinnelt stringje. Az akció-label is mérve. |
| A8 | Minden állapot mindhárom témában renderel | ✅ | 9 státusz × 3 téma, `takeException()` null. |

**Mérce-mátrix (§6.1):** a valódi-sértés próbát az implementer elvégezte és
dokumentálta (`message: failure.toString()` → 4 teszt piros, köztük az A1 és az
A7; visszaállítva, 12/12 zöld). A mutáció tényleg a mércét mozgatja.

## 4. Leletek

### F1 — MAJOR · `ss_permission_state.dart:82-87`

**`SsPermissionState` egy elérhető úton olyan gombot rendel, ami tartósan
letiltott, és amit a hívó NEM tud bekötni.**

Mérve (eldobható próbateszt, lefuttatva és törölve — §6):

```
P0 ✅ MicrophonePermissionState.unavailable.failure!
      → PermissionFailure(code: 'permission.unavailable', retryable: false)
      → a mapping actions = [contactSupport]        (elérhető, valós bemenet)
P1 ✅ SsPermissionState ezzel a presentationnel kirendeli a
      'ss-permission-state-contactSupport' gombot, és annak onPressed == null
```

A `_iconByKind` alatti `onPressed` switch a `continueOffline` és a
`contactSupport` ágra **beégetett `null`**-t ad, és a widgetnek **nincs**
`onContactSupport` / `onContinueOffline` paramétere — tehát a hívó nem is
tudná bekötni. Az eredmény egy látható, örökre halott vezérlő.

Ez a kör SAJÁT kötött döntéseivel ütközik: ADR 0277 §5.3 („a retry gomb hamis
reményt kelt — helyette a valódi kiút látszik") és §5.5 („minden üres
állapotnak van következő lépése"), valamint a `SsFailurePresentation`
doc-commentjének ígéretével: „[actions] is never empty: every failure resolves
to at least one next step". A `permission.unavailable` ágon a „next step"
ki van rajzolva, de nem létezik.

**Miért nem fogta meg egyetlen cella sem:** az A3/A4 a *prezentációs modellt*
méri (`hasAction`), soha nem a kirendelt gomb `onPressed`-jét.

**Javasolt irány (nem kész patch):** vagy ne épüljön gomb olyan
akció-fajtára, amit a komponens nem tud bekötni, vagy kapja meg a hiányzó
callback-paramétereket. A javításhoz tartozzon egy cella, amely kimondja:
egyetlen kirendelt akciógomb `onPressed`-je sem `null` — ez F1-et és F2-t
egyszerre fogja pirosra.

### F2 — MINOR · `ss_failure_state.dart:62,73-78`

**Ugyanaz az osztály `SsFailureState`-ben, enyhébb formában:** ha a mapping
előállít egy akciót, de a hívó nem ad hozzá callbacket, letiltott gomb
jelenik meg. Mérve:

```
P2 ✅ SsFailureState(presentation: <permanentlyDenied>)  // callback nélkül
      → 'ss-failure-state-openSettings' gomb, onPressed == null
```

A doc-comment („no [SsFailureActionKind.retry] entry means no retry button is
built at all") szó szerint igaz, de a §10 handoff erősebbet állít: „egy
hiányzó akció = nincs gomb (nem `onPressed: null`-lal letiltott gomb)" — ez
csak a hiányzó *akcióra* áll, a hiányzó *callbackre* nem. Itt a hívó
tudja orvosolni, ezért MINOR, nem MAJOR.

### F3 — MINOR · `ss_async_state.dart:110-118`

**Az `offline`/`syncPending`/`degraded` ág kötött magasságú szülőt kíván, és
ez nincs dokumentálva a publikus API-n.** A `_CachedContentBanner` `Expanded`-et
használ; korlátlan magasságú szülőben ez dob. Mérve:

```
P3 ✅ SingleChildScrollView(child: SsAsyncState(status: offline, …))
      → tester.takeException() != null
```

Az implementer maga is beleütközött (a katalógusban `SizedBox(height: 120)`-szal
kerülte meg, §10-ben dokumentálva), de a `SsAsyncState` osztály-doksijába nem
került bele. A migrációs körök (a `lib/features/**` átállítása) pontosan ezt
fogják eltalálni. **Javasolt irány:** a korlát kimondása az osztály
doc-commentjében, VAGY `Flexible`/`mainAxisSize: MainAxisSize.min`, ha a
komponens scrollolható környezetben is használható kell legyen.

### N1 — NOTE · `failure_presentation.dart:53`

`SsFailurePresentation.actions` publikus, **módosítható** `List`. A
doc-comment nem állít unmodifiable-t, tehát nincs bizonyítatlan állítás — de
egy `List.unmodifiable` / `UnmodifiableListView` olcsón zárná. Nem blokkol.

### N2 — NOTE · katalógus-szűkítés

Az `SsSkeleton` katalógus-demója kimaradt, mert a **nem módosítható**
`component_catalog_test.dart` `findsOneWidget`-et vár `DecoratedBox`-ra. Az
implementer helyesen a STOP-protokoll szerint járt el (meglévő zöld tesztet
nem írt át, és a fájl nincs az `allowed_paths`-on), és dokumentálta. Az A6-ot
ez nem érinti (bizonyítéka az `async_state_test.dart`). Nem blokkol.

## 5. Architektúra és biztonság

- **Rétegek:** a `design_system` fa nem importál `lib/features/**`-ot és nem hív
  plugint; a `SsPermissionState` kizárólag rendel és hívó-oldali callbacket hív
  (a `permission_handler` felé nincs él). `architecture` gate zöld.
- **Adatszivárgás:** a `cause`/`stackTrace` a mapping-be be sem lép (`from` csak
  `.code`-ot és `.retryable`-t olvas), és ezt teszt méri egy szándékosan
  „szivárgó" `cause`-szal. `secrets` gate zöld (0 lelet). A kör `risk = "high"`
  besorolása a permission-prezentáció és a szivárgási felület miatt indokolt
  volt; a mért felületen szivárgást nem találtam.
- **Erőforrás-életciklus:** a kör nem szerez erőforrást (nincs stream,
  subscription, controller) — nincs felszabadítási útvonal, amit vizsgálni kellene.

## 6. Próbatesztek

`test/core/design_system/feedback/zz_reviewer_probe_test.dart` (eldobható,
izolált `/tmp/review-e13-r10` klónban): P0–P3, **mind a négy átment**, azaz
mind a négy állítás IGAZ. A fájl a gate futtatása előtt **törölve**
(`git status --porcelain` üres), a kör diffjébe nem került bele.

## 7. Merge-döntés

| Osztály | Darab | Merge-hatás |
|---|---|---|
| BLOCKER | 0 | — |
| **MAJOR** | **1** (F1) | **merge TILOS, amíg nyitva** |
| MINOR | 2 (F2, F3) | a javító körben olcsón zárható (F2 ugyanaz az őr, mint F1) |
| NOTE | 2 (N1, N2) | nem blokkol |

**CHANGES REQUESTED.** A javító kör a lánc normál útja (ADR 0087 §2,
user-döntés 2026-07-31): ugyanaz a motor kapja meg az F1–F3 listát.
