# ADR 0058 — Közös WAV codec a core-ban és gépi architecture guard

- **Státusz:** elfogadva (2026-07-29, E01-R10 B-rész, [PR #13](https://github.com/wolfcasaba/strumsight/pull/13));
  **a fájl utólag, az E01-R16 zárókörben lett rögzítve** — a döntés és a hivatkozás
  (HANDOFF, [ADR 0057](0057-shared-music-domain-and-feature-public-api.md)) a
  merge óta élt, de az ADR-fájl lemaradt a körből.
- **Kontextus:** [ADR 0057](0057-shared-music-domain-and-feature-public-api.md)
  (közös zenei domain + feature public API — az R10 A-része), SDD Ch2 §10.3–10.5.

## Kontextus

Az R10 A-része a zenei szókincset (`Chord`, `Strum`, `Tuning`, …) emelte a
`lib/core/music/`-ba. A B-rész két maradék osztályt kezelt:

1. **WAV kódolás két példányban élt:** az encoder a Learn, a decoder az Analyze
   feature-ben — két külön RIFF-értelmezés, amelyeknek kompatibilitását semmi
   nem kötötte össze.
2. **Az architektúra-szabályokat (core nem importál feature-t, közös domain
   Flutter-mentes, cross-feature import csak `public.dart`-on át) semmi nem
   kényszerítette ki gépileg** — a szabály annyit ért, amennyit a review észrevett.

## Döntés

1. **A WAV encoder + decoder a `lib/core/audio/codec/`-be költözik** (a
   `SlidingFramer` a `lib/core/audio/dsp/`-be), és egy **round-trip teszt** köti
   össze a két oldal RIFF-értelmezését — encode → decode bájthelyes körutat állít.
2. **`tool/check_architecture.dart` + `test/core/architecture_dependency_test.dart`
   — a CLI és a teszt UGYANAZT a logikát hívja.** Négy szabály:
   core nem importál feature-t · a közös domain nem importál
   Fluttert/Riverpodot/Dio-t/plugint · cross-feature import csak `public.dart`-ra ·
   tételes allowlist a 12 ismert `analyze → live/engine/{dsp,ml}` kivételre.
3. **Az allowlist csak csökkenhet.** Új tétel írásos indoklást és ADR-t igényel;
   az **elavult (már nem sértő) bejegyzés is elhasítja a gate-et** — egy feloldott
   eltérés nem maradhat rejtve a listában.
4. A négy szabály mindegyike **valódi, kézzel bevitt sértéssel lett igazolva**
   (új cross-feature import, `core → feature`, `core/music → package:flutter`,
   elavult allowlist-sor) → mindegyik exit 1 + pontos hibasor.

## Következmények

- A RIFF-értelmezés egyetlen helyen él; az encoder/decoder drift gépi teszt alá került.
- Az architektúra-szabály többé nem review-fegyelem kérdése: az R14 óta a
  guard a CI gate-sor része is (ADR 0062), az R16 óta composite actionből fut.
- Ismert follow-up (R10-ből): a `WavDecoder`-t a `lib/`-ből semmi nem hívja —
  az „importáld a saját audiódat" út bekötése későbbi epicre maradt.
