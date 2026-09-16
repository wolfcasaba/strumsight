# Release Checklist

> **Állapot-mérés: 2026-09-16.** Egy sor CSAK akkor van pipálva, ha van hozzá
> MA létező, hivatkozható bizonyíték (fájl:sor, ADR vagy CI run-id) — a pipa
> mellett ott áll a mutató. A pipálatlan sorok vagy emberi műveletre várnak
> (produkciós aláírás, store-feltöltés, privacy URL, incident owner, szakaszos
> rollout, migrációs próba, verzió-monotonitás), vagy mért okból nyitottak — a
> soronkénti indoklás:
> [`docs/release/blockers.md`](../release/blockers.md) „Újramérés 2026-09-16" és
> [`docs/release/production-readiness-gap-2026-09-16.md`](../release/production-readiness-gap-2026-09-16.md).
> Három sor szándékosan pipálatlan maradt MEGLÉVŐ részbizonyíték mellett is:
> „backend/ML gate zöld" (a backend-láb zöld — `backend-ci.yml` run
> **34931715669**, 2026-09-15 —, de az ML-láb soha nem volt zöld: `ml-train.yml`
> egyetlen futása **29272597412**, `failure`), „device matrix kötelező sora zöld"
> (a `docs/testing/device-matrix.yaml` minden `camera_result`/`audio_result`
> mezője `pending` — nincs MÉRT eszköz-futás), és „monitoring dashboard"
> (a `docs/operations/release-dashboard.md` saját fejléce szerint „schema only",
> a `slo.yaml` séma, nem működő dashboard).

## Build identity

- [x] package/application ID végleges. — bizonyíték: `android/app/build.gradle.kts:116` (`applicationId = "com.wolfcasaba.strumsight"`, `namespace` a :100. sorban), normatív forrás [ADR 0051](../adr/0051-strumsight-application-identifiers.md).
- [ ] verzió és build number monoton.
- [x] release channel azonosítható. — bizonyíték: [ADR 0445](../adr/0445-environment-value-set-and-staging-isolation.md) (zárt environment-értékkészlet); a csatorna minden buildbe bele van fordítva: `.github/workflows/build-apk.yml:64` (`--dart-define=STRUMSIGHT_ENV=development`) és `.github/workflows/release-apk.yml:122` (`--dart-define=STRUMSIGHT_ENV=production`).
- [ ] production signing, nem debug.
- [ ] artifact checksum és commit SHA rögzített.

## Quality

- [x] format/analyze/test/property gate zöld. — bizonyíték: `full-gate.yml` run **34373102220** (`main` @ `1ae9e55`, 2026-09-09, `success`); a lánc lépései `.github/actions/flutter-gates/action.yml` (format, analyze, architecture, secret-scan, l10n-paritás, asset, teljes `flutter test`, randomizált property-gate).
- [ ] backend/ML gate zöld.
- [ ] migration rehearsal zöld.
- [ ] device matrix kötelező sora zöld.
- [ ] crash/resource/performance baseline elfogadott.

## Offline és privacy

- [ ] logged-out offline flow működik.
- [ ] diagnostics és cloud opt-in.
- [ ] nyers audio/video nem hagyja el eszközt beleegyezés nélkül.
- [ ] privacy policy és data inventory friss.
- [ ] account delete/export folyamat tesztelt, ha releváns.

## Security

- [x] secret scan tiszta. — bizonyíték: `.github/actions/flutter-gates/action.yml` „Secret scan gate" lépése (`dart run tool/ci/check_secrets.dart`, ugyanez `tools/round-gate.sh:238`), zölden a `full-gate.yml` run **34373102220**-ban (`main` @ `1ae9e55`).
- [ ] insecure default productionban tiltott.
- [ ] dependency és container scan review-zott.
- [ ] authorization és rate limit tesztelt.
- [ ] signing key és release credential hozzáférés auditált.

## Store

- [ ] ikon, screenshot, leírás, privacy form.
- [ ] mikrofon/kamera permission indoklás.
- [ ] content rating.
- [ ] support és privacy URL.
- [ ] release notes lokalizált.

## Rollout

- [x] kill switch/feature flag. — bizonyíték: [`docs/release/kill-switches.md`](../release/kill-switches.md) (mind a 40 valós `FeatureFlags` mező, kill-switch úttal), gépi katalógus `lib/core/feature_flags/feature_flag_registry.dart` + `dart run tool/check_feature_flags.dart` (pinnelve: `test/tooling/feature_flag_audit_test.dart`), és a ténylegesen lefuttatott kikapcsolás-mérés [`docs/operations/disaster-recovery-drill.md`](../operations/disaster-recovery-drill.md) §2 (2026-09-02). Korlát kimondva: a `remote`/`emergency` forrás ma interfész-szintű, az operábilis út a `local`/define (ADR 0446 D3).
- [x] rollback artifact. — bizonyíték: [`docs/operations/disaster-recovery-drill.md`](../operations/disaster-recovery-drill.md) — 2026-09-02-én TÉNYLEGESEN lefuttatott gyakorlat (kill-switch hatás, modellcsomag-manifest ellenőrzés, adat-helyreállítás), eszköz `tool/release/verify_rollback.py`, gépi mérce `test/tooling/rollback_policy_test.dart` (A5/A6). **Kimondott rés:** a store/APK szintű app-release visszagörgetés NEM része (drill §6) — az az aláírt produkciós artefaktumon múlik (R-SIGN-01, P0).
- [ ] monitoring dashboard.
- [ ] incident owner.
- [ ] 1% → 5% → 20% → 50% → 100% gate és stop feltétel.
