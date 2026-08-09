# E99-R05 (GOV-06b) — Dedikált biztonsági/adatvédelmi review

- **Kör:** `codex/e99-r05-gov-06b-bpm-metric-fix` @ `a3f54bc7`
- **Ok:** a brief `ai-router` blokkja `risk = "high"` → dedikált
  `security-reviewer` review kötelező (AGENTS.md §15.1).
- **Reviewer:** `security-reviewer` ágens (izolált `/tmp/review-e99-r05`
  klónban, READ-ONLY) · Dátum: 2026-08-09
- **Verdikt: PASS**

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

**Diff-scope (igazolt):** pontosan 5 fájl, `lib/` érintetlen; `ml/data/`,
`eval_real_sessions.py`, `eval_guitarset.py` nem módosult. Munkafa tiszta,
nincs commitolt `.json`/`.wav`/`.strums` adat-artefaktum.

**Fenyegetési modell:** önálló benchmark/mérés eszközlánc, operátor futtatja
a boxon. Bemenetek (korpusz-könyvtár, tempó-referencia JSON-útvonal)
build/futásidőben operátor-kontroláltak, nincs megbízhatatlan hálózati
bemenet. Nincs LLM/provider/prompt/tool-calling → a prompt-injection felület
N/A (ugyanaz, mint a GOV-06 testvérkörben).

## Ellenőrzött pontok és bizonyíték

**1. `ml/chords/tempo_reference.py` (ÚJ):**
- Hálózat: nincs (grep `http|requests|urllib|socket` → 0 találat).
- Shell/kód-injekció: nincs `subprocess|os.system|shell|eval(|exec(`.
  `librosa.load` közvetlenül olvassa a WAV-ot.
- Path-traversal zárt: `glob("*_phone.wav")` nem rekurzív, csak közvetlen
  gyerekek; a JSON-kulcs a `wav.name` basename-ből (`_recording_stem`)
  készül, suffix-validációval (`ValueError` egyébként) — könyvtár-komponens
  nem szivárog a kulcsba.
- Fail-closed: üres korpusz → `SystemExit`; rossz suffix → `ValueError`;
  nem-véges/≤0 tempó → kihagyva és stdout-on nevesítve.
- Titok: nincs credential-kezelés.

**2. `tool/benchmarks/real_audio_dsp_baseline.dart` (`_readTempoReference`
és a tempó-függvények):**
- A `REAL_AUDIO_DSP_TEMPO_REFERENCE` compile-time `--dart-define` —
  build-időben operátor-kontrollált, a `File` csak olvasva.
- Fail-closed rossz bemenetre: nem-objektum vagy nem-`num`/≤0 érték →
  `FormatException`, a per-felvétel ciklus ELŐTT — romlott referencia
  megszakítja az eszközt, nem gyárt hamis metrikát.
- Nincs osztás nullával (a referencia-értékek >0-ra validáltak).
- Hibaüzenet csak az anonimizált `recording_NNNN` kulcsot echózza vissza —
  nincs titok-szivárgás.
- Nincs hálózati hívás az eszközláncban.

**3. Titkok a diffben:** grep (`api_key|secret|token|bearer|private key|
AKIA|ghp_|xox…`) → nincs találat.

**4. Korpusz/eval-scriptek érintetlensége:** igazolt (`ml/data/`,
`eval_real_sessions.py`, `eval_guitarset.py` nincs a diffben).

**5. Prompt-injection a doksikban:** nincs beágyazott, agentnek címzett
utasítás. Az „ADR 0212 felülírja ADR 0199" szokványos governance-próza,
nem utasítás.

## AGENTS.md §5.5 — a kör nettó pozitív a false-confidence határra

A kör célja pontosan egy korábbi §5.5-sértő túlállítás **visszavonása**: a
GOV-06 „45,067 BPM tempóhiba" valójában pengetés-sűrűség volt, nem tempó. Az
új riport explicit leminősíti a gyenge jelet („a referencia is automatikus
beat-tracker, nem kézzel annotált igazság"; „A BPM ezen a korpuszon nem
mérhető, mert nincs validált tempó-annotáció"). Ez a nyílt leminősítés maga
a §5.5-megfelelés.

## Termékhatárok (AGENTS.md §5) — mind rendben

Nyers audio nem hagyja el az eszközt (N/A, nincs hálózat); rejtett hálózati
kérés nincs; titok/token/nyers audio logba/hibaüzenetbe nem kerül; nincs
futásidejű cloud/community funkció; gyenge confidence biztos állításként —
nettó pozitív (a kör pontosan ezt javítja).

## NOTE-ok (nem blokkoló)

- **NOTE-1 — repró-parancsok gép-relatív útvonalai**
  (`docs/eval/real-audio-dsp-baseline.md:46-47,50`): `~/audio-venv/bin/python`,
  `~/flutter/bin/flutter`, `/tmp/tempo_reference.json`. Nem titkok, `~`-t
  használ (tisztább, mint a GOV-06 build-path NOTE-ja); eval-riportban
  elvárt repró-tartalom. Nincs teendő.
- **NOTE-2 — bizalmi határ előretekintő megjegyzése**
  (`tool/benchmarks/real_audio_dsp_baseline.dart:402-417`): a
  `_readTempoReference` `jsonDecode`-ja méret-/mélység-korlát nélkül
  parse-ol. Ma nem lelet (a referencia-JSON operátor-generált, lokális
  fájl). Csak akkor válna relevánssá, ha az eszközt valaha megbízhatatlan
  (pl. hálózatról letöltött) referenciára állítanák. Jelen körben nincs
  teendő.

## Reprodukálhatóság (a reviewer által futtatott parancsok)

- `git diff --name-only origin/main...HEAD` → az 5 engedélyezett fájl.
- `grep -Ei 'http|dio|socket|websocket|Uri.|HttpClient|requests|urllib|
  subprocess|os.system|shell|popen|eval(|exec('` a két kódfájlon → csak
  lokális I/O / librosa / basename-minta.
- Titok-grep a teljes diffen → nincs.
- `base64|data:audio|;base64,` a doksikon → nincs.
- Injekció-frázis grep (EN+HU) a doksikon → csak governance-próza.
- `git status --porcelain` → tiszta.

## Merge-döntés

Biztonsági szempontból **nincs akadálya** a merge-nek. A fő review (F1,
MAJOR — a §10 handoff hiányos raw-output) attól függetlenül nyitva marad;
ez a review azt nem érinti.
