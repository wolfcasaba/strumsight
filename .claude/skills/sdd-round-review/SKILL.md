---
name: sdd-round-review
description: StrumSight kör-review protokoll (ADR 0055) — a Claude/Opus 5 ellenőrzői szerepe egy implementer-motor (Codex vagy MiniMax M3) diffje felett. READ-ONLY review, gate-újrafuttatás izolált /tmp klónban, scope-audit az engedélyezett-fájllista ellen, eldobható próbatesztek a legacy referenciával szemben, BLOCKER/MAJOR/MINOR/NOTE osztályozás. Használd, amikor kör-diffet kell review-zni, "review-zd a kört / a PR-t", javító kör utáni újra-ellenőrzésnél, vagy merge-döntés előtt.
---

# Kör-review protokoll (ellenőrzői oldal)

A review kimenete JELENTÉS (`docs/reviews/eXX-rYY-review.md`, sablon:
`docs/execution/09-review-report.md`), a merge ELŐTT commitolva. **Review
közben nem írsz production kódot** — különben összecsúszik az implementáló és
az ellenőrző szem. Kivétel csak explicit user-utasításra, a jelentésben rögzítve.

## Alapelv: a zöld gate NEM bizonyíték

Minden eddig átcsúszott hiba (E02-R04: 3 MAJOR, E02-R05: 3 MINOR) zöld gate-ek
mellett csúszott át. A motor formai fegyelme kiváló; a TARTALMI hűség a gyenge
pont — a szövegesen előírt viselkedést el tudja rontani úgy, hogy minden teszt
zöld marad. Ezért a review MÉR, nem olvas: eldobható próbatesztet ír, és a
kimenetet a legacy referenciával / a brief szó szerinti előírásával veti össze.

## Lépések (sorrendben)

1. **Jelzés + handoff.** `.codex-round-status` → a brief §10 „Implementation
   handoff" szekciója. `status=unknown` vagy bemásolt (csonkolt) gate-kimenet →
   semmit nem fogadsz el bemondásra.
2. **Gate-újrafuttatás SAJÁT kézzel, izolált /tmp klónban** — ezen a boxon
   párhuzamos ágens dolgozhat a közös working tree-ben, ezért reviewer-próbát
   SOHA ne a közös példányban futtass. A mérce egyetlen futtatható artefaktum
   (a csővezeték elrejti a kilépési kódot, `docs/LESSONS.md` L09; normatív
   forrás: `AGENTS.md` §12):
   ```bash
   git clone --branch <kör-branch> /home/ubuntu/music-theory /tmp/review-<kör>
   cd /tmp/review-<kör>
   tools/round-gate.sh test/<a kör érintett területe> [további teszt-útvonal ...]
   ```
3. **Scope-audit:** a hiteles eszköz `tools/scope-audit.py --repo <klón>
   --brief <brief> --base <a kör induló HEAD-je>` (ADR 0138 §1) — ne
   `git diff --stat` kézi átfutására hagyatkozz, a szemantikájuk nem azonos.
   Amit az eszköz `VIOLATION`-nak jelöl, az automatikusan legalább MAJOR.
   **A saját review-jelentésed (`docs/reviews/eXX-rYY-review.md`, kockázatos
   körnél `-security.md`) SOHA nem sértés, még akkor sem, ha a brief
   `allowed_paths`-a nem sorolja fel** — ez egy állandó, kód szintű mentesség
   (`tools/ai_router/security.py::GENERATED_IGNORED_PREFIXES`, mérve:
   `tools/tests/test_legacy_scope.py`), amit az eszköz `OK` sora mellett
   `N generated/ignored` számlálóként mutat. Ha bizonytalan vagy egy
   útvonalról, MÉRD MEG az eszközzel — ne a brief szövegéből következtess, és
   ne jelezz H3-at a saját kötelező review-artefaktumod miatt (mérve:
   E99-R08/H3, 2026-08-13 — a rotált orchestrátor pontosan ezt tévesztette el,
   az eszköz tényleges futtatása nélkül).
4. **Acceptance criteria tételesen** — kritériumonként bizonyíték (teszt,
   parancs-kimenet, futás-link). „Jól működik" nem bizonyíték.
5. **Próbatesztek** (eldobhatók, a jelentésben dokumentálva, merge előtt
   törölve): a számolt kimeneteket a legacy referencia-implementációval szembe
   mérd az ÉLEKEN (nem-nulla kezdet, határra kerekedő utolsó elem, üres
   bemenet); doc-comment állításokat (`const`, `immutable`, unmodifiable)
   tesztben bizonyíts; guard-testeknél valódi-sértés próba (ideiglenes
   rontás → piros → visszaállítás, a jelentés §-ában rögzítve).
6. **Architektúra + termékhatárok:** AGENTS.md §6 (domain-függetlenség,
   core↛feature, `public.dart` contract, UI↛plugin) és §5 (audio/hálózat/mic/
   secret). Lifecycle-erőforrások minden útvonalon felszabadulnak-e.
7. **Jelentés-írás** a súlyossági táblával; minden lelethez fájl:sor +
   bizonyíték + javasolt irány (de NEM kész patch).

| Osztály | Merge-hatás |
|---|---|
| BLOCKER / MAJOR | merge TILOS, amíg nyitva |
| MINOR | körben javítható, ha nem hizlalja a diffet; különben follow-up |
| NOTE | nem blokkol |

## Javító kör után

1. A gate-eket ÚJRA magad futtatod (friss /tmp klónban).
2. Leletenként ellenőrzöd a zárást — a javításhoz tartozik-e teszt, ami a
   hibát PIROSRA fogta volna.
3. A jelentést frissíted: APPROVED vagy újra CHANGES REQUESTED, a javító
   commit sha-jával.

## Merge-döntés előtt

- `gh pr list` / `gh run list` — a párhuzamos autonóm driver nyithatott már
  PR-t; a meglévő PR-törzset ellenőrizd, nem tulajdonít-e neked nem futtatott
  evidenciát.
- A zöld kapu (ADR 0052) minden elemét te magad láttad zöldnek (CI-run link a
  kör-branchre, nem `main`-re). Utána squash-merge kérdezés nélkül; a merge-elt
  `main`-en a gate-eket még egyszer függetlenül lefuttatod (AGENTS.md §15.1).
