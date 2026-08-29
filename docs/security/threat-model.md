# StrumSight — program-szintű threat model

- **Kör:** E12-R18 — [ADR 0481](../adr/0481-program-threat-model-and-release-security-scan.md)
- **Dátum:** 2026-08-29
- **Státusz:** mérő — minden `release_gate: true` ellenintézkedés guardját a
  `tool/release/security_scan.py` fail-closed módon méri a fán
- **Hatály:** a teljes StrumSight program (kliens app + opcionális FastAPI
  account-backend + release-lánc), a Chapter 12 release-roadmap biztonsági
  sávja

## 0. Hogyan olvasd ezt a dokumentumot

Ez a dokumentum **BEEMEL, nem duplikál** (ADR 0481 D1): a Community
platform nyolc kategóriája a [community-threat-model.md](community-threat-model.md)
(ADR 0395) alatt van részletezve, a fájlimport biztonsági határ az
[ADR 0091](../adr/0091-song-import-security-boundary.md) alatt, a production
signing és secret hardening pedig az
[ADR 0448](../adr/0448-production-signing-policy-and-secret-hardening.md)
alatt. Ez a dokumentum ezekre **hivatkozik**, komponensenként egy-egy rövid
összegzéssel, és minden ellenintézkedéshez egy géppel olvasható `guard`
blokkot rendel — a program-szintű hiány, amit a kör pótol, nem egy hiányzó
védelem, hanem a védelmek fölötti szerződés (ADR 0481 kontextus).

Minden ellenintézkedés alatt egy ```yaml``` blokk áll, pontosan ezekkel a
kulcsokkal (kötött alak, brief §5.1 — az alábbi sémaillusztráció szándékosan
NEM ```yaml``` nyelvcímkéjű blokk, hogy a `security_scan.py` guard-parsere
ne próbálja ténylegesen kiértékelni):

```text
id: <egyedi, [A-Z0-9-]+>
component: <az alábbi hét komponens egyike>
threat: <STRIDE-érték>
release_gate: <bool>
guard:
  path: <a repó gyökeréhez képesti, LÉTEZŐ útvonal>
  test: <opcionális — pytest def <név> vagy Dart test('<név>')>
```

`release_gate: true` ⇒ a `tool/release/security_scan.py` `guards` ága a
guard **létezését** (és ha van `test`, annak a `path` fájlban való
jelenlétét) release előtt fail-closed méri. Egy csendben törölt vagy
átnevezett védelmi teszt ma **release-blokkoló**, nem néma regresszió.

## 1. Komponensek

1. **client-storage** — a kliens-oldali tartós tárolás (session token,
   beállítások) az Android Keystore / iOS Keychain mögötti
   `flutter_secure_storage` rétegen keresztül.
2. **backend-api** — a FastAPI + SQLite + JWT account-backend (`backend/app/`,
   login + cloud settings sync; a detekció 100%-ban a kliensen marad).
3. **diagnostics-upload** — a `POST /diagnostics` Lab-mode feltöltési út
   (`backend/app/routers/diagnostics.py`).
4. **community-media-upload** — a Community presigned-PUT média-feltöltés
   (ADR 0410, `backend/app/community/services/media_upload_service.py` és
   társai).
5. **model-package** — a bundlelt ML modell-bináriskomponensek (kézi és
   vision modellek) integritása (`lib/core/ml/vision_model_manifest.dart`).
6. **community** — az aszinkron Community platform (post/komment/follow/club/
   challenge/leaderboard); a nyolc kategória teljes tárgyalása:
   [community-threat-model.md](community-threat-model.md) (ADR 0395).
7. **release-chain** — a release-előállítás lánca (signing policy, secret
   scan, dependency-korlátok; `tool/release/`, `tool/ci/`).

Az importált fájlok (natív JSON, MusicXML/MXL, MIDI) biztonsági határa
külön ADR-rel elfogadott ([ADR 0091](../adr/0091-song-import-security-boundary.md));
ez a dokumentum a fenti hét komponensre koncentrál — az import-határ
guardjait az importer-implementáló körök (Epic 3) tesztjei hordozzák, a
`security_scan.py` `guards` ága ide még nem terjed ki (jövőbeli kör).

## 2. client-storage

**Fenyegetés:** ha a session token vagy egy más érzékeny beállítás sima
`SharedPreferences`-ben (vagy más, nem Keystore/Keychain-mögötti tárban)
kerülne el, egy eszközhöz vagy titkosítatlan biztonsági mentéshez hozzáférő
támadó kiolvashatná — information disclosure. Az egyetlen `lib/`-beli hely,
amely a `flutter_secure_storage` pluginot importálja, a
`FlutterSecureStore` (`lib/core/storage/secure_store.dart`); minden más réteg
a `SecureStore` interfészen keresztül éri el.

```yaml
id: T-CLIENT-01
component: client-storage
threat: information-disclosure
release_gate: true
guard:
  path: test/core/storage/secure_store_test.dart
  test: round-trips a secret
```

## 3. backend-api

**Fenyegetés:** felhasználó-felsorolás (user enumeration) — ha a helytelen
jelszó és az ismeretlen e-mail cím eltérő válasz-alakot (státuszkód, body,
időzítés) adna, egy támadó regisztrált e-mail címeket térképezhetne fel.
`backend/app/routers/auth.py` a két esetre bizonyítottan bájt-azonos választ
ad.

```yaml
id: T-API-01
component: backend-api
threat: information-disclosure
release_gate: true
guard:
  path: backend/tests/test_auth.py
  test: test_unknown_email_and_wrong_password_responses_are_byte_identical
```

## 4. diagnostics-upload

**Fenyegetés (tampering — path traversal):** a kliens által küldött
`X-Session-Id` fejléc nélküli normalizálás esetén egy `../../etc/passwd`-
szerű érték kiléphetne a diagnosztika-tárolóból. A `_safe_id()`
(`backend/app/routers/diagnostics.py:56`) a bemenetet `c.isalnum() or c in
"-_"` szűrőn engedi át, 48 karakterre vágva.

```yaml
id: T-DIAG-01
component: diagnostics-upload
threat: tampering
release_gate: true
guard:
  path: backend/tests/test_diagnostics.py
  test: test_diagnostics_session_id_cannot_escape_data_dir
```

**Fenyegetés (denial-of-service — oversized payload):** egy korlátlan méretű
feltöltés kimerítheti a szerver lemez- vagy memóriakeretét. Az endpoint a
streamelt bájtszámot menet közben számolja, és `STRUMSIGHT_DIAG_MAX_BYTES`
felett `413`-mal megszakítja az olvasást (nem vár be egy teljes, túlméretes
body-t).

```yaml
id: T-DIAG-02
component: diagnostics-upload
threat: denial-of-service
release_gate: true
guard:
  path: backend/tests/test_diagnostics.py
  test: test_diagnostics_oversize_endpoint_returns_413
```

## 5. community-media-upload

**Fenyegetés (spoofing — lejárt aláírt URL újrafelhasználása):** egy régi,
lejárt presigned PUT URL-lel próbált finalize-hívást a szolgáltatásnak el
kell utasítania, különben egy korábban kiszivárgott URL tetszőleges időben
felhasználható lenne.

```yaml
id: T-MEDIA-01
component: community-media-upload
threat: spoofing
release_gate: true
guard:
  path: backend/tests/community/test_media_upload.py
  test: test_a2_finalize_rejects_expired_signed_url
```

**Fenyegetés (tampering — MIME-hamisítás):** a kliens által deklarált MIME
típus és a bucket-objektum tényleges MIME típusa közötti eltérést (vagy egy
nem engedélyezett MIME-et) a finalize-lépésnek el kell utasítania — egy
polyglot fájl (kép álcázott futtatható) így nem csúszhat át a deklarált
típuson.

```yaml
id: T-MEDIA-02
component: community-media-upload
threat: tampering
release_gate: true
guard:
  path: backend/tests/community/test_media_upload.py
  test: test_a3_finalize_rejects_bucket_mime_mismatch
```

**Fenyegetés (denial-of-service — túlméretes objektum):** a bucket-oldalon
ténylegesen tárolt objektum méretét a finalize-lépésnek a deklarált
méretkorláttal szemben is ellenőriznie kell, különben egy manipulált
feltöltés megkerülhetné a kliens-oldali méretkorlátot.

```yaml
id: T-MEDIA-03
component: community-media-upload
threat: denial-of-service
release_gate: true
guard:
  path: backend/tests/community/test_media_upload.py
  test: test_a4_finalize_rejects_oversize_bucket_object
```

## 6. model-package

**Fenyegetés (tampering — manipulált modellbináris):** ha egy bundlelt ML
modellbináris (kéz- vagy vision-modell) egy build- vagy disztribúciós hiba
miatt eltérne a manifestben deklarált sha256-tól, a detekció csendben rossz
kimenetet adhatna. A manifest-integritás VALÓDI fájl-hash ellenőrzést végez
mind a `models[]`, mind a `vision_models[]` listára.

```yaml
id: T-MODEL-01
component: model-package
threat: tampering
release_gate: true
guard:
  path: test/tooling/vision_model_integrity_test.dart
  test: bad checksum fails the integrity gate
```

```yaml
id: T-MODEL-02
component: model-package
threat: tampering
release_gate: true
guard:
  path: test/tooling/ml_asset_manifest_test.dart
  test: shipping manifest covers four valid declared ML binaries
```

## 7. community

A nyolc Community-kategória (Identity, IDOR, Audience bypass, Block bypass,
Spam, Media upload, Challenge replay, Moderation abuse) teljes tárgyalása:
[community-threat-model.md](community-threat-model.md) (ADR 0395). Az alábbi
két guard a program-szintű release-döntéshez kötött, mért reprezentánsa —
nem helyettesíti, csak bizonyítékhoz köti a Community dokumentumot.

**Fenyegetés (spoofing — challenge replay):** ugyanazon `source_event_id`
kétszeri beküldése (audio újrajátszás egy korábbi teljesítésből) nem
hozhat létre két külön eredmény-sort. A tényleges viselkedés **idempotens**,
nem "elutasított": terminális állapotú sor újrabeküldésekor az EREDETI sor
jön vissza változatlanul; `pending`/`review` állapotú, lejárt nonce-ú sor
`rejected` + `reason_code="nonce_expired"` állapotba kerül. A DB-oldali őr a
`uq_community_challenge_results_replay` unique constraint
(`participant_id`, `source_event_id`).

```yaml
id: T-COMM-01
component: community
threat: spoofing
release_gate: true
guard:
  path: backend/tests/community/test_challenge_verification.py
  test: test_a1_replay_same_source_event_id_lands_one_row
```

**Fenyegetés (information-disclosure — audience bypass blokkolt nézőnél):**
egy blokkolt fél számára a profil MINDIG úgy kell viselkedjen, mintha
`private` lenne (`SUMMARY` szint), függetlenül a tényleges `visibility`
beállítástól — különben egy blokkolás megkerülhető lenne a profil
nyilvános mezőinek kiolvasásával.

```yaml
id: T-COMM-02
component: community
threat: information-disclosure
release_gate: true
guard:
  path: backend/tests/community/test_access_policy.py
  test: test_a2_blocked_public_profile_returns_summary
```

## 8. release-chain

**Fenyegetés (tampering — production APK debug-tanúsítvánnyal):** a
production signing policy teljes tárgyalása:
[ADR 0448](../adr/0448-production-signing-policy-and-secret-hardening.md).
A `verify_signing_policy.py` statikus audit két irányban mér: a valós
`android/app/build.gradle.kts` + `.github/workflows/release-apk.yml` felett
zöld, egy, a elutasító ágat nélkülöző fixture felett piros.

```yaml
id: T-RELEASE-01
component: release-chain
threat: tampering
release_gate: true
guard:
  path: test/tooling/signing_policy_test.dart
  test: the real workflow passes with exit 0
```

**Fenyegetés (tampering — titok commitolása a fába):** a titok-minták
EGYETLEN forrása a `tool/ci/check_secrets.dart` (ADR 0138); a
`security_scan.py` `secrets` ága erre DELEGÁL, nem deklarál második
regex-készletet (ADR 0481 D3).

```yaml
id: T-RELEASE-02
component: release-chain
threat: tampering
release_gate: true
guard:
  path: test/tooling/check_secrets_test.dart
  test: flags provider token literals by their own prefix
```

**Fenyegetés (tampering — korlátlan vagy sebezhető függőség):** egy felső
verzió-korlát nélküli, vagy egy dokumentáltan sebezhető verzió-tartományba
eső backend-függőség pin csendben beengedhet egy jövőbeli, kompromittált
verziót vagy egy ismert sebezhetőséget. A `security_scan.py`
`dependencies` ága ezt maga méri (nem egy külön teszt-fájl guardján
keresztül) — a guard itt a mérce saját, bizonyított piros útja.

```yaml
id: T-RELEASE-03
component: release-chain
threat: tampering
release_gate: true
guard:
  path: test/tooling/security_scan_test.dart
  test: a dependency line without an upper bound is a critical finding
```
