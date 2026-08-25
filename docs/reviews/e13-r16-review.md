# E13-R16 — Review (Launch, recovery és onboarding migráció)

- **Kör:** `E13-R16` · **Branch:** `sonnet-impl/e13-r16-launch-and-onboarding`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude Opus 5 (orchestrátor), read-only
- **Reviewelt HEAD:** `c607f855` → javító kör 1 `7e14fe52` → javító kör 2 `e649386c`
  → javító kör 3 `64f02585` → **upstream-merge `721ab1f0`** → javító kör 4 `6ed51720`
- **Alap:** `origin/main` @ `3848ef72` → a §0.3 upstream-szinkron után `origin/main` @ `c064566f`
- **Brief:** `docs/rounds/e13-r16-launch-and-onboarding.md` (§0.0 + §0.0/B)
- **ADR:** `0281` (a `main`-en, a kör nem írt újat — helyes)
- **Kockázat:** `high` (authorization-határ + perzisztált felhasználói adat) —
  a biztonsági/adatvédelmi átvizsgálás a §6-ban, a jelentésbe integrálva.

## VÉGSŐ DÖNTÉS: **APPROVED** (`6ed51720`)

**Négy javító kör után 0 nyitott BLOCKER/MAJOR/MINOR.** Az F5 NOTE
(nem-lokalizált redakció) szándékosan marad nyitva, követő körre — a §0.0/B P4
megszorítása miatt a körben nem oldható meg.

A verdikt útja: az eredeti (`c607f855`) CHANGES REQUESTED volt (1 BLOCKER,
2 MAJOR, 1 MINOR, 1 NOTE); a reviewer-próbateszt a javító kör 1 után egy
további MINOR-t (F6) talált; a **teljes CI-suite** a javító kör 2 után két
olyan leletet hozott (F8, F9), amit a célzott gate szerkezetileg nem fedett
(§13). Az F9 a javító kör 3 idején **H3** volt (a célfájl a listán kívül) —
ezt a `c064566f` önjavító kör oldotta fel, a javító kör 4 pedig lezárta
(§15). A zárás leletenként a §9-ben és a §15-ben.

| Lelet | Súly | Állapot |
|---|---|---|
| F1 | BLOCKER | ZÁRVA (§9) |
| F2, F3 | MAJOR | ZÁRVA (§9) |
| F4, F6, F7 | MINOR | ZÁRVA (§9) |
| F8 | (CI-suite) | ZÁRVA (§13) |
| F9 | (CI-suite, volt H3) | **ZÁRVA (§15)** |
| F5 | NOTE | nyitva, szándékosan — követő körre |

---

## 1. Jelzés és handoff

| Mező | Érték |
|---|---|
| `status` | `done` |
| `head` | `c607f855` |
| `dirty_files` | `1` — **kivizsgálva**: a `.codex-round-status` maga (`.gitignore:66`); a munkafa a jelzés után tiszta, commit nem maradt le (utolsó commit `c607f855` @ 15:03:53, jelzés 15:04:22) |
| `scope_audit` | **HIÁNYZIK a jelzésfájlból** → nem bizonyíték (kör-prompt §1.1) |

**Kézi scope-audit (a hiányzó kulcs pótlása):**

```
$ tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r16 \
    --brief docs/rounds/e13-r16-launch-and-onboarding.md --base origin/main
Legacy scope audit OK (3848ef72b004..c607f85507df, 32 changed path(s), 0 generated/ignored)
```

Scope: **OK**, 32 útvonal, mind az engedélyezett listán. Sértés nincs.

---

## 2. Leletek

| # | Súly | Cella | Tárgy |
|---|---|---|---|
| F1 | **BLOCKER** | A1 | A carousel a primer MEGKERÜLÉSÉVEL kér rendszer-engedélyt; a `PermissionPrimerScreen` a futó appban elérhetetlen |
| F2 | **MAJOR** | A6/A7 | `OnboardingStep.permission` és `.firstWin` olyan állapot, amit EGYETLEN input sem produkál — a folytathatóság csak kézzel beültetett állapoton bizonyított |
| F3 | **MAJOR** | A7 | A perzisztált ellenőrzőpont `enum.index`-alapú, a doc-comment szerződést állít („Ordinal order matters"), de **egyetlen teszt sem pinneli a sorrendet** |
| F4 | MINOR | — | `_currentStep()` `StateError`-t nyel el, hogy egy `ProviderScope` nélküli teszt átmenjen |
| F5 | NOTE | §5.6 | A redaktált bootstrap-üzenet beégetett angol string, nem lokalizált modell |

---

### F1 — BLOCKER (A1): hideg engedélykérés; a primer elérhetetlen

**Fájl:sor**
- `lib/features/onboarding/screens/onboarding_screen.dart:98-103` — `_finish({requestMic: true})` → `await (widget.primeMic ?? _requestMicPermission)()`
- `lib/features/onboarding/screens/onboarding_screen.dart:53-54` — `_requestMicPermission()` → `ref.read(microphonePermissionGatewayProvider).request()`
- `lib/features/onboarding/screens/onboarding_screen.dart:146` — `_next(last)` → `_finish(requestMic: true)`
- `lib/features/onboarding/screens/onboarding_screen.dart:234` — `TextButton(onPressed: () => _finish(requestMic: true))` (`onboardStart`)
- `lib/features/onboarding/screens/onboarding_screen.dart:122` — `_firstWin()` → ugyanaz a közvetlen hívás

**Mit mértem.** A `PermissionPrimerScreen` csak akkor renderelődik, ha
`onboardingStepProvider == OnboardingStep.permission`
(`onboarding_screen.dart:157-166`). Ezt az értéket **a kör egyetlen kódútja sem
írja**:

- `_finish()` és `_firstWin()` egyaránt `_advanceStep(OnboardingStep.done)`;
- `OnboardingStepController.readStep` a legacy állapotból kizárólag
  `welcome`-ot vagy `done`-t származtat (`onboarding_provider.dart:64-76`).

Vagyis a futó appban a carousel utolsó oldalán a `Next`/`onboardStart` gomb
**közvetlenül a rendszer-párbeszédet nyitja meg**, primer nélkül — pontosan az
ADR 0281 §1 Döntés-pontja („A rendszer-párbeszédet **mindig** megelőzi a
primer") és a brief §5.1 „NEM elfogadható gyengítés" sora tiltja ezt.

Az A1 teszt (`permission_primer_test.dart`) **csak az izolált widgetet**
méri (`home: PermissionPrimerScreen(...)`), ezért zöld marad, miközben az
app-szintű állítás hamis. Ez a mérce-mátrix „Engedélykérés az indulásnál,
primer nélkül → **A1**" sorának éppen a néma bukása.

**Az implementer indoklása MÉRVE TÉVES.** Az `onboarding_screen.dart:16-25`
doc-comment szerint a bekötést az akadályozza, hogy
`test/app/routing/onboarding_first_win_test.dart` (a listán kívül) egyetlen
settle-ön belüli befejezést vár, „amit egy közbeiktatott, interaktív
primer/Stage nem tud". Mérve:

- `test/support/fake_audio.dart:26-28` —
  `FakeMicrophonePermissionGateway({this.state = MicrophonePermissionState.granted})`,
  és `fakeAudioOverrides()` (`fake_audio.dart:189-191`) ezt a **granted**
  alapértelmezést adja;
- a legacy E2E teszt `fakeAudioOverrides()`-t használ
  (`onboarding_first_win_test.dart:79`), tehát ott az engedély **már megadott**;
- a kör SAJÁT tesztje bizonyítja, hogy megadott engedélynél a primer
  **semmilyen interaktív felületet nem mutat**, hanem azonnal `onGranted`-et hív
  (`permission_primer_test.dart:88-107`: `granted`, `requestCalls == 0`, az
  Allow gomb `findsNothing`).

Egy megadott engedélynél tehát a primer **átfutó no-op**, és a legacy E2E
teszt egyetlen `pumpAndSettle()`-je változatlanul leszalad. Az interaktív
`FirstWinStageScreen`-re az indoklás igaz (az strum-emissziót vár) — a
**primerre nem**.

**Javasolt irány (nem kész patch).** A carousel mic-kérő útja ne hívja
közvetlenül a kaput: `_finish(requestMic: true)` és `_firstWin()` helyett a
`permission` ellenőrzőpont-lépésre lépjen, és a primer `onGranted`/`onSkipped`
folytassa az eredeti befejezést. A javító kör **futtassa le**
`test/app/routing/onboarding_first_win_test.dart`-ot bizonyítékként — a fenti
mérés szerint zöldnek kell maradnia; ha mégsem, az `stopped` (a fájl a listán
kívül van), nem csendes megkerülés.

---

### F2 — MAJOR (A6/A7): elérhetetlen ellenőrzőpont-állapotok

**Fájl:sor:** `lib/features/onboarding/onboarding_provider.dart:45` (`enum
OnboardingStep`), `onboarding_screen.dart:155-170`.

`OnboardingStep.permission` és `OnboardingStep.firstWin` **egyetlen input által
sem előállítható** (lásd F1 mérését). Az A6 bizonyítéka
(`onboarding_resume_test.dart:96-137`) a checkpointot **kézzel ülteti be** a
tárolóba (`InMemoryKeyValueStore({storageKey: step.index})`), tehát olyan
állapotból való folytatást bizonyít, amelybe a valódi app soha nem kerül.

Ez a kör-prompt §1.1 „elérhetetlen cél-státusz" hibaosztálya: az
átmenettáblában létező él, amit egyetlen bemenet sem produkál. Az A6
(„az onboarding megszakítás után folytatható") így a szállított appra nézve
**üres állítás**.

Az F1 javítása a `permission` lépést elérhetővé teszi. A `firstWin` lépéshez
vagy a Stage bekötése kell (a legacy E2E miatt a listán belül nem megoldható —
lásd F1), vagy az enum szűkítése arra, amit a kör ténylegesen elér; a
választást a javító kör a §10-ben indokolja.

---

### F3 — MAJOR (A7): a perzisztált sorrendnek nincs gépi őre

**Fájl:sor:** `lib/features/onboarding/onboarding_provider.dart:43-46, 66-72`.

A doc-comment kimondott szerződést állít: *„Ordinal order matters: it is the
flow's linear progression AND the persisted on-disk representation"*, és
`advanceTo` a `step.index`-et írja lemezre
(`onboarding_provider.dart:85-88`).

**Egyetlen teszt sem pinneli a sorrendet.** Az
`onboarding_resume_test.dart` mindkét oldalon szimbolikus `.index`-et használ
(`OnboardingStep.firstWin.index`), ezért egy jövőbeli beszúrás
(pl. `welcome, tour, permission, …`) esetén is **zöld maradna**, miközben minden
eszközön tárolt ellenőrzőpont némán elcsúszna: a `firstWin`-nél tartó
felhasználó `permission`-re térne vissza.

Ez pontosan a brief §9 első kockázata („a régi ellenőrzőpont-állapot ... némán
újrakezdeti az onboardingot a meglévő felhasználóknak"), és a driver-protokoll
„kipinnelt szekvencia" előírása. Doc-commentben állított szerződés tesztben
bizonyítatlan — a kör-prompt §7 tiltja.

**Javasolt irány:** egy őrcella, amely a `OnboardingStep.values` nevét ÉS
indexét literálisan pinneli (`expect(OnboardingStep.values.map((e) => e.name),
['welcome','permission','firstWin','done'])` + a `.index` értékek), azzal az
indoklással, hogy a sorrend perzisztált formátum.

---

### F4 — MINOR: elnyelt `StateError` a lépés-olvasásban

**Fájl:sor:** `lib/features/onboarding/screens/onboarding_screen.dart:68-80`.

`_currentStep()` és `_advanceStep()` `on StateError` ágon némán degradál, hogy
egy `ProviderScope` nélkül épített smoke-teszt átmenjen. Egy hiányzó
`ProviderScope` programozói hiba; elnyelve a jövőbeli bekötési hiba **néma
no-op**-ként jelenik meg (a projekt mért hibaosztálya), ráadásul az
`_advanceStep` csendes ága az ellenőrzőpont-írást is elejtheti.

**Javasolt irány:** vagy a hívó teszt kapjon `ProviderScope`-ot (és a `try`
tűnjön el), vagy a degradálás legyen kimondottan tesztelt viselkedés saját
cellával, ne mellékhatás.

---

### F5 — NOTE (§5.6): a redakció nem lokalizált

**Fájl:sor:** `lib/app/bootstrap/app_bootstrap.dart:103-116`.

A redakció **helyes és hatásos** (a nyers `$e` eltűnt, a kivétel naplóba megy),
és az A8 teljesül. A brief §5.6 / ADR 0277 viszont „kód → **lokalizált** modell"
alakot ír elő, itt pedig beégetett angol string keletkezik. A §0.0/B P4
megszorítása (a `BootstrapFailure` alakja nem törhet, mert két fogyasztója a
tilos zónában van) ezt a körben **jogosan** korlátozza — rögzítve követő körre,
nem blokkol.

---

## 3. Acceptance criteria — tételes mérés

| # | Kritérium | Bizonyíték | Ítélet |
|---|---|---|---|
| A1 | Nincs engedélykérés primer nélkül | `permission_primer_test.dart` (izolált widget) | **NEM TELJESÜL** — F1: a futó appban a carousel primer nélkül kér |
| A2 | Végleges megtagadásnál a beállítás-út | `permission_primer_test.dart:130-179` — `permanentlyDenied` és `restricted` is a settings-akciót mutatja, `requestCalls == 0` | ✅ |
| A3 | Az „első siker" gyenge jelnél nem jelent sikert | `first_win_test.dart:88-105` (küszöb-hármas) + `:150-196` (widget: 0.45 → csak Retry, 0.85 → Continue) | ✅ a Stage-re; a legacy `_firthWin()` rövidzár megkerüli (F2 kontextus) |
| A4 | A biztonságos mód nem töröl adatot | `bootstrap_routing_test.dart:70-118` — akció-címkékre szűkített destruktív-szó tiltás | ✅ |
| A5 | A mikrofon a route elhagyásakor felszabadul | `first_win_test.dart:107-131` — `sub.close()` → `fake.isStopped` | ✅ (fake motoron, a §0.0/B P2 szerint helyesen) |
| A6 | Az onboarding megszakítás után folytatható | `onboarding_resume_test.dart:96-137` | **GYENGE** — F2: kézzel beültetett, az app által elérhetetlen állapot |
| A7 | A régi ellenőrzőpont-állapot migrálódik | `onboarding_resume_test.dart:19-66` — üres/`true`/`false`/explicit/korrupt cellák | ✅ a migrációra; F3: a sorrend-szerződésnek nincs őre |
| A8 | A helyreállítási képernyőn nincs nyers kivétel | `bootstrap_routing_test.dart:16-68` — beültetett titok-string, `StateError`/`Bad state` kizárva | ✅ |
| A9 | Golden-felvétel minden §3 képernyőről, 2 keretben | `test/ui/goldens/e13_r16_screens_golden_test.dart` + **10 PNG** a diffben (launch, onboarding, permission_primer, first_win_stage, recovery × compact/scale2) | ✅ |

**A9 megjegyzés:** mind az öt felület megvan mindkét keretben, és az
`_Page` `Padding` → `SingleChildScrollView` váltása
(`onboarding_screen.dart:262`) valódi, `textScaler: 2.0`-ra adott válasz — nem
kozmetika.

---

## 4. Valódi-sértés próba

Az implementer a §10-ben dokumentálta a saját próbáját. **Reviewer-oldali
független ellenőrzés:** az A3 cella szerkezetileg falszifikálható, mert a
`isFirstWinSuccess` tiszta függvény és a widget-cellák külön kulcsokat
(`onboard-first-win-continue` / `-retry`) keresnek — egy feltétel nélküli
siker-képernyő a `0.45` cellában a `-continue` kulcsot találná meg és a
`-retry`-t nem, tehát PIROS. A próbateszt-futtatást a javító kör utáni,
végleges gate-újrafuttatással együtt végzem (a jelenlegi HEAD úgyis változik).

---

## 5. Scope és architektúra

- **Scope:** OK (fenti audit) — 32 útvonal, sértés 0.
- **Tilos zóna:** érintetlen. A `lib/core/audio/**`, `lib/core/storage/**`,
  `lib/main.dart`, `lib/app/strumsight_app.dart`, `docs/adr/**` egyike sem
  módosult; a `BootstrapFailure` alakja forrás-kompatibilis maradt (P4 tartva).
- **P1 tartva:** `kFirstWinConfidenceThreshold = 0.60` kör-lokális `const`
  (`first_win_providers.dart:12`), a `confidenceThresholdProvider`-t a kör
  sehol nem olvassa.
- **P2 tartva:** nincs új `AudioOwner`; `Provider.autoDispose` +
  `ref.onDispose(engine.stop)` a merge-elt `liveFrameProvider` mintát követi.
  A `onboardingFirstWinConfidenceProvider` szintén `autoDispose`, tehát nem
  pinneli az engine-t (a mért „autoDispose-t figyelő provider" csapda elkerülve).
- **P3 tartva:** a legacy `first_win_test.dart` mind a három eredeti cellája
  szó szerint megmaradt, az új cellák hozzáadva — gyengítés nincs.
- **P5 tartva:** `arb_parity_test.dart` +5 sor, pontosan egy tuple.
- **l10n:** új `lib/l10n/features/onboarding_{en,hu}.arb` fragmentum, az
  `app_{en,hu}.arb` regenerált (+17/+17) — az ADR 0307 §4 útja betartva.

## 6. Biztonsági / adatvédelmi átvizsgálás (`risk = "high"`)

Inline elvégezve (nem külön ügynökkel), az authorization- és
perzisztencia-határra fókuszálva:

- **Engedély-kezelés:** a kör nem hívja közvetlenül a `permission_handler`-t;
  minden út a `MicrophonePermissionGateway`-en megy (E01-R09 §9.1). ✅
- **Végleges megtagadás:** `permanentlyDenied`/`restricted` esetén nincs
  újrakérés, csak settings-út — a felhasználói döntés nem kerülhető meg. ✅
- **Erőforrás-szivárgás:** a fake motor `stop()`-ja idempotens, és a provider
  `autoDispose`; valódi mikrofont a kör nem nyit. ✅
- **Adatvesztés:** a safe mode nem kínál destruktív akciót (A4); a
  checkpoint-migráció **additív** — a legacy `ss.onboarding.seen` kulcsot nem
  írja felül és nem törli, csak olvassa. ✅
- **Adatszivárgás:** az A8 redakció megszünteti a nyers kivétel-szöveg
  megjelenítését; a kivétel a naplóba kerül. ✅ (F5 a lokalizációról szól,
  nem szivárgásról.)
- **Perzisztált formátum:** F3 — az `enum.index` on-disk szerződésnek nincs
  gépi őre. Ez az egyetlen adat-integritási lelet.

## 7. Gate és CI

- **Célzott gate:** a végleges (javító kör utáni) HEAD-en futtatom izolált
  `/tmp` klónban, a brief §7 parancsával, csővezeték nélkül.
- **CI:** a tervező (`tools/round-ci-plan.py --repo … --head c607f855`)
  `full-gate.yml`-t ír elő (`apk_required: false`, 32 fájl, natív/release
  útvonal nincs), és `router_ci_expected: true`
  (`docs/rounds/e13-r16-launch-and-onboarding.md`). Mindkettőnek a **merge
  SHA-ján** kell zöldnek lennie.
- Dispatch a `c607f855`-ön: `full-gate` `32863585131`, `router-ci`
  `32863545889` — a javító kör után újra kell dispatch-elni.

## 8. Merge-feltétel

A merge tilos, amíg az **F1 (BLOCKER)**, **F2** és **F3 (MAJOR)** nyitva van.
Az F4 a körben javítható, az F5 követő körre rögzítve.

---

## 9. Zárás leletenként (javító kör 1 `7e14fe52` + javító kör 2 `e649386c`)

Minden zárást **magam mértem**, izolált `/tmp/review-e13-r16` klónban.

| # | Súly | Állapot | A zárás bizonyítéka |
|---|---|---|---|
| F1 | BLOCKER | **ZÁRVA** | Mindkét mic-kérő CTA a `permission` ellenőrzőponton át megy (`_afterPermission` + `_advanceStep`), a `primeMic`/`_requestMicPermission` közvetlen hívás **törölve**; a primer a `PermissionPrimerScreen` egyetlen kapu-hívási helye. Új app-szintű mérce + a listán kívüli `onboarding_first_win_test.dart` zölden maradt (nem módosítva). |
| F2 | MAJOR | **ZÁRVA** | `OnboardingStep` **szűkítve**: `{welcome, permission, done}` — a `.firstWin` (amit semmilyen bemenet nem produkált) törölve. A `permission` mostantól valódi bemenettel elérhető, tehát az A6 nem üres állítás. |
| F3 | MAJOR | **ZÁRVA** | Új őrcella: `OnboardingStep.values` **neveit ÉS indexeit** literálisan pinneli (`['welcome','permission','done']`, 0/1/2), a perzisztált formátum indoklásával. Zölden fut (gate [5]). |
| F4 | MINOR | **ZÁRVA** | A `StateError`-degradálás kimondottan tesztelt viselkedés lett. |
| F6 | MINOR | **ZÁRVA** | (Javító kör 1 után, reviewer-próbateszttel találva — lásd §10.) Az A1 app-szintű mérce a MÁSIK CTA-ra (`onboardStart`) is kiterjed. |
| F7 | MINOR | **ZÁRVA** | A §10 handoff elavult, a javító kör 1 után hamissá vált bekezdése javítva. |
| F5 | NOTE | nyitva, szándékosan | Nem-lokalizált redakció — a §0.0/B P4 miatt a körben nem oldható; követő körre rögzítve. |

## 10. Reviewer-próbatesztek (eldobhatók, futtatva, visszaállítva)

A guard-tesztek **valódi-sértés** próbája — nem az implementer jelentése,
hanem saját mérés, izolált klónban. Mindhárom próba után a klón
`git checkout`-tal visszaállítva (`git status --short` üres).

| # | Injektált sértés | Elvárt | Mért |
|---|---|---|---|
| 1 | `_finish(requestMic: true)` → közvetlen `gateway.request()` (a `onboardStart` CTA), `7e14fe52`-n | PIROS | **`+8: All tests passed!` — ZÖLD** ⇒ **F6 lelet: az út őrizetlen volt** |
| 2 | `_firstWin()` → közvetlen `gateway.request()`, `7e14fe52`-n | PIROS | `00:02 +7 -1: Some tests failed` — az „A1 (app-level)" cella bukott ⇒ az őr **valódi**, nem tautologikus |
| 3 | ugyanaz mint az 1., de a javított `e649386c`-n | PIROS | `00:02 +8 -1: Some tests failed` — az ÚJ „Enable mic & start" cella bukott ⇒ **F6 zárva** |

A 2. és 3. próba együtt bizonyítja, hogy az A1 mindkét belépési pontja gépi
őrrel védett, és hogy az őrök tényleg pirosra váltanak a tiltott
implementációtól.

## 11. A merge-kapu mérése (saját futtatás)

**Célzott gate a merge-jelölten (`e649386c`), izolált klónban, csővezeték
nélkül** — `tools/round-gate.sh` a brief §7 öt teszt-útvonalával:

```
format zöld · analyze zöld · bootstrap_routing zöld · permission_primer zöld
onboarding_resume zöld · first_win zöld · e13_r16_screens_golden zöld
architecture zöld · secrets zöld · l10n zöld
MINDEN GATE ZÖLD          (GATE_EXIT=0)
```

**Scope-audit a végleges HEAD-en:** `ok` (a jelzésfájl `scope_audit=ok`,
`scope_audit_changed=2`), a teljes körre pedig OK, 34 útvonal / 1
generated-ignored (a saját review-jelentés).

**CI (a merge SHA-ján kötelező, ADR 0052 + ADR 0086 §2):** a tervező
`full-gate.yml`-t ír elő és `router_ci_expected: true`-t
(`docs/rounds/**` érintve) — mindkettőnek zöldnek kell lennie a merge SHA-n.

## 12. Rögzített megfigyelés (nem lelet)

A `FirstWinStageScreen` az F2 szűkítése után **nem hivatkozott a `lib/` fából**
(csak a saját tesztjéből és a goldenből) — kész, bizonyított komponens, amely a
bekötésre vár. Ez a brief §3 szándéka szerinti állapot („fake átjáróval és
motorral **tesztelhetően**"), és a mérés szerint a bekötés a listán kívüli
`test/app/routing/onboarding_first_win_test.dart` egyetlen-settle elvárása
miatt e körben nem lehetséges. **A követő kör (E13-R17+) briefjének fel kell
vennie azt a fájlt az `allowed_paths`-ra**, különben a mini Stage
bekötése ismét H3-ba fut.

---

## 13. A teljes CI-suite két leletet talált, amit a célzott gate NEM fed (`68c3ad16`)

A `full-gate.yml` `32867296946` futása a merge SHA-n **PIROS**:
`6366 tests passed, 2 failed, 15 skipped`. **Mindkettő valódi regresszió**, és
mindkettő a kör öt célzott teszt-fájlján KÍVÜL esik — a célzott gate nálam is,
az implementernél is zöld volt. Ez a mérce-rés maga is tanulság (L→ §14).

### F8 — a design system határának megsértése (scope-on BELÜL, **JAVÍTVA**)

`test/core/architecture_dependency_test.dart` → *„design system boundaries
(E13-R02) real production source reaches the design system only via
public.dart"*. A kör MINDHÁROM új képernyője közvetlenül importálta a
`design_system/foundations/**`-ot (és a primer a `components/feedback/**`-ot is)
a `public.dart` helyett — 11 sértés.

**Miért nem fogta a célzott gate:** a `tools/round-gate.sh` `architecture`
lépése a `tool/check_architecture.dart`-ot futtatja („Architecture dependencies
OK (12 allowlisted deviation(s))"), ami egy **másik**, tágabb szabálykészlet —
az E13-R02 design-system-határ mércéje egy külön `test/core/` teszt, amit csak
a teljes suite futtat.

**Javítva** a javító kör 3-ban (`ded7a628`): mindhárom fájl `public.dart`-on át
importál. Mind a három fájl a kör engedélyezett listáján van, tehát a javítás
teljes egészében scope-on belüli. Saját mérésem a javítás után:

```
$ flutter test test/core/architecture_dependency_test.dart \
    test/ui/goldens/e13_r16_screens_golden_test.dart test/ui/ui_inventory_test.dart
00:02 +54 -1
```

— az architecture-teszt ZÖLD, és a **10 golden PNG bit-azonos maradt** (a diff
egyetlen `.png`-t sem érint), tehát valóban csak import-csere történt.

### F9 — a képernyő-leltár számlálója (scope-on KÍVÜL, **H3**)

`test/ui/ui_inventory_test.dart:14` → `expect(first.screenPaths, hasLength(79))`.

A kör két új képernyőt ad a leltár hatókörébe
(`lib/features/onboarding/screens/permission_primer_screen.dart` és
`first_win_stage_screen.dart`), ezért a mért érték **81**. (A
`lib/app/bootstrap/` alatti `launch_screen.dart`/`recovery_screen.dart` a
`tool/ui_inventory.dart` szabálya szerint NEM számít bele — mérve.)

Reprodukció:

```
$ flutter test test/ui/ui_inventory_test.dart
Expected: an object with length of <79>
```

Mért új érték (eldobható próbával, `UiInventory(Directory.current).render()`):
`SCREEN_COUNT=81`.

**Ez a lelet a körön belül NEM javítható.** A `test/ui/ui_inventory_test.dart`
NINCS a brief `allowed_paths`-án (a lista `test/ui/goldens/` **könyvtár**-előtagot
tartalmaz, nem a `test/ui/` fát), és a felvétele **tágítás, azaz H3**
(ADR 0087 §2; [L478](../LESSONS.md): a pre-flight csak SZŰKÍTHET). Az
orchestrátor ezt nem oldhatja fel.

**A kerülőutak kifejezetten tiltottak** és nem is kértem őket: a képernyők
átnevezése/áthelyezése vagy a `tool/ui_inventory.dart` szabályának lazítása a
mérce meghamisítása lenne, nem javítás.

## 14. Merge-állapot

**A kör MINDEN egyéb mércéje zöld**, a merge-jelölt `64f02585`-ön:

- célzott gate 10/10 zöld (saját futtatás, izolált klón);
- scope-audit ok, 0 sértés;
- Router CI `success` (`32867354718`, a `68c3ad16` SHA-n);
- a review 8 leletéből 7 zárva, az F5 NOTE szándékosan nyitva;
- a teljes suite 2 leletéből az F8 javítva.

**Egyetlen nyitott elem az F9**, aminek a javítása pontosan **egy szám** egy
listán kívüli fájlban (`79` → `81`). A kör ezért **H3 halttal** áll meg, nem
merge-eléssel; a döntés az önjavító körre / emberre tartozik.

> **Ez a §14 a `64f02585` HEAD állapotát rögzíti, és a történeti tény miatt
> változatlanul marad.** Az önjavító kör azóta lefutott — a feloldás és a
> zárás a §15-ben.

---

## 15. Az F9 feloldása és zárása (upstream-merge `721ab1f0` + javító kör 4 `6ed51720`)

### 15.1 A H3 feloldása — nem az orchestrátor tágított, hanem az önjavító kör

A §14 H3-ja azon állt, hogy a `test/ui/ui_inventory_test.dart` **nem volt** a
brief `allowed_paths`-án, a felvétele pedig tágítás
([ADR 0087 §2](../adr/0087-autonomous-round-pipeline.md), [L478](../LESSONS.md)).

Az önjavító kör ezt a `main`-en oldotta fel — `c064566f`
([PR #454](https://github.com/wolfcasaba/strumsight/pull/454)): a leltártesztet
felvette az `allowed_paths`-ra **és** a `gate_tests`-be, megírta a brief
`§0.0/R6` szakaszát, és a **gyökérokot** is javította (a `tools/brief-lint.py`
`S9` predikátuma addig csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-
előtagot nem — ezért maradt néma a sáv-szintű batch pre-flight).

A kör-ág ezt a `§0.3` upstream-szinkronnal vette át: `git merge --no-ff
origin/main` → **`721ab1f0`**, konfliktus nélkül. Mérve utána:

```
$ git merge-base --is-ancestor origin/main HEAD ; echo $?
0
$ git diff --check ; echo $?
0
```

A merge megőrizte mindkét oldalt: a brief `§0.0/R6` (a `main`-ről) ÉS a kör
saját `§10.1–10.3` implementation-handoffja egyaránt jelen van.

**Az L345 kockázata kimérve.** Egy self-heal írhat pinnelt regressziós őrt a
brief alakjára; ha igen, a kör saját brief-szerkesztése új scope-rést nyitna.
Megmértem — a `tools/tests/test_brief_ui_inventory_scope.py` **szintetikus**
brief-fixture-t épít, a valós briefet csak S9-re nézi (és az a heal óta tiszta):

```
$ python3 -m pytest tools/tests/test_brief_ui_inventory_scope.py -q
16 passed in 43.10s
$ python3 tools/brief-lint.py --brief docs/rounds/e13-r16-launch-and-onboarding.md --level strict
# Brief-lint (strict) — nincs lelet
```

### 15.2 F9 — ZÁRVA

**Diff a javító kör 4-ben (`721ab1f0..6ed51720`):** pontosan **két** fájl —
`test/ui/ui_inventory_test.dart` (1 sor) és a brief (§10.3 pontosítás + §10.4).

```diff
-    expect(first.screenPaths, hasLength(79));
+    expect(first.screenPaths, hasLength(81));
```

A leltárteszt minden más állítása (`toMarkdown()` determinizmus, `orderedEquals`
rendezettség, a `contains` cellák) **érintetlen**; a `tool/ui_inventory.dart`
nem módosult. Kerülőút (képernyő-átnevezés/áthelyezés vagy a leltár-szabály
lazítása) nem történt — mérve a diffen.

### 15.3 Reviewer-próbateszt: az őr valódi, nem tautologikus

Eldobható próba izolált klónban (`/tmp/review-e13-r16` @ `6ed51720`). A kérdés:
a `hasLength(81)` **tényleg** figyeli-e a fát, vagy csak egy elmozdított
konstans.

| # | Injektált sértés | Elvárt | Mért |
|---|---|---|---|
| 4 | egy további `lib/features/onboarding/screens/zz_probe_screen.dart` | PIROS | **`Which: has length of <82>` — `Some tests failed`** ⇒ az őr él |

A próba után a fájl törölve, `git status --short` üres, a teszt újra
`+1: All tests passed!`. Az őr tehát a fa **mérhető** igazságát pinneli, nem egy
tautológiát.

### 15.4 A merge-kapu mérése a merge-jelölten (`6ed51720`)

**Célzott gate — saját futtatás, izolált klónban, csővezeték nélkül**
(`tools/round-gate.sh` a brief §7 HAT teszt-útvonalával; a hatodik a most
felvett leltárteszt):

```
format zöld · analyze zöld · bootstrap_routing zöld · permission_primer zöld
onboarding_resume zöld · first_win zöld · e13_r16_screens_golden zöld
ui_inventory zöld · architecture zöld · secrets zöld · l10n zöld

MINDEN GATE ZÖLD.          (GATE_EXIT=0)
```

A gate után a klón `git status --short` **üres** — a 10 golden PNG bit-azonos
maradt, a leltárszám emelése goldent nem érintett.

**Scope-audit a teljes körre** (a jelzésfájlból a kulcs ismét hiányzott, ezért
kézzel — a kör-prompt §1.1 szerint a hiány nem bizonyíték):

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r16 \
    --brief docs/rounds/e13-r16-launch-and-onboarding.md --base origin/main
Legacy scope audit OK (c064566fa347..6ed517203979, 35 changed path(s), 1 generated/ignored)
```

**Jelzés-ellenőrzés:** `status=done`, `head=6ed51720`, `dirty_files=1` —
**kivizsgálva**: a `.codex-round-status` maga (gitignore-olt); a munkafa a
jelzés után tiszta (`git status --short` üres), commit nem maradt le.

**CI a merge-jelölt SHA-ján** (a tervező `full-gate.yml`-t ír elő,
`apk_required: false`, `router_ci_expected: true`):

| Workflow | Run | headSha | Eredmény |
|---|---|---|---|
| `full-gate.yml` | [`32874118246`](https://github.com/wolfcasaba/strumsight/actions/runs/32874118246) | `6ed51720` | **success** |
| `router-ci.yml` | [`32874103970`](https://github.com/wolfcasaba/strumsight/actions/runs/32874103970) | `6ed51720` | **success** |

Mindkettő `headSha`-ja megegyezik a lokális HEAD-del (a néma-bukás elleni
kötelező összevetés), és az `origin/main` a dispatch óta **nem mozdult**
(`c064566f` → `c064566f`).

### 15.5 Merge-feltétel — teljesült

Az F1–F4 és F6–F9 zárva, az F5 NOTE szándékosan nyitva (követő körre). A zöld
kapu (ADR 0052) minden eleme igazolt a merge-jelölt SHA-n. **A merge
engedélyezett.**
