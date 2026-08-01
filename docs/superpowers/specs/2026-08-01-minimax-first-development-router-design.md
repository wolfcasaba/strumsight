# MiniMax-first fejlesztési router — tervspecifikáció

**Dátum:** 2026-08-01
**Állapot:** jóváhagyott tervezés, implementáció előtt
**Hatókör:** StrumSight / music-theory projekt az Oracle ARM Ubuntu szerveren

## 1. Cél

A StrumSight fejlesztési körök alapértelmezett implementere a MiniMax M3 legyen.
Az eredményt ne egy másik nyelvi modell, hanem a repository futtatható quality
gate-je ellenőrizze. Az M3 egy célzott javítási kört kapjon, a GPT-5.6 Terra
pedig csak objektíven igazolt elakadásnál vagy magas kockázatú diff célzott
ellenőrzésénél induljon el.

A kívánt eredmény:

- ugyanaz a Codex CLI és ugyanazok a repository-szabályok szolgálják ki mindkét
  modellt;
- az M3 az alapértelmezett, a Terra ritkán használt specialista;
- a routing determinisztikus és visszakövethető;
- kvóta-, hálózati és környezeti hibák nem fogyasztanak Terra-keretet;
- egyetlen modell sem dönthet saját eszkalációjáról;
- a jelenlegi round pipeline, gate, izoláció és Git-folyamat megmarad.

## 2. Kiinduló állapot

A szerver auditja alapján:

- a Codex CLI telepítve van, és ChatGPT-alapú bejelentkezést használ;
- a globális Codex-konfiguráció jelenlegi alapmodellje nem MiniMax, és ezt a
  terv nem változtatja meg;
- külön `m3` és `terra` profil még nincs;
- a `MINIMAX_API_KEY` nincs tartósan exportálva a munkafolyamat környezetébe;
- a MiniMax-hitelesítés a meglévő `~/.mmx/config.json` fájlból elérhető;
- a repository már rendelkezik `tools/round-pipeline.sh`,
  `tools/mm-round.sh`, `tools/round-gate.sh`, pipeline queue és kétmotoros ADR
  alapokkal.

Ezért nem készül párhuzamos, második fejlesztési rendszer. A meglévő pipeline
kap egy új, determinisztikus routing-réteget.

## 3. Hatókör és nem célok

### 3.1 Hatókör

- gépszintű, újrahasználható `m3` és `terra` Codex-profil;
- StrumSight-specifikus automatikus router;
- a meglévő round queue és pipeline integrációja;
- M3-futtatás, javítás, quality gate és célzott Terra-eszkaláció;
- futási naplók, hibaujjlenyomatok, napi Terra-korlát és helyreállítható
  állapot;
- automatizált tesztek a router állapotgépére;
- dokumentáció az `AGENTS.md`, az ADR-ek és a pipeline használói számára.

### 3.2 Nem cél

- a szerver összes repositoryjára kiterjedő automatikus routing;
- a jelenlegi globális Codex-alapmodell lecserélése;
- modellek szabad beszélgetése vagy kölcsönös, korlátlan eszközelérése;
- teljes repository automatikus betöltése a Terra kontextusába;
- automatikus push, GitHub PR-nyitás vagy merge;
- MiniMax szolgáltatási hiba automatikus átterelése a Terrára;
- két modell párhuzamos írása ugyanabba a worktree-be;
- a repository teljes CI-jának minden egyes modellkör utáni helyi futtatása.

## 4. Megközelítési döntés

Három lehetőség került értékelésre:

1. A meglévő round pipeline kibővítése determinisztikus routerrel.
2. Különálló `ai-run` rendszer létrehozása a jelenlegi pipeline mellett.
3. Csak profilok létrehozása, kézi modellváltással.

Az elfogadott megoldás az **1. lehetőség**. Ez őrzi meg a jelenlegi queue-,
státusz-, gate-, worktree- és értesítési működést, miközben elkerüli a
párhuzamos állapotkezelést.

## 5. Magas szintű architektúra

```text
docs/execution/pipeline-queue.tsv
                │
                ▼
       tools/round-pipeline.sh
                │  engine=auto
                ▼
  meglévő headless Claude-orchestrátor
       │                    │
       │                    └── független review + CI + merge + végső státusz
       ▼
 tools/model-router.py  (determinista implementációs alrendszer)
       │
       ├── gépszintű quota helper + autoritatív state és zár
       ├── codex exec --profile m3
       │          └── tools/round-gate.sh + kiegészítő gate-ek
       └── codex exec --profile terra
                  └── végső router-gate
```

Az `auto` útvonalon a Claude-orchestrátor nem választ implementermodellt, nem
értékeli az M3 bizonytalanságát, és nem dönt Terra-eszkalációról. Egyszer indítja
a routert, majd annak strukturált eredménye után a repositoryban már kötelező,
független read-only review-, CI- és merge-szerepét látja el. A router zöld
eredménye ezért `READY_FOR_REVIEW`, nem a teljes kör végleges `done` állapota.

### 5.1 Géphez tartozó komponensek

- `~/.codex/config.toml`: MiniMax custom provider, a jelenlegi alapbeállítások
  megőrzésével;
- `~/.codex/m3.config.toml`: MiniMax M3 profil;
- `~/.codex/terra.config.toml`: GPT-5.6 Terra profil;
- egy csak a felhasználó által futtatható credential helper;
- egy csak megtisztított kvótaadatot kiadó quota helper;
- projekt-specifikus, worktree-k között közös Terra-keretállapot a felhasználó
  helyi state könyvtárában.

### 5.2 Repository-komponensek

- `tools/model-router.py`: a determinisztikus állapotgép;
- `.ai/router.yaml`: limitek, retry-szabályok, tiltott útvonalak és
  magas-kockázatú minták;
- `tools/round-pipeline.sh`: az `auto` motor integrációja;
- `tools/round-gate.sh`: a meglévő Flutter quality gate, változatlan
  felelősséggel;
- router unit- és integrációs tesztek;
- dokumentáció és a következő szabad sorszámú ADR.

A YAML-konfiguráció verziózott sémát használ, safe loaderrel töltődik be, és
ismeretlen vagy hibás kulcsnál fail-closed módon leáll. A szükséges tooling
dependency verziója rögzített; hiánya `ENV_BLOCKED`, nem modellhiba.

### 5.3 Kompatibilitás

A queue új alapértelmezett motorértéke az `auto`. A meglévő explicit motorértékek
megmaradnak kézi felülbírálásra és korábbi körök reprodukálására. Az `auto`
értéket csak az új router kezeli.

### 5.4 Az `auto` task gépi szerződése

`auto` kör csak verziózott, géppel olvasható `ai-router` metaadatot tartalmazó
briefből indulhat. A metaadat legalább az alábbiakat rögzíti:

- `schema_version`;
- `risk: normal | high`;
- `allowed_paths`;
- `gate_tests`;
- `native_gate`.

A precheck a commitolt brief metaadatát betölti, validálja, hasheli, majd annak
változtathatatlan másolatát az autoritatív gépszintű run-state-be menti. A modell
futás közben nem bővítheti saját fájlhatárát vagy gate-jét a brief átírásával.
Hiányzó vagy kétértelmű metaadat `INVALID_TASK`. A korábbi, explicit
`minimax`/`codex` queue-sorok ettől továbbra is reprodukálhatók.

## 6. Végrehajtási állapotgép

Egy M3-kör jelentése egy teljes modellfuttatás, amelyet független quality gate
követ. A két engedélyezett M3-kör tehát:

1. első implementáció;
2. egy, az első gate-hibára célzott javítás.

Az állapotok:

1. `PRECHECK`
   - task és brief betöltése;
   - Git/worktree és tiszta kiindulási állapot ellenőrzése;
   - fájlzár megszerzése;
   - profilok, credential helper, quota helper és helyi függőségek ellenőrzése;
   - engedélyezett útvonalak és gate-argumentumok validálása;
   - tiszta HEAD-ről baseline diff-, manifest- és gate-snapshot készítése;
   - a célzott baseline gate futtatása még modellindítás előtt. Piros baseline
     `ENV_BLOCKED` vagy pre-existing `CODE_FAILURE`, és nem indít M3-at/Terrát.
2. `M3_ATTEMPT_1`
   - az eredeti, változatlan task átadása az M3-profilnak;
   - `workspace-write`, `approval_policy=never`, `--ephemeral` futtatás.
3. `GATE_1`
   - a router, nem az M3, futtatja az előírt quality gate-et;
   - siker esetén `READY_FOR_REVIEW`, kivéve ha magas kockázatú Terra-review
     szükséges;
   - szolgáltatási vagy környezeti hiba esetén `DEFERRED` vagy `BLOCKED`;
   - kódhiba esetén javítócsomag készül.
4. `M3_ATTEMPT_2`
   - csak az eredeti taskot, a konkrét hibaösszefoglalót, az érintett diffet és
     az előírt gate-et kapja;
   - nincs újratervezés vagy kapcsolódó refaktor.
5. `GATE_2`
   - siker esetén `READY_FOR_REVIEW`, kivéve ha magas kockázatú ellenőrzés
     szükséges;
   - második kódhiba esetén eszkalációs döntés.
6. `TERRA_REVIEW_OR_FIX`
   - legfeljebb egy Terra-hívás;
   - kizárólag a generált escalation packetből és a célzott workspace-olvasásból
     dolgozik;
   - magas kockázatú, már zöld diffnél elsősorban ellenőriz, és csak indokolt
     esetben javít;
   - ismételten hibás M3-megoldásnál minimális gyökérok-javítást készít.
7. `FINAL_GATE`
   - ugyanaz a független router-gate fut újra;
   - siker esetén `READY_FOR_REVIEW`;
   - bármely hiba esetén `STOPPED`, újabb automatikus modellhívás nélkül.
8. `INDEPENDENT_REVIEW_AND_CI`
   - a router visszaadja a vezérlést a meglévő orchestrátornak;
   - a reviewer újrafuttatja a gate-et, scope-auditot és tartalmi reviewt végez;
   - BLOCKER/MAJOR leletnél ugyanaz a router-run folytatódik: először csak a még
     fel nem használt M3-kör, utána legfeljebb a még fel nem használt Terra-hívás
     áll rendelkezésre;
   - minden review-javítás után ismét router-gate és független re-review kell;
   - ha a feladat teljes modellkerete elfogyott és kötelező lelet maradt, a kör
     `STOPPED`, nem nyílik új automatikus budget;
   - kizárólag a reviewer, a CI és az érvényes merge-szabályok sikere után lesz
     a pipeline-kör végső állapota `done`.

## 7. Routing- és eszkalációs szabályok

### 7.1 Alapkorlátok

```yaml
routing:
  default_engine: auto
  default_provider: minimax
  default_model: MiniMax-M3

limits:
  max_m3_attempts_per_task: 2
  max_terra_calls_per_task: 1
  max_automatic_terra_calls_per_utc_day: 3
  terra_reasoning: medium
  terra_packet_target_tokens: 40000
  terra_packet_max_bytes: 81920
```

A `terra_packet_target_tokens` router-szintű csomagméret-cél, nem kitalált vagy
nem támogatott Codex-konfigurációs kulcs. A Terra valódi modellablakát nem
csökkenti le mesterségesen.

### 7.2 Terra automatikus indításának feltételei

A második M3-kör után Terra indulhat, ha a hiba kódminőségi hiba és legalább az
alábbi objektív tény teljesül:

- a quality gate két M3-kör után is hibás;
- ugyanaz a normalizált hibaujjlenyomat maradt meg;
- a második körben nem változott a munkafa diff-hashe;
- ugyanaz a sikertelen gate és ugyanazok a diagnosztikai azonosítók maradtak;
- a task vagy a tényleges diff magas kockázatú kategóriát érint;
- publikus interfész törésének kockázata észlelhető;
- a commitolt, független review-jelentés BLOCKER/MAJOR leletet tartalmaz, és az
  adott task megmaradt M3-kerete már elfogyott.

A két sikertelen, kódhibával végződő gate önmagában elegendő az eszkalációhoz.
Az ismétlődő hiba és a változatlan diff az eszkalációs jelentés okát pontosítja,
nem egy harmadik M3-kört nyit meg.

### 7.3 Magas kockázatú diff

Magas kockázatú kategória:

- autentikáció vagy jogosultságkezelés;
- token-, kulcs- vagy titokkezelés;
- titkosítás;
- fizetés;
- adatbázis- vagy tárolómigráció;
- törlés, adatvesztés vagy visszaállíthatatlan transzformáció;
- konkurencia, race condition vagy processzek közötti zárolás;
- publikus modulinterfész kompatibilitást törő változása.

A besorolás két forrásból származik:

1. a round/task géppel olvasható kockázati jelölése;
2. a router konzervatív útvonal- és diffmintái.

Magas kockázat esetén a zöld M3-diff is kaphat egyetlen célzott Terra-reviewt.
A Terra nem kap felhatalmazást a teljes funkció újraírására.

### 7.4 Soha nem eszkaláló hibák

- MiniMax HTTP 429 vagy kifogyott tokenablak;
- MiniMax kvótakimerülés;
- MiniMax HTTP 5xx;
- DNS-, TLS-, hálózati vagy stream timeout;
- hiányzó Flutter/Dart/Gradle vagy más helyi dependency;
- sandbox- vagy jogosultsági blokk;
- hibás task/brief/gate konfiguráció;
- fájlzár vagy párhuzamos futás;
- az első quality gate egyszeri kódhibája.

### 7.5 Retry és defer

- A provider saját request/stream retry-ja legfeljebb két rövid próbát végezhet.
  A router csak akkor indíthat új transport-futtatást, ha bizonyíthatóan nem
  történt tool-hívás és nem változott a workspace. Részleges diff után a task
  `DEFERRED` vagy `STOPPED`, nem indul vakon újra.
- 429 vagy igazolt kvótahiba ugyanabban a futásban nem vált ki Terra-hívást.
  A router a quota helper alapján `DEFERRED` állapotot és — ha ismert — új
  próbálkozási időt rögzít.
- Hiányzó dependency vagy jogosultság esetén nincs modell-retry: a feladat
  `BLOCKED` állapotban, javítási útmutatóval leáll.
- Terra-hiba után az állapot `STOPPED`; nincs második Terra- vagy visszatérő
  M3-kör.

### 7.6 Terra napi költségkapu

- Egy feladat legfeljebb egy automatikus Terra-hívást fogyaszthat.
- A projekt UTC-naponként legfeljebb három automatikus Terra-hívást indíthat.
- A keret worktree-k között közös, gépszintű state fájlban és zárolással él.
- A `.ai/runs` jelentés a számláló eseményét tükrözi, de nem ez az autoritatív
  keretforrás, mert a modell által írható workspace nem módosíthatja a
  költségkaput.
- Kimerült napi keretnél a feladat `NEEDS_TERRA` állapotban megáll, és a branch
  változatlanul megmarad.
- Kézi Terra-indítás csak explicit emberi parancs lehet; az automatikus router
  nem emeli meg saját limitjét.

## 8. Codex-profilok

### 8.1 MiniMax provider

A jelenlegi `~/.codex/config.toml` megmarad, és kizárólag a custom provider
definícióval egészül ki:

```toml
[model_providers.minimax]
name = "MiniMax"
base_url = "https://api.minimax.io/v1"
wire_api = "responses"

[model_providers.minimax.auth]
command = "/home/ubuntu/.local/bin/codex-minimax-token"
timeout_ms = 5000
refresh_interval_ms = 0
```

Az implementáció előtt a tényleges felhasználói home és a helper útvonala
dinamikusan kerül feloldásra; a konfiguráció nem használ feloldatlan `$HOME`
helyőrzőt.

### 8.2 M3 profil

`~/.codex/m3.config.toml` tervezett lényegi beállításai:

```toml
model = "MiniMax-M3"
model_provider = "minimax"
model_context_window = 1000000
model_reasoning_effort = "high"
model_reasoning_summary = "none"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
```

MiniMax M3 esetén a `high` az Adaptive Thinking bekapcsolását jelenti. Egyszerű,
kézzel indított feladatnál később külön Think-Off profil készülhet, de az első
routerverzió nem növeli további profilokkal a konfigurációs felületet.

### 8.3 Terra profil

`~/.codex/terra.config.toml` tervezett lényegi beállításai:

```toml
model = "gpt-5.6-terra"
model_provider = "openai"
model_reasoning_effort = "medium"
model_verbosity = "low"
model_reasoning_summary = "none"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
```

A Terra a már meglévő ChatGPT-bejelentkezést használja. `OPENAI_API_KEY` vagy
`CODEX_API_KEY` nem kerül beállításra.

### 8.4 Automatizált indítás

A router nem hagyatkozik az interaktív profil approval-beállítására, hanem
explicit futtatási kapcsolókat ad:

```text
codex exec --profile <m3|terra> \
  --cd <izolált-task-worktree> \
  --sandbox workspace-write \
  --ask-for-approval never \
  --ephemeral \
  --json \
  -
```

A router a promptot közvetlen subprocess-stdin-en adja át. Nem használ shell
interpolációt, `$(cat ...)` alakot vagy promptot tartalmazó parancssori
argumentumot.

A teljes jogosultságú `danger-full-access` mód tiltott. A jelenlegi külső
munkamappa feloldott host-hozzáférése nem öröklődő engedmény a gyermek
modellfolyamatoknak. A router minden `codex exec` argv-jában explicit rögzíti a
`workspace-write` és `never` értékeket, naplózza a megtisztított invocationt, és
policy-felülírás vagy nem ellenőrizhető sandbox esetén `POLICY_BLOCKED`
állapotban leáll.

## 9. Titokkezelés és biztonsági határ

### 9.1 Credential helper

- A helper a meglévő `~/.mmx/config.json` fájlból olvassa ki az API-kulcsot.
- A helper induláskor `lstat` alapján ellenőrzi, hogy a credential rendes fájl,
  nem symlink, tulajdonosa az aktuális UID, és módja legfeljebb `0600`.
- A helper abszolút útvonalról, shell nélkül indul; saját módja `0700`, és
  `umask 077` mellett működik.
- A helper csak a tokent írja stdout-ra, egyéb adatot nem.
- Nincs `set -x`, teljes environment dump vagy Authorization fejléc naplózás.
- A Codex command-backed authentication hívja meg a helpert.
- A kulcs nem kerül job-wide környezeti változóba, ezért a repository által
  indított tesztfolyamatok nem öröklik `MINIMAX_API_KEY` néven.

### 9.2 Quota helper

- A helper közvetlenül olvassa a credentialt, majd meghívja a MiniMax
  `/v1/token_plan/remains` végpontját.
- A kulcs nem szerepel parancssori argumentumban.
- Stdout-on csak szükséges, megtisztított kvóta- és resetadat jelenik meg.
- A quota helper timeoutja, hibás JSON-ja vagy ismeretlen válasza fail-closed
  `DEFERRED` állapot; soha nem indít Terrát.
- A 401/403 credential-blokk, a 429/quota defer, az 5xx/hálózat korlátozott
  provider-retry után defer.
- A router nem kódol fix havi, heti vagy ötórás tokenmennyiséget; a szolgáltató
  aktuális válasza és a fiók usage felülete az irányadó.

### 9.3 Workspace-védelem

- Egy task egy izolált worktree-ben vagy a meglévő pipeline izolált klónjában
  fut.
- Ugyanabba a workspace-be egyszerre csak egy modell írhat.
- A router taskonként fájlzárat tart.
- A task engedélyezett és tiltott útvonalait a precheck ellenőrzi.
- Modellfuttatás után a router a tracked, untracked, ignored, törölt és
  symlinkes útvonalakat is auditálja; nem csak a normál `git diff` kimenetét.
- A határvizsgálat a precheckben rögzített manifesthez viszonyít. Tiltott fájl,
  symlinkes kikerülés vagy ignored artefaktum esetén nem fut új modell, hanem
  `POLICY_BLOCKED` állapotban leáll.
- A router állapotát és a Terra-ledgert a modell nem tekintheti autoritatív
  szerkeszthető bemenetnek.

### 9.4 Redakció

A naplóírás előtt legalább az alábbi minták redakciója kötelező:

- bearer token és Authorization fejléc;
- MiniMax- és OpenAI-kulcsformátumok;
- a credential fájl `api_key` értéke;
- érzékeny environment-hozzárendelések;
- URL queryben vagy headerben megjelenő token.

A megvalósítás Definition of Done része egy automatikus secret-leak teszt.

## 10. Quality gate

### 10.1 Meglévő gate újrahasználata

A Flutter quality gate egyetlen forrása továbbra is
`tools/round-gate.sh`. A router nem hiszi el egyik modell saját „tesztek
zöldek” állítását sem; a modelltől függetlenül futtatja a gate-et.

A jelenlegi sorrend megmarad:

1. `dart format --output=none --set-exit-if-changed`;
2. `flutter analyze`;
3. a kör által érintett, célzott Flutter-tesztek;
4. `tool/check_architecture.dart`.

A router ehhez hozzáadja:

5. `git diff --check`;
6. Android/Kotlin/Gradle változásnál a routerkonfigurációban rögzített natív
   gate-et.

A teljes suite, randomizált property gate és APK továbbra is a repository
meglévő CI-határán fut az érvényes ADR szerint.

### 10.2 Parancsbiztonság

- A briefből csak szigorúan felismert `tools/round-gate.sh` invocation és
  validált repository-relatív tesztútvonal vehető át.
- A router nem használ `eval`-t, és nem hajt végre tetszőleges Markdownból
  kinyert shellkódot.
- A validált argumentumok argv-listaként kerülnek a subprocesshez.
- A kiegészítő natív gate-ek fix, verziózott routerkonfigurációból származnak.
- A gate-lépések külön processzekben, csonkítatlan kimenettel futnak.
- Nincs `&&`-láncolás vagy kimenetet/correct exit code-ot elrejtő pipe.

A meglévő `round-gate.sh` opcionális, atomikusan írt strukturált eredményfájlt
kap (`ROUND_GATE_RESULT_FILE`). Ennek verziózott sémája legalább az outcome-ot
(`pass | code_failure | environment_failure | invalid_gate`), a hibás lépést és
a kilépési kódot tartalmazza. A router ebből és a subprocess exit státuszából
dönt; a terminál emberi szövegét nem parse-olja routing céljára.

### 10.3 Gate-kimenet osztályozása

A router az első hibás parancsot, kilépési kódot és teljes nyers naplót megőrzi,
majd külön, redaktált és normalizált változatot készít routing céljára.

A hibaujjlenyomat tartalmazza:

- a sikertelen gate azonosítóját;
- a tesztnevet vagy diagnosztikai kódot;
- a lényegi hibaüzeneteket;
- a normalizált releváns naplórész SHA-256 hashét.

A normalizálás eltávolíthat ANSI-kódokat, időbélyegeket, run ID-ket és izolált
workspace abszolút előtagokat, de nem távolíthatja el a tesztnevet,
diagnosztikai kódot vagy a tényleges hibaüzenetet.

A diff-előrelépéshez a router rögzíti:

- `git diff --stat`;
- az érintett fájlok listáját;
- a diff tartalmi hashét;
- a két M3-kör közötti változást.

## 11. Hibaosztályok

| Osztály | Példa | Router-reakció | Terra |
|---|---|---|---|
| `PASS` | minden gate zöld | kész vagy kockázati review | csak magas kockázatnál |
| `CODE_FAILURE` | teszt, analyze, build hiba | második M3-kör, majd eszkaláció | két kódhiba után igen |
| `PROVIDER_TRANSIENT` | hálózat, 5xx, stream timeout | korlátozott retry/defer | nem |
| `PROVIDER_QUOTA` | 429, tokenablak, quota | defer és jelentés | nem |
| `ENV_BLOCKED` | hiányzó dependency | leállás és útmutató | nem |
| `POLICY_BLOCKED` | sandbox, tiltott útvonal | leállás | nem |
| `INVALID_TASK` | hibás brief vagy gate | leállás | nem |

A hibaosztályozó szabályok verziózottak és teszteltek. A precedencia:

1. sandbox/policy és credential 401/403;
2. 429/quota;
3. strukturált provider 5xx, timeout vagy hálózati esemény;
4. baseline és helyi dependency;
5. strukturált gate-outcome;
6. ismeretlen hiba → `STOPPED`.

A providerosztályozás elsődleges forrása a `codex exec --json` eseménytípusa és
exit státusza; redaktált szövegminta csak másodlagos jel. Dependency-hiba csak
akkor `ENV_BLOCKED`, ha az adott M3-kör nem módosított dependency manifestet vagy
lockfile-t; ellenkező esetben kódhiba. Ismeretlen providerhiba nem eszkalál
Terra felé.

## 12. Futási artefaktumok és kontextus

### 12.1 Repository-lokális, redaktált futási tükör

A `.ai/runs/` Git által figyelmen kívül hagyott, nem autoritatív könyvtár. Csak
a taskhoz szükséges redaktált csomagokat és a felhasználói eredményjelentést
tartalmazza. Javasolt szerkezet:

```text
.ai/runs/<task-id>/<run-id>/
├── task.md
├── run.json
├── gate-1.redacted.log
├── repair.md
├── gate-2.redacted.log
├── escalation.md
├── final-gate.redacted.log
└── result.md
```

A modell módosíthatja ezt a tükröt, ezért routing- vagy keretdöntés nem bízhat
benne. A router minden továbblépés előtt az autoritatív state-ből újragenerálja
vagy ellenőrzi a szükséges fájl hashét.

### 12.2 Autoritatív gépszintű állapot

A teljes autoritatív run-state, a nyers processznaplók, a napi Terra-ledger és
azok lockjai nem a modell által írható worktree-ben élnek, hanem például:

```text
~/.local/state/strumsight-ai-router/
├── runs/<task-id>/<run-id>/
│   ├── run.json
│   ├── attempt-1.jsonl
│   ├── gate-1.raw.log
│   ├── attempt-2.jsonl
│   ├── gate-2.raw.log
│   ├── terra.jsonl
│   └── final-gate.raw.log
├── terra-usage.json
├── terra-usage.lock
└── task-locks/
```

Ez biztosítja, hogy külön worktree vagy pipeline-klón se kerülhesse meg a napi
limitet, és a modell ne írhassa át saját routing-előzményeit. A state könyvtár
és a raw logok jogosultsága csak a szerverfelhasználónak enged olvasást/írást.

### 12.3 `run.json` minimális mezői

- schema version;
- task ID, brief path, ADR és branch;
- kiindulási commit SHA;
- workspace útvonal;
- aktuális állapot;
- M3-körök és Terra-hívás száma;
- profil, modell és futási időbélyeg;
- gate-parancsok, kilépési kódok és hibaosztályok;
- hibaujjlenyomatok és diff-hashek;
- magas-kockázati jelölések;
- eszkaláció vagy leállás indoka;
- végső eredmény.

Titok és teljes környezeti lista nem lehet a state mezőiben.

A Terra-hívás előtt a router egyedi eseményazonosítóval, fájlzár alatt és
atomikusan lefoglal egy napi kerethelyet. A `reserved`, `started` és `finished`
állapotok miatt processzhalál után sem ismételhető meg vagy számolható el kétszer
ugyanaz az automatikus hívás. A foglalás a hívás megkezdésekor fogyasztásnak
számít; bizonytalan kimenetel esetén fail-closed módon nem szabad felszabadítani.

### 12.4 Terra escalation packet

Az `escalation.md` tartalma:

1. eredeti, változatlan feladat;
2. elfogadási feltételek;
3. sikertelen quality gate parancs;
4. legfeljebb 300 releváns, redaktált hibanaplósor;
5. az M3-körök tényszerű eredménye;
6. hiba- és diff-összehasonlítás;
7. `git diff --stat` és releváns fájlok;
8. szükség esetén célzott diff-hunks;
9. megengedett és tiltott módosítások;
10. a végül futtatandó gate pontos azonosítója.

A csomag nem tartalmazza az M3 teljes beszélgetését vagy JSONL-jét. A router
40 000 tokenes becsült célméretet és 81 920 bájtos determinisztikus promptcsomag-
plafont alkalmaz. Ez nem garantálja a Terra teljes sessionjének 40 000 token alá
szorítását, mert a modell további tool-olvasásokat végezhet; ezért a releváns
fájllista, az olvasási utasítás és a scope-audit is kötelező. Nagy diffnél csak
célzott hunks kerülnek a csomagba.

## 13. Terra feladatutasítás

A generált utasítás lényegi szerződése:

```text
Diagnosztizáld a sikertelen MiniMax-megoldás valódi gyökérokát.

Készíts minimális, célzott javítást. Ne írj újra működő részeket,
ne változtass publikus interfészt szükség nélkül, és ne végezz
kapcsolódó, de nem kért refaktort.

Csak az escalation packetben felsorolt fájlokra és gate-ekre
összpontosíts. Egyetlen megoldási köröd van. A gate eredményét
a router függetlenül ellenőrzi.
```

Magas kockázatú, már zöld diff reviewjánál az utasítás elsődlegesen
ellenőrzést kér. A Terra csak konkrétan igazolt hiba esetén módosítson.

## 14. Pipeline-integráció

### 14.1 Queue

A queue kommentje és validációja kiegészül az `auto` motorral. Az elfogadott
engine-ek: `auto | minimax | codex`. Az új Epic 3 körök alapértelmezett értéke
`auto`; a régi sorok nem kerülnek mechanikusan átírásra. Ismeretlen engine
preflight-hiba, nem csendes fallback.

### 14.2 Round pipeline

`tools/round-pipeline.sh` feladata marad:

- a következő futtatható kör kiválasztása;
- az izolált workspace előkészítése;
- státusz és értesítés kezelése;
- az elfogadott Git-folyamat fenntartása.

`engine=auto` esetén az orchestrátor pontosan egyszer átadja a taskot, briefet,
workspace-t és körmetaadatot a routernek. A modellek választása és a gate-ek
közötti állapotgép onnantól kizárólag a router felelőssége. Az explicit
`minimax` és `codex` sorok ideiglenesen a régi útvonalat használhatják
reprodukcióhoz; az új ADR ezt örökölt módnak jelöli.

### 14.3 Tulajdonosi és Git-határ

- A pipeline/Claude-orchestrátor tulajdona: izolált workspace és branch
  létrehozása, preflight commit, független review, CI, végső commit/PR/merge és
  queue-státusz.
- A router tulajdona: M3/Terra indítás, saját state, diff-snapshot,
  scope-ellenőrzés és router-gate.
- Az M3 és a Terra kizárólag az engedélyezett production/test fájlokat
  szerkesztheti; nem pushol, nem nyit PR-t és nem írja a pipeline queue-t.
- Hiba vagy limit esetén a branch és workspace megmarad.
- A Terra ugyanazt a task workspace-t folytatja, de csak az M3 folyamat teljes
  befejezése után, ugyanazon task-lock alatt.

### 14.4 Állapotleképezés

| Routerállapot | Pipeline-jelzés | Queue | Jelentés |
|---|---|---|---|
| futó precheck/M3/gate/Terra | `progress` | `running` | aktuális fázis |
| `READY_FOR_REVIEW` | `progress` | `running` | orchestrátor folytatja a reviewt |
| review BLOCKER/MAJOR, maradt budget | `progress` | `running` | ugyanaz a router-run folytatódik |
| review + CI + merge kész | `done` | `done` | csak az orchestrátor jelezheti |
| `DEFERRED` / `NEEDS_TERRA` | `blocked` | `halted` | retry-idő vagy keretblokk |
| `ENV_BLOCKED` / `POLICY_BLOCKED` / `INVALID_TASK` | `blocked` | `halted` | javítandó előfeltétel |
| `STOPPED` | `stopped` | `halted` | Terra vagy ismeretlen végső hiba |

A router strukturált result fájlt és dokumentált kilépési kódot ad. A
`round-pipeline.sh` nem a terminálszövegből következtet. Jelzés nélkül meghalt
router `H-NOSIGNAL`-nak megfelelő haltot eredményez. A review-javítás ugyanazt a
`task-id`/`run-id` párost használja, ezért a korábbi M3- és Terra-fogyasztás nem
nullázódik.

### 14.5 ADR-viszony

Az új, következő szabad ADR az `auto` útvonalon kifejezetten felülírja az ADR
0069 régi MiniMax harness- és motorválasztási részeit. Az ADR 0069 független
review-, scope-audit- és zöld-kapu követelményei érvényben maradnak. Így nem
marad két egymásnak ellentmondó operatív szabály.

## 15. Tesztstratégia

### 15.1 Unit tesztek

- konfiguráció és alapértékek;
- állapotátmenetek;
- injektálható process runner, monotonic/UTC clock és filesystem adapter;
- baseline gate és pre-existing failure kezelése;
- M3- és Terra-limitek;
- UTC napi Terra-ledger;
- quota-, 429-, 5xx-, hálózati és timeout-osztályozás;
- dependency-, sandbox- és invalid-task osztályozás;
- hibaujjlenyomat normalizálás;
- diff-előrelépés és változatlan diff felismerése;
- magas-kockázati task- és diffminták;
- logredakció;
- escalation packet csonkítása és relevanciasorrendje;
- tiltott fájlok;
- atomikus state mentés és megszakítás utáni resume;
- fájlzár és konkurens indítás.

### 15.2 Integrációs tesztek

Fake `codex`, credential helper, quota helper és gate processzekkel legalább:

1. M3 elsőre zöld, Terra nem indul;
2. M3 elsőre piros, javítás után zöld;
3. M3 kétszer ugyanazzal a kódhibával piros, Terra egyszer indul;
4. M3 kétszer eltérő kódhibával piros, Terra egyszer indul;
5. 429 vagy quota esetén Terra nem indul;
6. hálózati retry kimerülése után defer/stop, Terra nélkül;
7. hiányzó Flutter esetén azonnali `ENV_BLOCKED`;
8. zöld, magas-kockázatú diffnél egy célzott Terra-review;
9. napi Terra-limitnél `NEEDS_TERRA`;
10. Terra-hiba után nincs új modellkör;
11. tiltott fájl esetén leállás;
12. megszakított futás nem számolja el kétszer ugyanazt a Terra-hívást;
13. crash a Terra-foglalás előtt, a `reserved` és a `started` állapotban;
14. strukturált gate-result és pipeline-státuszleképezés.

### 15.3 Valós smoke tesztek

- `codex --profile m3` konfiguráció és minimális, írásmentes M3-futtatás;
- a quota helper redaktált válasza;
- `codex --profile terra` konfiguráció és minimális, írásmentes Terra-futtatás;
- egy fixture repositoryban teljes állapotgépfutás;
- egy alacsony kockázatú StrumSight pilotkör;
- secret-leak ellenőrzés a konfigurációban, state-ben és redaktált naplókban.

A valós smoke futások a lehető legkisebb prompttal történnek, és nem használnak
automatikus Terra-eszkalációt csak a teszt kedvéért.

## 16. Bevezetés

1. Következő szabad ADR és részletes implementációs terv elkészítése.
2. Routertesztek megírása fake processzekkel.
3. Credential és quota helper elkészítése, jogosultságok ellenőrzése.
4. Codex provider és profilok hozzáadása a jelenlegi konfiguráció megőrzésével.
5. Router állapotgép implementálása.
6. Pipeline és queue integrációja.
7. Dokumentáció és `AGENTS.md` frissítése.
8. Fake és fixture integrációs tesztek.
9. Írásmentes, valós profil-smoke tesztek.
10. Egy alacsony kockázatú StrumSight pilotkör.
11. Sikeres pilot után az új Epic 3 queue-sorok alapértelmezett motorja `auto`.

## 17. Megfigyelhetőség és eredményjelentés

A pipeline-státusz és a végső `result.md` mutassa:

- task, branch és kiindulási commit;
- aktuális routerállapot;
- használt profil és kísérletszám;
- gate neve és eredménye;
- hibaosztály és normalizált ujjlenyomat;
- Terra-eszkaláció tényszerű oka;
- napi automatikus Terra-keret állapota;
- defer/blocked esetén a következő emberi lépés;
- végső siker vagy leállás.

Érzékeny adat, teljes promptbeszélgetés és teljes environment nem jelenhet meg a
státuszkimenetben.

## 18. Definition of Done

A MiniMax-first router akkor tekinthető elkészültnek, ha:

- a globális alapmodell és a jelenlegi ChatGPT-login változatlan maradt;
- az `m3` és `terra` profilok külön-külön működnek;
- a MiniMax-kulcs nincs TOML-ban, repóban, modell-shellkörnyezetben vagy
  naplóban;
- `engine=auto` esetén az M3 indul elsőként;
- egy kódhiba után pontosan egy M3-javítás történik;
- két kódhiba után legfeljebb egy Terra-hívás történik;
- 429, quota, hálózat, 5xx és dependency hiba nem indít Terrát;
- a napi három automatikus Terra-hívásos limit worktree-k között is érvényes;
- magas kockázatú diff célzott Terra-reviewt kap;
- a gate-et minden esetben a router futtatja;
- tiltott fájl vagy policy-sértés leállítja a folyamatot;
- megszakított futás biztonságosan folytatható;
- a router unit- és fake-integrációs tesztjei zöldek;
- az M3- és Terra-smoke teszt zöld;
- az alacsony kockázatú pilotkör zöld;
- `git diff --check` zöld;
- a szükséges ADR, `AGENTS.md`, pipeline és üzemeltetési dokumentáció elkészült.

## 19. Források

- [MiniMax: Use M3 in Codex](https://platform.minimax.io/docs/token-plan/codex)
- [MiniMax Token Plan quickstart](https://platform.minimax.io/docs/token-plan/quickstart)
- [Codex custom model providers](https://learn.chatgpt.com/docs/config-file/config-advanced#custom-model-providers)
- [Codex configuration basics](https://learn.chatgpt.com/docs/config-file/config-basic.md)
- [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)
