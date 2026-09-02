# Internal production checklist — belső cohort telepítés előtt

**Kör:** E12-R31 (Chapter 12, Kör 31). Ez a lista a `tool/release/
production_smoke.py` füst-csomag és a hozzá tartozó dokumentumok által
lefedett ellenőrzőpontokat sorolja fel, **egyértelműen megjelölve**, melyik
pontot futtatja gép és melyiket dönti ember. A kör NEM deployol — ez a
telepítés UTÁN, a belső (publikus felhasználó nélküli) cohort megnyitása
ELŐTT futtatandó lista (round brief §0.0 EMBERI KAPU).

Minden sor `**[GÉPI]**` vagy `**[EMBERI]**` címkével kezdődik
(`test/tooling/production_readiness_test.dart` A5 cellája ezt gépileg méri —
egyetlen jelöletlen sor sem maradhat). A `**[GÉPI]**` pontok mögött egy
konkrét, futtatható parancs áll; az `**[EMBERI]**` pontok mögött infrastruktúra-
hozzáférés, titok vagy egy visszavonhatatlan döntés áll, amit production
futtatás szimulálásával nem lehet kiváltani (round brief §0.0 STOP-protokoll).

## 1. Deploy előtt

- [ ] **[EMBERI]** A négy production aláíró titok
      (`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`,
      `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) és a backend production
      titkok (`STRUMSIGHT_SECRET_KEY`, adatbázis-hitelesítő adatok) a céli
      infrastruktúra titokkezelőjében élnek — a repóban SOSEM (round brief
      §5.1).
- [ ] **[EMBERI]** A belső cohort tesztfiók(ok) létrehozása és a jelszavuk
      biztonságos átadása a füst-teszt futtatójának — a jelszó SOSEM kerül a
      `tool/release/production_smoke.py --password-env`-ben megnevezett
      környezeti változón kívül semmilyen fájlba vagy parancssori argumentumba.
- [ ] **[GÉPI]** A backend gate (`cd backend && python -m pytest
      tests/test_production_smoke_contract.py -q`) és a kliens gate
      (`tools/round-gate.sh test/tooling/production_readiness_test.dart
      test/app/app_config_test.dart`) mindkettő zöld a deployolandó commiton.

## 2. Deploy után — automatikus füst-teszt

- [ ] **[GÉPI]** `python3 tool/release/production_smoke.py --base-url
      https://<production-hosztnév> --email <cohort-teszt-email>
      --password-env <env-változó-neve> --signing-certificate
      dist/signing-certificate.json --expected-fingerprint <a
      store-listázásból ismert SHA-256> --asset-root .` fut, és **exit
      code 0**-t ad. A `--base-url` KÖTELEZŐEN `https://` sémájú — egy nem-
      https cél fail-closed exit 2-t ad (round brief MAJOR-3); a
      `--allow-insecure-http` kapcsoló KIZÁRÓLAG lokális/staging futtatáshoz
      való, production célon SOSEM használandó.
- [ ] **[GÉPI]** A fenti futás kimenete tartalmazza a `[PASS] readiness:
      ready` sort — a `GET /health/ready` (NEM `/readyz`, §0.0.1 P1) 200-at
      ad, a migrációs fej egyezik.
- [ ] **[GÉPI]** A kimenet tartalmazza a `[PASS] lab_routes_absent:` sort —
      a `POST /diagnostics`, `GET /diagnostics/health`, `GET /download`
      hármas mindegyike 404 (ADR 0061, §0.0.1 P3).
- [ ] **[GÉPI]** A kimenet tartalmazza a `[PASS] fingerprint:` sort — a
      célon telepített build aláíró-tanúsítványának SHA-256 lenyomata
      egyezik a `dist/signing-certificate.json` sidecarral (§0.0.1 P2).
- [ ] **[GÉPI]** A kimenet tartalmazza a `[PASS] model_manifest:` sort — a
      helyi `assets/ml/model_manifest.json` artefaktum jelen van és
      parszolható (§0.0.1 P4 — ez NEM hálózati hívás).
- [ ] **[GÉPI]** A kimenet tartalmazza a `[PASS] auth_login:`, `[PASS]
      auth_me:` és `[PASS] settings:` sorokat — a belső cohort fiók be tud
      jelentkezni és olvasni tudja a cloud beállításait.

## 3. Deploy után — emberi döntési pontok

- [ ] **[EMBERI]** A `docs/release/rollout-packet-template.md` kitöltése
      ehhez a lépcsőhöz (build/commit, aktív flag-profil, migrációs verzió,
      modell-verzió, ismert hibák, dashboard-pillanatkép, support-készenlét,
      rollback-cél, döntéshozó — SDD §26.1 mind a kilenc eleme).
- [ ] **[EMBERI]** A dashboard/monitoring pillanatkép manuális átnézése (hiba-
      ráta, p95 latencia, crash-free session arány) — a füst-teszt csak a
      pillanatnyi elérhetőséget méri, trendet nem.
- [ ] **[EMBERI]** A support-csapat értesítve van a belső cohort megnyitásáról
      és ismeri az ismert hibák listáját.
- [ ] **[EMBERI]** A rollback-cél (build/commit, amire vissza lehet állni) és
      az arra jogosult döntéshozó neve rögzítve van a rollout-csomagban —
      ennek hiánya önmagában blokkolja a cohort megnyitását (round brief A6).
- [ ] **[EMBERI]** A belső cohort tagjainak tényleges meghívása/telepítése —
      ez a lépés a jelen kör scope-ján kívül esik (§0.0 EMBERI KAPU: a kör
      NEM deployol és NEM telepít).
- [ ] **[EMBERI]** A cohort megnyitásáról szóló végső döntés — a füst-teszt
      zöld kimenete szükséges, de önmagában NEM elégséges feltétel; a
      döntés a rollout-csomagban megnevezett döntéshozóé.

## 4. Ha a füst-teszt piros

- [ ] **[EMBERI]** Egy nem-nulla kilépési kód esetén a cohort megnyitása
      STOP — a `[FAIL] <check>: <ok>` sor nevezi meg a hibás pontot; ez nem
      egy második gép által eldöntendő kérdés, hanem a döntéshozó (§3) elé
      viendő tény.
