import 'package:meta/meta.dart';

import '../../domain/models/tutor_source_ref.dart';
import 'knowledge_document.dart';
import 'knowledge_index.dart';

@immutable
final class KnowledgeRetrievalQuery {
  const KnowledgeRetrievalQuery({
    required this.queryText,
    required this.locale,
    this.topic,
    this.preferredSkill,
    this.difficulty,
    this.minScore = 1,
    this.maxResults = 3,
  });

  final String queryText;
  final String locale;

  /// Topic is the knowledge schema's [KnowledgeSkill].
  final KnowledgeSkill? topic;
  final KnowledgeSkill? preferredSkill;
  final KnowledgeDifficulty? difficulty;
  final int minScore;
  final int maxResults;
}

abstract interface class KnowledgeRetrievalBackend {
  List<TutorSourceRef> retrieve(KnowledgeRetrievalQuery query);
}

final class KnowledgeRetriever implements KnowledgeRetrievalBackend {
  KnowledgeRetriever({required this.index});

  static const int titleTokenWeight = 2;
  static const int contentTokenWeight = 1;
  static const int preferredSkillBoost = 1;

  final KnowledgeIndex index;

  @override
  List<TutorSourceRef> retrieve(KnowledgeRetrievalQuery query) {
    if (query.minScore < 0) {
      throw ArgumentError.value(
        query.minScore,
        'minScore',
        'Must be non-negative.',
      );
    }
    if (query.maxResults < 0) {
      throw ArgumentError.value(
        query.maxResults,
        'maxResults',
        'Must be non-negative.',
      );
    }
    if (query.maxResults == 0) return const <TutorSourceRef>[];
    final queryTokens = _tokenize(query.queryText);
    if (queryTokens.isEmpty) return const <TutorSourceRef>[];

    final candidates = <_ScoredSource>[];
    for (final entry in index.entries) {
      final document = entry.document;
      if (document.locale != query.locale) continue;
      if (query.topic != null && document.skill != query.topic) continue;
      if (query.difficulty != null && document.difficulty != query.difficulty) {
        continue;
      }

      var score = _score(queryTokens, document.title, entry.chunk.content);
      if (document.skill == query.preferredSkill) {
        score += preferredSkillBoost;
      }
      if (score < query.minScore) continue;
      candidates.add(
        _ScoredSource(
          score: score,
          source: TutorSourceRef(
            sourceId: document.id,
            title: document.title,
            locale: document.locale,
            topic: document.skill.name,
            knowledgeVersion: document.version,
            chunkIndex: entry.chunk.index,
            chunkHash: entry.chunk.contentHash,
          ),
        ),
      );
    }

    candidates.sort(_compareScoredSources);
    final sources = <TutorSourceRef>[];
    final seenChunkIds = <String>{};
    for (final candidate in candidates) {
      if (!seenChunkIds.add(candidate.source.chunkId)) continue;
      sources.add(candidate.source);
      if (sources.length == query.maxResults) break;
    }
    return List<TutorSourceRef>.unmodifiable(sources);
  }

  static int _score(
    Iterable<String> queryTokens,
    String title,
    String content,
  ) {
    final titleTerms = _termCounts(title);
    final contentTerms = _termCounts(content);
    var score = 0;
    for (final token in queryTokens) {
      score += (titleTerms[token] ?? 0) * titleTokenWeight;
      score += (contentTerms[token] ?? 0) * contentTokenWeight;
    }
    return score;
  }

  static int _compareScoredSources(_ScoredSource left, _ScoredSource right) {
    final scoreOrder = right.score.compareTo(left.score);
    if (scoreOrder != 0) return scoreOrder;
    final documentOrder = left.source.sourceId.compareTo(right.source.sourceId);
    if (documentOrder != 0) return documentOrder;
    return left.source.chunkIndex.compareTo(right.source.chunkIndex);
  }
}

final class _ScoredSource {
  const _ScoredSource({required this.score, required this.source});

  final int score;
  final TutorSourceRef source;
}

Map<String, int> _termCounts(String text) {
  final counts = <String, int>{};
  for (final token in _tokenize(text)) {
    counts.update(token, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

List<String> _tokenize(String text) => List<String>.unmodifiable(
  text.toLowerCase().split(_tokenSeparator).where((token) => token.isNotEmpty),
);

final RegExp _tokenSeparator = RegExp(r'[^0-9a-záéíóöőúüű]+');
