# Oracle dev box — security update and reboot runbook

Scope: the OCI ARM Ubuntu box that runs the autonomous SDD round pipeline
(`tools/round-pipeline.sh` under cron). It covers (a) deciding whether an Oracle
Critical Security Patch Update actually applies here, (b) applying the updates
that do apply, and (c) rebooting without killing a round in flight.

## 1. Advisory triage — does an Oracle CSPU apply to this box?

The August 2026 notification points at
<https://www.oracle.com/security-alerts/cspuaug2026.html>. That page was fetched
and is the genuine Oracle advisory: released **2026-08-18**, **Rev 2 on
2026-08-20** (affected-version correction for one CVE), **943 new security
patches**. Highest-severity entries include CVE-2026-61241 (CVSS 10.0, Oracle
Internet Directory LDAP Server) and CVE-2026-70905 (CVSS 9.8, Oracle Access
Manager SAML agent), both remotely exploitable without authentication.

The affected product families are Oracle **products**: Database, Fusion
Middleware / WebLogic, E-Business Suite, Enterprise Manager, Communications,
Financial Services, Retail, Supply Chain, MySQL, Java SE / GraalVM, Primavera,
PeopleSoft, Siebel and ~20 more.

What this box actually runs:

| Layer | Here | In the CSPU? |
|---|---|---|
| Kernel `6.17.0-1019-oracle` | Canonical's `linux-oracle` flavour (OCI-tuned Ubuntu kernel) | No — a Canonical package, not an Oracle product |
| OS | Ubuntu 24.04 aarch64 | No — Canonical security stream |
| App stack | Flutter/Dart, Python, Node, TensorFlow aarch64 | No |
| Backend | FastAPI + **SQLite** (`backend/`) | No — MySQL is not installed |
| JDK | none needed; `AGENTS.md:188` — no Android SDK on the box, APKs are built in CI on **Temurin 17** | No — the CSPU covers **Oracle** Java SE |
| OCI control plane | Oracle-managed | Patched by Oracle automatically |

**Expected verdict: no CSPU patch applies to this box.** Confirm it rather than
trusting the table — run §2 and only widen the work if something turns up.

The updates this box *does* need, and the reason it needs a **reboot**, come from
the ordinary Ubuntu/Canonical security stream (`apt`), including `linux-oracle`
kernel updates. That is a Canonical channel; the CSPU mail is not what triggers it.

## 2. Confirm the triage on the box

```bash
uname -srvmo
dpkg -l | grep -Ei 'oracle|mysql-server|weblogic|graalvm' || echo 'no Oracle products installed'
which java javac sqlplus mysql 2>/dev/null || echo 'no JDK / DB clients'
apt list --upgradable 2>/dev/null | grep -i security
```

If `dpkg -l` shows an Oracle product (Instant Client, MySQL server, Oracle JDK),
stop and re-read the matching risk matrix on the advisory page before continuing.

## 3. Find the safe restart window

The pipeline is cron-driven; its state lives in `.pipeline/`
(`PIPELINE_STATE_DIR`). A round holds `.pipeline/lock` and an entry under
`.pipeline/inflight/<ROUND>` for the whole session (`PIPELINE_SESSION_TIMEOUT`
4 h; a self-healing round `PIPELINE_SELFHEAL_TIMEOUT` 3 h). Rebooting mid-round
kills the orchestrator/implementer session and leaves both the lock and the
inflight entry orphaned.

```bash
tools/pipeline-status.sh
ls .pipeline/inflight/ 2>/dev/null            # empty => no round in flight
ls -l .pipeline/lock 2>/dev/null              # absent => no slot held
tail -20 .pipeline/chain.log
pgrep -af 'round-pipeline|claude|minimax|mm-watch|codex-watch'
```

The window is open when `.pipeline/inflight/` is empty, `.pipeline/lock` is
absent, and no session process is running.

**Do not use `tools/pipeline-status.sh --halt` as a maintenance pause.**
`HALTED` is a *fault* signal: since ADR 0112 the next cron firing starts a
**self-healing round** on it (`tools/round-pipeline.sh:1255`), which would spend
orchestrator quota diagnosing a fault that does not exist — and
`PIPELINE_SELF_CHAIN=1` means a landing round immediately chains the next one
without waiting for cron. Pause by disabling the crontab entry instead.

## 4. Procedure

```bash
# 4.1 Pause the chain (comment out the pipeline line; keep the file, do not delete it)
crontab -l > ~/crontab.backup.$(date +%Y%m%dT%H%M%S)
crontab -e            # prefix the round-pipeline.sh line with '#'

# 4.2 Wait for the in-flight round to land (re-run the §3 checks until clear)

# 4.3 Persist the inotify limit BEFORE rebooting — see §5
sudo tee /etc/sysctl.d/60-strumsight-inotify.conf <<'EOF'
fs.inotify.max_user_instances = 4096
EOF
sudo sysctl --system

# 4.4 Apply updates
sudo apt update
sudo apt upgrade -y            # or: sudo unattended-upgrade -d for security-only

# 4.5 Reboot only if the OS asks for it
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs && sudo reboot
```

## 5. Post-reboot checks

1. **inotify limit.** L105/L144 raised `fs.inotify.max_user_instances` to 4096
   with `sysctl -w`, which is **runtime-only** — a reboot resets it to the distro
   default and reintroduces the `flutter analyze` → `OS Error: Too many open
   files, errno=24` failure mode that has already produced one false `blocked`
   signal (E05-R02). §4.3 persists it; verify:
   `cat /proc/sys/fs/inotify/max_user_instances` → `4096`.
2. **Orphan cleanup is a side benefit.** The reboot clears the hundreds of
   orphaned `tail` processes left by old `codex-watch.sh` / `mm-watch.sh` runs
   (L144) and the deleted-cwd dart/flutter zombies (L142) — no manual kill needed:
   `grep -c '^inotify' /proc/*/fdinfo/* 2>/dev/null | grep -v ':0' | wc -l`.
3. **Kernel took.** `uname -r` matches the newly installed `linux-oracle`.
4. **RAM headroom.** `free -g` — a slot needs `PIPELINE_MIN_FREE_GB_PER_SLOT`
   (6 GB); the OOM guard (L05) refuses to dispatch below it. Check swap is back:
   `swapon --show`.
5. **Stale pipeline state**, if the reboot did catch a round despite §3:
   ```bash
   cat .pipeline/HALTED 2>/dev/null
   ls .pipeline/inflight/
   rm -f .pipeline/lock .pipeline/inflight/<ROUND>      # only for a round that is provably dead
   ```
6. **Toolchain still boots** (this is the real green light, not `apt` exiting 0):
   ```bash
   flutter --version
   python3 -m pytest tools/tests -q
   ```
   `tools/tests` is the pipeline's own suite. Note that `flutter analyze` and
   `flutter test` must never be chained in one command on this box (L05, OOM).

## 6. Re-arm

```bash
crontab -e            # uncomment the round-pipeline.sh line
tools/pipeline-status.sh
tail -f .pipeline/chain.log     # confirm the next firing picks up the queue
```

## 7. Recurrence

Oracle's published dates for the next releases: **2026-09-15** (CSPU),
**2026-10-20** (CPU), **2026-11-17** (CSPU), **2026-12-15** (CSPU). Unless an
Oracle product is installed on the box, each of these is a §2 triage that ends
in "no CSPU patch applies" — the Ubuntu/Canonical `apt` stream stays the only
thing that actually needs applying here, on its own cadence.
