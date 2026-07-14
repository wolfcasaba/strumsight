#!/usr/bin/env bash
# Real-audio corpus fetcher for StrumSight DSP tuning (DEV-ONLY, not shipped).
#
# WHY / WHERE TO RUN: the Oracle dev box's datacenter IP is bot-walled by
# YouTube ("Sign in to confirm you're not a bot"), so THIS SCRIPT MUST RUN FROM
# A RESIDENTIAL NETWORK (your laptop or phone at home). Then copy the produced
# WAVs to the server so the probe harness can pick them up:
#
#   ./fetch.sh                                              # run at home
#   scp wav/*.wav <server>:~/music-theory/ml/corpus/wav/    # copy over
#
# The harness auto-discovers ml/corpus/wav/*.wav. Files whose name contains
# speech/talk/hum/noise are treated as VOICE negatives; everything else as
# guitar. Guitar-LESSON clips are gold: they interleave talking + playing, so
# one clip tests both speech-rejection and chord/strum detection — and give the
# REAL speech negatives the r178 finding says the strum reject CRNN needs.
#
# Requires: yt-dlp (pip install yt-dlp) + ffmpeg on PATH.
set -u
export PATH="$HOME/.local/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
RAW="$HERE/raw"; WAV="$HERE/wav"
mkdir -p "$RAW" "$WAV"

dl () {  # id  label  [start-end secs]
  local id="$1" label="$2" span="${3:-0-120}"
  echo ">>> $label ($id)  [$span]"
  yt-dlp --no-warnings -f bestaudio -o "$RAW/${label}.%(ext)s" \
    --download-sections "*$span" "https://www.youtube.com/watch?v=$id" 2>&1 | tail -1
  local f; f=$(ls "$RAW/${label}."* 2>/dev/null | head -1)
  [ -z "$f" ] && { echo "  FAIL $label"; return; }
  ffmpeg -y -loglevel error -i "$f" -ac 1 -ar 16000 "$WAV/${label}.wav" \
    && echo "  wav ok: ${label}.wav"
}

# --- Guitar-lesson clips (talking + playing, chords named) — best negatives ---
dl 7WQEeGkQhx8 guitar_lesson_amfcg    30-150
dl tZaeiHGvZi8 guitar_lesson_cgamf    30-150
dl P4ZBxbpgwUs guitar_lesson_keyofc   60-180
# --- Pure solo guitar (positive control) ---
dl W6-Rit0xHBg guitar_solo_asmr       30-150
# --- Pure speech (voice negative control) ---
dl LAmGfokvgzA speech_talk            30-150

echo
echo "Done. WAVs in: $WAV"
echo "If you ran this at home, copy them to the server's ml/corpus/wav/ then run:"
echo "  DSP_PROBE=1 ~/flutter/bin/flutter test test/tools/real_audio_probe_test.dart"
