# ADR 0242 — A rotáció a KÖRHÖZ tartozik, és a force-push futtatható protokoll

**Státusz:** elfogadva (2026-08-13, user-döntés: *„Igen, governance-körként utána"* —
az `E06-R23` kétszeri megállása után).
Épít: [ADR 0087](0087-autonomous-round-pipeline.md) (kör-pipeline, H1–H8),
[ADR 0112](0112-self-healing-pipeline.md) (önjavítás),
[ADR 0138](0138-factory-hardening-scope-guard-and-independence.md)
(reviewer-függetlenség, `H-INDEP`),
[ADR 0140](0140-switchable-implementer-engine-profiles.md) (motor-nyilvántartás),
[ADR 0222](0222-orchestrator-rotation-and-session-budget-gauge.md) (rotáció).

**Felülírja:** az [ADR 0087](0087-autonomous-round-pipeline.md) §2 **H8-sorának
szövegét** (lásd Döntés 4). Az ADR 0087 minden más döntése, és az ADR 0222
rotációs elve **változatlanul érvényes** — ez az ADR nem a szabályt cseréli,
hanem az **állapot kulcsolását** javítja.

## Kontextus — egy kész, gate-zöld kör 4 óra 45 percet állt

2026-08-13-án az `E06-R23` (V2 analysis overview + metric cards) **kétszer**
állította meg a láncot. A kör munkája végig kész volt: a review és a security
review is APPROVED, a gate zöld. Egyik halt sem kódhiba volt.

**1. `H-INDEP` — 4 óra 35 perc** (`.pipeline/halted-20260813T040134.txt`).
Az eredeti dispatch helyes párt adott: `orchestrator=terra` +
`implementer=sonnet-impl`. A session `H3`-ra elhalt, a self-heal javította
(PR #240). Az **újraindítás** viszont a `round-pipeline.sh:1516` **globális**
állapotírása miatt `orchestrator=claude`-ra billent, miközben az ágon már
`sonnet-impl` (ugyanaz a `~/.claude` kvóta) commitolt. Nem maradt független
reviewer. A `H-INDEP` az ADR 0138 S4 szerint nem önjavítható → a lánc emberre várt.

**2. `H8` — 10 perc, majdnem adatvesztéssel** (`.pipeline/halted-20260813T044434.txt`).
A rebase `origin/main`-re **konfliktus nélkül sikerült**, a
`git push --force-with-lease` mégis elutasításra futott. A halt ezt
„branch-szabály szerint külön engedélyt igényel"-ként diagnosztizálta. Mérve:
`gh api repos/:owner/:repo/rulesets` → `[]`; nincs ilyen szabály. A push a git
**saját lease-ellenőrzésén** bukott (`stale info`), mert a remote közben
előrement: a session 04:38:41-kor pusholta a security review commitot
(`27bce64`). A halt által javasolt feloldás — *„fetch, majd force-with-lease"* —
szó szerint végrehajtva **eldobta volna ezt a commitot**, azaz a kör egyik
merge-feltételét.

**A közös nevező:** a lánc két olyan ponton döntött, ahol a döntés bemenete
**mérhető lett volna**, de senki nem mérte — az egyik a kör identitása, a másik
a távoli ág tényleges állapota.

## Döntés

### 1. A kör orchestrátora a KÖRHÖZ rögzül, nem a lánchoz

Az állapot körönként kulcsolt (`<state_dir>/orchestrator-round/<ROUND>`). Az
első dispatch rögzíti a kör orchestrátorát; **minden további dispatch ugyanazt
kapja vissza, léptetés nélkül.** A globális `orchestrator-last` megmarad az
`alternate` léptetés hordozójának, de **kizárólag ÚJ kör indításakor** frissül.

*Miért nem elég az utólagos ellenőrzés:* attól a kör még elveszíti az eredeti
orchestrátorát, és minden elhalt kör **torzítja** az `alternate` számlálást is —
azaz az ADR 0222 fele-fele arányát, aminek a kvóta-védelem a célja.

### 2. Folytatáskor az implementer-identitás az ágról MÉRT tény

Ha a körhöz már tartozik távoli ág, akkor az ág **prefixe** a commitolt
implementer neve (`sonnet-impl/e06-r23-…`), feloldva a
`docs/execution/engine-registry.tsv` `name` oszlopából. A dispatch **előtt**
ellenőrizni kell, hogy ez az implementer és a feloldott orchestrátor nem oszt-e
kvótát (`engine_uses_claude_quota()`).

Ütközéskor a feloldás kötött sorrendje:

1. a körhöz (1. döntés szerint) rögzített orchestrátor, ha az független;
2. ha nem: a registry bármely elérhető motorja, amely a mért implementerrel nem
   oszt kvótát;
3. ha nincs ilyen: `H-INDEP` — **fail-closed**.

**Folytatáskor az implementer fix, az orchestrátor a mozgatható szereplő.**
Aki az implementert billenti át, az a kész diffet dobja el.

Ismeretlen (registryből fel nem oldható) ág-prefix szintén `H-INDEP`: a
függetlenség **bizonyítandó, nem vélelmezendő**.

### 3. A rebase utáni push futtatható protokoll, nem prompt-szöveg

`tools/safe-force-push.sh <branch>` négy kötelező lépése:

1. a **pontos** ref lefetchelése (`refs/heads/<b>:refs/remotes/origin/<b>`);
2. a **remote-only** commitok felsorolása **patch-id** alapon
   (`git log --cherry-mark --left-right`, a `=` jelöltek kiszűrve) — a rebaseelt
   ekvivalensek NEM remote-only commitok;
3. ha van remote-only commit → **exit 3, a lista kiírásával, push NÉLKÜL**;
4. különben `git push --force-with-lease=<b>:<a 2. lépésben MÉRT SHA>`.

Sima `--force` és argumentum nélküli `--force-with-lease` egyaránt tilos: az
utóbbi a lokális remote-tracking refre támaszkodik, ami épp a mai hibamód volt.

*Miért script és nem szabálymondat:* a `docs/LESSONS.md` L09 mért tanulsága
szerint a szöveges előírás nem tart — a mérce futtatható artefaktum kell legyen.
Mai állapot: a `force-with-lease` a repó **egyetlen** scriptjében sem szerepelt,
a műveletet minden session újra kitalálta.

### 4. A H8 jelentése pontosítva

- **H8 marad:** a `main` mozdult ÉS a rebase **konfliktust** ad.
- **NEM H8:** a `--force-with-lease` elutasítása önmagában — az a 3. döntés
  protokolljának **első lépése**, nem a vége.
- **H8 lesz:** ha a remote-only commitok beépítése konfliktust ad.

Ez a pontosítás **felülírja** az ADR 0087 §2 H8-sorának szövegét. Az ADR 0087
fájlja nem szerkeszthető (merge-elt ADR módosítása = H1); az operatív szöveg a
`docs/execution/pipeline-orchestrator-prompt.md` H8-sorában frissül, erre az
ADR-re hivatkozva.

## Következmények

- Egy mid-round halt + újraindítás **nem tud** azonos-identitású reviewerbe
  fordulni. A `H-INDEP` megmarad emberi döntésnek (ADR 0138 S4), de a helyzet,
  ami kiváltotta, megelőzhetővé válik.
- Az `alternate` arány pontosabb lesz: az elhalt körök újraindításai nem
  számítanak külön léptetésnek.
- A rebase utáni push **nem tud csendben commitot eldobni** — a megtagadás
  felsorolja, mi lenne veszélyben.
- Az `orchestrator-round/` könyvtár körönként egy bejegyzéssel nő; ez szándékos
  audit-nyom, a takarítás a `.pipeline/archive` mintáját követi, ÉLŐ kört nem
  törölhet.
- **Nincs terméki hatás:** a döntés nulla Dart sort érint.

## Mérce

A döntések gépi mércéje az `E99-R08` (GOV-07) kör:
`tools/tests/test_round_resume_independence.py`,
`tools/tests/test_safe_force_push.py` és a kiegészített
`tools/tests/test_orchestrator_rotation.py` — mind hermetikus
(`PIPELINE_STATE_DIR`, lokális bare repók), hálózat és élő modellhívás nélkül.
A rotáció három kötelező cellája: **első dispatch** (rögzít) / **második
dispatch ugyanarra a körre** (nem billen) / **új kör** (billen).

Lásd: [`docs/rounds/e99-r08-gov-07-per-round-orchestrator-rotation.md`](../rounds/e99-r08-gov-07-per-round-orchestrator-rotation.md) §6.1.
