# E08-R02 — Security / Adatvédelmi / Prompt-injection Review

- **Kör:** `E08-R02` — Kanonikus tanulási esemény-szerződések (Chapter 9, Epic 8 Gamification)
- **Branch:** `codex/e08-r02-canonical-activity-events`
- **Reviewer:** Claude (security-reviewer agent, READ-ONLY) · **Dátum:** 2026-08-19
- **Kockázat (brief):** `high` → kötelező biztonsági review (AGENTS.md §15.1)
- **Verdikt:** **APPROVED (PASS)** — 0 CRITICAL · 0 BLOCKER · 0 MAJOR · 1 MINOR · 4 NOTE

> **Megjegyzés a futtatásról:** ennek a review-nak egy ELSŐ futása (kb. 20 perccel
> korábban) egy elavult worktree-snapshotot vizsgált (az orchesztrátor akkor még
> nem pusholta az implementer commitját az origin-re), és ezért téves BLOCKER-t
> jelentett ("a kód hiányzik az ágról"). Az orchesztrátor pusholta a hiányzó
> commitot, majd EBBEN a friss futásban a reviewer a GitHub origin-ról
> KÖZVETLENÜL klónozva (nem a helyi hub-ból, nem worktree-ből) igazolta a
> branch valós tartalmát, mielőtt bármit állított volna — lásd §0.

## 0. Klón-hitelesítés (a korábbi téves BLOCKER feloldása)

Friss klón közvetlenül a GitHub origin-ról:

```
git clone --branch codex/e08-r02-canonical-activity-events https://github.com/wolfcasaba/strumsight.git <clone>   → exit 0
git -C <clone> log --oneline -5:
  3b63029d docs(reviews): E08-R02 correctness review — APPROVED
  95ddec13 feat(gamification): add canonical learning activity contracts
  af86bc59 docs(gamification): prepare E08-R02 canonical activity event contracts
  1a051d85 chore(pipeline): E08-R01 done (ADR 0087)
git -C <clone> rev-parse HEAD → 3b63029d40f19d0593d03a4df7a0832e25f9494a
```

A branch-tip a várt `3b63029d`, HEAD~1 az implementáció (`95ddec13`), HEAD~2
a pre-flight (`af86bc59`). Az implementáció **jelen van**
(`lib/features/gamification/domain/activity/*.dart` létezik). A merge-base
`origin/main`-nel = `1a051d85` (= main tip). A diff 10 fájlja pontosan a
brief `allowed_paths`-a + a review-reportok. **A korábbi „a kód hiányzik"
BLOCKER egy elavult snapshot műterméke volt; ezen a friss klónon nem
reprodukálható.**

## 1. Összegzés

Tiszta Dart domain-típusok + JSON (de)szerializáció. **Nincs** storage-írás,
hálózati hívás, UI, logging, analytics vagy cross-feature import (grep-pel
igazolva). A deszerializáló út végig **fail-closed**, a nem-megbízható JSON
nem okoz crasht/DoS-t, a decode ugyanolyan szigorú, mint a konstrukció. A
`Random`/`DateTime.now()` tilalom valósan kikényszerített (standalone Dart
reprodukcióval igazolva). Nincs PII, nyers audio/kamera-adat, secret a
típusokban vagy a JSON alakban. Nincs prompt-injection minta vagy rejtett
vezérlő-karakter a dokumentumokban. Egyetlen érdemi lelet egy **latens
guard-teljességi hézag** (MINOR), amely ma semmit nem sért.

## 2. Termékhatár-audit (AGENTS.md §5)

| # | Határ | Verdikt | Bizonyíték |
|---|---|---|---|
| 1 | Nyers audio/kamera-frame nem hagyja el az eszközt | N/A / tiszta | A típusok mezői opak `eventId`, `occurredAt`, `epochDay`, `source`/`trust` (enum), `schemaVersion`, `duration`, `score`. Nincs `Uint8List`/audio/frame mező. |
| 2 | Kijelentkezett/diagnostics-off állapotban nincs rejtett hálózati kérés | tiszta (lásd MINOR-1) | Grep: nincs `Dio`/`http`/`HttpClient`/`Socket`/`Supabase` a domainben. |
| 3 | Secret/token/nyers adat nem kerül logba/hibaüzenetbe/commitba | tiszta (lásd NOTE-1) | Grep: nincs `print`/`debugPrint`/`log`/logger/secret-token/base64-blob. Fixture-ök szintetikusak. |
| 4 | Cloud/community funkció nem rontja az offline alapélményt | N/A | Nincs cloud/community érintés. |
| 5 | Gyenge confidence nem jelenik meg biztos állításként | tiszta | `score`∈[0,1] + `EvidenceTrust` hűen hordozza a bizalmi fokot; decode fail-closed, nem tud trustot „felminősíteni". |

**Prompt-injection / importált tartalom / ellátási lánc:** N/A ebben a
körben (nincs AI-provider/tool-hívás/fájl-IO/új dependency); rejtett
vezérlő-karakter és injection-minta scan a 9 diff-fájlon: 0 találat.

## 3. Deszerializáló út — DoS/crash-elemzés

`LearningActivityEvent.fromJson` → `_DecodedEvent.fromJson` → `_require*` →
altípus `_fromDecoded` → **a validáló public factory** → `_validateEventFields`
végig **fail-closed**: nem-Map json, nem-String kulcs, rossz ISO időbélyeg,
hiányzó/rossz típusú mező, ismeretlen `type`, ismeretlen `source`/`trust` név
— mind dob. A decode a PUBLIC factory-t hívja (nem a privát `const ._`-t),
tehát egy ellenséges JSON ugyanúgy elutasításra kerül, mint egy rossz
konstruktor-hívás. Nincs DoS-amplifikáció: nincs rekurzió, nincs
nested-bejárás, az allowlist-scan O(8)/O(5), a domain nem hív `jsonDecode`-ot
(a hívó már materializált Mapet ad át).

## 4. `Random`/`DateTime.now()` tilalom — a replay/dedup-védelem alapja

Standalone Dart-reprodukcióval igazolva: a valós domain tiszta, a guard
ténylegesen tüzel `DateTime.now(`/`Random(`/framework-import valódi
sértésre, komment-only említésre nem. A caller-adta, stabil `eventId`
invariáns (ADR 0329 §5.3) ténylegesen védett.

## 5. Megállapítások

### MINOR-1 — A gamification domain-purity guard marker-listája hiányos: `dart:io` / `dart:convert` / `package:dio/` / `package:http/` nincs benne

- **Fájl:sor:** `test/core/architecture_dependency_test.dart` a
  `_gamificationImportUriMarkers` konstans és a hozzá tartozó guard-csoport;
  az ok: `tool/check_architecture.dart` `_isSharedDomain()` csak
  `lib/core/music/`, `lib/core/audio/codec/`, `lib/features/practice/domain/`
  prefixet fed — `lib/features/gamification/domain/`-t nem, így a checker
  saját `package:dio/`-tiltó ága erre a fára nem fut, és az E08-R02-ben
  hozzáadott önálló marker-lista (Flutter/Riverpod/shared_preferences/
  flutter_secure_storage/sqflite/dart:ui) sem tartalmaz hálózati/fájl-IO
  markert.
- **Failure scenario (reprodukálva standalone Dart-tal):** egy jövőbeli kör
  fájl-/hálózati sinket ad a `lib/features/gamification/domain/` alá (pl.
  `import 'dart:io';` file-cache, `import 'package:dio/dio.dart';` a Kör 4
  outbox-sync számára) — a guard erre NEM tüzel, a domain némán
  hálózati/fájl-sinket kap, miközben a szerződés „tiszta Dart, nincs
  storage/hálózat"-ként hirdeti magát.
- **Hatás ma:** nincs — mind a 4 domain-fájl tiszta, csak testvér-import.
  Latens, nem aktív határsértés.
- **Javasolt irány:** vedd fel a `dart:io`, `dart:convert`, `package:dio/`,
  `package:http/` markereket a `_gamificationImportUriMarkers` listába egy
  következő körben, mielőtt a Kör 3 (ledger) / Kör 4 (outbox) sink-hordozó
  szomszédot hoz a domain mellé.
- **Státusz:** OPEN (follow-up, nem blokkolja ezt a merge-öt — MINOR)

### NOTE-1 — A decode-hibaüzenetek visszaadják a nyers mező-értéket (`ArgumentError.value(value, …)`)

Ma nulla kockázat (opak azonosítók, enumok, számok, ISO-időbélyeg; nincs
logging sink a diffben). Forward: ha egy jövőbeli mező user-eredetű
szabadszöveget hordozna, és egy jövőbeli hívó logolná a kivételt, a nyers
érték logba kerülhetne (AGENTS.md §5 #3). Javasolt: amint user-eredetű adat
elérheti ezeket a dekódolókat, a hibaüzenet a mező NEVÉRE hivatkozzon, ne az
ÉRTÉKÉRE.

### NOTE-2 — Az `epochDay` nem-megbízható JSON-ból validáció nélkül elfogadott

`_validateEventFields` nem ellenőrzi `epochDay`-t (sem tartományt, sem
`occurredAt`-konzisztenciát). Ma ártalmatlan (nincs fogyasztó). Javasolt: a
Kör 3 ledger napi bucketing-je `occurredAt`-ból származtassa a napot, ne a
szabad `epochDay` wire-mezőből, vagy validáld `epochDay`-t `occurredAt`
ellen konstrukciókor.

### NOTE-3 — A fail-closed elutasító ágaknak nincs dedikált negatív tesztjük

A nem-objektum JSON, nem-String kulcs, rossz időbélyeg, ismeretlen
`source`/`trust` allowlist-elutasítás mind helyesen dob ma, de nincs
dedikált teszt rájuk — egy jövőbeli refaktor csendben elveszíthetné a
fail-closed tulajdonságot anélkül, hogy bármelyik meglévő teszt pirosra
váltana. Javasolt: negatív-decode tesztek felvétele egy jövőbeli körben.

### NOTE-4 — Enum wire-formátum a Dart `.name`-en (a correctness-review N2 biztonsági szemmel megerősítve)

Biztonsági szemből nem szivárgás (enum-név, nem PII/secret). Integritási
forward-kockázat, amit a correctness review N2-je már felvett (ADR 0257 §3
hivatkozással) — independensen megerősítve, nem duplikált külön leletként.

## 6. A correctness review ellenőrzése

Nem fogadtam el bemondásra; a biztonság-releváns állításokat (A6/A2
valódi-sértés próbák, „nincs cross-feature import", enum `.name` wire)
független standalone-reprodukcióval és grep-alapú audittal igazoltam. A
correctness review a MINOR-1 guard-hézagot nem azonosította — ez ennek a
rétegnek a hozzáadott lelete.

## Merge-döntés

Nem tárgyalható termékhatár nem sérül; nincs CRITICAL/BLOCKER/MAJOR. **A
biztonsági review nem blokkolja a merge-öt.** A MINOR-1 latens guard-hézag a
Kör 3/4 sink-szomszéd megjelenése ELŐTT javítandó (nem e körben blokkoló); a
NOTE-ok forward follow-upok.
