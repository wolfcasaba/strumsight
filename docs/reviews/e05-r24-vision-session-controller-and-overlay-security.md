# E05-R24 — Biztonsági / adatvédelmi / prompt-injection review

**Brief:** `docs/rounds/e05-r24-vision-session-controller-and-overlay.md`
**Diff vizsgálva:** `ffef5d7` (`codex/e05-r24-vision-session-controller-and-overlay`) vs `origin/main`
**Reviewer:** Claude (security-reviewer agent, READ-ONLY, izolált `/tmp` klón)
**Dátum:** 2026-08-08
**Verdikt (az eredeti diffre, `ffef5d7`): CHANGES REQUESTED — 1 BLOCKER**

> Ezt a jelentést az orchestrátor (Claude Sonnet 5) rögzíti a security-reviewer
> ágens teljes, ellenőrzött kimenete alapján — az ágens a saját futásában nem
> tudta a fájlt a megosztott fába írni, a talált szöveges jelentést adta
> vissza. A talált konkrét fájl:sor hivatkozásokat az orchestrátor a saját,
> független kódolvasásával egyeztette és megerősítette valósnak. Lásd a
> záró **Utólagos állapot** szakaszt a javítás(ok) utáni verdiktért.

## Összegzés

**BLOCKER: 1 · MAJOR: 0 · MINOR: 0 · NOTE: 2**

A round adatvédelmi felülete alapvetően jól épített: nincs frame/pixel a
state-ben vagy a result-ban, nincs új hálózati hívás, a cue-t a UI nem
választja/rangsorolja, a route helyesen a `visionEnabled` (default `false`)
flag mögött van, és a logokba csak enum + leaseId + timestamp kerül.
**Egyetlen, de merge-tiltó hiba volt az eredeti diffben:** a kör
kulcs-acceptance kritériumát (§6 kilépési-út mátrix, §5.4 „minden kilépési
út zár") megsértette egy reprodukált erőforrás-szivárgás a kamera-bemelegítési
(`capture.start()`) ablakban — a kamera bekapcsolva maradt, miután a
felhasználó elhagyta a képernyőt / háttérbe tette az appot, és utána a Stop
néma no-op volt. Ez ugyanaz a gyökér-ok, mint a független (nem-biztonsági)
review F1 BLOCKER lelete — a két review egymástól függetlenül, más
próba-módszerrel jutott ugyanarra a hibaosztályra.

## Acceptance criteria

| # | Kritérium | Teljesült (eredeti `ffef5d7`) | Bizonyíték |
|---|---|---|---|
| 1 | Állapotgép-mátrix, kontrollált érvénytelen átmenetek | ✅ | `vision_session_controller_test.dart` 10/10 PASS (lefuttatva); `_allows()` → `VisionSessionIssue.invalidTransition`, nem crash/no-op |
| 2 | **Kilépési-út mátrix (kulcsbizonyíték): mind az 5 út zár, nincs dispose utáni state-írás, pontosan 1 eredmény** | ❌ | A `dispose` és `app-háttér` út a `capture.start()` bemelegítés alatt NEM zár: `activeOwner=visionPractice, capture.isClosed=false, closeCalls=0, results=0` (reprodukálva) |
| 3 | Dupla-finalizáció → egy eredmény | ✅ | `stop`+`leaveRoute` egyszerre → 1 eredmény; a `_finalization` future-cache dedupál |
| 4 | Provider-state audit: fix kulcshalmaz, nincs frame/pixel mező | ✅ | `vision_session_state.dart:101-111` `auditFields`; grep 0 `CameraFrame/Uint8List/pixel/bytes` |
| 5 | Cue-teszt: pontosan az R23 cue, UI nem duplikál | ✅ | `reportRealtimeCue` as-is tárol; overlay az egy `state.realtimeCue`-t rajzolja |
| 6 | Golden overlay portrait/landscape, nincs widget-oldali korrekció | ✅ (nem futtatva pixelszinten) | R07 `PreviewFit`→`CameraTransform`; golden opt-in (host-policy) |
| 7 | Lokalizációs paritás; route `visionEnabled` guard mögött | ✅ | route csak `visionEnabled` alatt; routing teszt mindkét ág PASS |
| 8 | Valódi-sértés próba (§10) | ⚠ részleges | Az implementer próbája csak a *dupla*-finalizáció őrét feszítette; a bemelegítési-ablak erőforrás-felszabadítást nem fedte |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** A 17 módosított útvonal
mind a brief `allowed_paths` listáján van. Nincs új dependency, nincs új
asset, nincs `pubspec.yaml` érintés.

## Megállapítások (eredeti diff, `ffef5d7`)

### F1 — BLOCKER — Kamera-lease + capture szivárgás a `capture.start()` bemelegítési ablakban; utána a Stop néma no-op

- **Fájl:** `lib/features/vision/application/vision_session_controller.dart:351-359`
  (`_finalizeOnce` korai `return` a `_closeCapture` előtt), gyökér-ok `:159`
  (`_session` csak az `await capture.start()` UTÁN jött létre) + `:151-152`
  (a második `if (_disposed) return;` nem takarított, szemben az elsővel
  `:133-139`) + `:343-349` (`_finalize` a „kiürült" future-t cache-elte).
- **Probléma:** a `_finalizeOnce` első érdemi lépése `if (session == null)
  return null;` volt — de a `_session` csak a `start()` VÉGÉN jött létre. Az
  egész `coordinator.acquire()` + `capture.start()` async ablak alatt
  `_session` null volt. Ha ebben az ablakban indult finalizáció (`dispose`,
  `app-háttér` az `onRevoke`-on át, stream-hiba), a `_finalizeOnce` a
  `_closeCapture` hívása ELŐTT tért vissza — és ezt a „kiürült" eredményt a
  `_finalization` cache véglegesen eltárolta, így minden KÉSŐBBI finalizációs
  kísérlet is néma no-op maradt ugyanarra a sessionre.
- **Hatás:** a fizikai kamera bekapcsolva maradt a bemelegítés alatti
  kilépés után; az exkluzív lease bennragadt (más owner nem szerezhette meg a
  kamerát); a felhasználó semmilyen művelettel nem tudta utólag leállítani.
- **Reprodukció (a security-reviewer ágens saját mérése, izolált klónban):**
  ```
  REPRO  (dispose a start() alatt):            activeOwner=visionPractice  capture.isClosed=false  closeCalls=0  results=0
  REPRO2 (háttér a start() alatt, majd Stop):   status=running  stopResult=null  capture.isClosed=false  closeCalls=0  results=0
  CONTROL (dispose a running UTÁN):             activeOwner=null  capture.isClosed=true  results=1  → PASS
  ```
  A CONTROL igazolja, hogy a hiba kizárólag a bemelegítési ablakra
  jellemző — a round saját exit-mátrix tesztje (mindig `running`-ig hajtva)
  ezt nem fedte, ezért volt 10/10 zöld a hiba mellett.
- **Sértett szabályok:** AGENTS.md §5 (kamera egy owner, nem maradhat aktív
  owner nélkül), brief §5.3 (pontosan egyszeri finalizáció), §5.4 (minden
  kilépési út zár), §6 kilépési-út mátrix.
- **Státusz:** lásd **Utólagos állapot**.

### NOTE 1 — `_resultListener` nem `_disposed`-őrzött

`_resultListener(result)` (eredeti :371) a `_setState`-őrrel ellentétben nem
volt védve `if (!_disposed)`-dal. A state-írás helyesen védett volt, tehát
dispose utáni state-írás nem történt — de a végeredmény-kézbesítés
disszkor szándékos is lehet. A composition-root fogyasztónak (R25+
bekötéskor) kezelnie kell a disposed-célra érkező emissziót. Nem blokkol.

### NOTE 2 — Prompt-injection felület: N/A ebben a körben

Nincs AI-provider hívás. A cue-szöveg zárt `InsightCode` enum → ARB switch,
tehát külső (kamera-eredetű vagy szabad szöveges) tartalom nem
értelmeződhet utasításként. Amikor R25–R27 valós insight-forrást vagy
provider-választ köt be, ez a határ újra-ellenőrzendő.

## Ami rendben volt (tételes bizonyítékkal, eredeti diff)

- **Nyers frame/pixel nincs a state-ben/result-ban (§5.1):** grep
  `CameraFrame|Uint8List|pixel|bytes|copyBytes` a state/result fájlokon → 0
  találat; `_onFrame` eldobja a frame-et, csak számlálót léptet.
- **Kamera-exkluzivitás egy úton (§5.2):** egyetlen `coordinator.acquire`
  hívás; check-and-take az első await előtt; `release()` idempotens; a
  revoke-on belüli owner-release helyesen a `finally`-ba halasztva.
- **Gyenge confidence nem lesz biztos állítás (§5.6):** a UI nem
  szűr/rangsorol/felülbírál; az egy cue-t az R23 `CueBudget` adja.
- **Nincs rejtett hálózat / új dependency / új permission.**
- **Titok/log:** csak enum + leaseId + timestamp; nincs frame/személyes adat.
- **Route-guard:** `visionSession` route csak `visionEnabled` alatt
  regisztrált, default `false`.

## Utólagos állapot — javító körök

**Javító kör #1 (`3060cef`):** a `start()` async ablakát egy
`_startSettled`-completer véd, a `_finalize()` ezt bevárja mielőtt
`_finalizeOnce`-ot hívná; a `_session` a lease-megszerzés UTÁN azonnal
létrejön (nem a capture-start után). **Saját, önálló próbateszttel
megerősítve** (a security-reviewer eredeti REPRO2-forgatókönyvét
megismételve): az app-háttér-a-bemelegítés-alatt eset **helyesen zár**
(`activeOwner=null, captureClosed=true, closeCalls=1, results=1`), és az
utólagos Stop a cache-elt eredményt adja vissza (nem null, nem új
eredmény) — **F1 az app-háttér és a stop/leaveRoute útra ZÁRVA.**

**Új regresszió a #1 javító körben, saját próbateszttel talált:** a
`dispose` (Riverpod `container.dispose()`/autoDispose) a bemelegítési
ablakban **kivétellel elszállt** (`Cannot use the Ref of NotifierProvider...
after it has been disposed`, `vision_session_controller.dart:187`, a
`_startOnce`-ban maradt `state.copyWith(...)` hívás, ami a korábbi
`if (_disposed) return;` őrök eltávolítása után futásidőben olvasta a már
disposed `state` gettert).

**Javító kör #2 (`51572a5`):** `ref.mounted` őr került minden `await` UTÁN,
MIELŐTT `state`-et érintő kód futna (`acquire` mindkét ága, `capture.start()`
után, annak Failure-ága után, és a hívási oldalon is). **Saját, önálló
próbateszttel megerősítve** (VALÓDI `container.dispose()`-zal, nem csak
`leaveRoute()`-tal, a bemelegítési ablakban): **nincs kivétel**,
`activeOwner=null`, `captureClosed=true`, `closeCalls=1`, `results.length==1`,
`endReason=disposed`. Ugyanabban a próbafutásban újra megerősítve az
app-háttér és a stop/leaveRoute utak is (mind PASS).

**Végállapot (`51572a5`): F1 + a #1 javító kör saját regressziója egyaránt
ZÁRVA — 0 nyitott BLOCKER.** A nem-biztonsági review
(`e05-r24-vision-session-controller-and-overlay-review.md`) tartalmazza a
teljes F1–F4 tételes lezárási bizonyítékot; ez a jelentés csak a biztonsági
szempontú keresztellenőrzést rögzíti.
