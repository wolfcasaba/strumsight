# E13-R16 — Review (Launch, recovery és onboarding migráció)

- **Kör:** `E13-R16` · **Branch:** `sonnet-impl/e13-r16-launch-and-onboarding`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude Opus 5 (orchestrátor), read-only
- **Reviewelt HEAD:** `c607f855`
- **Alap:** `origin/main` @ `3848ef72`
- **Brief:** `docs/rounds/e13-r16-launch-and-onboarding.md` (§0.0 + §0.0/B)
- **ADR:** `0281` (a `main`-en, a kör nem írt újat — helyes)
- **Kockázat:** `high` (authorization-határ + perzisztált felhasználói adat) —
  a biztonsági/adatvédelmi átvizsgálás a §6-ban, a jelentésbe integrálva.

## VÉGSŐ DÖNTÉS: **CHANGES REQUESTED**

1 BLOCKER, 2 MAJOR, 1 MINOR, 1 NOTE. A BLOCKER a kör **két címadó
acceptance-cellájának egyikét** (A1) érinti, és a mérés szerint a
kör `allowed_paths`-án belül javítható.

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
