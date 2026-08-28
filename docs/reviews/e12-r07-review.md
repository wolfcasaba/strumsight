# E12-R07 — Review (Claude / Opus 5, orchesztrátor)

- **Kör:** `E12-R07` — Production signing és secret hardening
- **Ág:** `sonnet-impl/e12-r07-production-signing-and-secret-hardening`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Review-alap:** `95ba5f4b` (pre-flight) → `85e40009`, 6 fájl, +1378/−1
- **Normatív forrás:** [ADR 0448](../adr/0448-production-signing-policy-and-secret-hardening.md) D1–D7
- **Kötelező kiegészítő review:** `security-reviewer` (a brief `risk = "high"`) — LEFUTOTT
- **Gépi jelzések:** `status=done`, `gate_shape=ok`, `scope_audit=ok`
  (`scope_audit_base=95ba5f4b`, `scope_audit_changed=6`), a munkafa a commitok után tiszta
  (`git status --short` üres; a jelzéskori `dirty_files=1` a §10-et író, azóta commitolt fájl volt)

## Verdikt: CHANGES REQUESTED — 2 MAJOR

Mindkét lelet **mérve** van, nem olvasásból következtetve, és mindkettő ugyanabban a
szabályban (`keystore-not-echoed`) él: az egyik hamis pozitív, ami a kör SAJÁT,
dokumentált merge-utáni lépését blokkolná; a másik hamis negatív, ami az **A4**
acceptance-kritériumot méretlenül hagyja a legvalószínűbb szivárgás-alak ellen.

---

## F1 (MAJOR) — Az audit a `::add-mask::` idiómát szivárgásnak minősíti, tehát a kör saját fingerprint-javaslata a beillesztés pillanatában PIROSRA váltja a gate-et

**Hol:** `tool/release/verify_signing_policy.py:207–209` (`_ECHO_OF_SECRET`), a kiváltó
bemenet `docs/release/workflows/release-apk-fingerprint.proposal.md:100`.

**Mérés (reprodukálható):** a javaslat YAML-fragmentjét egy egyébként szabálykövető
workflow-ba illesztve:

```
$ python3 tool/release/verify_signing_policy.py \
    --gradle android/app/build.gradle.kts --workflow /tmp/e12r07-rev/spliced.yml --strict
VIOLATION keystore-not-echoed: a signing password env var appears to be echoed/printed/catted
EXIT=1
```

**Miért MAJOR:** az ADR 0448 D5 **kötelezővé** teszi az `::add-mask::` maszkolást a
felhasználás előtt, az ADR „Következmények" szakasza pedig kimondja, hogy a javaslat
beillesztése merge utáni orchesztrátor-lépés. A kör tehát olyan javaslatot szállít,
amelyet a saját D6-auditja tilt: a beillesztés pillanatában a `signing_policy_test.dart`
„the real workflow passes with exit 0" cellája (`test/tooling/signing_policy_test.dart:262`)
pirosra vált, és a `release-apk.yml` bekötése blokkolva marad. Ez nem elméleti: ez a kör
egyetlen dokumentált folytatása.

**Elvárt javítás:** a `keystore-not-echoed` szabály zárja ki a kanonikus maszkoló
idiómát (az `echo`, amelynek payloadja pontosan a `::add-mask::` direktíva) — és a
kizárás ne legyen tágabb ennél. **Gépi cella kötelező:** a javaslat fragmentjét egy
fixture workflow-ba illesztve az audit **exit 0**; ugyanaz a fixture a maszkoló prefix
nélküli `echo "$STRUMSIGHT_RELEASE_STORE_PASSWORD"` sorral **nem-nulla**.

## F2 (MAJOR) — Az A4 regresszió-őr NEM fogja meg a kanonikus GitHub-Actions szivárgás-alakot (`${{ secrets.* }}`)

**Hol:** `tool/release/verify_signing_policy.py:207–209`; a fixture-oldal
`test/tooling/signing_policy_test.dart:267–288` (a fixture kizárólag az
`echo "$ANDROID_STORE_PASSWORD"` env-alakot méri).

**Mérés (reprodukálható):** egy workflow, amelynek egyetlen lépése kiírja a jelszót a
GitHub secrets-kontextusból:

```yaml
      - name: Leak
        run: |
          echo "${{ secrets.ANDROID_STORE_PASSWORD }}"
```

```
$ python3 tool/release/verify_signing_policy.py \
    --gradle android/app/build.gradle.kts --workflow /tmp/e12r07-rev/leak.yml --strict
signing policy: all rules satisfied
EXIT=0
```

**Miért MAJOR:** az `_ECHO_OF_SECRET` regex a `\$\{?<NÉV>` alakot keresi, a
`${{ secrets.ANDROID_STORE_PASSWORD }}` interpolációban viszont a `$` és a név közé
`{{ secrets.` ékelődik — a minta nem illeszkedik. A brief **A4** kritériuma („a workflow
egyetlen lépése sem írja ki a keystore jelszót vagy a kulcsanyagot") egyetlen gépi
bizonyítéka ez az eszköz; egy őr, amely a legvalószínűbb szivárgás-alakot átengedi, az
**A4-et nem bizonyítja**. Ez pontosan az [L220](../LESSONS.md#l220) hibaosztály
(a mérés némán semmit sem mér), és a kör §9-ben nevesített első kockázata
(„titok-szivárgás a logba"). A mai fán szivárgás NINCS — a lelet az őrre vonatkozik,
nem a viselkedésre.

**Elvárt javítás:** a szabály fedje a `${{ secrets.<NÉV> }}` (és `${{ env.<NÉV> }}`)
interpolációs alakot is a jelszó-nevekre, a `${{ secrets.ANDROID_KEYSTORE_BASE64 }}`
`base64 --decode` pipe-jának mai, legitim alakját (`release-apk.yml:106–107`) **nem**
pirosítva — a valós workflow-nak zöldnek kell maradnia. **Gépi cella kötelező:** a
fenti `leak.yml` fixture → nem-nulla, `keystore-not-echoed`; a valós workflow → exit 0.

---

## Amit a review MÉRT és RENDBEN talált

- **A1 / ADR 0448 D2 (Gradle):** a debug-elutasítás mindkét forrást (`key.properties` ÉS
  env) fedi, mert mindkettő ugyanabba a `releaseSigningValues`-ba fut; `ignoreCase = true`
  mindkét összehasonlításon; `throw GradleException`, nem figyelmeztetés; a kivétel
  üzenete aliast/útvonalat nevez, jelszó-ÉRTÉKET soha
  (`android/app/build.gradle.kts:72–96`).
- **A3 / D3 (Lab):** `lab-apk.yml:36` és `build-apk.yml:63` signing env nélkül futnak, így
  `releaseSigningRequired=false` → a debug-fallback ág változatlan; az új
  `buildTypes.release` őr nem tüzel. A Lab APK nem sérül.
- **A5 / D4 (fingerprint-kötés):** a javaslat a fingerprintet a
  `dist/signing-certificate.json` sidecarba írja, és a MEGLÉVŐ
  `--artifact dist/signing-certificate.json` flaggel köti a manifesthez — új
  manifest-mező nincs, a `schemaVersion` érintetlen (§0.0/R2 pontosan így írta elő).
  A `keytool` jelszava `-storepass:env`-en megy (nincs nyílt CLI-argumentum), a nyers
  kimenet sehol nem íródik ki, `set -x` nincs.
- **A6:** a runbook mind a négy szakaszt (backup, rotáció, hozzáférés, elvesztés)
  megadja, felelőssel.
- **A7 / D7:** a diffben nincs valódi kulcsanyag; a fixture-ök szintetikus szövegek
  (`/tmp/keystore.jks`, `some-value`, `release_key`); a `androiddebugkey` közismert
  publikus alias, nem titok. A `check_secrets` gate zöld.
- **D6 (kétirányúság):** az audit hívási felülete paraméteres (`--gradle`/`--workflow`),
  és a suite valós fájlon ÉS fixture-ön is mér; a `python3` hiánya `ProcessException`-nel
  pirosít, néma skip nincs; `package:yaml` import nincs; a spawnolt bináris kizárólag
  `python3` (a `rg`/`grep`/`jq`/`gh` shell-kihívás tiltása mérve).
- **A §10 valódi-sértés próbája elvégezve és kimenettel dokumentálva** (az elutasító ág
  kivágása pirosította az A1-et; a fixture-alias próba nem-nulla kilépést adott), a fa a
  próbák után tiszta.
- **`verify_signing_policy.py` maga nem szivárogtat:** csak `argparse`/`re`/`sys`/`pathlib`,
  külső binárist nem hív, hibaágon csak az ÚTVONALAT írja ki, fájltartalmat soha.

## NOTE-ok (nem javítandók ebben a körben)

- **N1 — a debug-keystore elutasítás fájlnév/út-heurisztika.** A `File.getAbsolutePath()`
  nem old fel szimlinket és nem normalizál `..`-t, ezért a debug keystore átnevezett
  másolata vagy szimlinkje a fájlnév-ágat átcsúszná; az alias-ellenőrzés az esetek nagy
  részét így is elkapja. Ez az ADR 0448 D2 **szándékosan szűkített** hatóköre (a
  tanúsítvány-identitás egyeztetése nincs a kör scope-jában), nem defektus.
- **N2 — a kulcs-alias secret-csatornából artifact-csatornába kerül** a sidecarban. Nem
  szivárgás: az alias minden aláírt APK-ból kinyerhető, és a D4/D5 kifejezetten engedi.
- **N3 — `grep 'SHA256:'` több találatra többsoros értéket írna a sidecarba** (törött
  JSON, titkot nem tartalmaz). Robusztussági megjegyzés a javaslat élesítéséhez.
- **N4 — jelölés:** a tesztfájl „A7" csoportja a bináris-függetlenséget méri, míg a brief
  A7-e a kulcsanyag-mentességet (azt a `check_secrets_test.dart` fedi). Csak elnevezési
  átfedés, mérési rés nincs.

## A javító kör elvárása

Egy javító kör, ugyanazzal a motorral (`sonnet-impl`), a fenti F1 + F2 leletlistával; a
javítás a `tool/release/verify_signing_policy.py` + `test/tooling/signing_policy_test.dart`
fájlokra korlátozódik (az engedélyezett listán belül), és **mindkét lelethez gépi cella
tartozik**. A javítás nem gyengítheti a meglévő cellákat, és a valós fájlokon az auditnak
exit 0-nak kell maradnia.
