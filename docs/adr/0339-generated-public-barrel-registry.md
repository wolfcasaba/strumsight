# ADR 0339 — Csak bizonyított generált feature-barrel kerülhet az ütközésmentes registry-be

**Státusz:** elfogadva (E99-R18 pre-flight, 2026-08-20)

## Kontextus

A kör-szlotter a közös fájlutakat ütközésként kezeli. Egy generált
`public.dart` csak akkor hagyható figyelmen kívül, ha újragenerálása
determinista és a gate frissességét ténylegesen ellenőrzi. Az első D4-kísérlet
globbal minden feature gyökér `public.dart`-ját generáltnak minősítette; ez az
E04-R15/E04-R16 valódi ütközését elrejtette.

## Döntés

A `tools/round-slots.py` explicit registry-je tartalmazza az ütközésmentes
generált barrel-outputokat. Bejegyzéshez kötelező a fragmentum-forrás, a
determinista generátor és a `--check`-et futtató architecture gate. A pilot
egyetlen bejegyzése `lib/features/practice_generator/public.dart`.

Glob vagy más blanket szabály nem helyettesítheti ezt a bizonyítékot. A nem
regisztrált feature gyökér `public.dart` továbbra is teljes ütközési felület.

## Következmények

Új feature csak a saját migrációs körében, a fenti három bizonyítékkal kerülhet
a registry-be. A fragmentumok maguk nem generált outputok, ezért továbbra is
ütköznek. A meglévő E04 valós-brief regressziós teszt és az E99-R18 D4
falszifikációs cellái mindkét irányt őrzik.

## Hivatkozások

- ADR 0307 §5
- ADR 0176
- `docs/LESSONS.md` L129, L343
- E99-R18 brief §0.0c–§0.0e
