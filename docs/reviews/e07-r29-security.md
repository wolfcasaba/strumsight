# E07-R29 — Security review

Reviewer: Codex · Dátum: 2026-08-19
Update: Claude (orchestrátor) — S2/F3 zárás ellenőrzése · Dátum: 2026-08-19
Verdikt: PASS

## Találatok

### S1 — BLOCKER — Plan-scoped privacy törlés minden evidence-re kiterjedhet

Az eredeti `InMemoryPracticeEvidenceRepository.deleteForPlan` alapértelmezett ága
(`practice_evidence_repository.dart:116-124`) minden evidence rekordot a
hívó `planId` tulajdonának tekint. Izolált próbában két outcome-id rekordból
a `deleteForPlan('plan-a')` a plan-b rekordot is eltávolította. Ez
felhasználói adatvesztés, ezért a review jelentés F2 leletének javítása a
security gate feltétele volt. Javítva: `0a6315d2` ownership-as-data
regressziós tesztekkel.

### S2 — MAJOR — Restart után a privacy delete nem teljes

A local plan repository `_writtenKeys` process-lokális nyilvántartása miatt
restart után maradhat érzékeny draft vagy archive adat. Lásd a review F1
reprodukcióját; az A7 „delete every planning datum” ígéretéhez restart-álló
felfedezés kellett. Javítva: `39219376`/`3e05d243` perzisztált manifesttel és
restart-regressziókkal. A manifest-írás hibakezelése a review F3 MAJOR
leletében maradt nyitva — ezt `8212b0cb` zárta: `_trackWrite`/`_trackRemove`
mostantól `await`-eli a manifest-perzisztálást, a hiba `StorageFailure`-ként
propagálódik silent no-op helyett. Orchestrátor-oldali független ellenőrzés:
a `8212b0cb` diffjének elolvasása + a `local_repository_test.dart` saját,
izolált futtatása — 36/36 zöld, az új `F3 — manifest persistence failures`
eset is köztük. Mindkét finding (S1/S2) zárva.

## Határvizsgálat

Nem találtam új hálózati hívást, raw-audio/camera logolást vagy secretet a
diffben. A két törlési hiba (S1/S2) mindkettő javítva és regresszióval védve;
nincs más nyitott biztonsági/adatvédelmi lelet.
