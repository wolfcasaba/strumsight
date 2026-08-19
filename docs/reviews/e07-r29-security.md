# E07-R29 — Security review

Reviewer: Codex · Dátum: 2026-08-19  
Verdikt: BLOCKED

## Találatok

### S1 — BLOCKER — Plan-scoped privacy törlés minden evidence-re kiterjedhet

Az `InMemoryPracticeEvidenceRepository.deleteForPlan` alapértelmezett ága
(`practice_evidence_repository.dart:116-124`) minden evidence rekordot a
hívó `planId` tulajdonának tekint. Izolált próbában két outcome-id rekordból
a `deleteForPlan('plan-a')` a plan-b rekordot is eltávolította. Ez
felhasználói adatvesztés, ezért a review jelentés F2 leletének javítása a
security gate feltétele.

### S2 — MAJOR — Restart után a privacy delete nem teljes

A local plan repository `_writtenKeys` process-lokális nyilvántartása miatt
restart után maradhat érzékeny draft vagy archive adat. Lásd a review F1
reprodukcióját; az A7 „delete every planning datum” ígéretéhez restart-álló
felfedezés kell.

## Határvizsgálat

Nem találtam új hálózati hívást, raw-audio/camera logolást vagy secretet a
diffben. Ez nem oldja fel a két nyitott törlési hibát.
