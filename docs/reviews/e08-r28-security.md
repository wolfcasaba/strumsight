# E08-R28 — Security review

Brief: `docs/rounds/e08-r28-ledger-sync-contract-and-merge.md` (`risk = "high"`)
Diff: `f055e97e..af7f2264`
Reviewer: `security-reviewer` agent (dispatched by Claude Sonnet 5 orchestrator) · Dátum: 2026-08-22
Verdikt: **PASS** (0 CRITICAL, 0 BLOCKER)

## Kockázat-indoklás (a brief-lint S7 leletére, §0.0 kiegészítése)

A kör két új, kliens-adatot fogadó backend API-felületi fájlt hoz létre (`schemas.py`, `service.py`), és a szerződés maga a jutalom-integritás biztonsági határa (a szerver soha nem fogadhat el kliens-oldali összesített XP-t). A dedikált review ezért kötelező volt (AGENTS.md §15.1).

## Terjedelem

Read-only review, `/tmp/review-e08-r28` izolált klónban. A 7 deklarált fájl mindegyike ellenőrizve; nincs élő fogyasztó a `lib/`-ben (a `public.dart` barrel-exporton kívül semmi nem hívja az új szimbólumokat), nincs `dio`/`http`/`Socket`/`HttpClient` a diffben.

## Eredmények

1. **Kliens-összesített XP nem juthat el a szerver totáljáig — PASS.** `extra="forbid"` mindkét szinten (nyugta és envelope), a szerver-oldali `compute_total_xp` kizárólag a validált nyugták `baseXp+bonusXp` összegéből számol; a `ReceiptOut.totalXp`-t is eldobja és újraszámolja a `_to_uploads` kerülőn át.
2. **`verified` nem önmagára-állítható a kliens által — PASS**, egy látens MAJOR mellékleltettel: a `verified` ma kizárólag séma-érvényességet jelent, XP felső korlát vagy policy-újraszámolás NÉLKÜL (lásd a fő review N1 lelete — nem blokkoló, mert nincs élő fogyasztó, ami bizalmi jelzésként olvasná).
3. **Nulla hálózati kérés kikapcsolt szinkron esetén — PASS** erre a körre (nincs hálózati kód a diffben); MINOR: a `shouldRun`/transport kapcsolat ma csak doc-comment, nem strukturális — jövőbeli hívónak kell fegyelmezettnek lennie (lásd a fő review N2 lelete).
4. **Nincs secret/token/nyers audio vagy kamera-adat a diffben — PASS** (grep-pel ellenőrizve).
5. **Injekció/hibás bemenet kezelése — PASS**, egy MINOR melléklelettel: nincs felső korlát (`max_length`) az id-mezőkön és a nyugta-listán (látens DoS, be nem drótozott útvonalon — lásd a fő review F2 lelete, JAVÍTANDÓ a fix körben).
6. **Supersession nem használható legitim nyugta eldobására — PASS.** A backend-oldali `_apply_supersession` valódi no-op; a Dart-oldali csak a REMOTE oldalt szűri, a LOKÁLIS nyugta soha nem esik ki.

## Összegzés a fő reviewhoz

A biztonsági review NEM talált CRITICAL/BLOCKER-t — a kör központi invariánsa (a szerver soha nem bízik kliens-összegben) empirikusan zárt mindkét rétegen. A talált MAJOR (látens, N1) és a két MINOR (N2, és a max_length hiánya — utóbbi a fő review F2-jébe emelve, mert olcsón javítható MOST) nem blokkolják ezt a kört, de a max_length hiányát a fő review kötelező javításként viszi tovább (F2), mert ugyanabban a fájlban, ugyanabban a fix körben olcsón megoldható.
