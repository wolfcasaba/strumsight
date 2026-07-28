# ADR 0002 — Feature-first, fokozatos Clean Architecture

**Státusz:** elfogadva (E01-R01, 2026-07-28)

## Döntés

A kód feature-first marad (`lib/features/<feature>/`), és FOKOZATOSAN veszi
fel a Clean Architecture rétegeket (`domain/ application/ data/ presentation/
public.dart`). A célszabályok: domain nem függ Fluttertől/Riverpodtól/Dio-tól;
core nem importál feature-t; cross-feature elérés csak `public.dart` vagy közös
core contract útján. Riverpod 3 kézzel írt providerekkel, codegen nélkül.

## Kontextus

A kódbázis ~168 forrás- és ~163 tesztfájllal, működő DSP-motorral érkezik a
programba (204 kör). A big-bang átszervezés tiltott (SDD Ch2 §2.2): a meglévő
cross-feature importok ideiglenes allowlistre kerülnek, amely csak csökkenhet.

## Következmények

- Architecture guard (tool/check_architecture.dart) az E01-R10 körben jön létre.
- Új kód azonnal az új szabályok szerint; régi kód körönként migrál.
- Kompatibilitási re-export átmenetileg megengedett, @Deprecated jelöléssel.
