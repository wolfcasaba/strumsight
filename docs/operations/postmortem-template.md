# Postmortem template

- **Kör:** E12-R34 (ADR 0490)
- **Használat:** minden [`hotfix-runbook.md`](hotfix-runbook.md) szerinti
  hotfixhez KÖTELEZŐ egy ebből másolt postmortem. Ez a fájl maga VÁZ — nem
  töltendő ki itt; másold `docs/operations/postmortems/<incident_id>.md`
  útvonalra, és ott töltsd ki.

**A kitöltés emberi lépés** (user + support + az implementer, aki a hotfixet
írta) — ez a dokumentum a MEZŐKET rögzíti, nem az adatot. Kitalált root
cause-t, kitalált időbélyeget vagy kitalált metrikát TILOS beírni.

---

## Incident azonosító

`<INC-YYYY-NNNN>` — kötelező, a [`hotfix-runbook.md`](hotfix-runbook.md) §2
szerint. A hozzá tartozó hotfix verziója: `<version>` (előző: `<previous_version>`).

## Idővonal

| Időpont (UTC) | Esemény |
|---|---|
| `<TBD>` | Első jelzés (monitoring riasztás / support jegy / user report) |
| `<TBD>` | Diagnózis kezdete |
| `<TBD>` | Root cause azonosítva |
| `<TBD>` | Hotfix `approve-hotfix` jóváhagyva |
| `<TBD>` | Hotfix production-ban |
| `<TBD>` | Incidens lezárva |

## Hatás

- **Érintett felhasználók / arány:** `<TBD>`
- **Súlyosság:** `<TBD>` (crash-loop / adatvesztés / biztonsági rés /
  fizetési vagy hitelesítési törés / egyéb)
- **Időtartam:** az első jelzéstől a hotfix production-ba kerüléséig.

## Root cause

`<TBD — a tényleges technikai ok, nem a tünet>`

## A javítás

- **Diff / PR:** `<link>`
- **Hotfix workflow dispatch:** `<run-link, ha telepítve van>`

## Kötelező regressziós teszt (ADR 0490 D4)

A [`hotfix-runbook.md`](hotfix-runbook.md) §3 szerint MINDEN hotfixhez
kötelező a hibát reprodukáló tesztcella, RED a javítás előtt, GREEN utána.

- **Tesztcella:** `<fájl:teszt-név>`
- **RED bizonyíték (javítás előtt):** `<a piros futás kimenete vagy linkje>`
- **GREEN bizonyíték (javítás után):** `<a zöld futás kimenete vagy linkje>`

## Miért nem kapta el ezt a rendes suite?

`<TBD — a tesztlefedettségi rés, amit a §-beli regressziós cella zár be>`

## Follow-up

| # | Teendő | Felelős | Határidő |
|---|---|---|---|
| 1 | `<TBD>` | `<TBD>` | `<TBD>` |

## Kapcsolódó dokumentumok

- Incidens: `<link>`
- Hotfix runbook: [`hotfix-runbook.md`](hotfix-runbook.md)
- Post-launch riport (ha a hotfix a 7./14. napi ablakba esik):
  [`post-launch-day7.md`](../release/post-launch-day7.md) /
  [`post-launch-day14.md`](../release/post-launch-day14.md)
