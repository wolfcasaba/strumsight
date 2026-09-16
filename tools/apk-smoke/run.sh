#!/usr/bin/env bash
# StrumSight APK smoke — runs the SHIPPED development APK on a real Android
# emulator and produces machine evidence that it starts, survives basic
# navigation and does not crash.
#
# This is the layer the host-side gate (`flutter test`) cannot reach: a real
# Dalvik/ART process, the real Flutter engine, the real plugin registrations
# and the real Android permission model. It is a LIVENESS smoke, not a
# functional suite — see docs/release/apk-smoke.md for what it does NOT prove.
#
# Usage:  bash tools/apk-smoke/run.sh <path-to.apk>
# Env:    SMOKE_OUT_DIR   (default: smoke-out)
#         SMOKE_TAB_COUNT (default: 5 — lib/app/home_shell.dart destinations)
#         SMOKE_PKG       (default: com.wolfcasaba.strumsight)

set -euo pipefail

PKG="${SMOKE_PKG:-com.wolfcasaba.strumsight}"
ACTIVITY="${PKG}/.MainActivity"
OUT_DIR="${SMOKE_OUT_DIR:-smoke-out}"
TAB_COUNT="${SMOKE_TAB_COUNT:-5}"
HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/png_stats.py"

RESULTS=()
FAILURES=0
NOTES=()
COLD_START_MS="n/a"
PSS_KB="n/a"
SCREEN_SIZE="unknown"
FINALIZED=0

log() { printf '[apk-smoke] %s\n' "$*"; }

# record <step> <PASS|FAIL|NOTE> <detail>
record() {
  local status="$2"
  RESULTS+=("$1|$status|$3")
  if [ "$status" = "FAIL" ]; then
    FAILURES=$((FAILURES + 1))
    log "FAIL  $1 — $3"
  else
    log "$status  $1 — $3"
  fi
}

adb_sh() { adb shell "$@" 2>/dev/null | tr -d '\r'; }

app_pid() { adb_sh pidof "$PKG" | tr -d '[:space:]'; }

resumed_activity() {
  adb shell dumpsys activity activities 2>/dev/null \
    | tr -d '\r' \
    | grep -E 'mResumedActivity' \
    | head -1
}

is_resumed() { resumed_activity | grep -q "$PKG"; }

# assert_alive <step-label>
assert_alive() {
  local pid
  pid="$(app_pid || true)"
  if [ -n "$pid" ]; then
    record "$1" PASS "process alive (pid $pid)"
    return 0
  fi
  record "$1" FAIL "process $PKG is gone"
  return 1
}

# screenshot <file-name> <label> [strict]
# strict=1 → the frame must not be uniformly blank/black (launch frame only).
screenshot() {
  local name="$1" label="$2" strict="${3:-0}"
  local path="$OUT_DIR/$name"
  if ! adb exec-out screencap -p >"$path" 2>/dev/null; then
    record "$label" FAIL "screencap failed"
    return 0
  fi
  local stats rc=0
  if [ "$strict" = "1" ]; then
    stats="$(python3 "$HELPER" "$path" --min-bytes 20480 --min-colors 16 --min-non-black 0.02)" || rc=$?
  else
    stats="$(python3 "$HELPER" "$path" --min-bytes 1024)" || rc=$?
  fi
  printf '%s\n' "$stats" >>"$OUT_DIR/screenshots.jsonl"
  # Compact digest for the summary table; the full JSON lives in
  # screenshots.jsonl.
  local compact
  compact="$(printf '%s' "$stats" | sed -E \
    's/.*"bytes": ([0-9]+).*"unique_colors": ([0-9]+).*"non_black_ratio": ([0-9.]+).*/\1 B, colors=\2, non_black=\3/' \
    | head -c 160)"
  if [ "$rc" -eq 0 ]; then
    record "$label" PASS "$name — $compact"
  else
    record "$label" FAIL "$name rejected — $compact"
  fi
}

# ui_dump <file-name> — sets UI_NODE_COUNT (never called in a subshell, so the
# NOTES it appends survive).
UI_NODE_COUNT=0
ui_dump() {
  local name="$1"
  UI_NODE_COUNT=0
  if adb shell uiautomator dump /sdcard/apk-smoke-dump.xml >/dev/null 2>&1; then
    adb pull /sdcard/apk-smoke-dump.xml "$OUT_DIR/$name" >/dev/null 2>&1 || true
    adb shell rm -f /sdcard/apk-smoke-dump.xml >/dev/null 2>&1 || true
  fi
  if [ -s "$OUT_DIR/$name" ]; then
    # `|| true` guards `set -o pipefail`: a dump with zero nodes is data,
    # not a script failure.
    UI_NODE_COUNT="$( { grep -o '<node ' "$OUT_DIR/$name" || true; } | wc -l | tr -d ' ')"
    NOTES+=("uiautomator dump \`$name\`: $UI_NODE_COUNT node(s)")
  else
    NOTES+=("uiautomator dump \`$name\`: unavailable on this image")
  fi
}

# Re-launch when a BACK press sent the app to the background, so the following
# steps still exercise the app and not the launcher.
ensure_foreground() {
  if is_resumed; then
    return 0
  fi
  NOTES+=("app was not resumed before \`$1\` — relaunched via monkey")
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  sleep 3
}

finalize() {
  local exit_code=$?
  [ "$FINALIZED" = "1" ] && exit "$exit_code"
  FINALIZED=1
  set +e

  # ---- 4. crash / ANR evidence -------------------------------------------
  adb logcat -d >"$OUT_DIR/logcat.txt" 2>/dev/null
  if [ -s "$OUT_DIR/logcat.txt" ]; then
    local hits=""
    grep -q 'FATAL EXCEPTION' "$OUT_DIR/logcat.txt" && hits="${hits}FATAL EXCEPTION; "
    grep -q "ANR in ${PKG}" "$OUT_DIR/logcat.txt" && hits="${hits}ANR; "
    grep -Eq "Process ${PKG} .*has died" "$OUT_DIR/logcat.txt" && hits="${hits}process died; "
    grep -q 'Unhandled Exception' "$OUT_DIR/logcat.txt" && hits="${hits}Flutter Unhandled Exception; "
    if [ -n "$hits" ]; then
      grep -nE "FATAL EXCEPTION|ANR in ${PKG}|Process ${PKG} .*has died|Unhandled Exception" \
        "$OUT_DIR/logcat.txt" | head -60 >"$OUT_DIR/crash-hits.txt"
      record "logcat-clean" FAIL "${hits%; } (see crash-hits.txt)"
    else
      record "logcat-clean" PASS "no FATAL/ANR/died/Unhandled Exception"
    fi
  else
    record "logcat-clean" FAIL "logcat could not be captured"
  fi

  adb shell dumpsys meminfo "$PKG" >"$OUT_DIR/meminfo.txt" 2>/dev/null
  if [ -s "$OUT_DIR/meminfo.txt" ]; then
    # Android 10+ prints "TOTAL PSS:  89012 ...", older images "TOTAL  89012 ...".
    PSS_KB="$(tr -d '\r' <"$OUT_DIR/meminfo.txt" \
      | grep -E '^[[:space:]]*TOTAL([[:space:]]+PSS)?:?[[:space:]]+[0-9]+' \
      | head -1 \
      | sed -E 's/.*TOTAL([[:space:]]+PSS)?:?[[:space:]]+([0-9]+).*/\2/')"
    [ -n "$PSS_KB" ] || PSS_KB="n/a"
  fi

  # ---- report ------------------------------------------------------------
  {
    echo "# StrumSight APK smoke report"
    echo
    echo "- APK: \`${APK_PATH:-n/a}\` ($(du -h "${APK_PATH:-/dev/null}" 2>/dev/null | awk '{print $1}'))"
    echo "- Package: \`$PKG\` (activity \`$ACTIVITY\`)"
    echo "- Device: \`$(adb_sh getprop ro.product.model)\` / API $(adb_sh getprop ro.build.version.sdk) / abi $(adb_sh getprop ro.product.cpu.abi)"
    echo "- Screen: \`$SCREEN_SIZE\`, bottom-nav bands: $TAB_COUNT"
    echo "- Cold start (\`am start -W\` TotalTime): **${COLD_START_MS} ms**"
    echo "- Memory (\`dumpsys meminfo\` TOTAL PSS): **${PSS_KB} kB**"
    echo "- UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo
    echo "## Assertions"
    echo
    echo '| # | Step | Result | Detail |'
    echo '| --: | --- | --- | --- |'
    local index=0 line step status detail
    for line in "${RESULTS[@]}"; do
      index=$((index + 1))
      step="${line%%|*}"
      status="${line#*|}"
      status="${status%%|*}"
      detail="${line#*|*|}"
      detail="${detail//|/\\|}"
      echo "| $index | $step | $status | ${detail} |"
    done
    echo
    if [ "${#NOTES[@]}" -gt 0 ]; then
      echo "## Notes"
      echo
      for line in "${NOTES[@]}"; do echo "- $line"; done
      echo
    fi
    echo "## Verdict"
    echo
    if [ "$FAILURES" -eq 0 ]; then
      echo "**PASS** — ${#RESULTS[@]} assertions, 0 failures."
    else
      echo "**FAIL** — $FAILURES of ${#RESULTS[@]} assertions failed."
    fi
    echo
    echo "Evidence files: \`screenshots.jsonl\`, \`logcat.txt\`, \`meminfo.txt\`,"
    echo "\`ui-*.xml\`, \`*.png\`. What this smoke does NOT prove:"
    echo "docs/release/apk-smoke.md."
  } >"$OUT_DIR/report.md"

  echo
  echo '================ APK SMOKE SUMMARY ================'
  printf '%-34s %-6s %s\n' 'STEP' 'RESULT' 'DETAIL'
  local line step status detail
  for line in "${RESULTS[@]}"; do
    step="${line%%|*}"
    status="${line#*|}"
    status="${status%%|*}"
    detail="${line#*|*|}"
    printf '%-34s %-6s %s\n' "$step" "$status" "$(printf '%s' "$detail" | head -c 90)"
  done
  echo '---------------------------------------------------'
  printf 'cold start: %s ms | TOTAL PSS: %s kB | failures: %s/%s\n' \
    "$COLD_START_MS" "$PSS_KB" "$FAILURES" "${#RESULTS[@]}"
  echo '==================================================='

  if [ "$FAILURES" -gt 0 ]; then
    exit 1
  fi
  exit "$exit_code"
}

# ---------------------------------------------------------------------------
# 0. arguments
# ---------------------------------------------------------------------------
if [ "$#" -ne 1 ]; then
  echo "usage: $0 <path-to.apk> (got $# argument(s): $*)" >&2
  exit 2
fi
APK_PATH="$1"
if [ ! -s "$APK_PATH" ]; then
  echo "error: APK '$APK_PATH' is missing or empty" >&2
  exit 2
fi
mkdir -p "$OUT_DIR"
: >"$OUT_DIR/screenshots.jsonl"
trap finalize EXIT

log "APK: $APK_PATH ($(du -h "$APK_PATH" | awk '{print $1}'))"

# ---------------------------------------------------------------------------
# 1. device boot, unlock, install, permissions
# ---------------------------------------------------------------------------
adb wait-for-device
boot_ok=0
for _ in $(seq 1 150); do
  if [ "$(adb_sh getprop sys.boot_completed || true)" = "1" ]; then
    boot_ok=1
    break
  fi
  sleep 2
done
if [ "$boot_ok" = "1" ]; then
  record "boot-completed" PASS "sys.boot_completed=1"
else
  record "boot-completed" FAIL "sys.boot_completed never reached 1 (300 s)"
  exit 1
fi

adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
adb shell input keyevent 82 >/dev/null 2>&1 || true
SCREEN_SIZE="$( { adb_sh wm size || true; } | sed -nE 's/.*: *([0-9]+x[0-9]+).*/\1/p' | tail -1)"
[ -n "$SCREEN_SIZE" ] || SCREEN_SIZE="1080x2400"
SCREEN_W="${SCREEN_SIZE%x*}"
SCREEN_H="${SCREEN_SIZE#*x}"
log "screen: ${SCREEN_W}x${SCREEN_H}"

if adb install -r -g "$APK_PATH" >"$OUT_DIR/install.log" 2>&1; then
  record "install" PASS "adb install -r -g succeeded"
else
  cat "$OUT_DIR/install.log" >&2 || true
  record "install" FAIL "adb install failed (see install.log)"
  exit 1
fi

adb shell dumpsys package "$PKG" >"$OUT_DIR/dumpsys-package.txt" 2>/dev/null || true
for perm in android.permission.RECORD_AUDIO android.permission.CAMERA; do
  short="${perm##*.}"
  if ! grep -q "${perm}: granted=true" "$OUT_DIR/dumpsys-package.txt"; then
    adb shell pm grant "$PKG" "$perm" >/dev/null 2>&1 || true
    adb shell dumpsys package "$PKG" >"$OUT_DIR/dumpsys-package.txt" 2>/dev/null || true
  fi
  if grep -q "${perm}: granted=true" "$OUT_DIR/dumpsys-package.txt"; then
    record "perm-${short}" PASS "granted"
  else
    record "perm-${short}" FAIL "still not granted after pm grant fallback"
  fi
done

adb logcat -c >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 2. launch
# ---------------------------------------------------------------------------
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
resumed=0
for _ in $(seq 1 60); do
  if is_resumed; then
    resumed=1
    break
  fi
  sleep 1
done
if [ "$resumed" = "1" ]; then
  record "launch-resumed" PASS "mResumedActivity = $(resumed_activity | sed -E 's/.*(com\.[^ }]*).*/\1/')"
else
  record "launch-resumed" FAIL "no $PKG activity became mResumedActivity in 60 s"
fi
assert_alive "launch-alive" || true
sleep 4  # let the first real Flutter frame settle before capturing
screenshot "01-launch.png" "launch-frame" 1

# ---------------------------------------------------------------------------
# 3. navigation smoke (no source-level test hooks)
# ---------------------------------------------------------------------------
# Flutter only publishes its semantics tree to uiautomator while an
# accessibility service is running. TalkBack is absent from most AOSP emulator
# images, so this is best-effort: when the dump stays a single FlutterView node
# we simply keep the coordinate-free liveness checks.
adb shell settings put secure enabled_accessibility_services \
  com.android.talkback/com.google.android.marvin.talkback.TalkBackService >/dev/null 2>&1 || true
adb shell settings put secure accessibility_enabled 1 >/dev/null 2>&1 || true
sleep 2
ui_dump 'ui-01-launch.xml'
if [ "${UI_NODE_COUNT:-0}" -gt 1 ]; then
  record "ui-semantics" NOTE "$UI_NODE_COUNT nodes exposed (accessibility tree available)"
else
  record "ui-semantics" NOTE "opaque FlutterView (${UI_NODE_COUNT:-0} node) — coordinate-free checks only"
fi

adb shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
sleep 3
assert_alive "back-once-alive" || true
screenshot "02-after-back.png" "back-once-frame"

tap_y=$((SCREEN_H * 96 / 100))
for tab in $(seq 1 "$TAB_COUNT"); do
  ensure_foreground "tab-$tab"
  tap_x=$(((2 * tab - 1) * SCREEN_W / (2 * TAB_COUNT)))
  adb shell input tap "$tap_x" "$tap_y" >/dev/null 2>&1 || true
  sleep 2
  assert_alive "tab-${tab}-alive" || true
  screenshot "03-tab-${tab}.png" "tab-${tab}-frame"
done

ensure_foreground "back-twice"
adb shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
sleep 2
adb shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
sleep 3
assert_alive "back-twice-alive" || true
screenshot "04-after-back-twice.png" "back-twice-frame"
ui_dump 'ui-99-final.xml'

# ---------------------------------------------------------------------------
# 4. cold-start measurement (a genuine cold start: force-stop first)
# ---------------------------------------------------------------------------
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
sleep 2
adb shell am start -W -n "$ACTIVITY" >"$OUT_DIR/am-start.txt" 2>&1 || true
tr -d '\r' <"$OUT_DIR/am-start.txt" >"$OUT_DIR/am-start.clean.txt" || true
mv "$OUT_DIR/am-start.clean.txt" "$OUT_DIR/am-start.txt" || true
COLD_START_MS="$( { grep -E '^TotalTime:' "$OUT_DIR/am-start.txt" || true; } | awk '{print $2}' | head -1)"
[ -n "$COLD_START_MS" ] || COLD_START_MS="n/a"
if [ "$COLD_START_MS" = "n/a" ]; then
  record "cold-start" FAIL "am start -W reported no TotalTime (see am-start.txt)"
else
  record "cold-start" PASS "TotalTime ${COLD_START_MS} ms"
fi
sleep 3
assert_alive "cold-start-alive" || true
screenshot "05-cold-start.png" "cold-start-frame" 1

# The EXIT trap (finalize) collects logcat, meminfo, writes report.md and
# decides the exit code from the failure count.
