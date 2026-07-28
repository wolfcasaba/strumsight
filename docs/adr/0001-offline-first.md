# ADR 0001 — Offline-first

**Státusz:** elfogadva (a projekt kezdete óta gyakorlat; formalizálva E01-R01, 2026-07-28)

## Döntés

A StrumSight alapfunkciói (Live, Tuner, Learn, Practice, Analyze helyi fájllal,
Songs, Progress, Streak, lokális Library) fiók és hálózat nélkül működnek.
A detektálás 100%-ban on-device fut; nyers audio alapértelmezetten nem hagyja
el az eszközt. A FastAPI backend opcionális réteg (login + settings sync +
Lab diagnosztika), a kliens kijelentkezett, diagnostics-off állapotban nem
indíthat hálózati kérést.

## Kontextus

A round 14-ben a Supabase helyett saját FastAPI+SQLite+JWT backend készült,
kifejezetten opcionálisként. A Lab-diagnosztika (r197–r199) explicit opt-in.

## Következmények

- Minden új feature-nek definiálnia kell az offline viselkedését (SDD Ch1 §3.3).
- Network guard teszt kötelező az Epic 1 zárásához (Ch2 Kör 16.2: 0 request).
- Cloud AI / Community / sync soha nem ronthatja az offline alapélményt.
