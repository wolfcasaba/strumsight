# E12-R12 review — Release fixture-korpusz és golden data

- **Kör:** `E12-R12` · **ág:** `sonnet-impl/e12-r12-release-fixture-corpus-and-golden-data`
- **Reviewer:** Claude (Opus 5, orchestrátor) — READ-ONLY, produkciós szerkesztés nélkül
- **Implementer:** `sonnet-impl` (Claude Sonnet 5), commit `0f958b6b`
- **Brief:** [`docs/rounds/e12-r12-release-fixture-corpus-and-golden-data.md`](../rounds/e12-r12-release-fixture-corpus-and-golden-data.md)
- **ADR:** [`0473`](../adr/0473-release-fixture-corpus-manifest.md)
- **Dátum:** 2026-08-29

## 1. Scope

`tools/scope-audit.py --repo … --brief … --base 79701f96` →
**`Legacy scope audit OK (79701f966bbb..0f958b6b93c4, 5 changed path(s), 0 generated/ignored)`**.

A diff pontosan az engedélyezett lista + a pre-flight ADR:

```
docs/adr/0473-release-fixture-corpus-manifest.md   | 123 +++++   (pre-flight, Claude)
docs/rounds/e12-r12-…md                            | 223 +++++-  (§0.0 revízió + §10 handoff)
docs/testing/release-fixture-corpus.md             | 105 ++++
test/fixtures/manifest.json                        | 389 ++++++++
test/tooling/fixture_manifest_test.dart            | 566 ++++++++
tool/check_fixture_manifest.dart                   | 424 ++++++++
```

`test/fixtures/**` MEGLÉVŐ adatfájlja, `test/ui/goldens/**`, `tool/ci/**`,
`lib/**`, `tools/**`, `.github/**` **nem** változott — a tilos zóna tiszta.
`dirty_files=1` a jelzésben: a futás utáni `git status --short` a
munkapéldányban ÜRES, tehát a jelzés pillanatában még nem commitolt §10-szakasz
azóta a `0f958b6b` commit része. Nincs elveszett munka.

## 2. Leletek

### F1 — MAJOR: az „unknown" licenc-helykitöltőt semmi nem fogja meg, és a teszt EZT rögzíti zöldként

**Hol:** `tool/check_fixture_manifest.dart:303–322` (`_readEntry`, csak
`trim().isEmpty` vizsgálat) és `test/tooling/fixture_manifest_test.dart:211–234`.

**Mit mértem.** A brief §6.1 mérce-mátrixának harmadik sora szó szerint:
„A licenc-hiány »unknown« értékkel átcsúszik → **A3**" — vagyis pontosan
ennek a hibás implementációnak kell az A3 cellát PIROSRA vinnie. Az ADR 0473 D4
és a brief §5.1 ugyanezt köti ki („Ismeretlen licenc = megállás, nem
»unknown«"). A leszállított cella ezzel szemben az ELLENKEZŐJÉT rögzíti:

```dart
_writeManifest(projectRoot, [ _entry(…, license: 'unknown') ]);
final report = checkFixtureManifest(projectRoot: projectRoot);
expect(report.isClean, isTrue, reason: report.format());   // ← zöldre pinnelve
```

A cella neve és kommentje a rést szándékként dokumentálja („a human review
concern, not a string the checker can distinguish"). Ez az a hibaosztály, amit
a brief kifejezetten tilt: a *szövegesen leírt* tartalmi előírás mellől
hiányzik a GÉPI mérce, sőt a hiány zöld cellává vált. A valódi manifestet
őrző, `unknown`-t kereső cella (`:259–276`) csak a MA committolt tartalmat
méri — egy jövőbeli kör „unknown"-ja azon átmegy, mert az a cella csak a
`license`/`source` mező szó szerinti `unknown` értékét nézi a *jelenlegi*
manifestben, a checker pedig egyáltalán nem nézi.

**Miért MAJOR és nem MINOR:** a kör EGYETLEN jogi kockázat-őre ez a mező. Egy
fail-closed licenc-kapunál a placeholder átengedése pontosan az a „zöld gate
mellett hamis biztonság", ami miatt az ADR 0447 a license-feloldást
fail-closedre írta elő.

**Javítás (a kör engedélyezett fájljain belül):**
1. `tool/check_fixture_manifest.dart` — a `license` és a `source` mező
   normalizált (trim + lowercase) értéke nem lehet placeholder. Legalább:
   `unknown`, `unspecified`, `n/a`, `na`, `tbd`, `todo`, `none`, `-`, `?`,
   `fixme`. Új `FixtureManifestIssueKind.placeholderLicense` (vagy a meglévő
   `missingLicense`/`missingSource` újrahasznosítása — a lényeg a nem-nulla
   kilépés).
2. `test/tooling/fixture_manifest_test.dart:211–234` — a cella FORDULJON meg:
   `license: 'unknown'` → `expect(report.isClean, isFalse)` + a kind
   ellenőrzése; ugyanez egy `source: 'n/a'` esetre.
3. A placeholder-lista legyen a checkerből EXPORTÁLT konstans, és egy cella
   mérje, hogy a lista minden elemére piros a checker (ne csak egyre).
4. `docs/testing/release-fixture-corpus.md` — a mezőleírásnál mondja ki, hogy
   a placeholder-értékek gépileg tiltottak, és ismeretlen licenc esetén a
   kimenet a `stopped` jelzés.

### F2 — NOTE: a manifest önkizárása helyes, és dokumentálva van

A `_walkFixtureFiles` a `test/fixtures/manifest.json`-t kihagyja a fából
(fixpont-probléma: a saját hash-e a saját tartalmától függne). Ez a D2
szövegében nem szerepel, de a §10 handoff kimondja, a
`docs/testing/release-fixture-corpus.md` rögzíti, és külön cella méri
(`:101–123`). Elfogadva; az ADR 0473 D2 szövegének utólagos bővítése nem
szükséges, mert a következmény-szakasz és a korpusz-dokumentum együtt lefedi.

### F3 — NOTE: az A6 nem kapott saját cellát, és ez helyes

Az A6 („`check_assets_test.dart` VÁLTOZATLANUL zöld") bizonyítéka a §7 gate
futása. Az implementer egy önhivatkozó cellát próbált (a keresett
sztring-literál a saját forrásában is szerepelt → mindig piros), majd
eltávolította és a §10-ben dokumentálta. A fájl valóban érintetlen
(`git diff --stat` fent), és a gate mindkét tesztet futtatta.

### F4 — NOTE: a valódi-sértés próba érvényes

Az A2 cella (`:126–160`) a VALÓDI `test/fixtures/song_trainer/midi/format0.mid`
bájtjait MÁSOLJA egy `systemTemp` projektbe, ott billenti az első bájtot, és a
másolat-projekten kap `checksumMismatch`-et; a záró `expect` az EREDETI fájl
bájtjait a próba előtti állapottal veti össze. Az eredeti fa érintetlen
(scope-audit: 0 változás a `test/fixtures/**` adatfájlokon).

### F5 — NOTE: a valódi korpusz a gate-en át MÉRVE van

A `:22–30` cella a VALÓDI repó-gyökéren futtatja a checkert
(`isClean == true` + `hasLength(48)`), tehát a committolt manifest 48
sha256-ja a valódi bájtokkal szemben minden gate-futáson igazolódik. Ez zárja
azt a kérdést, hogy az A7 kereszt-cella „csak átmásolt" hash-eket hasonlítana
össze: a hash-eket a tartalom validálja, a kereszt-cella pedig a védett
forrással való egyezést.

## 3. Acceptance

| # | Verdikt | Bizonyíték |
|---|---|---|
| A1 | ✅ | fa-bejárás + `hasLength(48)` a valódi gyökéren; „fixture nincs a manifestben" és „bejegyzés nincs a lemezen" cellák |
| A2 | ✅ | valódi-sértés próba (F4) + „size-only egyezés is piros" mátrix-cella |
| A3 | ⚠️ **F1** → ✅ a javító kör után (§5) | üres/hiányzó mező ✅; az „unknown" placeholder eredetileg ÁTMENT (F1), a `fa42dcb0` óta gépileg tiltott |
| A4 | ✅ | `test/ui/goldens/**` bejegyzés elutasítva + valódi manifest cellája |
| A5 | ✅ | `containsUserData` kötelező bool; `true` → hiba; a valódi 48 bejegyzés mind `false` |
| A6 | ✅ | a gate futtatta, a fájl érintetlen (F3) |
| A7 | ✅ | 30 song-fixture sha256 egyezik a védett forrással; a védett fájl nem módosult |
| A8 | ✅ | `/home/`, `/Users/`, `C:\` fragmentum-tiltás + valódi manifest cellája |

## 4. Verdikt

**CHANGES REQUESTED** — 1 MAJOR (F1). A javító kör az engedélyezett fájlokon
belül elvégezhető; a többi lelet NOTE, javítást nem igényel.
*(Az F1 a `fa42dcb0` javító körrel lezárva — a végső döntés a §6.)*

---

## 5. Javító kör utáni újra-ellenőrzés (2026-08-29, `fa42dcb0`)

**F1 — ZÁRVA.** Leletenként ellenőrizve a `101fb586..fa42dcb0` diffen
(`scope_audit=ok`, 4 változott fájl, mind az engedélyezett listán;
`tool/ci/**` és a `test/fixtures/**` adatfájlok érintetlenek):

1. `tool/check_fixture_manifest.dart` — új **exportált**
   `const placeholderProvenanceValues = {unknown, unspecified, n/a, na, tbd,
   todo, none, -, ?, fixme}` és új
   `FixtureManifestIssueKind.placeholderProvenance`. A `license` ÉS a `source`
   mező normalizált (`trim().toLowerCase()`) alakja is ellenőrzött; találat →
   `isClean == false`, a hibaüzenet az EREDETI (nem normalizált) értéket idézi.
2. `test/tooling/fixture_manifest_test.dart:211+` — a kifogásolt cella
   **megfordítva**: `license: 'unknown'` → `expect(report.isClean, isFalse)` +
   a `placeholderProvenance` kind ellenőrzése. A rést szándékként rögzítő
   kommentblokk törölve.
3. Új cellák: `source: 'n/a'`, valamint a teljes exportált lista végigjárása
   eredeti ÉS nagybetűs kezdetű alakban (`_shout`) — tehát a lista bővítése
   automatikusan mércét is kap, nem marad „egy elemre mért" őr.
4. `docs/testing/release-fixture-corpus.md` — a mezőleírás kimondja a gépi
   tiltást és azt, hogy ismeretlen licenc esetén a helyes kimenet a `stopped`
   jelzés.

A valódi korpusz a szigorítás után is tiszta: `dart run
tool/check_fixture_manifest.dart` → `Fixture manifest OK (48 fixture(s)).`, és
a `tools/round-gate.sh test/tooling/fixture_manifest_test.dart
test/tooling/check_assets_test.dart` mind a hét lépése zöld (format, analyze,
mindkét teszt külön, architecture, secrets, l10n).

**Nincs nyitott BLOCKER/MAJOR/MINOR.**

## 6. VÉGSŐ DÖNTÉS: APPROVED

A merge feltétele változatlanul a teljes CI-kapu (Full Gate + Router CI)
`success` a merge SHA-n.
