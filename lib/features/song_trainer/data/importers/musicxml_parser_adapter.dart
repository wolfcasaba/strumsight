import 'dart:convert';

import 'package:xml/xml.dart';

/// Keeps package parser values inside the data-layer import boundary.
final class MusicXmlParserAdapter {
  const MusicXmlParserAdapter();

  XmlDocument? parse(List<int> bytes) {
    final source = utf8.decode(bytes, allowMalformed: false);
    if (RegExp(r'<!DOCTYPE', caseSensitive: false).hasMatch(source)) {
      return null;
    }
    try {
      return XmlDocument.parse(source);
    } on XmlException {
      return null;
    } on FormatException {
      return null;
    }
  }
}
