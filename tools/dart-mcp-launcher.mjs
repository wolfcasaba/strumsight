#!/usr/bin/env node
// Cross-platform launcher for the official Dart MCP server (`dart mcp-server`).
//
// Why: `.mcp.json` is committed and shared between boxes (Windows dev box,
// Oracle Linux box), but the Flutter SDK lives at a different path on each and
// is not on PATH on Windows. Claude Code cannot branch per platform in
// `.mcp.json`, so this launcher resolves the SDK at start-up and execs the
// server with stdio passed through untouched.
//
// Resolution order (first hit wins):
//   1. FLUTTER_SDK / FLUTTER_ROOT environment variable
//   2. Well-known locations of this project's boxes
//   3. `flutter` on PATH (its parent-of-bin is the SDK root)
//
// The Dart binary is taken from the SDK's own cache
// (`bin/cache/dart-sdk/bin/dart[.exe]`) — the `.bat` shim is deliberately
// avoided: Node ≥ 20 refuses to spawn `.bat` without a shell (EINVAL).
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { delimiter, dirname, join, resolve } from 'node:path';

const isWin = process.platform === 'win32';
const dartName = isWin ? 'dart.exe' : 'dart';

function sdkFromEnv() {
  for (const key of ['FLUTTER_SDK', 'FLUTTER_ROOT']) {
    const v = process.env[key];
    if (v && existsSync(join(v, 'bin'))) return resolve(v);
  }
  return null;
}

function sdkFromKnownPaths() {
  const candidates = isWin
    ? ['C:/src/flutter', join(process.env.LOCALAPPDATA ?? '', 'flutter')]
    : ['/home/ubuntu/flutter', join(process.env.HOME ?? '', 'flutter'), '/opt/flutter'];
  return candidates.find((c) => c && existsSync(join(c, 'bin', isWin ? 'flutter.bat' : 'flutter'))) ?? null;
}

function sdkFromPath() {
  const names = isWin ? ['flutter.bat', 'flutter'] : ['flutter'];
  for (const dir of (process.env.PATH ?? '').split(delimiter)) {
    for (const n of names) {
      if (dir && existsSync(join(dir, n))) return resolve(dir, '..');
    }
  }
  return null;
}

const sdk = sdkFromEnv() ?? sdkFromKnownPaths() ?? sdkFromPath();
if (!sdk) {
  console.error('dart-mcp-launcher: no Flutter SDK found (set FLUTTER_SDK).');
  process.exit(20);
}
const dart = join(sdk, 'bin', 'cache', 'dart-sdk', 'bin', dartName);
if (!existsSync(dart)) {
  console.error(`dart-mcp-launcher: ${dart} missing — run \`flutter doctor\` once to populate the SDK cache.`);
  process.exit(20);
}

const extra = process.argv.slice(2); // e.g. --log-file, --disable …
const child = spawn(dart, ['mcp-server', '--flutter-sdk', sdk, ...extra], {
  stdio: 'inherit',
  windowsHide: true,
});
child.on('error', (e) => { console.error(`dart-mcp-launcher: ${e.message}`); process.exit(20); });
child.on('exit', (code, signal) => process.exit(code ?? (signal ? 1 : 0)));
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => child.kill(sig));
