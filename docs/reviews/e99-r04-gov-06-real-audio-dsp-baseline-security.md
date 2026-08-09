# E99-R04 (GOV-06) — Biztonsági / adatvédelmi / prompt-injection review

- **Kör:** `E99-R04` (GOV-06) — valós-audio DSP baseline mérés (measurement round, governance)
- **Branch:** `codex/e99-r04-gov-06-real-audio-dsp-baseline`
- **Diff-tartomány:** `dc201524` (pre-flight) → `d3c8a516` (fej) — 4 fájl, +1657/−9
- **Reviewer:** dedikált `security-reviewer` ágens (AGENTS.md §15.1 — kötelező, mert a brief `risk = "high"`). READ-ONLY, production/teszt fájlt nem módosított.
- **Dátum:** 2026-08-09
- **Verdikt:** **PASS** — nulla CRITICAL/BLOCKER/MAJOR/MINOR. Két forward-looking NOTE + egy pozitív megfigyelés.

## Súlyossági összegzés

| Súlyosság | Darab |
|---|---|
| CRITICAL | 0 |
| BLOCKER | 0 |
| MAJOR | 0 |
| MINOR | 0 |
| NOTE | 2 |

## Scope-audit

`git diff --name-status dc201524..d3c8a516` — pontosan a brief 4 engedélyezett
útvonala, semmi azon kívül:

| Állapot | Fájl |
|---|---|
| A | `docs/eval/real-audio-dsp-baseline.md` |
| M | `docs/rounds/e99-r04-gov-06-real-audio-dsp-baseline.md` (brief handoff-kitöltés) |
| A | `test/tooling/real_audio_dsp_baseline_test.dart` |
| A | `tool/benchmarks/real_audio_dsp_baseline.dart` |

`git diff --stat dc201524..d3c8a516 -- lib/` **üres** — a `lib/` alatt zéró sor
változott, a `ClipAnalyzer` bájtra azonos. `pubspec.yaml`/`pubspec.lock`
érintetlen. Scope-fegyelem: **OK**.

## Mit vizsgált a review és mi volt a bizonyíték

Ez egy mérési kör: egy önálló Dart CLI (`tool/benchmarks/real_audio_dsp_baseline.dart`)
a változatlan `const ClipAnalyzer()`-t futtatja 82 helyi, nem-verziózott
telefonos WAV-on, és aggregált metrikát commitol. Nincs benne LLM/provider/
tool-calling/prompt → az ADR 0131–0136 prompt-injection felület **nem
alkalmazható**; a releváns analóg a „külső korpusz adatként kezelése".

**1. Hálózat / exfiltráció — bizonyítottan zéró.** A tool importjai:
`dart:convert`, `dart:io`, `package:crypto/crypto.dart`,
`package:strumsight/{core/audio/codec/wav_decoder, features/analyze/engine/clip_analyzer, features/analyze/model/analyze_result}`.
Grep `http|dio|socket|Uri.parse|HttpClient|WebSocket|supabase|upload` a
`tool/`+`test/`+`docs/eval/` diffben: **nincs valódi találat**. A riportban
látszó `dio 5.10.0` a beágyazott `pub outdated` kimenet része (az app meglévő
tranzitív függősége), **nem** a tool használata. §5.1/§5.2: OK.

**2. Secret/credential — nincs.** Grep
`api_key|secret|token|password|bearer|authorization|private_key|-----BEGIN|credential`
a teljes diffben: **nincs találat**. Az egyetlen hexa string a korpusz
SHA-256 ujjlenyomata — publikus tartalom-hash, nem titok. §5.3: OK.

**3. Nyers audio a commitolt riportban — nincs.** Grep
`base64|data:audio|;base64,` a `docs/eval/real-audio-dsp-baseline.md`-ben:
**nincs találat**. A 872 soros riport tartalma: aggregált százalékok,
per-label support/precision/recall, anonimizált stemek (`recording_1001` …
`recording_4028`), a korpusz SHA-256-ja, és egy numerikus BPM-tábla (stem + 4
szám). Nincs nyers audio, nincs PII, nincs szabad szöveg. A `corpus.path` a
commitolt JSON-ban relatív `ml/data/klangio`, nem szivárogtat abszolút/
érzékeny útvonalat. §5.1: OK.

**4. Külső korpusz adatként, fail-closed (§5.1 adatforrás-fegyelem).** A
`.strums` parse: soronként tab-split, **pontosan 3 mező** kell (különben
`FormatException`), a 0. mező `double >= 0` (különben `FormatException`), a
2. mező (címke) illesztve a `^([A-G](?:#|b)?)-(major|minor)$` regexre
(különben `FormatException`), üres fájl → dobás. Az 1. mezőt a kód **nem
használja**. Nincs `eval`, nincs dinamikus dispatch, nincs fájltartalom-alapú
kódfuttatás. A címke kizárólag Map-kulcsként és a riportba írva jelenik meg.
Fail-closed minden eltérésre. **OK.**

**5. Path traversal — strukturálisan zárt.** A WAV-út összefűzése
(`stem = strum.uri.pathSegments.last`-ból — a `pathSegments.last` **levágja a
könyvtár-komponenseket**), a `strum` egy **nem-rekurzív**
`listSync().whereType<File>()` közvetlen korpusz-gyermeke. POSIX fájlnév nem
tartalmazhat elválasztót, így a `${corpus.path}${sep}${stem}_phone.wav` mindig
közvetlen korpusz-gyermek. Nem sikerült olyan bemenetet konstruálni, ami kilép
a korpuszból. A korpusz maga operátor-adott (CLI arg / `--dart-define`),
helyi, nem hálózati bemenet. **OK** (pozitív megfigyelés — lásd lent).

**6. Erőforrás-kezelés.** Minden olvasás `readAsLinesSync`/`readAsBytesSync`
(teljes olvasás + zárás, nincs lógó handle). **Nincs fájl-írás sink** (grep
`writeAsString|openWrite|\.create\(`: nincs) — csak `stdout` (JSON) + `stderr`
(progress); a commitolt riport a stdout ember által kurált átemelése. A
ciklusok korlátosak. Nincs végtelen ciklus. Egyszeri CLI, fájlonként
memóriában egy WAV. **OK.**

**7. Checksum-hitelesség (§5.5 — nem félrevezető biztonsági látszat).** A
`_corpusChecksum` sorbarendezett `filename\n`+bájt digestet ad. A riport
ujjlenyomatként mutatja: `"sha256": …`, `"versionControlled": false`, és a
próza kimondja: „A korpusz nincs verziókövetve, ezért a mérés ma ezen a boxon
kívül nem reprodukálható." **Nem** állítja kriptográfiai integritás-/
tamper-garanciának. Az eredményeket a korpuszra szűkíti („nem általános zenei
állítások"). Nincs túlállítás. **OK.**

**8. Brief-módosítás.** A `docs/rounds/…` diff kizárólag a §10 handoff
kitöltése (fájlok, parancsok, mért számok, §6.1 valódi-sértés próba nyers
kimenete, A1 `lib/`-üres bizonyíték). Dokumentáció-only, engedélyezett
útvonalon. **OK.**

## Leletek

Nulla blokkoló, MAJOR és MINOR lelet.

### Pozitív megfigyelés (nem lelet)

- **`tool/benchmarks/real_audio_dsp_baseline.dart:429-433, 411-417`** — a
  fájlnév-kezelés `uri.pathSegments.last` + nem-rekurzív `listSync` révén
  strukturálisan zárja a path traversalt. Defenzíven helyes.

### NOTE-1 (hygiene, forward-looking — nem blokkol)

- **`docs/eval/real-audio-dsp-baseline.md:88`** — a beágyazott csonkítatlan
  futási kimenet egy lokális abszolút build-útvonalat commitol:
  `00:00 +0: loading /home/ubuntu/ss-codex-e99-r04/tool/benchmarks/…`.
  **Failure scenario:** a repóba kerül a build-környezet könyvtárszerkezete
  és az `ubuntu` felhasználónév. **Nem** §5.3 sértés — nem secret/token/
  kulcs/nyers audio (generikus cloud-username, nincs credential), ezért NOTE,
  nem BLOCKER. **Irány:** a riport kurálásakor normalizáld/töröld a
  build-path „loading …" sort (az érdemi mérési kimenet nem sérül).
  **Státusz:** OPEN (opcionális).

### NOTE-2 (forward-looking — nem blokkol)

- **`tool/benchmarks/real_audio_dsp_baseline.dart:445-447, 526-531, 261`** —
  `_SkippedRecording.error = error.toString()`, ami a `skippedRecordings`
  alatt a riportba kerül. **Failure scenario:** a `_readStrums`
  `FormatException`-jei tartalmazzák a hibás `.strums` sort/címkét (pl.
  `unsupported ground-truth label: <nyers>`), így korpusz-eredetű szöveg
  átfolyhat a commitolt riportba. Ebben a futásban `skipped = []`, tehát
  **semmi nem szivárgott**, és a `.strums` szerkezetileg nem érzékeny
  (időbélyeg + akkordcímke). **Irány:** ha egy jövőbeli korpusz `.strums`-
  fájljai szabad/érzékeny szöveget hordoznának, a skip-error stringet
  redaktáld a kurálás előtt. **Státusz:** OPEN (nagyon alacsony prioritás).

## Nem tárgyalható termékhatárok (AGENTS.md §5) — ellenőrzés

| Szabály | Állapot | Bizonyíték |
|---|---|---|
| §5.1 Nyers audio/kamera nem hagyja el az eszközt | **OK** | zéró hálózati sink; riport = aggregált metrika + anonimizált stem, nincs nyers audio/base64 |
| §5.2 Kijelentkezve/diagnostics-off nincs rejtett kérés | **OK (n/a)** | offline CLI dev-tool, zéró hálózat, app-runtime út érintetlen |
| §5.3 Secret/token/nyers audio nem kerül logba/commitba | **OK** | 0 secret a diffben; SHA-256 = publikus ujjlenyomat; NOTE-1 build-path nem secret |
| §5.4 Cloud/community nem rontja az offline élményt | **OK (n/a)** | végig helyi fájl-I/O |
| §5.5 Gyenge confidence nem biztos állításként | **OK** | riport a korpuszra szűkít; checksum = identitás, nem integritás; nincs túlállítás |

## Gate-bizonyíték (a brief §10 állításai)

A `test/tooling/real_audio_dsp_baseline_test.dart` szintetikus contract-teszt
(fixture-alapú, a korpuszra nem hivatkozik). A round-gate/CI-futás
verifikációja funkcionális/merge-felelősség az orchesztrátornál (lásd a
funkcionális review: `e99-r04-gov-06-real-audio-dsp-baseline-review.md`) —
biztonsági szempontból a fenti 8 pont a bizonyíték. A prompt-injection és
import/ellátási-lánc felület nem érintett (nincs új dependency: `crypto:
^3.0.7` már deklarált, pubspec érintetlen).

## Verdikt

**PASS.** A GOV-06 mérési kör tiszta, alacsony felszínű: helyi fájl-I/O only,
zéró hálózat, zéró secret, a `lib/`/`ClipAnalyzer` bájtra változatlan, a scope
pontosan a 4 engedélyezett útvonal. A külső korpuszt fail-closed adatként
parse-olja, a fájlnév-összefűzés path-traversal-biztos, a checksum
identitásként (nem integritásként) van kommunikálva, és a commitolt riport
csak aggregált metrikát tartalmaz, nyers audio nélkül. A kör biztonsági/
adatvédelmi szempontból **mergelhető**; a két NOTE opcionális follow-up, nem
blokkol.
