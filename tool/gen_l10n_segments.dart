// GENERATED-FILE-MARKER: tool/gen_l10n_segments.dart
//
// ARB-fragmentum → generált aggregátum (ADR 0307 §4).
//
// A `lib/l10n/app_<locale>.arb` fájlok MÁR NEM kézzel szerkesztett források: a
// `lib/l10n/base/app_<locale>.arb` (még nem migrált maradék) és a
// `lib/l10n/features/<feature>_<locale>.arb` fragmentumok determinisztikus
// uniója. A gate a `--check` móddal biztosítja, hogy a lemezen lévő aggregátum
// megegyezzen a generálttal — így a kulcsvesztés azonnal pirosra vált, és a
// `lib/l10n/app_<locale>.arb` NEM számít slot-konfliktusnak a párhuzamos
// kör-ütemezésben (a `tools/round-slots.py` `GENERATED_PATHS` halmaza).
//
// A generátor három hibát KEVERT szándékosan:
//   1. ütköző kulcs (ugyanaz a kulcs két fragmentumban) → `errors` lista;
//   2. `--check` módban a lemezen lévő aggregátum elavult → kilépési kód 1;
//   3. bármely más futásidejű hiba (hiányzó fájl, parse-hiba) → kilépési kód 2.
//
// A kimenet kulcs-sorrendje ALFABETIKUS a `@@locale` fejléccel az első helyen;
// az egyes üzenetek `@kulcs` metaadata azonnal a `kulcs` után következik.
import 'dart:convert';
import 'dart:io';

/// Egy forrás-ARB a merge-be (alap vagy feature-fragmentum).
final class Segment {
  Segment({required this.label, required this.path, required this.data});

  /// Emberi olvasásra szánt azonosító (a hibaüzenetben és a `seenFrom` térképben).
  final String label;

  /// A lemezen lévő útvonal (diagnosztikához).
  final String path;

  /// A beolvasott ARB JSON-objektum.
  final Map<String, dynamic> data;
}

/// A sikeres egyesítés eredménye: az aggregátum kulcs-érték halmaza.
final class GeneratedAggregate {
  GeneratedAggregate({required this.locale, required Map<String, dynamic> data})
    : data = Map.unmodifiable(data);

  final String locale;
  final Map<String, dynamic> data;

  /// A `@key` metaadatok ÉS a `@@locale` kivételével a tényleges üzenetkulcsok.
  Iterable<String> get messageKeys =>
      data.keys.where((key) => !key.startsWith('@'));

  String encode() {
    final entries = data.entries.toList()
      ..sort((a, b) => _aggregateKeyOrder(a.key, b.key));
    final ordered = <String, dynamic>{
      for (final entry in entries) entry.key: entry.value,
    };
    return const JsonEncoder.withIndent('  ').convert(ordered);
  }
}

/// A `mergeSegments` hívás eredménye: vagy tiszta aggregátum, vagy hibalista.
final class MergeResult {
  MergeResult({required this.aggregate, required List<String> errors})
    : errors = List.unmodifiable(errors);

  final GeneratedAggregate? aggregate;
  final List<String> errors;

  bool get isClean => errors.isEmpty;
}

/// Összeolvasztja a megadott szegmenseket egy lokálra vonatkozó aggregátummá.
///
/// A kulcsok sorrendje a kimenetben ALFABETIKUS; a `@kulcs` metaadat azonnal a
/// `kulcs` üzenet után következik; a `@@locale` fejléc az első helyen áll.
/// Két szegmens ugyanazt a kulcsot tartalmazhatja NEM: ez `errors` bejegyzést
/// ad, és `aggregate` értéke `null`.
MergeResult mergeSegments({
  required String locale,
  required List<Segment> segments,
}) {
  final merged = <String, dynamic>{};
  final seenFrom = <String, String>{};
  final errors = <String>[];

  for (final segment in segments) {
    for (final entry in segment.data.entries) {
      final key = entry.key;
      if (key == '@@locale') {
        continue; // a fejlécet a generator írja a saját lokáljával
      }
      if (key.startsWith('@')) {
        // üzenet-metaadat: csak akkor kerül be, ha a hozzá tartozó kulcs
        // már bekerült (és nem ütközött). Ez garantálja, hogy a `@kulcs`
        // ÁRVAKÉNT soha ne jelenjen meg a kimenetben.
        final messageKey = key.substring(1);
        if (!seenFrom.containsKey(messageKey)) {
          continue;
        }
        if (merged.containsKey(key)) {
          errors.add(
            'ismétlődő metaadat "$key" a(z) ${segment.label} fájlban '
            '(a "${seenFrom[messageKey]}" már szolgáltatta)',
          );
          continue;
        }
        merged[key] = entry.value;
        continue;
      }
      if (seenFrom.containsKey(key)) {
        errors.add(
          'ismétlődő kulcs "$key" a(z) ${segment.label} fájlban '
          '(korábban a(z) ${seenFrom[key]}-ban jelent meg)',
        );
        continue;
      }
      seenFrom[key] = segment.label;
      merged[key] = entry.value;
    }
  }

  merged['@@locale'] = locale;

  if (errors.isNotEmpty) {
    return MergeResult(aggregate: null, errors: errors);
  }
  return MergeResult(
    aggregate: GeneratedAggregate(locale: locale, data: merged),
    errors: const [],
  );
}

/// Egy szegmensfájl (`base/app_<locale>.arb` vagy
/// `features/<feature>_<locale>.arb`) névből kiolvasott lokál-sztring.
String localeFromSegmentPath(String relativePath) {
  final base = relativePath.split('/').last;
  final dot = base.lastIndexOf('.');
  final stem = base.substring(0, dot);
  final underscore = stem.lastIndexOf('_');
  if (underscore < 0) {
    throw FormatException(
      'a(z) "$relativePath" nem "<név>_<locale>.arb" alakú',
    );
  }
  return stem.substring(underscore + 1);
}

/// A `lib/l10n/<base-or-features>` könyvtárban lévő ARB-okat adja vissza,
/// lokálra szűrve, rendezve.
///
/// A `features/` hiánya NEM hiba — egyetlen feature sem migrált még.
List<File> listSegmentFiles(Directory directory, String locale) {
  if (!directory.existsSync()) {
    return const [];
  }
  final suffix = '_$locale.arb';
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith(suffix))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// Beolvas egy ARB-fájlt; a JSON-dekódolás hibáját `FormatException`-re
/// képezi, hogy a `main` egységesen kezelhesse.
Segment loadSegment(File file) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('a törzs nem JSON-objektum');
    }
    return Segment(label: file.path, path: file.path, data: decoded);
  } on FormatException catch (error) {
    throw FormatException('${file.path}: ${error.message}');
  }
}

/// Az aggregátum-mentés vagy -ellenőrzés eredménye.
final class GenerationOutcome {
  GenerationOutcome({
    required this.locale,
    required this.wrote,
    required this.stale,
    required List<String> errors,
  }) : errors = List.unmodifiable(errors);

  final String locale;
  final bool wrote;
  final bool stale;
  final List<String> errors;

  bool get isOk => errors.isEmpty && !stale;
}

/// Egy lokál mentését/előállítását végzi a megadott projekt-gyökérben.
///
/// `check == true` esetén a függvény NEM ír, csak összehasonlítja a lemezen
/// lévő aggregátumot a generálttal; `stale: true` ha a kettő nem egyezik.
GenerationOutcome generateLocale({
  required String locale,
  required Directory projectRoot,
  required bool check,
}) {
  final l10nDir = Directory('${projectRoot.path}/lib/l10n');
  final baseDir = Directory('${l10nDir.path}/base');
  final featuresDir = Directory('${l10nDir.path}/features');
  final aggregate = File('${l10nDir.path}/app_$locale.arb');

  final baseFile = File('${baseDir.path}/app_$locale.arb');
  if (!baseFile.existsSync()) {
    return GenerationOutcome(
      locale: locale,
      wrote: false,
      stale: false,
      errors: ['hiányzó alap: ${baseFile.path}'],
    );
  }

  final segments = <Segment>[
    loadSegment(baseFile),
    for (final file in listSegmentFiles(featuresDir, locale)) loadSegment(file),
  ];
  final merge = mergeSegments(locale: locale, segments: segments);
  if (!merge.isClean) {
    return GenerationOutcome(
      locale: locale,
      wrote: false,
      stale: false,
      errors: merge.errors,
    );
  }
  final generated = merge.aggregate!.encode();

  if (check) {
    if (!aggregate.existsSync()) {
      return GenerationOutcome(
        locale: locale,
        wrote: false,
        stale: true,
        errors: const [],
      );
    }
    final existing = aggregate.readAsStringSync().trim();
    final expected = generated.trim();
    if (existing != expected) {
      return GenerationOutcome(
        locale: locale,
        wrote: false,
        stale: true,
        errors: const [],
      );
    }
    return GenerationOutcome(
      locale: locale,
      wrote: false,
      stale: false,
      errors: const [],
    );
  }

  aggregate.writeAsStringSync('$generated\n');
  return GenerationOutcome(
    locale: locale,
    wrote: true,
    stale: false,
    errors: const [],
  );
}

int _aggregateKeyOrder(String a, String b) {
  if (a == '@@locale') return -1;
  if (b == '@@locale') return 1;
  final aBase = a.startsWith('@') ? a.substring(1) : a;
  final bBase = b.startsWith('@') ? b.substring(1) : b;
  final baseCompare = aBase.compareTo(bBase);
  if (baseCompare != 0) return baseCompare;
  final aIsMeta = a.startsWith('@');
  final bIsMeta = b.startsWith('@');
  if (aIsMeta == bIsMeta) return 0;
  return aIsMeta ? 1 : -1;
}

void main(List<String> arguments) {
  var check = false;
  var writeOk = false;
  for (final arg in arguments) {
    if (arg == '--check') {
      check = true;
    } else if (arg == '--write') {
      writeOk = true;
    } else {
      stderr.writeln('gen_l10n_segments: ismeretlen argumentum: $arg');
      exitCode = 64;
      return;
    }
  }

  if (check == writeOk) {
    stderr.writeln(
      'gen_l10n_segments: pontosan egy üzemmódot válassz: --check vagy --write',
    );
    exitCode = 64;
    return;
  }

  final projectRoot = Directory.current;
  final outcomes = <GenerationOutcome>[];
  for (final locale in const ['en', 'hu']) {
    try {
      outcomes.add(
        generateLocale(locale: locale, projectRoot: projectRoot, check: check),
      );
    } on FormatException catch (error) {
      outcomes.add(
        GenerationOutcome(
          locale: locale,
          wrote: false,
          stale: false,
          errors: [error.message],
        ),
      );
    }
  }

  var hasError = false;
  for (final outcome in outcomes) {
    if (outcome.errors.isNotEmpty) {
      hasError = true;
      stderr.writeln('[$outcome.locale] HIBA:');
      for (final message in outcome.errors) {
        stderr.writeln('  - $message');
      }
    } else if (outcome.stale) {
      hasError = true;
      stderr.writeln(
        '[$outcome.locale] az aggregátum elavult — futtasd '
        '`dart run tool/gen_l10n_segments.dart --write` -t',
      );
    } else if (check) {
      stdout.writeln('[$outcome.locale] aggregátum naprakész');
    } else {
      stdout.writeln('[$outcome.locale] aggregátum írva');
    }
  }

  if (hasError) {
    exitCode = 1;
  }
}
