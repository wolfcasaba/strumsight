# Epic 04 — Knowledge retrieval latency baseline

**Mérés dátuma:** 2026-08-05
**Kör:** E04-R07
**Módszer:** a commitolt knowledge pack manifestjének és tíz JSON-dokumentumának
helyi fájlból olvasása, validálása és indexelése; utána 101 meleg `chord`/`en`
lekérdezésből a középső minta.

| Mért érték | Fixture | Eredmény |
| --- | ---: | ---: |
| Index-load | 10 dokumentum, 20 chunk | 36 315 µs (36,315 ms) |
| Warm query p50 | 10 dokumentum, 20 chunk | 449 µs (0,449 ms) |

Reprodukció:

```bash
flutter test test/features/ai_tutor/data/knowledge_retriever_test.dart --plain-name 'measures the committed pack load and warm retrieval baseline'
```

Ez fejlesztői boxon, fájlrendszer-alapú asset-loaderrel mért baseline; nem Android
készülékes latency-ígéret. A 150 ms-os Epic 4 célértékhez külön célkészülékes mérés
szükséges, amikor a retrievalnek már van hívója.
