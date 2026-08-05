# Review — E04-R06 Kurált tutor tudásbázis schema és első content pack

- **Verdikt:** ✅ **APPROVED**
- **Branch:** `codex/e04-r06-knowledge-schema-and-content-pack` · **impl. commit:** `dacda69`
- **Implementer:** Codex (`gpt-5.6-terra`, örökölt kézi override) · **Reviewer:** Claude Opus 4.8 (független, read-only)
- **Review-mód:** izolált `/tmp/review-e04-r06` klón (a közös working tree-t nem érintette)
- **ADR:** [0135](../adr/0135-tutor-knowledge-governance.md) (tutor-knowledge-governance, pre-flight)

## 1. Jelzés + handoff

Az implementer záró jelzése `stopped` volt — **NEM** kód-hiba: a gitignore-olt,
generált `lib/l10n/app_localizations.dart` hiánya miatt az `analyze` piros lett a
motor worktree-jében. Ez **build-előfeltétel, nem scope-kérdés** (a fájl tracked
forrás nem, az allowed_paths-ba nem tartozik). Az orchestrátor a worktree-ben
`flutter pub get` + `flutter gen-l10n` futtatásával helyreállította; a CI maga is
regenerálja. A brief §10 handoff kitöltve, a szállított diff tételesen leírva.

## 2. Gate — reviewer által, izolált /tmp klónban ÚJRAFUTTATVA

```
tools/round-gate.sh test/features/ai_tutor/data
  format         zöld
  analyze        zöld
  test           zöld (28 teszt, ebből 14 az új knowledge_codec + manifest)
  architecture   zöld (12 allowlisted deviation)
GATE_EXIT=0
```

A gate a friss `/tmp/review-e04-r06` klónban zöld (l10n-előfeltétel helyreállítva).
A teljes suite + randomizált property + APK a CI exact-SHA (`dacda69`) dispatch alatt.

## 3. Scope-audit

`git diff --stat main...branch`: 18 fájl, mind a brief §4 `allowed_paths` listáján
belül (5 en + 5 hu content JSON, `manifest.json`, `knowledge_document.dart`,
`knowledge_codec.dart`, `build_tutor_knowledge_manifest.dart`, 2 teszt,
`pubspec.yaml` additív assets, brief §10). **`lib/features/ai_tutor/public.dart`
érintetlen** (pre-flight §0.0 nulla-export boundary invariáns) — igazolva
`git diff`-fel. Listán kívüli fájl: nincs.

## 4. Acceptance criteria — tételes bizonyíték

| Kritérium | Bizonyíték | Verdikt |
|---|---|---|
| Manifest 4 hibakód (duplicate ID / missing license / hash mismatch / corrupt content) külön kóddal | `KnowledgeManifestErrorCode` 4 distinct const; 4 teszt zöld a gate-ben | ✅ |
| **Approved-only build** (reviewNeeded/rejected kizárva) | `status == KnowledgeApprovalStatus.approved` erős egyenlőség (`build_tutor_knowledge_manifest.dart:96`); teszt `hasLength(1)` | ✅ |
| Approved-only szűrő mutáció-próbával RED | **Reviewer-próba** (lásd §5) — `!= rejected` gyengítés → a teszt PIROS | ✅ |
| Locale coverage rhythm/chord/technique/practice/safety en+hu | `manifest.json` 10 dokumentum, 5 topic × {en,hu}, mind `approved`, `CC0-1.0` | ✅ |
| Build reprodukálható (bit-azonos kétszeri futtatás) | `writes a bit-identical manifest when built twice` teszt zöld; sha256, óra/véletlen/float nincs | ✅ |
| Jogtisztaság (license-mező, nincs `docs/rag` másolás) | minden dok. `CC0-1.0`; content saját szerzésű, rövid; `docs/rag` érintetlen | ✅ |

## 5. Reviewer-próba (eldobható, dokumentálva, futtatás után eldobva)

**Approved-only guard valódi-sértés próba** (a legmagasabb kockázatú tartalmi
előírás, brief §6): a `build_tutor_knowledge_manifest.dart` szűrőjét
ideiglenesen `status != KnowledgeApprovalStatus.rejected`-re gyengítettem (ez egy
`reviewNeeded` dokumentumot átengedne).

```
flutter test test/features/ai_tutor/data/knowledge_manifest_test.dart
  → FAIL: "includes only explicitly approved documents in production output"
git checkout tool/build_tutor_knowledge_manifest.dart   # visszaállítva
```

A guard genuine: a gyengítés PIROSRA váltja a delivered tesztet. A próba a
klónban futott, a fájl visszaállítva, a merge-elt diff nem tartalmazza.

## 6. Architektúra + termékhatárok

- Greenfield, **hívó nélkül**: `public.dart` üres → production viselkedés
  változatlan; a knowledge kód még nincs bekötve (R07 retrieval fogyasztja).
- Nincs audio/mic/hálózat/secret érintés (AGENTS.md §5). A codec tiszta,
  determinisztikus; nincs clock/random/float (AGENTS.md §9 szellemében a hash
  reprodukálható). `crypto ^3.0.7` direkt függőség, forrás-SHA provenance-hoz.
- A `tool/` build-script feature-internal importja megengedett (nem lib-kód); az
  architecture-gate zöld (12 allowlisted deviation).

## 7. Leletek

| # | Osztály | Lelet |
|---|---|---|
| — | — | Nincs BLOCKER / MAJOR / MINOR. |
| N1 | NOTE | A `KnowledgeChunk.id` 1-alapú (`$documentId#${index+1}`), miközben az `index` 0-alapú — konzisztens és tesztelt, csak jelzés a jövőbeli retrieval-körnek. |

**Merge-döntés:** zöld kapu (format/analyze/architecture reviewer-igazolt; teljes
suite + property + APK a CI exact-SHA `dacda69` dispatch alatt) és nulla OPEN
BLOCKER/MAJOR → merge engedélyezett a CI zöldjének megerősítése után.
