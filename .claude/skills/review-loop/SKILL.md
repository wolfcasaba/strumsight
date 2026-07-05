---
name: "Review Loop"
description: "Iteratív kód-review és hibajavítás loop fejlesztés befejezése után a recipewiser-mobile projektben. Maximum 5 körös automatikus minőség-ellenőrzés: flutter analyze hibák, Riverpod 3 minták, silent backend no-op csapda, Supabase tábla/oszlop nevek, brand tokenek, perf. Használd amikor: befejezett egy feature-t, commit előtt állsz, vagy user azt mondja 'review loop', 'review kör', 'ellenőrzés loop', 'nézd át 5x'."
---

# Review Loop (mobile)

## Mit csinál

Fejlesztés befejezése után max 5 alkalommal végigvizsgálja és javítja a változtatott Dart kódot.
Minden körben megkeresi és javítja a hibákat; ha tiszta — korábban kilép. Flutter/Riverpod/Supabase-
specifikus ellenőrzésekkel.

**⚠️ Soha ne láncold `flutter analyze && flutter test`** — OOM (exit 143) ezen az ARM gépen. Külön
Bash hívások, mindegyik ≥240s timeout.

---

## Indítás (minden loop előtt egyszer)
1. `git diff --name-only HEAD` → ez a review scope.
2. Jegyezd a fájlokat + iterációs számlálót (0/5).
3. `flutter analyze lib/` (ALONE) → baseline állapot.

---

## Minden iteráció (max 5x)

Az elején hirdesd: `--- Review Loop — N. kör / 5 ---`

### 1. Statikus elemzés
- `flutter analyze lib/` → javítsd az összes analyzer hibát/warningot/lintet (flutter_lints ^6).
- Nem használt import/változó, hiányzó `const`, dynamic ahol típus kéne.

### 2. Kódminőség review (a változott fájlokon)
- Logikai hibák, hiányzó edge-case-ek, hiányzó error handling.
- **Silent no-op csapda**: minden Supabase hívás `try/catch(_){}`-ben → rossz tábla/oszlop nevet
  elnyel. Ellenőrizd a neveket a baseline ellen (lásd lent), ne bízz az optimista UI-ban.
- Riverpod 3: hand-written provider (NINCS codegen), NINCS StateProvider (Notifier/NotifierProvider/
  AsyncNotifier), soha ne fagyaszd be `DateTime.now()`-t provider state-be (null = "ma").
- Repository-provider minta: real repo ha configured+signed-in, különben Preview repo.

### 3. Javítás
- Kritikus → magas → közepes sorrendben. Csak amit ez a fejlesztés érintett.

### 4. Ellenőrzés
- Ha érintett teszt van: `flutter test test/<érintett>` (ALONE), ne hozz be regressziót.

### 5. Döntés
- Találtál+javítottál → következő kör. Nem találtál → **early exit** (nem kell mind az 5). 5. kör → stop + összegzés.

---

## RecipeWiser-mobile-specifikus ellenőrzések

### Supabase műveletek
- [ ] EXACT tábla/oszlop a baseline ellen ellenőrizve:
      `awk '/CREATE TABLE.*"<table>"/,/\);/' ~/Recipewiser/supabase/migrations/00000000000000_remote_baseline.sql`
- [ ] Ismert gotchák: `recipe_favorites` (nem recipe_likes); cookbooks.`title` (nem name); social_posts.`profile_image`; weekly_meal_plans NINCS status oszlop.
- [ ] AI route hívás Bearer token-nel megy (`Authorization: Bearer <accessToken>`), különben 401.

### UI komponensek
- [ ] Brand: `AppColors.primary/secondary/brandGradient` — SOHA hardcode hex.
- [ ] Scraped title sanitizálva (`core/utils/text.dart` `sanitizeTitle`).
- [ ] Navigáció imperatív `Navigator.push(MaterialPageRoute(...))` — NEM go_router/context.go.
- [ ] Minden string/komment/identifier ANGOL (a userrel magyarul kommunikálsz).

### Perf
- [ ] `const` widget ahol a propok statikusak; `ListView.builder` nem-triviális listához.
- [ ] `ref.watch(p.select((s) => s.x))` a legkisebb slice-ra, alacsony szinten.

---

## Kimeneti formátum
Kör végén: `### N. kör — Talált: [...] · Javított: [...] · Státusz: Tiszta/Maradtak`
Loop végén: lefutott körök, összes javított, maradék, átnézett fájlok, ajánlás (Commit-ready / Manuális review).

## Fontos korlátok
- NE javíts olyan sort amit a fejlesztés nem érintett.
- NE futtasd a teljes `flutter test` suite-ot minden körben — csak az érintett teszt-fájlt.
- NE módosítsd a teszteket ha nem voltak a változtatás része.
- 5 kör után maradék hiba → jelezd, de ne blokkolj.
