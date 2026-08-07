# E05-R13 — Security / Privacy / Prompt-Injection Review

Round: **E05-R13** — Hand track assignment és temporal smoothing
Branch: `minimax/e05-r13-hand-track-assignment-and-smoothing` @ `cd4d49e`
Diff reviewed: `origin/main...HEAD` (10 files, +1754 / −3; 4 új production Dart fájl + additív `public.dart` + tesztek/fixtures)
Risk header: `risk = "high"` → dedikált security-review kötelező (Epic 5 CV; a §0.0 szerint ezúttal **merge ELŐTT** ütemezve)
Reviewer: security-reviewer agent (read-only), izolált klón
Módszer: a 4 production fájl + a fogyasztott R12 input-típus (`hand_landmarks.dart`) teljes olvasása; a 8 teszt/fixture cella tényleges gate-elésének ellenőrzése; danger-grep (IO/network/logging/`assert`/mutable-static/loop/division) a diff production fájljain; a §5.1/5.2/5.5/5.6, §15.3–15.4, ADR 0179/0183 szöveg keresztref; és három reprodukciós próba eldobható pure-Dart harness-szel.

## Verdikt: **PASS** — 0 CRITICAL, 0 BLOCKER, 0 MAJOR

3 MINOR (mind **látens** — R13-ban nincs fogyasztó/untrusted feed; defense-in-depth az R14+ számára) + 2 NOTE. Egyik sem blokkolja a merge-et önmagában a biztonsági lencsén át. A round tiszta a nem-tárgyalható termékhatárokra: nincs persistencia, nincs hálózat, nincs raw-frame/landmark logolás, nincs titok, nincs nem-determinizmus, nincs prompt-injection útvonal.

> **Orchestrátor megjegyzés (2026-08-07):** a MINOR-2 itt ugyanazt a
> jelenséget írja le, amit a független funkcionális review (nem ez a
> jelentés) F1 **BLOCKER**-ként azonosított — a két review egymástól
> függetlenül, más módszerrel jutott ugyanarra a gyökérokra. A
> security-lencse MINOR-nak minősíti (nincs mai fogyasztó → nincs mai
> privacy/security kár), a funkcionális/architektúra-lencse BLOCKER-nek
> (a brief §5 pont 4 kötött döntését sérti, függetlenül a fogyasztó
> meglététől). A merge-gátló besorolás a funkcionális review-é; ez a
> jelentés a MINOR-2-t a saját súlyossági rendszerében hagyja, de a javító
> kör mindkettőt egyszerre oldja meg (ugyanaz a kódrészlet).

## Severity table

| # | Súlyosság | Fájl:sor | Egy sor |
|---|---|---|---|
| 1 | MINOR | `landmark_smoothing.dart:114-119` | A simított `visibility = max(raw, previous)` → monoton nem-csökkenő, elavult-optimista confidence (§5.5/§15.4/ADR 0179). |
| 2 | MINOR | `hand_track_assigner.dart:245-268`, `172-181` | Tartós áthelyeződés: a jump-rejection örökre elutasít, a track mégis `active` marad friss `lastSeen`-nel, a pozíció befagyva — hamis „aktívan követem" jelzés, nincs kiút. (Lásd orchestrátor-megjegyzés fent — ugyanez a review F1 BLOCKERje.) |
| 3 | MINOR | `hand_track_assigner.dart:98,108-134` + `hand_landmarks.dart:140-165` | Nincs kéz-szám korlát frame-enként; a greedy matching `matched.contains` List-en → mért O(N³)/frame; unbounded track-mintázás (ADR 0183 „no unbounded runtime accumulation" szelleme). |
| 4 | NOTE | `landmark_smoothing.dart:102-108` | `filter(raw:null, previous:null)` egy `(0,0,0)` origó-pontot gyárt (visibility 0 jelzi, de a koordináta valódinak tűnik); R13-ban `filterMap`-en át nem elérhető. |
| 5 | NOTE | `hand_track_assigner.dart:94-99,160,173` | Az injektált `frameIndex`-re nincs validáció; negatív/nem-monoton érték csendben elrontja a gap-logikát (nem crashel). Hívó-kontraktus, trusted app-kód. |

---

## Nem-tárgyalható termékhatárok (AGENTS.md §5 / SDD §5) — mind betartva

- **§5.1 / ADR 0183 (raw frame/landmark nem persistál, nincs unbounded history):** a 4 fájlban nulla IO/fájl/hálózat import. Danger-grep `dart:io|http|dio|Socket|File|print|debugPrint|developer.log|logger` a production diffre → üres. Nincs mit exfiltrálni, nincs logolt koordináta. A `_internal` track-lista korlátos (elveszett track törlődik, `:167`).
- **§5.2 kijelentkezett/diagnostics-off → nincs rejtett hálózat:** nincs hálózati felület egyáltalán.
- **§5.3 titok/token/frame nem kerül logba/hibába/commitba:** nincs log-hívás; a `handedness.name` (`track_continuity.dart:79`) zárt enum-név, nem szabad szöveg. A brief §10.7 szerint `tools/secrets` 0 találat 1911 fájlon.
- **§5.4 offline alapélmény:** N/A — tisztán on-device domain.
- **§5.5 gyenge confidence ≠ biztos állítás:** lásd MINOR-1 és MINOR-2 — a réteg magvakat ültet, de R13-ban nincs user-facing fogyasztó, a határ ma nincs áthágva (látens).
- **Prompt-injection / adat-provenance:** N/A. A round kimenete numerikus/enum; nincs szöveg-formázás, nincs AI-Tutor-felé menő útvonal.

---

## Findings

### MINOR-1 — a simított `visibility = MAX(raw, previous)` monoton nem-csökkenő, elavult-optimista confidence-t termel

- **Fájl:** `lib/features/vision/domain/landmarks/landmark_smoothing.dart:114-119`, a track-oldali visszacsatolással `hand_track_assigner.dart:241,260-266`.
- **Hibaforgatókönyv:** egy kéz eleinte tisztán látszik (`raw.visibility = 0.95`), majd tartósan gyengén (occlusion/rossz fény → `raw.visibility = 0.10` sok frame-en át). Mivel a `previous` maga is a futó maximum, a simított visibility soha nem csökken a történelmi max alá.
- **Mérve (reprodukálva):**
  ```
  frame 0: raw.visibility=0.95  smoothed.visibility=0.95
  frame 1: raw.visibility=0.10  smoothed.visibility=0.95
  frame 5: raw.visibility=0.10  smoothed.visibility=0.95
  ```
- **Sértett szabály:** SDD §5.5, §15.4 („confidence-aware exponential smoothing"), ADR 0179 §2.
- **Miért MINOR:** R13-ban egyetlen fogyasztó sem olvassa a `visibility`-t. Látens mag, ami az első `visibility`-t olvasó körben (R14+) hamis magabiztossággá válik, ha addig nem javítják.
- **Javasolt irány:** a simított visibility ne MAX legyen, hanem konzervatív (a raw követése, vagy külön confidence-EMA).

### MINOR-2 — tartós áthelyeződés: a jump-rejection örökre elutasít (= a funkcionális review F1 BLOCKERje)

Lásd a funkcionális review `docs/reviews/e05-r13-hand-track-assignment-and-smoothing-review.md` F1 tétele a teljes elemzésért, mért próbákért és javítási irányért — ugyanaz a gyökérok, ugyanaz a fix oldja meg mindkettőt.

### MINOR-3 — nincs kéz-szám korlát frame-enként → O(N³) matching-robbanás és unbounded track-mintázás

- **Fájl:** `hand_track_assigner.dart:98` (`result.hands` korlátlan), `:108-134` (1a matching, `matched.contains(candidate)` List-en a dupla cikluson belül), `:137-153` (1b: minden párosítatlan obszerváció új track).
- **Mérve (5 frame tartós sok-kéz bemenet):**
  ```
  n=500  hands x5 frames:    402 ms
  n=1000 hands x5 frames:   1972 ms
  n=2000 hands x5 frames:  15142 ms
  n=4000 hands x5 frames: 118571 ms     (dupla N ≈ 8× idő → köbös)
  ```
- **Miért MINOR:** R13-ban a bemenet valós on-device ML (≤2 kéz), nincs untrusted feed a hatókörben. Defense-in-depth az R14+ pipeline-drótozáshoz.
- **Javasolt irány (follow-up, NEM ennek a körnek a scope-ja — `hand_landmarks.dart` nincs az allowed_paths-on):** a `matched` legyen `Set` (O(1) tagság) a `List.contains` helyett; egy jövőbeli kör tegyen felső korlátot a kéz-számra a bemeneti oldalon.

### NOTE-1 — `filter(raw:null, previous:null)` egy `(0,0,0)` origó-pontot gyárt

`landmark_smoothing.dart:102-108`. `visibility:0` jelzi a hiányt; R13-ban `filterMap`-en át nem elérhető. Alacsony hatás.

### NOTE-2 — az injektált `frameIndex` validálatlan

`hand_track_assigner.dart:94-99,160,173`. Negatív/nem-monoton érték csendben elrontja a gap-számítást, de nem crashel, nem szivárogtat. Trusted app-kód kontraktusa.

---

## Ellenőrzött és PASS-elt pontok (evidenciával)

1. **Nincs persistencia/IO/hálózat/logolás — PASS.** Danger-grep a 4 production fájlon üres.
2. **Determinizmus (§5.6) — PASS.** `DateTime.now`/`Random`/`Stopwatch` a production kódban nem szerepel (csak doc-kommentben, az elkerülés dokumentálva).
3. **Nincs assert-only validáció — PASS.** A 4 fájlban nulla `assert`. A landmark-bemenet a `HandLandmarkPoint`/`HandObservation` konstruktorban valódi `ArgumentError`-ral védett (release-safe).
4. **Handedness/`leftHanded` szerep-leképezés — PASS.** Konfigurálható, nem hardcode; a 4-cellás mirror/left-handed paritás-teszt invariancia-próbaként igazolja.
5. **Nincs domain-en túli globális/statikus mutable állapot — PASS.**
6. **Additív public boundary — PASS.**
7. **A tesztek ténylegesen gate-elnek — PASS** (a fedetlen esetek MINOR-1/2/3-ként jelölve).

---

## Merge-döntés

**PASS a biztonsági lencsén át** — 0 CRITICAL/BLOCKER/MAJOR. A tényleges merge-gátat a párhuzamos funkcionális review F1 (BLOCKER) + F2 (MAJOR) tétele adja (lásd `e05-r13-hand-track-assignment-and-smoothing-review.md`) — a javító kör mindkét jelentés érintett tételeit egyszerre oldja meg, mert MINOR-2 itt = F1 ott.
