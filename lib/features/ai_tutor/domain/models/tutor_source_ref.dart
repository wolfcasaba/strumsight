import 'package:meta/meta.dart';

@immutable
final class TutorSourceRef {
  const TutorSourceRef({
    required this.sourceId,
    required this.title,
    required this.locale,
    required this.topic,
    required this.knowledgeVersion,
    required this.chunkIndex,
    required this.chunkHash,
  });

  final String sourceId;
  final String title;
  final String locale;
  final String topic;
  final int knowledgeVersion;
  final int chunkIndex;
  final String chunkHash;

  String get chunkId => '$sourceId#${chunkIndex + 1}';

  @override
  bool operator ==(Object other) =>
      other is TutorSourceRef &&
      sourceId == other.sourceId &&
      title == other.title &&
      locale == other.locale &&
      topic == other.topic &&
      knowledgeVersion == other.knowledgeVersion &&
      chunkIndex == other.chunkIndex &&
      chunkHash == other.chunkHash;

  @override
  int get hashCode => Object.hash(
    sourceId,
    title,
    locale,
    topic,
    knowledgeVersion,
    chunkIndex,
    chunkHash,
  );

  @override
  String toString() =>
      'TutorSourceRef(sourceId: $sourceId, locale: $locale, topic: $topic, '
      'knowledgeVersion: $knowledgeVersion, chunkIndex: $chunkIndex)';
}
