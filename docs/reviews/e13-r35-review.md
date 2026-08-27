# E13-R35 review — Account, Settings, Privacy, Offline AI és Share UI

- **Kör:** `E13-R35` (Chapter 13, Kör 35)
- **Branch / HEAD:** `sonnet-impl/e13-r35-account-privacy-and-share` @ `76d3bf2a`
- **PR:** [#480](https://github.com/wolfcasaba/strumsight/pull/480)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5) — két részletben futott
  (az elsőt az abszolút időkorlát lőtte ki, a folytatás ugyanazon a branchen ment)
- **Reviewer:** Claude (Opus 5), orchestrátor — read-only, izolált `/tmp/review-e13-r35` klón
- **Verdikt (1. kör):** **CHANGES REQUESTED** — 3 MAJOR, 1 MINOR, 2 NOTE

## 1. Jelzés és handoff

`.codex-round-status`: `status=done`, `gate_shape=ok`, `scope_audit=ok`,
`head=76d3bf2a`. A `dirty_files=1` a jelzés pillanatában a §10 handoff
commitja előtti állapot volt; a fa a jelzés után tiszta
(`git status --short` üres).

A §10 handoff kitöltött, részletes, és — a lenti M3 kivételével — a mért
állításokat helyesen attribuálja. A valódi-sértés próba (A6) dokumentált és
hihető: `if (false && !verification.verified)` → 10-ből 3 cella pirosra váltott,
visszaállítás után 10/10 zöld.

## 2. Amit ÉN futtattam (nem bemondás)

| Mérés | Eredmény |
|---|---|
| `tools/round-gate.sh` a §7 24 útvonalával, izolált `/tmp/review-e13-r35` klónban | **MINDEN GATE ZÖLD** (29 lépés: format, analyze, 24 teszt-fájl, architecture, secrets, l10n) |
| `python3 tools/scope-audit.py --base 9ca4a0dc` a kör TELJES diffjére | `Legacy scope audit OK (9ca4a0dc..76d3bf2a, 45 changed path(s), 0 generated/ignored)` |
| Router CI a merge SHA-n (`76d3bf2a`) | [33103705782](https://github.com/wolfcasaba/strumsight/actions/runs/33103705782) — `success` |
| Full Gate exact-SHA (`76d3bf2a`) | [33103714125](https://github.com/wolfcasaba/strumsight/actions/runs/33103714125) — a review írásakor `in_progress` |
| 2 eldobható reviewer-próbateszt (lásd M1, M2) | mindkettő REPRODUKÁLTA a leletet; a próbák törölve |

## 3. Leletek

### MAJOR — M1: hálózati/tárolási hiba INTEGRITÁS-SÉRTÉSNEK látszik, és ZSÁKUTCÁBA visz (modellkezelő)

**Fájl:** `lib/features/offline_ai/providers/offline_model_controller.dart:51–60`
(`checkAndActivate`) + `lib/features/offline_ai/screens/model_manager_screen.dart:82–110`
(`_ActionArea` `blockedIntegrity` ága).

A `checkAndActivate` a forrás MINDEN `Failure()`-ét — hálózati hiba, tárhelyhiány,
IO-hiba — `OfflineModelPhase.blockedIntegrity`-re képezi. A képernyő ebben a
fázisban a „Not activated — checksum could not be verified" biztonsági riasztást
mutatja, **és a `modelManagerCheck` gombot NEM letiltja, hanem egyáltalán nem
rendereli** — a controllernek pedig nincs reset/„próbáld újra" útja.

A produkciós alapértelmezett forrás ma `UnavailableOfflineModelSource`, ami
`NetworkFailure`-t ad (`offline_model_source.dart:19–25`), tehát **az ELSŐ
koppintás a valós appban mindig ebbe az állapotba visz**.

**Mért bizonyíték** (reviewer-próbateszt, `/tmp/review-e13-r35`, azóta törölve):

```
PROBE: fázis egy HÁLÓZATI hiba után = OfflineModelPhase.blockedIntegrity
PROBE: van-e még Check gomb? false
PROBE: integritás-blokk blokk látszik? true
```

**Miért MAJOR.** Nem biztonsági gyengítés (fail-safe: nem aktivál), de (a) a
brief §3 a „tárolási/hálózati hiba" állapotot KÜLÖN nevesíti a
„ellenőrzőösszeg-hiba" mellett — ez a két állapot itt egybeolvadt; (b) az
ADR 0292 kontextusa pont azt mondja ki, hogy a felhasználó nem tudja eldönteni,
egy ellenőrzőösszeg-eltérés hálózati hiba-e vagy támadás — a felület tehát nem
állíthat integritás-sértést ott, ahol hálózati hiba történt; (c) a képernyő
egyetlen koppintás után visszafordíthatatlanul használhatatlan.

**Javasolt irány (NEM kész patch):** külön fázis a beszerzési hibának (pl.
`fetchFailed`), saját, nem-riasztó szöveggel, ahol a „Check" akció MEGMARAD; a
`blockedIntegrity` maradjon szigorúan a MÉRT ellenőrzőösszeg-eltérés fázisa (a
gomb ott továbbra is legyen ABSZENS — az A6 mércéje nem lazulhat). A javításhoz
tartozzon cella, ami a hálózati hibát az integritás-blokktól megkülönbözteti.

### MAJOR — M2: a „Saving…" sáv ÖRÖKRE beragad, ha a felhasználó a debounce ablakon belül visszaállítja az értéket

**Fájl:** `lib/features/settings/providers/settings_sync.dart:243–252`
(`_onLocalChange` korai visszatérési ága) — a `_publishStatus(pending)` a
280. sorban megtörténik, de a visszaállításkor futó
`if (!_pushInFlight && _currentSignature() == _syncedSignature) { _debounce?.cancel(); return; }`
ág **nem publikál vissza `synced`-et**.

**Mért bizonyíték** (reviewer-próbateszt, valódi 600 ms-os debounce-szal, azóta törölve):

```
PROBE: kiindulás státusz=SettingsSyncStatus.synced érték=0.45 updates=0
PROBE: szerkesztés után státusz=SettingsSyncStatus.pending
PROBE: visszaállítás után státusz=SettingsSyncStatus.pending updates=0
PROBE: látszik-e a "Saving…" sáv? true
PROBE: látszik-e az "All changes saved"? false
```

**Miért MAJOR.** A trigger triviálisan elérhető: a confidence-küszöb egy
CSÚSZKA — az oda-vissza húzás (600 ms-on belül ugyanarra az értékre visszaérve)
mindennapos. Az állapot ezután **véglegesen** hazudik: „Saving…" látszik,
miközben **nulla** push van úton (`updates=0`), tehát semmi nem fogja
visszabillenteni; a felület egy nem létező, függőben lévő mentést állít. Ez
ugyanaz a hibaosztály, mint az [L06](../LESSONS.md) (a felület állapota ≠ a
valóság), csak az ellenkező irányban.

**Javasolt irány:** a korai visszatérési ág publikáljon `synced`-et (nincs mit
menteni), és a javítást fogja meg cella, ami a szerkesztés-visszaállítás
szekvenciát méri.

### MAJOR — M3: az A3 „in-flight" cellája NEM azt méri, amit a NEVE és a §10 handoff állít

**Fájl:** `test/features/settings/settings_persistence_failure_test.dart:97–105`.

A cella neve: `'A3 — while a save is in flight the screen shows "Saving…", not "saved"'`.
A törzse viszont megnyitja a beállításokat és **azt** állítja, hogy
`find.text('All changes saved')` LÁTSZIK — se repülő mentés, se `Saving…`
állítás nincs benne. A §10 handoff ezt a cellát nevezi meg az A3
bizonyítékaként.

A `settingsSyncStatusPending` („Saving…") szöveg tehát a kör ÚJ állapotgépének
egyetlen olyan ága, amit **egyetlen teszt sem mér** — és épp ez az ág az, ahol
az M2 él. Ez az `E02-R15`-ben mért attribúciós hibaosztály (a handoff olyan
tesztnek tulajdonít egy cellát, ami nem azt méri).

Az A3 érdemben **nem fedetlen**: az első cella (74–80. sor: bukott mentés után
NINCS „All changes saved", VAN függő állapot és Retry) plusz a nem
szerkeszthető `settings_sync_test.dart` őrcellái valósan mérik a
„csak szerver-megerősítés után szinkronizált" szabályt. A lelet a hamis
cella-attribúció és a mérce lyuka, nem a szabály sérülése.

**Javasolt irány:** a cella tényleg mérje az in-flight állapotot (késleltetett
`update()` a fake repóban → `Saving…` látszik, „All changes saved" nem), vagy —
ha ez nem járható — a név és a §10 attribúció igazodjon ahhoz, amit ténylegesen mér.

### MINOR — m1: az adatvédelmi export csak egy dialógusba írja ki a nyers JSON-t

**Fájl:** `lib/features/settings/screens/privacy_center_screen.dart:43–66`.

Az „export" feladat állapotgépe (`idle → running → done|failed`) rendben van, és
az A8 értelmében a művelet explicit és auditálható. Az eredmény azonban egy
`AlertDialog`-ban megjelenített nyers JSON-szöveg — az adat nem hagyja el az
eszközt (nincs fájl, nincs megosztás). Ez védhető minimum, de a §3 „export"
szava alatt a felhasználó jellemzően átvihető adatot ért.

**Javasolt irány:** vagy a felület mondja ki egyértelműen, hogy ez egy
megtekinthető pillanatkép, vagy egy későbbi kör adja hozzá a tényleges kimentést
(follow-up — a diffet ez a kör ne hizlalja).

### NOTE — n1: a `StrumCard` `TextScaler.noScaling`-je indokolt, de érdemes őrizni

`lib/features/share/widgets/strum_card.dart:44–50`. A kártya rögzített 360×640
px-es EXPORTÁLT grafika, nem olvasási felület; a rendszer-szövegskála nála
túlcsordulást okozott (a §10 mérése szerint valódi, kör ELŐTTI hiba volt, ami
minden nagy betűméretet használó felhasználó megosztott képét elrontotta). A
javítás helyes. NOTE, mert a repóban ez az EGYETLEN `noScaling` előfordulás —
ha máshova is elterjed, az már akadálymentesítési regresszió lenne; egy jövőbeli
őrteszt (csak exportált grafikán engedélyezett) olcsón zárná.

### NOTE — n2: a redakció mindkét artefaktumon alapból KI van kapcsolva — ellenőrizve

Az A7-et nem csak a szöveges caption oldalán mértem: a `StrumCard` a címet is
`showTitle` mögé tette (`strum_card.dart:76–80`), a `SharePreviewScreen`
`_includeTitle` alapértéke `false` (`share_preview_screen.dart:40`), és a
`ShareContent.caption` / `ShareService.shareCard|shareText` `includeTitle`
paramétere is `false` alapon. A megosztás tehát KÉPEN és SZÖVEGBEN is minimális
alapból — ez a lelet-mentes, mért állapot.

## 4. Acceptance criteria — tételes ellenőrzés

| # | Verdikt | Mit láttam |
|---|---|---|
| A1 | ✅ | `login_screen.dart:174–181` — `authContinueWithoutAccount` gomb, `maybePop()`; `auth_states_test.dart` zöld a saját gate-futásomban |
| A2 | ✅ | a UI kizárólag `authFailureMessage(l10n, auth.error)`-t rendereli (`login_screen.dart:135–139`), a mapper stabil `FailureCode`-ra képez |
| A3 | ⚠ | a szabály maga TELJESÜL (`settings_sync.dart` `Success` ág + a nem szerkeszthető őrcellák), de a §10 által megnevezett „in-flight" cella nem méri, amit állít — **M3** |
| A4 | ✅ | `settings_persistence_failure_test.dart:60–95` — 1 push → hiba → Retry → PONTOSAN 1 új push (összesen 2); automatikus replay sehol; `settings_sync_test.dart` zölden fut a gate-emben |
| A5 | ✅ | `consent_center_test.dart` a felső szintű belépőt méri; a §0.0.B/B6 mérése szerint ez valódi új wiring volt |
| A6 | ✅ | a verifikáció VALÓDI sha256 (`offline_model.dart:25–26, 48–55`, `package:crypto`), az `activate()` egyetlen kapuja a `verification.verified`, és a `blockedIntegrity` ágon **nincs** aktiváló vezérlő (nem letiltott — hiányzó). A §10 valódi-sértés próbája 3 cellát váltott pirosra |
| A7 | ✅ | lásd n2 — kép ÉS szöveg oldalon is alapból minimális, tételes felsorolással |
| A8 | ✅ | export/törlés feladat-állapotgéppel, a törlés következmény-központú megerősítéssel (`privacy_center_screen.dart:75–99`, ADR 0279); a hiba `failed` állapotként LÁTSZIK, nincs elnyelve |
| A9 | ⏳ | 10 PNG (5 képernyő × {compact, scale2}) commitolva, a golden-teszt valódi `matchesGoldenFile` (nincs `skip`), a felvétel `tools/golden-x86.sh`-val ment (ADR 0426). A VÉGSŐ bizonyíték az exact-SHA Full Gate — a review írásakor még fut |

## 5. Architektúra és scope

- **Scope:** tiszta (mért, lásd §2) — 45 fájl, mind az `allowed_paths`-on.
- **Design-system határ:** a `test/core/architecture_dependency_test.dart` (44
  cella) zölden futott a saját gate-emben; a képernyők a `public.dart` barrelen
  át importálnak.
- **Router:** nem módosult; az új képernyők `Navigator.push`-sal érhetők el
  (§0.0.B/B5), a `route_literal_guard` zöld.
- **`ui_inventory`:** 94 → 96, pontosan a két új `_screen.dart`-ra; a teszt többi
  állítása érintetlen (`git diff` ellenőrizve).
- **Automatikus retry:** nincs — a `settings_sync.dart` diffjében egyetlen új
  `Timer` sincs, a `retryFailedPush` a MEGLÉVŐ `_queuePush(force: true)` út.

## 6. Merge-döntés

**Merge TILOS**, amíg az M1–M3 nyitva van (ADR 0052 mércéje egyébként
független: a Full Gate zöldjét is meg kell várni a VÉGLEGES merge SHA-n, és a
javító kör után ÚJRA kell dispatch-elni).

A javító kör ugyanazzal a motorral (`sonnet-impl`), a fenti leletlistával megy.
