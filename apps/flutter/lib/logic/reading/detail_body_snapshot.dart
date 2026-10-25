import 'package:flutter/foundation.dart';

import 'markdown_content.dart';

/// Captured at accepted response time, not inferred later from mutable models.
@immutable
class DetailBodySnapshot {
  DetailBodySnapshot({
    required this.account,
    required this.generation,
    required this.feedId,
    required this.originalBody,
    required Map<String, String> sources,
    Map<String, MarkdownContent> documents = const {},
    Map<String, String?> rawFields = const {},
  })  : sources = Map.unmodifiable(sources),
        documents = Map.unmodifiable(documents),
        rawFields = Map.unmodifiable(rawFields);
  final String account;
  final int generation;
  final String feedId;
  final String originalBody;
  final Map<String, String> sources;
  final Map<String, MarkdownContent> documents;
  final Map<String, String?> rawFields;
  // Structured source is useful even when every retained block is plain text,
  // an image or a share card. Never derive it from a reconstructed model.
  bool get offersSource =>
      rawFields.containsKey('message_raw_output') ||
      documents.values.any((value) => value.offersSource);
  bool sameBody(DetailBodySnapshot other) =>
      account == other.account &&
      generation == other.generation &&
      feedId == other.feedId &&
      originalBody == other.originalBody &&
      mapEquals(sources, other.sources) &&
      mapEquals(rawFields, other.rawFields);
  bool belongsTo(String uid, int epoch) =>
      account == uid && generation == epoch;

  DetailBodySnapshot prepared(Map<String, MarkdownContent> result) =>
      DetailBodySnapshot(
        account: account,
        generation: generation,
        feedId: feedId,
        originalBody: originalBody,
        sources: sources,
        documents: result,
        rawFields: rawFields,
      );
}

/// In-memory raw reading position, owned by one exact controller body scope.
class RawSourcePosition {
  final offsets = <int>[0];
  final splitEnds = <int>[0];
  int index = 0;
}
