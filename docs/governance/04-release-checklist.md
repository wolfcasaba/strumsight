# Release Checklist

## Build identity

- [ ] package/application ID végleges.
- [ ] verzió és build number monoton.
- [ ] release channel azonosítható.
- [ ] production signing, nem debug.
- [ ] artifact checksum és commit SHA rögzített.

## Quality

- [ ] format/analyze/test/property gate zöld.
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

- [ ] secret scan tiszta.
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

- [ ] kill switch/feature flag.
- [ ] rollback artifact.
- [ ] monitoring dashboard.
- [ ] incident owner.
- [ ] 1% → 5% → 20% → 50% → 100% gate és stop feltétel.
