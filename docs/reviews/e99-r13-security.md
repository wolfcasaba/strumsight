# E99-R13 — Security review

Brief: `docs/rounds/e99-r13-gov-30c-5-runner-audio-path-and-wiring.md`
Reviewer: Codex (gpt-5.6-terra) · Dátum: 2026-08-15
Verdikt: CHANGES REQUIRED (a funkcionális review F1 MAJOR megállapításával együtt)

## Ellenőrzés

- A `AnalysisRunRequest` a PCM-et külön, csak memóriabeli hordozóban tartja.
- A dokumentumkódoló nem kap PCM-mezőt. Egy eldobható negatív próba a kódolt JSON-hoz fűzött `0.918273645` markerrel az A4 tesztet pirosra váltotta; a próba visszaállítása után A4 zöld.
- A diff nem érint flaget, hálózati kódot, perzisztencia-sémát vagy logolást; nyers audio kiírására utaló új kód nincs.

## Független security újraellenőrzés — 2026-08-15

Verdikt: CHANGES REQUIRED

### MAJOR — A lezárt futási handle a nyers PCM-et megtartja

`analysis_isolate_runner.dart:137-139` végleges `request` referenciája a
`request.audio.input.samples` listára mutat. `_dispose()` (`259-270`) a
portokat és az izolátumot felszabadítja, de ezt a referenciát sem teljes
futáskor, sem `cancel()`-kor nem engedi el. Így egy hívó által megtartott
lezárt `AnalysisRunHandle` a nyers PCM-et is megtartja, ami ütközik a brief
§5.2 „a futás végén eldobódik” előírásával.

Javasolt irány: a belső request/audio referencia legyen nullázható, a spawn
értékeit lokálisan rögzítse, majd teljesítés, hiba és cancel után minden úton
engedje el; komplett és cancel regressziós teszt szükséges. Új PCM-logolást,
perzisztenciát, exportot vagy dokumentum-codec transzportot a review nem talált.
