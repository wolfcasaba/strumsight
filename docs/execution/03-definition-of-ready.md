# Definition of Ready

Egy SDD-kör akkor indítható, ha minden kötelező pont teljesül.

## Scope

- [ ] Pontos Chapter és kör meg van nevezve.
- [ ] A kör célja és scope-on kívüli része ismert.
- [ ] Az acceptance criteria egyértelmű.
- [ ] A következő kör nincs belekeverve.

## Függőségek

- [ ] Előfeltétel-körök befejezettek vagy dokumentált waiver létezik.
- [ ] Szükséges public contract stabil.
- [ ] Szükséges fixture, modell, backend vagy eszköz elérhető.
- [ ] Nincs feloldatlan schema- vagy API-ütközés.

## Repository állapot

- [ ] Working tree ismert és biztonságos.
- [ ] Baseline tesztállapot dokumentált.
- [ ] Érintett production kód és tesztek azonosítva.
- [ ] Nincs ismeretlen secret vagy nem commitolható artifact a scope-ban.

## Tervezés

- [ ] Adatmigráció és rollback viselkedés meghatározott, ha releváns.
- [ ] Permission, privacy és lifecycle hatás meghatározott.
- [ ] Teljesítménygate meghatározott, ha audio/vision/AI változik.
- [ ] API authorization és idempotency meghatározott, ha backend írás történik.
- [ ] Lokalizáció és accessibility hatás meghatározott, ha UI változik.

## Tesztelés

- [ ] Célzott tesztek megnevezve.
- [ ] Kötelező teljes gate-ek megnevezve.
- [ ] Valódi device vagy real-audio gate megnevezve, ha szükséges.
- [ ] Tesztadat licence és adatvédelme rendezett.

## Issue

- [ ] GitHub Issue tartalmazza a requirement ID-t.
- [ ] Issue linkeli az SDD-fájlt és kört.
- [ ] Kockázat és blocker címke beállítva.
- [ ] Tulajdonos és milestone kijelölve.

Ha bármely release-, adatvédelmi, secret- vagy irreverzibilis migrációs pont hiányzik, a kör nem Ready.

---
