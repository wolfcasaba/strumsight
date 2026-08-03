# ADR 0088 — MiniMax-first fejlesztési router a Codex execution harnessben

**Státusz:** elfogadva (explicit user-döntés, 2026-08-01; napi policy
módosítva explicit user-döntéssel, 2026-08-02).
Pontosítja az [ADR 0069](0069-two-engine-implementer-pool.md) motorválasztását és
az [ADR 0087](0087-autonomous-round-pipeline.md) implementer/javítókör ágát. Az
[ADR 0052](0052-ci-apk-automerge-session-per-round.md) független review-, CI- és
merge-kapuja változatlan.

## Kontextus

A StrumSight fejlesztésénél a MiniMax M3 legyen az alapértelmezett kódoló, a
Codex/ChatGPT keret pedig csak objektíven igazolt elakadásnál vagy magas
kockázatú diff célzott vizsgálatánál fogyjon. A korábbi rendszer a motort a
kör előtt, emberi/LLM-besorolással választotta ki, majd a MiniMaxot a Claude
Code harnessben futtatta. Ez nem különítette el kellően:

- a kódhibát a provider kvóta-, 429-, 5xx- vagy hálózati hibájától;
- az első sikertelen megoldást a valódi, ismétlődő elakadástól;
- a modell szerkesztési jogát a review/CI/merge tulajdonjogától;
- az egy taskra és UTC-napra engedett Terra-fogyasztást a processzhaláltól.

Az Epic 3 huszonkét commitolt briefje már tételes scope-ot és célzott gate-et
ad. Ezekből géppel olvasható, fail-closed szerződés készíthető.

## Döntés

### 1. Közös Codex harness, MiniMax-first állapotgép

Az új `engine=auto` útvonal a `tools/model-router.py` programot használja. A
router a Codex CLI Responses API execution harnessén keresztül futtatja:

1. MiniMax M3 első megoldási kör;
2. strukturált scope-audit és quality gate;
3. legfeljebb egy célzott M3 javítás;
4. csak két kódhibás kör vagy magas kockázat esetén egy Terra kör;
5. végső scope-audit és gate.

A limitek taskonként: pontosan **2 befejezett M3-megoldási kísérlet**, legfeljebb
**1 Terra-hívás**. A `max_automatic_terra_calls_per_utc_day = 0` érték
**korlátlan UTC-napi összesített policyt** jelent; pozitív érték megtartott,
explicit vészkorlát. A task-keretet review-javítás, resume, új worktree vagy
processzhalál nem nullázhatja. A Terra-ledger korlátlan módban is minden
foglalást megőriz audit- és crash-safety célból.

### 2. Objektív eszkaláció és providerhibák

Terra indulhat, ha két M3-kör után kódminőségi gate marad piros, vagy a brief /
tényleges diff magas kockázatú. Magas kockázat:

- auth, jogosultság, token, titok, kriptográfia vagy fizetés;
- tárolómigráció, törlés, adatvesztés vagy irreverzibilis transzformáció;
- konkurencia, race, processzközi lock;
- kompatibilitást törő publikus modulinterfész.

MiniMax 429, quota/tokenablak, HTTP 5xx, DNS/TLS/hálózat/timeout, hiányzó helyi
dependency vagy sandbox/jogosultsági blokk **soha nem Terra-eszkaláció**. Ezek
`DEFERRED` vagy `BLOCKED` állapotot adnak, és nem fogyasztanak befejezett
M3-megoldási kísérletet.

### 3. Állapotok és tulajdonosi határ

| Routerállapot | Pipeline-jelzés | Jelentés |
|---|---|---|
| `READY_FOR_REVIEW` | `progress` | scope + router-gate zöld; független review következik |
| `STOPPED` | `stopped` | nincs további automatikus modellhívás |
| `DEFERRED` | `blocked` | provider/kvóta vagy napi keret helyreállására vár |
| `BLOCKED` | `blocked` | környezet-, policy-, credential- vagy task-előfeltétel hibás |
| `INTERNAL_ERROR` | `blocked` | router-integritási/konfigurációs hiba |

`READY_FOR_REVIEW` **nem Done**. A pipeline/Claude-orchestrátor tulajdona marad:
worktree/branch, pre-flight commit, a router diffjének commitja, független
review, CI-dispatch, PR, merge, queue és HANDOFF. Csak review + CI + merge után
adható `done`.

Az M3/Terra nem commitol, nem pushol, nem nyit PR-t, nem ír queue-t és nem futtat
`tools/codex-signal.sh`-t. A külső `tools/ai-router-round.sh` adapter írja a
redaktált jelzést.

### 4. Brief-szerződés és scope-védelem

Minden `auto` task pontosan egy fenced `ai-router` TOML blokkot tartalmaz:

- `schema_version = 1`;
- `risk = "normal" | "high"`;
- normalizált, repository-relatív `allowed_paths`;
- kizárólag `test/` alatti `gate_tests`;
- `native_gate` boolean.

Ismeretlen vagy hiányzó kulcs, abszolút/`..`/wildcard út, duplikált blokk vagy
nem engedélyezett gate fail-closed. Az audit a kiindulási commit óta minden
tracked, untracked, ignored, törölt és symlink útvonalat vizsgál. A router és a
pipeline policy, `.git`, `.pipeline`, queue és router-config védett.

### 5. Gate és Git-határ

A router baseline-kapuja format + analyze + architecture ellenőrzést futtat,
majd minden megoldási kör után a brief célzott tesztjeit és `git diff --check`-et.
`native_gate=true` esetén a repó tényleges natív szerződése a debug APK build.
A teljes suite, randomizált property és APK CI továbbra is az orchestrátor
független, exact-`headSha` kapuja.

A modellek szándékosan uncommitted diffen dolgoznak. Ez biztosítja, hogy a Terra
csak a szükséges scoped diffet kapja meg; `READY_FOR_REVIEW` után az
orchestrátor auditál és commitol.

### 6. Crash-safe külső state

A hiteles state nem a modell által írható worktree-ben, hanem
`~/.local/state/strumsight-ai-router/` alatt él, privát jogosultságokkal és
fájllockkal. Tartalmazza a brief hashét, baseline SHA-t, fázist, kísérleteket,
gate-kategóriákat, diff-hasheket és Terra-ledgert, de nem tartalmaz promptot,
titkot vagy teljes provider-választ.

A Terra-helyet a hívás előtt atomikusan `reserved`, majd `started` és
`finished` állapotba kell tenni. Bizonytalan processzhalálnál a foglalás
elfogyasztottnak számít. Megszakított M3-hívás után resume előbb auditálja és
gate-eli a megmaradt diffet; csak üres/piros diffnél nyithat következő kört.

### 7. Profilok és hitelesítés

- `m3.config.toml`: `MiniMax-M3`, provider `minimax`, adaptive thinking;
- `terra.config.toml`: `gpt-5.6-terra`, medium reasoning;
- mindkét modell explicit `workspace-write`, `never`, `ephemeral`, JSONL és
  stdin-prompt módban fut;
- a smoke tesztek `read-only` módban futnak;
- a MiniMax provider command-backed credential helpert használ, amely a privát
  `~/.mmx/config.json` fájlból csak stdouton adja át a tokent;
- a korábbi OpenSpace MCP-ben ugyanennek a kulcsnak a literal példánya privát
  runtime-wrapperre migrálódik, a többi MCP-beállítás változtatása nélkül;
- a globális Codex modell/provider és a ChatGPT login változatlan marad.

A quota helper kizárólag tipizált, redaktált százalékos állapotot ír ki; nyers
provider bodyt vagy kulcsot soha.

### 8. Queue és örökölt módok

Az engine enum: `auto | minimax | codex`. Ismeretlen érték preflight-hiba. Az
Epic 2 meglévő sorai változatlan, explicit legacy motorral futnak. Az Epic 3
R01–R21 sorai `auto`, de kezdetben `prepared` állapotúak; csak az Epic 2 kézi
lezárása után tehetők `pending`-gé. Az Epic 3 R22 epic-zárás az ADR 0087 szerint
kézi indítású.

Az explicit `minimax` és `codex` reprodukciós override megtartja a régi
wrapper-útvonalat. Az ADR 0069 előzetes, feladattípus szerinti motorválasztása
és a Claude Code MiniMax harness **csak az `auto` alapértelmezésre nézve
felülírt**; legacy reprodukcióhoz tovább él.

### Módosítás (ADR 0112 önjavító kör, 2026-08-03) — egy review-gated Terra javítás

**Mérés.** E03-R12-ben a két M3 megoldási kísérlet és a magas-kockázatú diff
első Terra-eszkalációja zöld router-gate-tel `READY_FOR_REVIEW`-t adott. Az
izolált független review ezután négy MAJOR leletet mért; a H3 scope-heal csak a
közös MIDI track-limit ownerét oldotta fel. A következő szabályos
`resume(review_findings)` a korábbi, taskonkénti egy Terra-hívás miatt még a
leletek továbbítása előtt `STOPPED: task Terra budget is exhausted` lett.

**Döntés.** A taskonkénti Terra-keret pontosan két hívás: az első a meglévő
M3→Terra eszkaláció, a második kizárólag egy már `READY_FOR_REVIEW` állapotú
tasknak, nem üres független review-leletet tartalmazó `resume` útján érhető el.
Egy sima `run` nem nyithatja újra a terminális review-állapotot, STOPPED vagy
DEFERRED task továbbra sem kap új hívást, a globális UTC-napi ledger pedig
mindkét foglalást auditálja. Nem változik a két M3-kísérlet, a scope-audit, a
gate vagy a CI-kapu; a második Terra csak a reviewer által konkrétan mért
BLOCKER/MAJOR javítására szolgál.

**Regresszió.** `RouterResumeTest.test_review_findings_get_one_bounded_terra_repair_after_initial_escalation`
egy megmaradt első Terra-foglalás, két elfogyasztott M3-kísérlet és explicit
review-lelet mellett pontosan egy második Terra-profilt, majd `terra_calls=2`
állapotot követel. A config-teszt a 2-n kívüli task-limitet fail-closed elutasítja.

## Következmények

- A feladatok nagy része MiniMaxon marad, a Terra-fogyasztás objektív és
  crash-safe task-korlátot, valamint teljes audit-ledgert kap.
- Providerhiba nem égeti automatikusan a ChatGPT/Codex keretet.
- A gépi scope/gate eredmény reprodukálható, de nem helyettesíti a szemantikailag
  független review-t.
- A magas kockázatú zöld diff is fogyaszthat egy Terra-reviewt. A helyi napi
  összesített policy nem állítja meg; tényleges provider-kvóta, rate limit,
  auth- vagy hálózati hiba továbbra is fail-closed állapotot okoz.
- A `prepared` queue miatt a telepítés és smoke nem indít el fejlesztési kört.

## Elutasított alternatívák

- **Szabad M3–Terra beszélgetés:** nem determinisztikus és keretpazarló.
- **GPT minden feladat előzetes osztályozására/reviewjára:** a ritka specialistát
  állandó vezérlővé tenné.
- **MiniMax szolgáltatási hiba automatikus Terra-fallbackje:** összekeveri a
  provider elérhetőségét a modell képességével.
- **Teljes repository elküldése Terrának:** szükségtelen kontextus- és
  keretfogyasztás; a bounded escalation packet elég.
- **State a worktree-ben:** a modell módosíthatná vagy új worktree-vel
  megkerülhetné a limiteket.
