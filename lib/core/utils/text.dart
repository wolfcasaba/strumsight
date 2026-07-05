/// Shared text helpers.
///
/// Recipe titles in the shared DB were scraped from cooking sites and often
/// contain raw HTML (`<span class="fn">…</span>`) and HTML entities
/// (`&amp;`, `&#39;`). [sanitizeTitle] strips tags, decodes the common
/// entities, and collapses whitespace so titles read cleanly everywhere.
final _htmlTag = RegExp(r'<[^>]*>');
final _whitespace = RegExp(r'\s+');
final _numericEntity = RegExp(r'&#(\d+);');

String sanitizeTitle(String input) {
  if (input.isEmpty) return input;
  var s = input;

  // 1. Strip HTML tags.
  s = s.replaceAll(_htmlTag, ' ');

  // 2. Decode numeric entities (e.g. &#39; → ', &#233; → é) before the
  //    named-entity pass so `&amp;#39;`-style double-encodings resolve too.
  s = s.replaceAllMapped(_numericEntity, (m) {
    final code = int.tryParse(m.group(1)!);
    if (code == null) return m.group(0)!;
    try {
      return String.fromCharCode(code);
    } catch (_) {
      return '';
    }
  });

  // 3. Decode the common named entities.
  const named = <String, String>{
    '&amp;': '&',
    '&quot;': '"',
    '&rsquo;': "'",
    '&lsquo;': "'",
    '&rdquo;': '"',
    '&ldquo;': '"',
    '&apos;': "'",
    '&nbsp;': ' ',
    '&lt;': '<',
    '&gt;': '>',
    '&frac12;': '½',
    '&frac14;': '¼',
    '&frac34;': '¾',
    '&deg;': '°',
    '&hellip;': '…',
    '&mdash;': '—',
    '&ndash;': '–',
  };
  named.forEach((entity, replacement) {
    s = s.replaceAll(entity, replacement);
  });
  // A second `&amp;` pass catches double-encoded ampersands surfaced above.
  s = s.replaceAll('&amp;', '&');

  // 4. Collapse whitespace and trim.
  return s.replaceAll(_whitespace, ' ').trim();
}
