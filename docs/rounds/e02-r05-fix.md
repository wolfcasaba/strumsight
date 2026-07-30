# E02-R05 javító kör — az Analyze-adapter idővonal-hossza és két teszt-rés

- **Státusz:** FIX ROUND (indítás: 2026-07-30)
- **Alap:** a te saját E02-R05 implementációd, ugyanabban a munkapéldányban, commit nélkül
- **Review:** [`docs/reviews/e02-r05-review.md`](../reviews/e02-r05-review.md) — 0 BLOCKER · 0 MAJOR · **3 MINOR** · 1 NOTE
- **Implementer motor:** MiniMax M3 (változatlan)

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh done    "<egy sor>"    # kész, minden gate zöld
tools/codex-signal.sh stopped "<egy sor>"    # brief-ütközés
tools/codex-signal.sh blocked "<egy sor>"    # a gate 3 javítás után is piros
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne commitolj, ne
pusholj. **STOP-klauzula:** ha bármelyik követelmény ütközik a §2
fájllistával vagy egy meglévő teszttel, ÁLLJ MEG és küldd a `stopped` jelzést.
A §3 a terved — ne készíts külön task-listát.

**A meglévő, zöld munkádból semmit ne írj át azon felül, amit ez a brief kér.**

## 1. Mit kell javítani

### MINOR-1 (kötelező) — a post-loop idővonal-növelés hibás feltétele

`lib/features/practice/data/adapters/analyze_practice_adapter.dart:104–107`:

```dart
// If the last issued tick is still at the bound, extend one more bar.
if (lastIssuedTick >= totalBeatsTicks - 1) {
  totalBeatsTicks += bpb * BeatPosition.ticksPerBeat;
}
```

A cikluson belüli növelés (`if (tick >= totalBeatsTicks) …`) után a
`lastIssuedTick >= totalBeatsTicks` eset **nem fordulhat elő**, a `- 1` viszont
azt is elkapja, amikor az utolsó esemény szabályosan a kizárólagos határ alatti
UTOLSÓ ticken ül — ilyenkor az idővonal indokolatlanul egy ütemmel hosszabb
lesz.

**Mért eset (120 BPM, 4/4, két pengetés `0.0` és `1.9989583333333334` s-nál):**
az utolsó esemény tickje **1919**, a határ **1920** → érvényes, mégis
`totalBeats == 8.0` lesz `4.0` helyett (a legacy `Lessons.fromAnalyze` 4-et ad).

**Javítás:** a post-loop blokk feltétele legyen `>= totalBeatsTicks` — vagy a
blokk törlendő, ha bizonyítod (teszttel), hogy a ciklus után már sosem igaz.
A választott megoldást a §4.1-ben indokold.

### MINOR-2 (kötelező) — a növelő ág nincs kipinnelve, és az eltérés nem volt deklarálva

A tick-ütközés feloldásánál a brief §5.5/8 „eldobás"-t írt elő, te
idővonal-növelést valósítottál meg. **A viselkedésed a jobb, marad** — az
[ADR 0071 §6](../adr/0071-legacy-practice-adapters.md) már ehhez igazítva.
Hiányzik viszont:

1. teszt, ami a **növelő ágat** méri: olyan klip, ahol a kerekítés az utolsó
   pengetést pont a `totalBeats` határra viszi (pl. 120 BPM, 4/4, pengetések
   `0.0` és `1.99995` s-nál → az utolsó tick 1920, a kiinduló határ 1920) →
   az elvárás: **két esemény marad** (nincs eldobás), a `totalBeats` egy
   ütemmel nő (8.0), és `validate()` üres;
2. a §4.3-ban deklaráld eltérésként (mit írt elő a brief, mit csináltál, miért).

### MINOR-3 (kötelező) — a t0-normalizálás nincs elkötelezett teszttel lefedve

Mind a négy Analyze-fixture 0,0 s-nál kezdődik, így a `timeSec - t0` kivonás
nem megkülönböztethető a nullától. **Kell egy teszt nem-nulla `t0`-val**, pl.
120 BPM, pengetések `1.7`, `2.2`, `2.7` s-nál → az elvárt tickek `0`, `480`,
`960`, és `totalBeats == 4.0`.

### NOTE-1 (opcionális, de kérem) — halott értékadás

`analyze_practice_adapter.dart:91`: a `bars = totalBeatsTicks ~/ (…)` értékadást
ezután semmi nem olvassa — törlendő (vagy a `bars` változó teljesen kivezethető,
ha a MINOR-1 javítás után sem kell).

## 2. Engedélyezett fájlok

| Fájl | Miért |
|---|---|
| `lib/features/practice/data/adapters/analyze_practice_adapter.dart` | MINOR-1 + NOTE-1 |
| `test/features/practice/data/adapters/analyze_practice_adapter_test.dart` | MINOR-2 + MINOR-3 tesztek |

**Minden más fájl tilos zóna** — beleértve a másik három adaptert, a
domain-modelleket, a `docs/`-ot és a `HANDOFF.md`-t.

## 3. Sorrend (ez a terved)

1. A két új teszt megírása (MINOR-2, MINOR-3) — a MINOR-1-et rögzítő
   `totalBeats == 4.0` assertion **RED** kell legyen a javítás előtt.
2. A MINOR-1 javítása + NOTE-1 törlése → GREEN.
3. Záró gate-sor (§4).

## 4. Kötelező ellenőrzések

Külön hívásokként, `&&` láncolás nélkül, **csővezeték és `tail` nélkül, teljes
kimenettel**:

```bash
~/flutter/bin/dart format --set-exit-if-changed lib test
~/flutter/bin/flutter analyze lib/ test/
~/flutter/bin/flutter test test/features/practice/
```

## 5. Jelentés

### 4.1 A MINOR-1 javítás és indoklása

### 4.2 Az új tesztek (RED → GREEN evidenciával)

### 4.3 Deklarált eltérés a brief §5.5/8-tól (MINOR-2)

### 4.4 A záró gate-ek szó szerinti kimenete
