import 'dart:convert';

import 'package:xml/xml.dart';

/// Keeps package parser values inside the data-layer import boundary.
final class MusicXmlParserAdapter {
  const MusicXmlParserAdapter();

  /// Returns null for any score this boundary refuses: a payload that is not
  /// valid UTF-8 (an ISO-8859-1 export), a DOCTYPE, or unparseable XML. The
  /// decode is inside the guard so callers map it to their own invalid-XML
  /// failure instead of seeing a [FormatException] escape the adapter.
  XmlDocument? parse(List<int> bytes) {
    try {
      final source = utf8.decode(bytes, allowMalformed: false);
      if (RegExp(r'<!DOCTYPE', caseSensitive: false).hasMatch(source)) {
        return null;
      }
      return XmlDocument.parse(source);
    } on XmlException {
      return null;
    } on FormatException {
      return null;
    }
  }
}
