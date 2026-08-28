# Production signing key — runbook (backup, rotáció, hozzáférés, elvesztés)

- **Kör:** E12-R07 — [ADR 0448](../adr/0448-production-signing-policy-and-secret-hardening.md)
- **Hatály:** a `release-apk.yml` production APK-aláírásához használt Android
  keystore (`ANDROID_KEYSTORE_BASE64`) és a hozzá tartozó jelszavak
  (`ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`) és alias
  (`ANDROID_KEY_ALIAS`) — a négy GitHub Actions repository secret, amit a
  `.github/workflows/release-apk.yml` `signing-prerequisites` jobja
  (9–36. sor) a build ELŐTT kényszerít ki.
- **Felelős:** a repó tulajdonosa (`kcsabi176@gmail.com`) — jelenleg
  egyszemélyes projekt, a négy lépés (backup, rotáció, hozzáférés,
  elvesztés) mindegyikét ő hajtja végre. Csapat-bővüléskor ez a szakasz
  bővül a szerepkörök szerinti felelős-mátrixszal.

## 0. Miért ez a négy secret, és miért fail-closed a hiányuk

A production APK-t a `release-apk.yml` `release-apk` jobja építi
(`needs: signing-prerequisites`), a négy secretet a
`STRUMSIGHT_RELEASE_STORE_FILE` / `_STORE_PASSWORD` / `_KEY_ALIAS` /
`_KEY_PASSWORD` env-eken és a `STRUMSIGHT_REQUIRE_RELEASE_SIGNING=true`
kapcsolón keresztül adja át a Gradle-nek (113–119. sor). Ha bármelyik
secret hiányzik, a `signing-prerequisites` job `::error::`-rel megáll a
build ELŐTT (9–36. sor) — ez a mai, MÁR mért fail-closed viselkedés
([ADR 0062](../adr/0062-ci-gate-chain-and-fail-closed-release-signing.md)),
amit ez a kör NEM változtat, csak kiegészít (ADR 0448 D1–D3).

## 1. Backup

- **Hol van ma a keystore.** A keystore fájl (`.jks`) NEM a repóban él — a
  `ANDROID_KEYSTORE_BASE64` GitHub Actions secret hordozza base64-kódolva.
  A `Materialize production keystore` lépés (97–112. sor) `umask 077`
  mellett dekódolja a `$RUNNER_TEMP`-be, és a `Remove production keystore`
  lépés (141–149. sor) `if: always()` mellett törli — a runner disken a
  keystore SOHA nem marad a job végeztével, sikeres vagy sikertelen futás
  esetén sem.
- **Kötelező offline backup.** A keystore-nak a GitHub secret-en KÍVÜL is
  léteznie kell legalább egy, a repó tulajdonosa által ellenőrzött, offline
  helyen (pl. jelszóval védett archívum egy külön tárolón) — ha a GitHub
  Actions secret törlődik vagy a szervezet-hozzáférés elvész, ez az
  egyetlen helyreállítási út. **A keystore fájl és a jelszavak SOHA nem
  kerülhetnek a repóba** (ADR 0448 D7) — sem commitba, sem Issue-ba, sem
  chatbe olvasható formában.
- **Backup gyakorisága.** A keystore élettartama alatt NEM változik (az
  aláírás-folytonosság store-követelmény — l. §2), ezért a backupot csak a
  kezdeti létrehozáskor és minden jelszó-rotációkor (§2) kell frissíteni,
  nem rendszeres időközönként.
- **Ellenőrzés.** A backupból visszaállított keystore-nak ugyanazt a SHA-256
  tanúsítvány-fingerprintet kell adnia, mint amit a Play Console (vagy az
  első publikált build) rögzített — ellenőrzés:
  `keytool -list -v -keystore <backup.jks> -alias <alias>` (interaktív
  jelszó-promptban, SOHA parancssori argumentumként — l. §4 a
  `-storepass:env`/`-storepass:file` alakról).

## 2. Rotáció

- **A store-aláírás folytonossága korlátozza a rotációt.** A Google Play
  (és minden Android store) ugyanazt az aláíró-tanúsítványt várja minden
  frissítéshez — a KEY (a `.jks` fájl és a hozzá tartozó privát kulcs) NEM
  cserélhető szabadon egy már publikált alkalmazásnál anélkül, hogy a store
  App Signing (key upgrade / key rotation) folyamatát végigvinné a
  tulajdonos. **A kulcs rotációja tehát elsősorban store-oldali folyamat,
  nem CI-oldali** — ez a runbook a CI-oldali secret-rotációt (jelszavak)
  fedi, a kulcs-fájl cseréjét csak vészhelyzeti eljárásként (§4).
- **Jelszó-rotáció (rendszeres, ajánlott évente vagy gyanú esetén
  azonnal).** A keystore-jelszó (`ANDROID_STORE_PASSWORD`) és a
  kulcs-jelszó (`ANDROID_KEY_PASSWORD`) a `keytool -storepasswd` /
  `keytool -keypasswd` paranccsal cserélhető a keystore tartalmának
  (a kulcsanyagnak) érintése nélkül. Lépések:
  1. a régi keystore-ból friss offline másolat (§1);
  2. `keytool -storepasswd -keystore <backup.jks>` és
     `keytool -keypasswd -alias <alias> -keystore <backup.jks>` — mindkettő
     interaktív jelszó-prompttal, SOHA parancssori argumentummal;
  3. a négy GitHub Actions repository secret frissítése
     (`ANDROID_KEYSTORE_BASE64` marad, ha csak a jelszót cserélted;
     `ANDROID_STORE_PASSWORD` / `ANDROID_KEY_PASSWORD` az új értékre);
  4. egy `release-apk.yml` `workflow_dispatch` futtatás a merge-kapu
     előtt — a `signing-prerequisites` job azonnal jelzi, ha egy secret
     hiányzik vagy hibás.
- **A rotáció SOHA nem megy végig commit vagy Issue útján** — a GitHub
  repository secrets UI (vagy a `gh secret set` CLI, amit a tulajdonos
  interaktívan, sosem scriptbe ágyazott jelszóval futtat) az egyetlen
  csatorna.

## 3. Hozzáférés

- **Ki érheti el a secreteket ma.** A négy `ANDROID_*` GitHub Actions
  repository secret kizárólag a repó Settings → Secrets and variables →
  Actions felületén keresztül olvasható/írható — ez ma a repó
  tulajdonosára korlátozódik (egyszemélyes projekt). A secretek értéke
  workflow-futás közben SOSEM jelenik meg a logban (GitHub automatikus
  maszkolása minden `secrets.*` értékre, plusz a `signing-prerequisites`
  job explicit `::error::`-je csak a HIÁNYZÓ secret NEVÉT írja ki, az
  értékét soha — 29–32. sor).
- **Csapat-bővüléskor kötelező (nem ma aktív, de rögzítendő elvárás):** a
  keystore-hoz és a négy secrethez való hozzáférés a legszűkebb kör (a
  release-t ténylegesen indító személyek) — NEM minden collaborator —
  jogosultsága legyen; a GitHub environment-protection-rules (kötelező
  reviewer egy `production` environmenten) a soron következő kör dolga,
  amint a projekt egynél több emberhez tartozik.
- **A offline backup (§1) hozzáférése** ugyanerre a körre korlátozódik —
  egy jelszóval védett archívum, amelynek jelszavát a tulajdonos NEM tárolja
  ugyanabban a rendszerben, mint magát az archívumot.

## 4. Kulcs-elvesztés (a keystore vagy a jelszó megsemmisül/elveszik)

- **Ha az offline backup (§1) még megvan:** nincs incidens — a
  `ANDROID_KEYSTORE_BASE64` secret újratölthető a backupból
  (`base64 -w0 <backup.jks>` majd a GitHub Secrets UI-ba beillesztve,
  SOHA parancssori historyba nem kerülő módon, pl. `gh secret set
  ANDROID_KEYSTORE_BASE64 < base64.txt` fájlból, nem `--body` argumentumból).
- **Ha az offline backup ÉS a GitHub secret is elveszett (a legrosszabb
  eset):** a régi aláíró-kulccsal a jövőben NEM lehet frissítést kiadni a
  már publikált csomaghoz. Ez NEM CI-oldali probléma, hanem store-szintű:
  - Google Play: a Play App Signing (ha a projekt ezt használja) lehetővé
    teheti az upload-kulcs cseréjét a Google support folyamatán keresztül
    — ez a tulajdonos feladata, a store fiókjához kötve, ezen a repón
    kívül eső lépés;
  - ha a Play App Signing NINCS bekapcsolva (a projekt még nem publikált,
    vagy a régi séma szerint fut), az alkalmazást ÚJ `applicationId`-vel
    (l. [ADR 0051](../adr/0051-strumsight-application-identifiers.md)) és
    ÚJ aláíró-kulccsal kell újra közzétenni — a meglévő felhasználók a
    régi build-et NEM tudják in-place frissíteni, csak új telepítésként
    kapják a friss csomagot.
  - a jövőre nézve: egy ÚJ keystore-t kell generálni
    (`keytool -genkeypair -v -keystore <new.jks> -keyalg RSA -keysize 2048
    -validity 10000 -alias <new-alias>`, interaktív jelszó-prompttal), az
    új keystore-t azonnal §1 szerint offline backupolni, és a négy secretet
    az új értékekre cserélni.
- **A tanulság ebből az esetből mindig egy `docs/LESSONS.md` bejegyzés** —
  a runbook e szakasza a jövőbeli körök számára rögzíti, hogy a §1 offline
  backup NEM opcionális lépés, hanem az egyetlen védelem ez ellen a
  visszafordíthatatlan eset ellen.

## 5. Amit ez a runbook NEM fed (kifejezetten rögzítve)

- A store-oldali App Signing key-upgrade folyamat lépésről lépésre
  dokumentációja — az a Google/Apple felület dolga, ez a runbook csak a
  döntési pontot (§4) rögzíti.
- A GitHub environment-protection-rules bevezetése — soron következő kör,
  amint a projekt egynél több hozzáférőt kap (§3).
- A tanúsítvány-fingerprint provenance-hoz kötése — az
  [`docs/release/workflows/release-apk-fingerprint.proposal.md`](workflows/release-apk-fingerprint.proposal.md)
  javaslat dolga, nem ennek a runbooknak.
