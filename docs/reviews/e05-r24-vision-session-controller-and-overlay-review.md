# E05-R24 — Review

Brief: `docs/rounds/e05-r24-vision-session-controller-and-overlay.md`
Diff: `git diff b14a753...ffef5d7` (pre-flight commit `c44f019` + implementer commit `ffef5d7`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-08
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 1 · MAJOR: 1 · MINOR: 1 · NOTE: 0

Gate (format, analyze, `test/features/vision`, `test/core/camera`,
`test/core/l10n_parity_test.dart`, architecture, secrets, l10n) mind **ZÖLD**,
saját kézzel, izolált `/tmp/review-e05-r24` klónban újrafuttatva. A zöld gate
azonban — a review-protokoll alapelve szerint — nem bizonyíték a tartalmi
hűségre: az F1 BLOCKER egy konkrét, eldobható próbateszttel reprodukált,
gate-en NEM átment hiba (a meglévő suite nem fedi ezt az időzítési ablakot).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Állapotgép-mátrix, minden érvénytelen átmenet cellánként assert | ❌ | `vision_session_controller_test.dart` csak EGY invalid-transition cellát ellenőriz (117. sor: `beginCalibration()` `permissionDenied`-ből). Lásd F2. |
| 2 | Kilépési-út mátrix — mind az öt út után lease szabad, stream lezárva, nincs dispose utáni state-írás, pontosan egy eredmény | ⚠️ részleges | A commitolt `expectReleased` teszt (161-236. sor) mind az 5 utat lefedi a **happy-path** időzítésben (session már fut). Az async `start()` acquire-ablakában (calibrating állapotban, mielőtt a `_session` létrejön) UGYANEZEK az utak (stop/leaveRoute/dispose) **csendben nullát adnak vissza, eredmény és lease-felszabadítás nélkül** — lásd F1, saját próbateszttel reprodukálva. |
| 3 | Dupla-finalizáció teszt: Stop + azonnali route-leave → egy eredmény | ✅ | `vision_session_controller_test.dart:227-236`, `Future.wait([stop(), leaveRoute()])` → `results` hossza 1. |
| 4 | Provider-state audit: rögzített kulcshalmaz, nincs frame/pixel mező | ⚠️ részleges | A jelenlegi mezőkészlet ténylegesen frame-mentes (kézzel ellenőrizve: `vision_session_state.dart`, `vision_session_result.dart`). Az `auditFields` viszont egy kézzel karbantartott string-literál, nem a tényleges osztálymezőkből származtatott — lásd F3. |
| 5 | Cue-teszt: pontosan az R23 által adott egy cue, nincs UI-duplikálás | ✅ | `vision_preview_overlay_test.dart:63-74` (pontos cue-szöveg + egyetlen `vision-realtime-cue` widget); a típus (`VisionInsight?`, nem lista) szerkezetileg kizárja a duplikálást. |
| 6 | Golden overlay teszt portrait + landscape, R07 mapping, nincs widget-oldali korrekció | ✅ | `vision_preview_overlay_test.dart:82-110` (numerikus `mapLandmark` egzakt koordináta-teszt mindkét irányban) + 112-126 (golden fájlok, `GOLDENS=1` opt-in — ugyanaz a mintázat, mint a meglévő `test/features/live/chord_timeline_golden_test.dart`, NEM új kivétel). Terra §10 handoffja szerint `GOLDENS=1 flutter test --update-goldens` 5/5 PASS — nem reprodukáltam újra pixelszinten (host-függő), a mapping-egzaktságot igen. |
| 7 | Lokalizációs paritás zöld; route `visionEnabled` guard mögött | ✅ | `l10n` gate zöld; `vision_session_routing_test.dart` mindkét ágat teszteli (flag ON → route regisztrált, flag OFF → redirect Live-ra); `app_router.dart:244-249` ténylegesen csak `visionEnabled`-et néz, nem vezet be új per-feature flaget (a brief §0.0 R3 szerint szándékosan). |
| 8 | Valódi-sértés próba (§10): finalizáció egyszeresség-őr kiiktatása → dupla-finalizáció teszt PIROS → visszaállítás | ✅ (implementer-oldali, dokumentált) | Terra §10 handoffja szerint elvégezte és visszaállította; a mechanizmus (`_finalization` cache, `vision_session_controller.dart:343-349`) olvasva korrekt, és a #3 kritérium commitolt tesztje ma is zöld ugyanerre a védelemre. Nem ismételtem meg — a leírás konkrét és a kódolvasás megerősíti. |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. A gépi scope-audit
(`tools/round-scope-audit.sh`, a `codex-round.sh` futása után) `scope_audit=ok`,
`scope_audit_base=c44f019`, `scope_audit_changed=17` — mind a 17 megváltozott
fájl a (pre-flight §0.0 R4-ben bővített) `allowed_paths`-on belül van. Saját
kézzel is összevetve (`git diff --stat b14a753..ffef5d7`): 6 módosított +
11 új fájl, egyezik.

## Megállapítások

### F1 — BLOCKER — Stop/route-leave/dispose csendben elveszik a `start()` async acquire-ablakában

- **Fájl:** `lib/features/vision/application/vision_session_controller.dart:343-355` (a `_finalize`/`_finalizeOnce` pár), a hívási oldalak: `stop()` (237), `leaveRoute()` (240), `_dispose()` (406-409).
- **Probléma:** `stop()`, `leaveRoute()` és `_dispose()` szándékosan **ungated** (nem megy át `_allows()`-on), hogy MINDIG megbízhatóan működjenek, bármilyen állapotból. De mindhárom a `_finalize()` → `_finalizeOnce()` párost hívja, és `_finalizeOnce` **első sora** `if (session == null) return null;` (354-355. sor). A `_session` mező csak a `start()` metódus VÉGÉN, a `capture.start()` sikeres visszatérése UTÁN kap értéket (159. sor: `_session ??= VisionSession(...)`) — az egész `coordinator.acquire()` + `capture.start()` async ablak alatt (114-168. sor, `calibrating` állapotban) `_session` még `null`. Ha `stop()`/`leaveRoute()`/dispose (Riverpod `autoDispose`, pl. route-pop) EBBEN az ablakban fut le, a finalizáció **nullát ad vissza, a `_resultListener` sosem hívódik, és a state sosem vált `finalizing`/`completed`-re** — miközben a `start()` a maga async munkája végén ZAVARTALANUL folytatja, lízinget tart, és `running`-ra állítja a state-et, mintha a Stop/leave sosem történt volna meg.
- **Hatás:** a felhasználó Stop-ot nyom (vagy visszalép, vagy az app háttérbe kerül PONTOSAN ebben a — valós kamera-hardveren nem elhanyagolható — időablakban), és a kamera **némán tovább fut**: a lízing nem szabadul fel, a `VisionSessionResult` sosem keletkezik, a UI a felhasználó szándékával ellentétben `running` állapotba kerül. Ez közvetlenül megsérti a brief §5 pont 3 („A finalizáció pontosan egyszer emit-el eredményt… NEM elfogadható: 'általában egyszer' viselkedés" — itt NULLA alkalommal, ami ennél is rosszabb) és §5 pont 4 („Minden kilépési út zár… a lease felszabadul") kifejezetten „NEM elfogadható"-nak jelölt klauzuláit, valamint a kör saját „kulcsbizonyíték" (§6 #2) kritériumát.
- **Reprodukció (saját, eldobható próbateszt, review után törölve, NEM commitolva):**
  `FakeCameraCapture(startGate: <kontrollált Completer>)`-rel a rig-et úgy állítottam be, hogy a `start()` a `capture.start()`-nál blokkoljon; `begin()` + `beginCalibration()` után elindítottam a `start()`-ot (await NÉLKÜL), egy `Future<void>.delayed(Duration.zero)`-val hagytam, hogy elérje az await-et, majd **await-eltem a `stop()`-ot**, és csak utána oldottam fel a gate-et. Mért kimenet:
  ```
  stopResult=null finalStatus=VisionSessionStatus.running resultsCount=0 activeOwner=CameraOwner.visionPractice
  ```
  Azaz: a `stop()` hívás `null`-t adott vissza (nem `VisionSessionResult`-ot), a session végül mégis `running`-ba került, `results` listája üres maradt, és a kamera-lízing továbbra is a `visionPractice` ownernél van — pontosan az állítás szerint.
- **Kötelező javítás:** a `start()` async ablakát is védeni kell egy konkurens finalizáció-kéréssel szemben — pl. egy „start in-flight" jelző/`Completer` bevezetése, amit a `stop()`/`leaveRoute()`/dispose ellenőriz: ha `start()` folyamatban van, vagy (a) várja meg annak lezárását és utána azonnal finalizál a már beállt `_session`-nel, vagy (b) állítson be egy cancellation-jelzőt, amit a `start()` az await-ek után ellenőriz, és ha be van állítva, ne lépjen `running`-ba, hanem zárja le azonnal a frissen szerzett capture-t/lízinget és finalizáljon. A pontos megoldást az implementerre bízom; a tesztlefedettségnek tartalmaznia kell legalább egy, a fenti próbához hasonló, kontrollált-időzítésű esetet mind a `stop()`, mind a `leaveRoute()`, mind a dispose útra.
- **Ellenőrzés:** egy commitolt teszt, amely `FakeCameraCapture(startGate: ...)`-tel kontrolláltan nyitva tartja a `start()` async ablakát, és bizonyítja, hogy egy ezalatt érkező stop/leaveRoute/dispose UTÁN (a gate feloldása és a `start()` lezárása után) a session NEM `running`, a lízing szabad, és pontosan egy `VisionSessionResult` született.
- **Státusz:** OPEN

### F2 — MAJOR — Az állapotgép-mátrix „cellánként assert" kritériuma nincs teljesítve

- **Fájl:** `test/features/vision/application/vision_session_controller_test.dart`
- **Probléma:** a brief §6 első acceptance-cellája szó szerint „minden érvénytelen átmenet kontrollált… **cellánként assert**"-et kér. A commitolt suite ebből pontosan EGY cellát ellenőriz explicit módon (117. sor: `beginCalibration()` `permissionDenied`-állapotban → `issue == invalidTransition`). A `_allows()` mechanizmus maga megosztott és szerkezetileg helyesnek tűnik olvasva (minden gated metódus ugyanazt a mintát követi), de a brief saját, mérhető bizonyítási kötelezettsége (nem csak „a mechanizmus jó", hanem „minden cella bizonyítva") nincs teljesítve — ez pontosan az a hibaosztály, amit a review-protokoll explicit kiemel („a szövegesen előírt viselkedést el tudja rontani úgy, hogy minden teszt zöld marad").
- **Hatás:** egy jövőbeli, `_allows()`-t megkerülő vagy hibásan bővítő módosítás (pl. egy új action metódus, ami elfelejti meghívni `_allows()`-t) nem bukna el egyetlen célzott teszten sem — csak akkor derülne ki, ha épp az az egy tesztelt cella érintett.
- **Kötelező javítás:** egy táblázatos/parametrizált teszt, amely az ÖSSZES `(VisionSessionStatus, action)` párra, ahol az action nincs az adott állapotból engedélyezve, ellenőrzi hogy `issue == invalidTransition` lesz és a `status` NEM változik. Nem kell minden egyes párt kézzel felsorolni kódban, ha egy generatív/táblázatos szerkezet olvashatóbb, de a lefedettségnek ki kell terjednie mind a kilenc gated action metódusra (`begin`, `requestPermission`, `beginCalibration`, `start`, `pause`, `resume`, `recalibrate`, `reportQuality`, `reportRealtimeCue`) és a hozzájuk tartozó `_allows()`-halmazokon kívüli állapotokra.
- **Ellenőrzés:** a bővített teszt zöld, és egy ideiglenes mutáció (pl. egy `_allows()` hívás eltávolítása egy action metódusból) legalább egy új cellán PIROSRA fordítja.
- **Státusz:** OPEN

### F3 — MINOR — A provider-state audit kézzel karbantartott stringhalmaz, nem a tényleges mezőkből származik

- **Fájl:** `lib/features/vision/application/vision_session_state.dart:100-111` (`auditFields` getter), teszt: `vision_session_controller_test.dart:121-138`.
- **Probléma:** `auditFields` egy kézzel írt `const <String>{...}` literál, amit a fejlesztőnek MANUÁLISAN kell szinkronban tartania a `VisionSessionState` tényleges mezőivel. A jelenlegi mezőkészlet ténylegesen frame-/pixel-mentes (kézzel ellenőrizve), de a teszt ezt nem a VALÓS mezőkből, hanem egy külön karbantartott listából olvassa vissza — egy jövőbeli fejlesztő, aki új mezőt ad a state-hez (akár egy `CameraFrame`-et is, amit a brief §5 pont 1 kifejezetten „NEM elfogadható"-nak jelöl, „még debug módban sem") és elfelejti frissíteni az `auditFields`-t, ezen a teszten NEM bukna el.
- **Hatás:** a brief legerősebben hangsúlyozott invariánsa (nincs frame-buffer a state-ben) végső soron egy manuális fegyelmi szabályra támaszkodik, nem egy gépi kényszerre — jelenleg NEM defektus, de regresszió-megelőzési rés.
- **Kötelező javítás (vagy dokumentált WONTFIX):** vagy egy erősebb, a tényleges mezőkészletből származtatott ellenőrzés (pl. a konstruktor named-paraméter listájának vagy egy `toString()`/`toJson()`-szerű reprezentációnak a `auditFields`-szel való összevetése), vagy — ha ez aránytalanul nagy diffet igényelne — egy explicit doc-comment az `auditFields`-en, ami kimondja, hogy ez egy kézzel karbantartott lista, és minden új mezőhöz kötelező a bővítése.
- **Ellenőrzés:** ha erősebb ellenőrzés készül, egy próbateszt (ideiglenesen hozzáadott mező az `auditFields` bővítése nélkül) pirosra fordítja.
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld (Terra §10 + saját futás) | ✅ |
| analyze | zöld (Terra §10 + saját futás) | ✅ |
| test test/features/vision | zöld (saját futás, izolált `/tmp/review-e05-r24` klón) | ✅ |
| test test/core/camera | zöld (saját futás) | ✅ |
| test test/core/l10n_parity_test.dart | zöld (saját futás) | ✅ |
| architecture | zöld, 12 allowlisted deviation (változatlan szám — saját futás) | ✅ |
| secrets | zöld, 0 lelet (saját futás) | ✅ |
| l10n parity | zöld, en→hu 997 üzenet (saját futás) | ✅ |
| CI (teljes suite + property + APK) | dispatch folyamatban a review-val párhuzamosan | ⏳ a review lezárásakor még nem érkezett vissza — lásd a PR-t a run-linkért |

## Merge-döntés

Az ADR 0052 szerint minden gate-nek zöldnek KELL lennie ÉS nem lehet nyitott
BLOCKER/MAJOR. Jelenleg **1 BLOCKER + 1 MAJOR nyitva** (F1, F2) — **merge
TILOS**, amíg ezek nem záródnak. Javító kört indítok ugyanazzal a motorral
(Terra), a fenti három lelettel a promptban. F3 (MINOR) a javító körben
javítható, ha nem hizlalja érdemben a diffet; különben follow-up.
