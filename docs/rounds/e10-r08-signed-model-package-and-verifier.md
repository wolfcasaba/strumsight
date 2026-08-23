# E10-R08 — Aláírt modellcsomag-specifikáció és Dart-oldali verifier

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 8
- **Kör-azonosító:** `E10-R08`
- **Branch:** `<motor>/e10-r08-signed-model-package-and-verifier`
- **Előfeltétel:** `E10-R05` merge-elve (a natív runtime választástól — Kör 6/7 — FÜGGETLEN, lásd §0.0)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0423` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/ai_tutor/application/context/tutor_context_snapshot.dart` `canonicalJson`/`_canonicalMap` mintáját — ez a MEGLÉVŐ kanonikus-JSON precedens a projektben, amit ez a kör közös, újrafelhasználható segédfüggvénnyé emel. Eltérésnél §0.0 brief-revízió.

## 0.0 Hardver/scope-korlát (batch-prep megjegyzés) — miért PENDING, nem HOLD

A SDD Kör 8 eredeti fájllistája tartalmazza az `android/app/src/main/kotlin/.../PackageVerifier.kt` natív fájlt is — ezt a brief **szándékosan kihagyja** az `allowed_paths`-ból (ugyanaz a hardver/CI-infra korlát, mint a Kör 6/7/13-nál). A csomag-formátum és az aláírás-ellenőrzés kriptográfiai LOGIKÁJA azonban NEM függ a runtime-választástól (a manifest formátum §8 szerint runtime-agnosztikus) — ezért ez a kör TELJES EGÉSZÉBEN Dart-oldalon, futtatható és tesztelhető a natív réteg nélkül is. A natív Kotlin tükörkép egy jövőbeli, a Kör 7/13 native-infrastruktúrájával együtt nyíló körnek marad — ez NYITOTT, dokumentált tartozás, nem hallgatólagos scope-csökkentés.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "signature verification canonical json checksum quarantine"` → nincs közvetlen StrumSight-precedens signature-verifikációra (a `TutorContextSnapshot.canonicalJson` kulcs-rendezéses mintája az egyetlen rokon kód, de az NEM aláírás-ellenőrzés, csak determinisztikus szerializáció) — ez az ELSŐ kriptográfiai biztonsági réteg a projektben.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/security/canonical_json.dart",
  "lib/core/security/signed_manifest_verifier.dart",
  "lib/core/ai/model_package_manifest.dart",
  "test/core/security/canonical_json_test.dart",
  "test/core/security/signed_manifest_verifier_test.dart",
  "test/fixtures/local_ai_packages/",
  "docs/rounds/e10-r08-signed-model-package-and-verifier.md",
]
gate_tests = [
  "test/core/security/signed_manifest_verifier_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** egyik `allowed_paths` sem egyezik szó szerint a `high_risk_path_fragments` listával, de a `crypto`/`signature` kategóriával azonos a kockázati profil: egy hibás implementáció engedne aktiválni egy manipulált modellcsomagot, ami a teljes Offline AI supply chain integritását sértené.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

A modell csak verziózott, ellenőrzött és aláírt csomagból legyen aktiválható — a kriptográfiai és séma-validációs logika teljes egészében Dart-oldalon, natív réteg nélkül tesztelhető.

## 2. Jelenlegi állapot — mért tények

- `lib/core/security/` **nem létezik** — ez teljesen ÚJ infrastruktúra.
- A `TutorContextSnapshot.canonicalJson`/`_canonicalMap` (`lib/features/ai_tutor/application/context/tutor_context_snapshot.dart`) egy LOKÁLIS, nem megosztott kanonikus-JSON implementáció — ez a kör mintaként veszi, de NEM importálja (a `core/security` nem függhet `features/ai_tutor`-tól, lásd Kör 2 §0.0 core→features tiltás).
- A Kör 2 (E10-R02) `ModelPackageDescriptor`-t már definiálta a `lib/core/ai/`-ban — ez a kör a MANIFEST parsolását (`ModelPackageManifest`) adja hozzá, ami a descriptor-t termeli.

## 3. Scope

**Benne van:** manifest schema + descriptor parser · canonical JSON előállítás golden fixture-ökkel · signature verification (Dart `package:cryptography` vagy ekvivalens auditált könyvtár, pinned public keyring) · streaming fájlméret- és SHA-256 ellenőrzés · progress-reporting és cancellation-képes verifier · quarantine állapot hibás package-hez · signing key rotation/revocation dokumentáció.

**NINCS benne (tilos):**

- Natív Kotlin `PackageVerifier.kt` — lásd §0.0, jövőbeli kör.
- A private signing key generálása vagy tárolása bármilyen formában a repóban.
- `docs/adr/**` — az ADR 0423-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/security/canonical_json.dart` | ÚJ — újrafelhasználható kanonikus JSON |
| `lib/core/security/signed_manifest_verifier.dart` | ÚJ — aláírás + checksum ellenőrzés |
| `lib/core/ai/model_package_manifest.dart` | ÚJ — manifest parser/descriptor |
| `test/core/security/canonical_json_test.dart` | a §6 cellái |
| `test/core/security/signed_manifest_verifier_test.dart` | a §6 cellái |
| `test/fixtures/local_ai_packages/` | ÚJ — golden fixture csomagok (valid, módosított manifest, módosított modellfájl, path traversal) |

**Tilos zóna:** `android/**` · `lib/features/offline_ai/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0423)

### 5.1 Hibás package SOHA nem válhat aktívvá — fail closed

Signature mismatch, checksum mismatch, path traversal bejegyzés vagy ismeretlen key ID esetén a verifier `SignatureRejected`/`ChecksumMismatch`/`UnknownKeyId` hibát ad, és a hívó réteg (Kör 10) kötelezően karanténba helyezi a csomagot.

**NEM elfogadható gyengítés:** egy "csak figyelmeztető" mód, ami logolja a signature-hibát, de engedi az aktiválást "fejlesztői kényelemből" — production módban ismeretlen key ID MINDIG elutasítás, lab módban is csak explicit, külön megjelölt dev-keyring engedett.

### 5.2 A verifier nem tölti memóriába a teljes modellfájlt

A SHA-256 ellenőrzés streaming módon fut (chunk-onkénti hash-frissítés), hogy egy több GB-os modellfájl ne okozzon OOM-ot a verifikáció alatt.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Érvényes aláírású, érvényes checksumú csomag elfogadott | `signed_manifest_verifier_test.dart` |
| A2 | Módosított manifest (aláírás után) elutasított | `signed_manifest_verifier_test.dart` |
| A3 | Módosított modellfájl (checksum eltérés) elutasított | `signed_manifest_verifier_test.dart` |
| A4 | Ismeretlen signing key ID production módban elutasított | `signed_manifest_verifier_test.dart` |
| A5 | Path traversal bejegyzés (`../../etc/passwd`-szerű fájlnév) elutasított | `signed_manifest_verifier_test.dart` |
| A6 | Cancellation közben a verifier nem hagy félig írt state-et | `signed_manifest_verifier_test.dart` |
| A7 | A kanonikus JSON ugyanarra a bemenetre mindig ugyanazt a byte-sorozatot adja (kulcs-sorrend, whitespace) | `canonical_json_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A verifier a manifest MÓDOSÍTÁSA UTÁN is elfogadja az aláírást (rossz canonical form) | A2 |
| A checksum-ellenőrzés csak a fájlméretet nézi, nem a tartalmat | A3 |
| Az ismeretlen key ID lab-módban ÉS production-ben is elfogadott | A4 |
| A fájlnév-validáció nem szűri a `..`-t tartalmazó path-eket | A5 |
| A kanonikus JSON a map-kulcsok beszúrási sorrendjét őrzi rendezés helyett | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** módosíts egy bájtot a fixture modellfájlban aláírás UTÁN, futtasd a verifiert → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/security/canonical_json_test.dart test/core/security/signed_manifest_verifier_test.dart
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `canonical_json.dart` — kulcs-rendezéses, determinisztikus JSON encoder.
2. `model_package_manifest.dart` — manifest parser, mezővalidáció.
3. Golden fixture csomagok: valid, módosított manifest, módosított modell, ismeretlen key, path traversal.
4. `signed_manifest_verifier.dart` — signature + streaming checksum + cancellation.
5. Quarantine állapot és signing key rotation dokumentáció.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A canonical JSON inkonzisztenciája.** Ha a kanonikus forma nem determinisztikus, az aláírás-ellenőrzés hamis pozitívot VAGY hamis negatívot adhat (A7).
- **A natív tükörkép elmaradása.** A Dart-oldali logika a natív rétegtől függetlenül helyes, de amíg a Kotlin `PackageVerifier.kt` nem készül el, a TÉNYLEGES natív aktiválási útvonal nem védett — ezt a HANDOFF-nak és a Kör 13 pre-flightjának explicit rögzítenie kell nyitott tartozásként.
- **A streaming checksum implementációs hibája nagy fájlon.** Ha a chunk-határok rosszul kezelik a hash state-et, a teszt kis fixture-rel zöld maradhat, de valós méretű fájlon hibázna — a teszt legalább egy több chunk-határt átívelő fixture-mérettel fusson.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
