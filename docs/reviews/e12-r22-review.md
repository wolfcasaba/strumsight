# Review — E12-R22 (Beta distribution, tester enrollment és feedback)

- **Kör:** `E12-R22` · **Branch:** `sonnet-impl/e12-r22-beta-distribution-and-feedback`
- **Reviewelt HEAD:** `958df30c` (base: a pre-flight commit `b2b37735`)
- **Motor:** `sonnet-impl` (Claude Sonnet 5) · **Reviewer:** Claude (Opus 5), független szem
- **Szerződés:** [ADR 0486](../adr/0486-beta-distribution-consent-and-redacted-diagnostics-bundle.md)
  D1–D7 + a brief §0.0.A R1–R9, §5, §6
- **Kötelező biztonsági review (risk = high):** [`e12-r22-review-security.md`](e12-r22-review-security.md)
  — VERDIKT: CHANGES REQUESTED

## 0. VÉGSŐ DÖNTÉS: **CHANGES REQUESTED** (1 BLOCKER, 3 MAJOR, 2 kért MINOR)

A gate ZÖLD — a saját, független futásomban is —, de a zöld gate itt is pontosan
azt takarta el, amire a review-protokoll való: **a szállított A3 cella csak azért
zöld, mert a hang-fixture csupa nulla bájt.** Valósághű (szinusz vagy véletlen) PCM
mellett a csomagoló a consentelt hangot **csendben megsemmisíti**, `exit 0`-val —
ez pontosan az a „néma csonkítás", amit az ADR 0486 D3 nevesítve tilt.

## 1. Amit MAGAM mértem (nem bemondásra)

| Mérés | Parancs | Eredmény |
|---|---|---|
| Független gate, izolált klón (`/tmp/review-e12-r22`, `958df30c`) | `tools/round-gate.sh test/tooling/beta_release_notes_test.dart test/tooling/diagnostics_storage_separation_test.dart` | **MINDEN GATE ZÖLD** (10/10): format, analyze, `beta_release_notes_test.dart` **44/44**, `diagnostics_storage_separation_test.dart` 3/3, architecture (12 allowlistelt eltérés, változatlan), secrets (4118 fájl, 0 találat), l10n (2298 üzenet), backend ruff format/check, backend pytest — `GATE_EXIT=0` |
| Scope-audit (ADR 0138) | `tools/scope-audit.py --repo /tmp/review-e12-r22 --brief docs/rounds/e12-r22-… --base b2b37735` | `Legacy scope audit OK (b2b37735..958df30c, 8 changed path(s), 0 generated/ignored)` — `lib/**`, `.github/**`, `lab_build.json`, `docs/adr/**`, `tools/**` érintetlen |
| Implementer-jelzés | `.codex-round-status` | `status=done`, `gate_shape=ok`, `scope_audit=ok`, `scope_audit_changed=8` |
| M1 reprodukció (saját, a security-jelentéstől függetlenül) | 1 s / 44,1 kHz szinusz WAV → csomagoló `--consent-diagnostics --consent-raw-audio` | `exit 0`, a klip **117 660 → 189** base64 karakter, a kimenet **nem dekódolható** (`binascii.Error`) |
| M2 reprodukció (saját) | 8 MB-os klip `events[0].wavBase64`-ben, CSAK `--consent-diagnostics` | `exit 0`, a hang **bekerül** a csomagba (11 184 812 karakter), a méret-korlát rá sem fut |

CI a review SHA-ján: Full Gate `33560917444`, Router CI `33560913492`, Backend CI
`33561184379` — a merge-kapu értékelése a javító kör utáni ÚJ SHA-n történik
(exact-SHA, ADR 0086 §2).

## 2. Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | A bundle alapból NEM tartalmaz nyers hangot | `beta_release_notes_test.dart:98`; az implementer valódi-sértés próbája (`_should_include_raw_audio` → `return True`) PIROSRA vitte A1-et és az A4 harmadik sorát, majd visszaállította (§10.3) | **TELJESÜL** |
| A2 | Token, e-mail, útvonal maszkolva | 4 osztály × több írásmód, rekurzívan mérve (security-jelentés D2 táblája); backend-oldali end-to-end cella (`test_diagnostics_redaction.py:79`) | **TELJESÜL** a specifikált osztályokra; a kulcs-szintű redakció hiánya N1 |
| A3 | Méret-korlát fölötti melléklet elutasított, nem csonkolt | küszöb-hármas cellák zöldek (5 242 879 / 880 / 881) | **NEM TELJESÜL a szándéka szerint** → **M1**: a cella csupa-nulla fixture-rel mér, valós klipen a tartalom csendben elvész |
| A4 | A négy consent-pár pontosan a R5 tábla szerint | mind a négy kombináció mérve, részleges fájl egyik hibaágon sem | **TELJESÜL** |
| A5 | Jegyzet bájtazonos + build-azonosító + fail-closed | 8 mutáció mind `exit 1`, a kulcsot nevesítve; két futás sha256-azonos eltérő `PYTHONHASHSEED`/`LC_ALL`/`TZ` mellett | **TELJESÜL** |
| A6 | `tester-consent.md` ↔ data-inventory, kétirányban | 12 mező / 3 útvonal (account_api 6, diagnostics_upload 3, share_export 3), szó szerinti egyezés; a teszt a szállított `DataInventory.parseFile`-t importálja (nincs 2. parszer), és van hiányzó-sor / kitalált-mező / rossz-útvonal cellája | **TELJESÜL** |
| A7 | `diagnostics_storage_separation_test.dart` változatlanul zöld | gate `[4]` 3/3 | **TELJESÜL** |
| A8 | Kanonikus, determinisztikus csomag-JSON | rendezett kulcsok, egyetlen záró `\n`, két futás bájtazonos | **TELJESÜL** |

## 3. Leletek

### BLOCKER

**B1 — a hibaüzenet a NEM redaktált session-részletet írja ki.**
`tool/release/build_diagnostics_bundle.py:171` (`f"malformed audio clip: {clip!r}"`),
kiírva `:235`. A `_raw_audio_byte_count` a redakció **előtt** fut (`main:224` vs
`:232`), tehát a teljes klip-dict — token, e-mail, abszolút útvonal, device-id
együtt — a triage-operátor termináljára és a CI-logba kerül. Ez megszegi az
`AGENTS.md` §5 „secret/PII nem kerülhet logba vagy hibaüzenetbe" határát és a
`docs/beta/tester-consent.md` állítását, hogy a csomagolás az egyetlen hely, ahol
a maszkolás garantáltan megtörtént. Reprodukció és tényleges stderr: security-jelentés B1.
**Irány:** a hibaüzenet index/kulcs szintű legyen (`audioClips[3]: missing "wavBase64"`),
bemeneti tartalom nélkül; mérje egy stderr-t vizsgáló cella (ma egyetlen teszt sem nézi).

### MAJOR

**M1 — a valósághű nyers hang CSENDBEN megsemmisül (D3 megsértése), és az A3 cella
degenerált fixture miatt zöld.** A base64 ábécé tartalmazza a `/`-t, így a
`_POSIX_PATH_PATTERN` (`:95`) belemar a `wavBase64` tartalmába (`:111`). Saját
mérésem: 1 s szinusz klip 117 660 → 189 karakter, `exit 0`, a kimenet nem
dekódolható. A gate azért zöld, mert a fixture `Uint8List(n)` → csupa `A` base64,
egyetlen `/` nélkül (`beta_release_notes_test.dart:56`). A méret-ellenőrzés
ráadásul a redakció ELŐTTI bájtszámon fut, tehát az „elfogadva" üzenet mögött
törmelék marad a lemezen.
**Irány:** a base64/opaque bináris mezőt ne érje sztring-redakció (nevesített
allowlist vagy dekódolt tartalmon futó vizsgálat); a csomagoló ellenőrizze, hogy a
kimeneti klip dekódolható és bájthossza változatlan — ha nem, az HIBA legyen; a
fixture legyen nem-degenerált (véletlen/szinusz PCM), különben a cella nem tud
pirosra váltani.

**M2 — a hang-réteg és a méret-korlát EGYETLEN legfelső szintű kulcsnéven áll.**
`:190` (`pop("audioClips")`) és `:164-176`. Saját mérésem: `events[0].wavBase64`-ben
elhelyezett 8 MB-os klip CSAK `--consent-diagnostics` mellett bekerül a csomagba, és
a korlát rá sem fut. A szállított kliens-alak ma fix, legfelső szintű kulcsot ír,
tehát a lelet **latens** — de a csomagoló bemenete a szerveren verbatim tárolt,
tetszőleges JSON, és a D1 a hang-réteget tartalmi, nem kulcsnév-alapú ígéretként
mondja ki.
**Irány:** rekurzív keresés minden `wavBase64` mezőre; `--consent-raw-audio` nélkül
MIND eltávolítva; a korlát az összes megtalált klip összegére. Cella: beágyazott
klip + csak diagnostics-consent → a kimenetben nincs `wavBase64`.

**M3 — korlátlan gzip-kicsomagolás nem megbízható bemeneten.** `:148-152`. Egy
2 MB-os feltöltés 2 GB-ra bomlik; mérve `MemoryError` nyers tracebackkel (nem a
tool hibacsatornáján). A `/diagnostics` végpontot csak az eldobható spam-gate
token védi.
**Irány:** inkrementális olvasás explicit, MÉRT felső korláttal (`read(limit+1)` →
`BundleError`), és korlát a bemeneti fájl méretére is.

### MINOR — ebben a körben kérem (olcsó és a kör saját témája)

**N1 — a JSON-kulcsok maguk soha nem redaktálódnak** (`:119-128`): a kulcs csak
osztály-kiválasztásra szolgál, a `_redact_string` csak értékekre fut. Egy
e-mail- vagy útvonal-kulcsú map PII-t visz a csomagba. Ütközés (két e-mail-kulcs
→ ugyanaz a maszk) determinisztikusan kezelendő — a D4 miatt hash nem használható,
tehát ütközésre `BundleError`.

**N2 — a kimeneti fájl világ-olvasható (0664), és a `--output` szimlinket követ**
(`:238`, ill. `generate_beta_notes.py:197`). A csomag consentelt tesztelői adatot
és `--consent-raw-audio` mellett nyers hangot hordoz.
**Irány:** `os.open(..., O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW, 0o600)`.

**NT1 (a B1 javításával egy helyen) — nem-`BundleError` kivételek nyers
tracebackként szöknek ki** (`:154-157`, `MemoryError`/`RecursionError`). A `main`
burkolja őket bemeneti tartalom nélküli `BundleError`-rá.

### NOTE — follow-up, NEM blokkol

- **NT2** — a jegyzet a manifest sztringjeit nyersen interpolálja Markdownba
  (`generate_beta_notes.py:137-165`); a manifest ma futásidejű, megbízható
  artefaktum, ezért NOTE.
- **NT3** — ismeretlen manifest-kulcs csendben elfogadott (a D5 ezt nem tiltja).
- **NT4** — túl-redakció URL-eken (`https:/[REDACTED:path]`); nem szivárgás,
  információvesztés a triage számára.
- **N3/N4 (a security-jelentésből, follow-upnak sorolva)** — az e-mail-osztály
  ASCII-only (IDN cím átmegy), és a titok-osztályt egyedül a `token`
  kulcs-részsztring definiálja (`apiKey`, `password`, `authorization` átmegy). Ez
  megfelel az ADR 0486 D2 betűjének, tehát nem szerződés-sértés; a
  `tester-consent.md` szövege viszont erősebbnek hangzik nála. Egy későbbi kör
  vagy a D2 bővítése, vagy a dokumentum-szöveg pontosítása.

## 4. Architektúra, termékhatárok, teszt-minőség

- **Termékhatárok (AGENTS.md §5):** nyers audio alapból nem hagyja el az eszközt
  (A1 ✅); rejtett hálózati kérés nincs (a két eszköz stdlib-only, `subprocess`,
  `eval`, `pickle`, `yaml.load`, hálózat: 0 találat); mic/lifecycle nem érintett.
  A secret-a-logban határ MEGSZEGVE → B1.
- **Architektúra:** `lib/**` nem változott, a `check_architecture` gate zöld,
  új dependency nincs.
- **Teszt-minőség:** 44 cella, `skip:` ág nincs (az egyetlen `skip:` találat a
  fejléc-kommentben áll, épp azt kimondva); az A6 kétirányú és a szállított
  parszert importálja; az implementer valódi-sértés próbája dokumentált és
  visszaállított. **Kivétel:** az A3 fixture degenerált → M1.
- **Fixture-higiénia:** valódi token/e-mail/tesztelői adat sehol; `example.test`
  fenntartott TLD és `fixture-*` szintetikus értékek.

## 5. Mit kérek a javító körtől

1. **B1** (blokkoló) + **NT1** — hibaüzenet bemeneti tartalom nélkül, ismeretlen
   kivételek burkolva; stderr-cella.
2. **M1** — a bináris/base64 payload ne essen sztring-redakció alá; a kimeneti klip
   dekódolhatóságát és bájthosszát a csomagoló ellenőrizze (eltérés = HIBA);
   nem-degenerált fixture, hogy az A3 cella tudjon pirosra váltani.
3. **M2** — tartalom-alapú hang-gate és összesített méret-korlát; cella beágyazott klipre.
4. **M3** — korlátos gzip-kicsomagolás, MÉRT konstanssal.
5. **N1**, **N2** — kulcs-szintű redakció ütközés-kezeléssel; `0600` + `O_NOFOLLOW`.

Minden javításhoz tartozzon cella, amely a mai (hibás) viselkedést PIROSRA fogja.
A szerződést lazítani (pl. a D3 korlát felpuhítása) tilos — a mérce nem mozdul.
