import 'package:mangayomi/services/fetch_subtitles.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'subtitle_search_state_provider.g.dart';

/// The last subtitle search for a given chapter.
///
/// Lives in a non-auto-disposed provider keyed by chapter so dismissing the
/// search sheet does not throw away its result set. Reopening restores it;
/// only an explicit new search clears and refetches.
class SubtitleSearchState {
  const SubtitleSearchState({
    this.query = '',
    this.titles = const [],
    this.episodes,
    this.subtitles,
    this.errorMsg,
    this.isLoading = true,
    this.searched = false,
  });

  final String query;
  final List<ImdbTitle> titles;
  final List<ImdbEpisode>? episodes;
  final List<ImdbSubtitle>? subtitles;
  final String? errorMsg;
  final bool isLoading;
  final bool searched;

  SubtitleSearchState copyWith({
    String? query,
    List<ImdbTitle>? titles,
    List<ImdbEpisode>? episodes,
    List<ImdbSubtitle>? subtitles,
    bool clearEpisodes = false,
    bool clearSubtitles = false,
    String? errorMsg,
    bool clearError = false,
    bool? isLoading,
    bool? searched,
  }) => SubtitleSearchState(
    query: query ?? this.query,
    titles: titles ?? this.titles,
    episodes: clearEpisodes ? null : (episodes ?? this.episodes),
    subtitles: clearSubtitles ? null : (subtitles ?? this.subtitles),
    errorMsg: clearError ? null : (errorMsg ?? this.errorMsg),
    isLoading: isLoading ?? this.isLoading,
    searched: searched ?? this.searched,
  );
}

@Riverpod(keepAlive: true)
class SubtitleSearchStateNotifier extends _$SubtitleSearchStateNotifier {
  @override
  SubtitleSearchState build(String key) => const SubtitleSearchState();

  /// Public read so the sheet can restore a cached search without touching
  /// Riverpod's protected [state] member.
  SubtitleSearchState snapshot() => state;

  void update(SubtitleSearchState Function(SubtitleSearchState) change) =>
      state = change(state);
}
