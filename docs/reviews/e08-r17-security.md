# E08-R17 — Security review

Brief: `docs/rounds/e08-r17-daily-quest-generator.md`  
Reviewed head: `a8980cab`  
Reviewer: független Codex / `gpt-5.6-sol` security reviewer · 2026-08-21  
Verdikt: **PASS**

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

A high-risk minősítés oka a permission/cloud capability határ. A generator
pure caller-fed snapshotot kap; nem importál Fluttert, Riverpodot, permission
plugint, authot, hálózati klienst vagy storage-ot. A hiányzó capability
fail-closed kizárás, a planned-rest eredmény optional. Security blocker nincs;
a correctness review megmaradt F1 tesztbizonyíték-rése ettől függetlenül
merge-blokkoló H4.

## Határellenőrzések

### S1 — PASS — Nincs permission-kényszer

`daily_quest_generator.dart:132-141` kizárólag három caller-fed booleánt olvas.
Nincs `CameraPermissionGateway.request()`, platform plugin vagy UI callback.
A kamera-negálás mutáció az A3 cellát pirosra vitte.

### S2 — PASS — Offline és adatminimalizált

A diffben nincs Dio/network/auth/storage import, logolás, secret, raw audio,
kamera-frame vagy személyes tartalom. A profile snapshot csak caller-fed
stabil kulcs; a generator nem továbbítja és nem perzisztálja.

### N1 — NOTE — A capability-axis regressziót tartósan külön kell mérni

A correctness F1 re-review bizonyítja, hogy az `account → cloud` hibás kötést
a max-3 truncation elrejti. Ez jelenleg nem production security sértés, mert a
kód helyesen mapel, de izolált candidate-pool teszt szükséges a határ tartós
őrzéséhez.

### N2 — NOTE — Scope és dependency

A kézi scope-audit 5 engedélyezett útvonalat mért, sértés nélkül. A két új
production fájl csak gamification-internal domain/infrastructure típust és
`dart:convert`-et importál; feature-internal vagy core permission út nincs.

## Gate és mutációs bizonyíték

Az exact `a8980cab` izolált re-review klónjában a round-gate 6 gate-lépése és
9/9 célzott tesztje zöld, secret scan 0 finding. A default katalógus kiürítése
és két capability-axis mutáció piros; az account→cloud mutáció correctness
teszthiányként zöld marad. Restore után a klón tiszta.

## Döntés

Security verdict **PASS**. A correctness F1/F2 MAJOR leleteinek lezárása és
független re-review továbbra is kötelező a merge előtt.
