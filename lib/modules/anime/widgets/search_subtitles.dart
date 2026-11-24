import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:shiori/shiori.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/eval/model/m_bridge.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/services/local_folders.dart';
import 'package:mangayomi/modules/widgets/custom_extended_image_provider.dart';
import 'package:mangayomi/modules/widgets/error_state.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/providers/storage_provider.dart';
import 'package:mangayomi/services/fetch_subtitles.dart';
import 'package:mangayomi/services/http/m_client.dart';
import 'package:mangayomi/services/http/rhttp/src/model/settings.dart';
import 'package:mangayomi/services/custom_subtitle_source_store.dart';
import 'package:mangayomi/modules/anime/providers/subtitle_search_state_provider.dart';
import 'package:mangayomi/modules/anime/widgets/custom_subtitle_source_editor.dart';
import 'package:mangayomi/services/external_browser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mangayomi/utils/log/logger.dart';
import 'package:path/path.dart' as path;

/// A stable identity for a chapter's cached search, across sheet closes.
String subtitleSearchCacheKey(Chapter chapter) =>
    '${chapter.id ?? ''}|${chapter.url ?? ''}|${chapter.name ?? ''}';

class SubtitlesWidgetSearch extends ConsumerStatefulWidget {
  final Chapter chapter;
  final bool isLocal;
  const SubtitlesWidgetSearch({
    required this.chapter,
    required this.isLocal,
    super.key,
  });

  @override
  ConsumerState<SubtitlesWidgetSearch> createState() =>
      _SubtitlesWidgetSearchState();
}

class _SubtitlesWidgetSearchState extends ConsumerState<SubtitlesWidgetSearch> {
  late final String _cacheKey = subtitleSearchCacheKey(widget.chapter);
  late final _controller = TextEditingController(
    text: _notifier.snapshot().query.isNotEmpty
        ? _notifier.snapshot().query
        : widget.chapter.manga.value?.name?.trim() ?? '',
  );

  /// The notifier is captured once: it lives in the app-wide container, so an
  /// in-flight search can still write its result after the sheet is dismissed
  /// (a `ref.read` from a disposed widget would throw).
  late final SubtitleSearchStateNotifier _notifier =
      ref.read(subtitleSearchStateProvider(_cacheKey).notifier);

  /// The state for this chapter, owned by the provider so it survives the
  /// sheet being dismissed. Reads and writes both go through it.
  SubtitleSearchState get _state => _notifier.snapshot();

  void _update(SubtitleSearchState Function(SubtitleSearchState) change) =>
      _notifier.update(change);

  @override
  initState() {
    super.initState();
    // Only the very first open searches on its own. A reopen restores the
    // last result set, so dismissing the sheet no longer loses the search.
    if (!_state.searched) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  /// Runs [load] behind the loading state, and shows its failure if any.
  Future<void> _run(Future<void> Function() load) async {
    _update((s) => s.copyWith(isLoading: true, clearError: true));
    try {
      await load();
    } catch (e) {
      _update((s) => s.copyWith(errorMsg: e.toString()));
    }
    // Clear loading even if the sheet was dismissed mid-search, otherwise the
    // next open would show a spinner that never resolves.
    _update((s) => s.copyWith(isLoading: false));
  }

  /// Searches the titles again, from the field. This is the only path that
  /// clears the previous results — a mere close/reopen never does.
  Future<void> _search() => _run(() async {
    _update(
      (s) => s.copyWith(
        clearSubtitles: true,
        clearEpisodes: true,
        titles: const [],
      ),
    );
    final customSource = await CustomSubtitleSourceStore.load();
    final query = _controller.text.trim();
    if (isSubtitleVideoCode(query) || customSource.enabled) {
      final searches = <Future<List<ImdbSubtitle>>>[
        fetchDefaultSubtitleSources(
          query: query,
          xunleiEnabled: customSource.xunleiEnabled,
          subtitleCatEnabled: customSource.subtitleCatEnabled,
          avSubtitlesEnabled: customSource.avSubtitlesEnabled,
        ),
        if (customSource.enabled)
          fetchCustomSubtitles(
            query: query,
            urlTemplate: customSource.url,
            sourceName: customSource.name,
            resultPath: customSource.path,
          ).then((results) => results ?? const []),
      ];
      final errors = <Object>[];
      final resultSets = await Future.wait(
        searches.map((search) async {
          try {
            return await search;
          } catch (error) {
            errors.add(error);
            return const <ImdbSubtitle>[];
          }
        }),
      );
      final unique = <String, ImdbSubtitle>{};
      for (final subtitle in resultSets.expand((results) => results)) {
        final url = subtitle.url?.toLowerCase();
        if (url != null && url.isNotEmpty) {
          unique.putIfAbsent(url, () => subtitle);
        }
      }
      final found = unique.values.toList();
      _update((s) => s.copyWith(subtitles: found, titles: const []));
      if (found.isEmpty && errors.isNotEmpty) {
        throw FormatException(
          errors.map((error) => error.toString()).join('\n'),
        );
      }
    } else {
      final found = await fetchImdbTitles(query);
      _update((s) => s.copyWith(titles: found));
    }
    _update((s) => s.copyWith(query: query, searched: true));
  });

  /// Goes down a level: a title's episodes (or its subtitles when it has
  /// none), an episode's subtitles.
  Future<void> _open(int index) => _run(() async {
    final state = _state;
    if (state.episodes != null) {
      final found = await fetchImdbSubtitles(state.episodes![index].id);
      _update((s) => s.copyWith(subtitles: found));
    } else {
      final episodes = await fetchImdbEpisodes(state.titles[index].id);
      final found =
          episodes == null || episodes.isEmpty
          ? await fetchImdbSubtitles(state.titles[index].id)
          : null;
      _update((s) => s.copyWith(episodes: episodes, subtitles: found));
    }
  });

  /// Back up a level, to the episodes or the titles.
  void _back() => _update(
    (s) => s.copyWith(
      clearError: true,
      clearSubtitles: s.subtitles != null,
      clearEpisodes: s.subtitles == null,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch so restoring a cached search rebuilds the sheet immediately.
    final state = ref.watch(subtitleSearchStateProvider(_cacheKey));
    final l10n = context.l10n;
    final media = MediaQuery.of(context);
    final count =
        state.subtitles?.length ?? state.episodes?.length ?? state.titles.length;
    final Widget body;
    if (state.isLoading) {
      body = const ShioriLoading();
    } else if (state.errorMsg != null) {
      body = ErrorState(detail: state.errorMsg, onRetry: _search);
    } else if (count == 0) {
      body = ShioriEmptyState(
        icon: Symbols.search_off_rounded,
        title: l10n.no_result,
        compact: true,
      );
    } else {
      body = ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: ShioriSpace.s16),
        itemCount: count,
        itemBuilder: (context, index) => state.subtitles != null
            ? _subtitleRow(context, state.subtitles![index], index)
            : state.episodes != null
            ? _episodeRow(context, state.episodes![index], index)
            : _titleRow(context, state.titles[index], index),
      );
    }
    return Padding(
      // The keyboard covers the sheet's foot; the results stay above it.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      // As tall as the results, up to three quarters of the screen; the
      // loading, empty and failed states keep a modest height of their own.
      child: AnimatedSize(
        duration: ShioriMotion.of(context, ShioriMotion.standard),
        curve: ShioriMotion.standardCurve,
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ShioriSpace.s8,
                  0,
                  ShioriSpace.s16,
                  ShioriSpace.s8,
                ),
                child: Row(
                  spacing: ShioriSpace.s4,
                  children: [
                    if (state.subtitles != null || state.episodes != null)
                      IconButton(
                        tooltip: l10n.back_to_results,
                        onPressed: _back,
                        icon: const Icon(Symbols.arrow_back_rounded),
                      )
                    else
                      const SizedBox(width: ShioriSpace.s8),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: _controller,
                        builder: (context, _) => TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: l10n.search,
                            prefixIcon: const Icon(Symbols.search_rounded),
                            suffixIcon: _controller.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: MaterialLocalizations.of(context)
                                        .clearButtonTooltip,
                                    onPressed: _controller.clear,
                                    icon: const Icon(Symbols.close_rounded),
                                  ),
                          ),
                          onSubmitted: (_) => _search(),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Custom subtitle source',
                      onPressed: () async {
                        final saved = await CustomSubtitleSourceEditor.show(
                          context,
                          testQuery: _controller.text.trim(),
                        );
                        if (saved == true && mounted) await _search();
                      },
                      icon: const Icon(Symbols.settings_rounded),
                    ),
                    IconButton(
                      tooltip: 'Search on JavSub.ai',
                      onPressed: () async {
                        final query = normalizeSubtitleSearchId(
                          _controller.text.trim(),
                        );
                        if (query.isEmpty) return;
                        final uri = Uri.https('javsub.ai', '/search', {
                          'q': query,
                        });
                        if (!await ExternalBrowser.open(uri.toString()) &&
                            context.mounted) {
                          botToast(context.l10n.error);
                        }
                      },
                      icon: const Icon(Symbols.open_in_new_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: body is ListView
                    ? body
                    : SizedBox(height: context.shiori.scaled(240), child: body),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A title: its poster, its name, its rating and its years.
  Widget _titleRow(BuildContext context, ImdbTitle title, int index) {
    final tokens = context.shiori;
    final years = [title.startYear, title.endYear].whereType<int>().join(' – ');
    final meta = [
      if (title.aggregateRating != null)
        '★ ${title.aggregateRating!.toStringAsFixed(1)}${title.voteCount == null ? '' : ' (${title.voteCount})'}',
      if (years.isNotEmpty) years,
    ].join(' · ');
    return InkWell(
      onTap: () => _open(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShioriSpace.s16,
          vertical: ShioriSpace.s8,
        ),
        child: Row(
          spacing: ShioriSpace.s12,
          children: [
            ShioriThumbnail(
              height: tokens.scaled(72),
              child: title.primaryImage == null
                  ? Icon(Symbols.movie_rounded, color: tokens.color.fgMuted)
                  : Image(
                      image: CustomExtendedNetworkImageProvider(
                        title.primaryImage!,
                      ),
                      fit: BoxFit.cover,
                    ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    title.primaryTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.text.row.copyWith(
                      color: tokens.color.fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (meta.isNotEmpty) Text(meta, style: tokens.caption),
                ],
              ),
            ),
            Icon(Symbols.chevron_forward_rounded, color: tokens.color.fgMuted),
          ],
        ),
      ),
    );
  }

  /// An episode: "S1E2", then its title.
  Widget _episodeRow(BuildContext context, ImdbEpisode episode, int index) {
    return ShioriListRow(
      title: episode.title,
      subtitle: 'S${episode.season}E${episode.episode}',
      trailing: Icon(
        Symbols.chevron_forward_rounded,
        color: context.shiori.color.fgMuted,
      ),
      onTap: () => _open(index),
    );
  }

  /// A subtitle file: its name, its language, format and encoding, and a
  /// download for a local episode.
  Widget _subtitleRow(BuildContext context, ImdbSubtitle subtitle, int index) {
    final meta = [
      subtitle.source,
      subtitle.displayLang,
      subtitle.format?.toUpperCase(),
      subtitle.encoding,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return ShioriListRow(
      title: subtitle.name ?? subtitle.displayLang ?? '',
      titleMaxLines: 2,
      subtitle: meta.isEmpty ? null : meta,
      trailing: widget.isLocal
          ? IconButton(
              tooltip: context.l10n.download,
              onPressed: () => _downloadSubtitle(index),
              icon: const Icon(Symbols.download_rounded),
            )
          : null,
      onTap: () => _selectSubtitle(subtitle),
    );
  }

  Future<void> _selectSubtitle(ImdbSubtitle subtitle) async {
    if (subtitle.source != 'AVSubtitles') {
      Navigator.pop(context, subtitle);
      return;
    }

    try {
      final bytes = await fetchAvSubtitleFile(subtitle.url!);
      final directory = await getTemporaryDirectory();
      final file = File(
        path.join(directory.path, 'mangayomi_${subtitle.id}.srt'),
      );
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      Navigator.pop(
        context,
        ImdbSubtitle(
          id: subtitle.id,
          url: Uri.file(file.path).toString(),
          format: subtitle.format,
          encoding: subtitle.encoding,
          displayLang: subtitle.displayLang,
          language: subtitle.language,
          name: subtitle.name,
          source: subtitle.source,
          isHearingImpaired: subtitle.isHearingImpaired,
        ),
      );
    } catch (error) {
      if (mounted) botToast(context.l10n.error_with_message(error));
    }
  }

  Future<void> _downloadSubtitle(int index) async {
    botToast(context.l10n.started);
    try {
      final subtitle = _state.subtitles![index];
      final storageProvider = StorageProvider();
      final resolvedArchivePath =
          widget.chapter.archivePath?.isNotEmpty ?? false
          ? await resolveLocalArchivePath(widget.chapter.archivePath!)
          : null;
      final animeDir =
          resolvedArchivePath != null &&
              widget.chapter.manga.value?.source == "local"
          ? Directory(path.dirname(resolvedArchivePath))
          : null;
      final chapterDirectory = (await storageProvider.getMangaChapterDirectory(
        widget.chapter,
        mangaMainDirectory: animeDir,
      ))!;
      final subtitleFile = File(
        path.join(
          '${chapterDirectory.path}_subtitles',
          '${subtitle.language}.srt',
        ),
      );
      final client = MClient.httpClient(
        settings: const ClientSettings(
          throwOnStatusCode: false,
          tlsSettings: TlsSettings(verifyCertificates: false),
        ),
      );
      await subtitleFile.create(recursive: true);
      final bytes = subtitle.source == 'AVSubtitles'
          ? await _withRetry(() => fetchAvSubtitleFile(subtitle.url!))
          : await _withRetry(() async {
              final response = await client.get(Uri.parse(subtitle.url ?? ''));
              if (response.statusCode != 200) {
                throw HttpException(
                  'Subtitle download returned HTTP ${response.statusCode}',
                );
              }
              return response.bodyBytes;
            });
      AppLogger.log('Subtitle file downloaded: ${subtitle.language}');
      await subtitleFile.writeAsBytes(bytes);
      if (mounted) {
        botToast(context.l10n.finished(""));
      }
    } catch (e) {
      AppLogger.log("Failed to download subtitle:", logLevel: LogLevel.error);
      AppLogger.log(e.toString(), logLevel: LogLevel.error);
      if (mounted) {
        botToast(context.l10n.failed);
      }
    }
  }

  Future<T> _withRetry<T>(Future<T> Function() operation) async {
    int attempts = 0;
    while (true) {
      try {
        attempts++;
        return await operation();
      } catch (e) {
        if (attempts >= 3) {
          AppLogger.log("Request retries failed", logLevel: LogLevel.error);
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 300 * attempts));
      }
    }
  }
}

/// Opens the subtitle search for [chapter]; resolves to the subtitle
/// picked, or null.
Future<ImdbSubtitle?> subtitlesSearchraggableMenu(
  BuildContext context, {
  required Chapter chapter,
  required bool isLocal,
}) {
  return showShioriSheet<ImdbSubtitle>(
    context,
    title: context.l10n.group_subtitles,
    builder: (_) => SubtitlesWidgetSearch(chapter: chapter, isLocal: isLocal),
  );
}
