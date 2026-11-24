import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mangayomi/eval/model/m_bridge.dart';
import 'package:mangayomi/eval/model/m_manga.dart';
import 'package:mangayomi/eval/model/m_pages.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/anime/widgets/search_subtitles.dart'
    show extractJavCode;
import 'package:mangayomi/modules/manga/widgets/manga_image_card_widget.dart';
import 'package:mangayomi/providers/browse_state_provider.dart';
import 'package:mangayomi/services/isolate_service.dart';
import 'package:mangayomi/utils/utils.dart';
import 'package:mangayomi/modules/manga/detail/tv/widgets/tv_key_utils.dart';
import 'package:mangayomi/modules/widgets/entry_badge_chip.dart';
import 'package:mangayomi/modules/more/providers/algorithm_weights_state_provider.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/repositories/track_repository.dart';
import 'package:mangayomi/services/discovery/media_lookup_context.dart';
import 'package:mangayomi/services/recommendation.dart';
import 'package:mangayomi/utils/cached_network.dart';
import 'package:mangayomi/utils/constant.dart';
import 'package:mangayomi/utils/platform_utils.dart';
import 'package:shiori/shiori.dart';

/// Fetches the recommendations shown in [DetailRecommendationRow]. Injectable
/// so widget tests can supply a deterministic result without reaching the
/// network.
typedef DetailRecommendationFetcher =
    Future<List<RecommendationResult>> Function(
      MediaLookupContext media,
      AlgorithmWeights weights,
    );

/// Searches the title's own extension source for similar entries. Used when
/// the catalog services know nothing about the title, the same fallback
/// Anikku/Komikku use for sources without a "related" endpoint.
typedef DetailSourceRelatedFetcher =
    Future<List<MManga>> Function(Manga manga, String? proxyServer);

/// Strips "(2023)", "[HD]", "第2季", "Season 2" and similar noise so the
/// source search matches sibling entries, not only the exact title.
String relatedSearchQuery(String name) {
  var q = name
      .replaceAll(RegExp(r'[\(\[（【].*?[\)\]）】]'), ' ')
      .replaceAll(RegExp(r'第\s*[\d一二三四五六七八九十]+\s*[季部期]'), ' ')
      .replaceAll(RegExp(r'\b(season|s)\s*\d+\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (q.isEmpty) q = name.trim();
  return q;
}

/// Builds the ordered list of search terms to try. For a normal title it is
/// just the cleaned title. For a title that carries a JAV-style code (either a
/// bare "SSNI-123" or embedded in "SSNI-123 女优名 中文字幕"), it skips straight
/// to the actress (author/artist) and then the first tag, because the code
/// itself only ever returns the entry we are already on.
List<String> relatedSearchCandidates(Manga manga) => relatedSearchCandidatesFrom(
  name: manga.name,
  author: manga.author,
  artist: manga.artist,
  genre: manga.genre,
);

/// Splits a metadata field that may pack several values into one string
/// ("赤井彗星, Real Works") into clean individual search terms, and drops the
/// parenthetical alias that code sources love to append ("天宫まりん (天宮まりん)"
/// → "天宫まりん"). Both of those forms return HTTP 500 when searched verbatim,
/// so only the split/cleaned terms are usable.
List<String> splitMetaTerms(String? raw) {
  if (raw == null) return const [];
  final out = <String>[];
  for (final part in raw.split(RegExp(r'[,，、/／]'))) {
    // Keep the base name, drop any "(...)"/（...） alias suffix.
    final cleaned = part
        .replaceAll(RegExp(r'[\(（].*?[\)）]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isNotEmpty && !out.contains(cleaned)) out.add(cleaned);
  }
  return out;
}

/// Field-based variant so metadata fetched via `getDetail` can be reused.
List<String> relatedSearchCandidatesFrom({
  String? name,
  String? author,
  String? artist,
  List<String>? genre,
}) {
  final manga = (author: author, artist: artist, genre: genre);
  name = (name ?? '').trim();
  final out = <String>[];
  void add(String? v) {
    final t = (v ?? '').trim();
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }

  final code = name.isEmpty ? null : extractJavCode(name);
  final isCode = code != null;
  if (!isCode) add(relatedSearchQuery(name));
  // Actress / author first — it is the strongest "more like this" signal on a
  // code source, and a reasonable secondary signal on a normal title. These
  // fields often pack several values ("赤井彗星, Real Works") or carry a
  // parenthetical alias, both of which only match once split and cleaned.
  splitMetaTerms(manga.author).forEach(add);
  splitMetaTerms(manga.artist).forEach(add);
  // Tags/genres are the last resort: broad, but better than an empty rail.
  final genres = manga.genre ?? const <String>[];
  for (final g in genres) {
    splitMetaTerms(g).forEach(add);
  }
  // A code title must NEVER be searched by its own code: the code is unique
  // to this entry, so it would only ever find itself. If there is no actress
  // or tag to go on, leave the rail empty instead. For a normal title, fall
  // back to the raw name so the search still runs.
  if (out.isEmpty && !isCode && name.isNotEmpty) add(name);
  return out;
}

Future<List<MManga>> searchSourceRelated(
  Manga manga,
  String? proxyServer,
) async {
  final name = manga.name;
  if (name == null || name.trim().isEmpty) {
    if (kDebugMode) debugPrint('[RecRow] source search skipped: empty name');
    return const [];
  }
  final source = getSource(manga.lang ?? '', manga.source ?? '', manga.sourceId);
  if (source == null) {
    if (kDebugMode) {
      debugPrint('[RecRow] source not found: lang=${manga.lang} '
          'name=${manga.source} sourceId=${manga.sourceId}');
    }
    return const [];
  }
  var candidates = relatedSearchCandidates(manga);
  String detailInfo = '未拉详情';
  if (candidates.isEmpty &&
      extractJavCode(name) != null &&
      (manga.link ?? '').isNotEmpty) {
    // Code entries are stored with only a name; fetch the detail page to get
    // the actress and tags to search by.
    try {
      final detail = await getIsolateService.get<MManga>(
        url: manga.link,
        source: source,
        serviceType: 'getDetail',
        proxyServer: proxyServer,
      );
      candidates = relatedSearchCandidatesFrom(
        name: name,
        author: detail.author,
        artist: detail.artist,
        genre: detail.genre,
      );
      detailInfo = '详情author="${detail.author}" artist="${detail.artist}" '
          'genre=${detail.genre}';
    } catch (e) {
      detailInfo = '详情失败:$e';
      if (kDebugMode) debugPrint('[RecRow] getDetail failed: $e');
    }
  }
  final selfCode = extractJavCode(name);
  final selfName = name.trim().toLowerCase();
  final selfLink = manga.link;
  bool isSelf(MManga m) {
    final mName = (m.name ?? '').trim();
    if (mName.isEmpty) return true;
    if (m.link == selfLink) return true;
    if (mName.toLowerCase() == selfName) return true;
    // Code sources often expose the same entry under slightly different
    // links/mirrors; dedupe by the JAV code so the rail never shows itself.
    if (selfCode != null && extractJavCode(mName) == selfCode) return true;
    return false;
  }

  for (final query in candidates) {
    MPages? pages;
    try {
      pages = await getIsolateService.get<MPages?>(
        query: query,
        filterList: const [],
        source: source,
        page: 1,
        serviceType: 'search',
        proxyServer: proxyServer,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RecRow] source search threw for "$query" '
            '(${manga.source}): $e');
      }
      // Code sources commonly return "no more result found" as a thrown error
      // for a term that simply has no hits. Treat every candidate the same:
      // move on to the next one instead of letting one bad term kill the rail.
      continue;
    }
    final raw = pages?.list ?? const <MManga>[];
    final filtered = raw
        .where((m) => !isSelf(m))
        .take(20)
        .toList(growable: false);
    if (kDebugMode) {
      debugPrint('[RecRow] source="${manga.source}" query="$query" '
          'raw=${raw.length} kept=${filtered.length}');
    }
    if (filtered.isNotEmpty) return filtered;
  }
  return const [];
}

/// The recommendation "slot" on a title's detail page: a section heading and
/// a horizontal strip of covers, mirroring Anikku's `RelatedMangasRow`.
///
/// Unlike the full [RecommendationScreen] this is deliberately quiet: a
/// provider outage or a title with no matches simply leaves no slot behind,
/// so opening a detail page never turns into an error wall. Tapping the
/// heading opens the full screen, tapping a cover searches the user's sources.
class DetailRecommendationRow extends ConsumerStatefulWidget {
  const DetailRecommendationRow({
    super.key,
    required this.manga,
    this.fetcher = getRecommendations,
    this.sourceFetcher = searchSourceRelated,
    this.onOpenAll,
  });

  final Manga manga;
  final DetailRecommendationFetcher fetcher;
  final DetailSourceRelatedFetcher sourceFetcher;

  /// Defaults to pushing the full `/recommendations` screen. Injectable so a
  /// test can assert the heading is tappable without a GoRouter in the tree.
  final VoidCallback? onOpenAll;

  @override
  ConsumerState<DetailRecommendationRow> createState() =>
      _DetailRecommendationRowState();
}

class _DetailRecommendationRowState
    extends ConsumerState<DetailRecommendationRow> {
  List<RecommendationResult>? _data;
  List<MManga>? _sourceData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final manga = widget.manga;
    // Local files have no catalog identity (and no useful title for AniList
    // in most cases), so don't send them to the discovery services.
    if (manga.isLocalArchive ?? false) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final media = MediaLookupContext.fromManga(
      manga,
      tracks: trackRepository.getAllByMangaId(manga.id),
    );
    List<RecommendationResult> results = const [];
    try {
      results = await widget.fetcher(
        media,
        ref.read(algorithmWeightsStateProvider),
      );
    } catch (_) {
      // A detail page is not the place to narrate an AniList/Trakt outage.
      // The full Recommendations screen still surfaces the real error.
    }
    if (results.isNotEmpty) {
      if (mounted) {
        setState(() {
          _data = results;
          _isLoading = false;
        });
      }
      return;
    }
    // Catalogs know nothing about this title (typical for Chinese video
    // sources). Ask the title's own extension, like Anikku does.
    List<MManga> fromSource = const [];
    try {
      fromSource = await widget.sourceFetcher(
        manga,
        ref.read(androidProxyServerStateProvider),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[RecRow] source fallback failed: $e');
    }
    if (mounted) {
      setState(() {
        _sourceData = fromSource;
        _isLoading = false;
      });
    }
  }

  void _openAll() {
    final onOpenAll = widget.onOpenAll;
    if (onOpenAll != null) {
      onOpenAll();
      return;
    }
    final media = MediaLookupContext.fromManga(
      widget.manga,
      tracks: trackRepository.getAllByMangaId(widget.manga.id),
    );
    context.push('/recommendations', extra: (
      media,
      ref.read(algorithmWeightsStateProvider),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // While loading show the heading plus a spinner so the user knows
    // recommendations are on the way; an error or empty match leaves no slot.
    if (_isLoading) return _loading(context);
    final data = _data ?? const <RecommendationResult>[];
    final sourceData = _sourceData ?? const <MManga>[];
    if (data.isEmpty && sourceData.isEmpty) return const SizedBox.shrink();
    final fromSource = data.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: ShioriSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context),
          SizedBox(
            height: _cardExtent,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: ShioriSpace.s12,
              ).add(tvPageInsets),
              itemCount: fromSource ? sourceData.length : data.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: ShioriSpace.s8),
              itemBuilder: (context, index) => fromSource
                  ? _sourceCard(context, sourceData[index])
                  : _card(context, data[index], index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loading(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: ShioriSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context),
          SizedBox(
            height: _cardExtent,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.shiori;
    return InkWell(
      onTap: _openAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShioriSpace.s12,
          vertical: ShioriSpace.s4,
        ).add(tvPageInsets),
        child: Row(
          children: [
            Icon(
              Symbols.auto_awesome_rounded,
              size: tokens.scaled(16),
              color: tokens.color.accentInk,
            ),
            const SizedBox(width: ShioriSpace.s8),
            Text(
              l10n.recommendations,
              style: tokens.text.section.copyWith(color: tokens.color.fg),
            ),
            const Spacer(),
            Text(
              l10n.more,
              style: tokens.text.meta.copyWith(color: tokens.color.accentInk),
            ),
            const SizedBox(width: 2),
            Icon(
              Symbols.chevron_forward_rounded,
              size: tokens.scaled(16),
              color: tokens.color.accentInk,
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, RecommendationResult rec, int index) {
    return _coverCard(
      context,
      coverUrl: rec.imgURLs.isNotEmpty ? rec.imgURLs.first : "",
      title: rec.title,
      badge: rec.rating?.valueLabel,
      open: () => context.push(
        '/globalSearch',
        extra: (rec.searchTarget.query, rec.searchTarget.itemType),
      ),
    );
  }

  /// A result from the title's own source opens straight into its detail
  /// page in that source, no global search detour.
  Widget _sourceCard(BuildContext context, MManga item) {
    final manga = widget.manga;
    return _coverCard(
      context,
      coverUrl: item.imageUrl ?? "",
      title: item.name!.trim(),
      badge: null,
      open: () => pushToMangaReaderDetail(
        ref: ref,
        context: context,
        getManga: item,
        lang: manga.lang ?? '',
        source: manga.source ?? '',
        sourceId: manga.sourceId,
        itemType: manga.itemType,
      ),
    );
  }

  Widget _coverCard(
    BuildContext context, {
    required String coverUrl,
    required String title,
    required String? badge,
    required VoidCallback open,
  }) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isTvSelectKey(event.logicalKey)) {
          open();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          final tokens = context.shiori;
          return Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(ShioriShape.cover),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: open,
              child: Container(
                width: _coverWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ShioriShape.cover),
                  border: focused
                      ? Border.all(
                          color: tokens.color.accentInk,
                          width: 2,
                        )
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(ShioriShape.cover),
                      child: Image(
                        image: coverProvider(toImgUrl(coverUrl)),
                        width: _coverWidth,
                        height: _coverHeight,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: ShioriSpace.s4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.text.meta.copyWith(
                        color: tokens.color.fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 2),
                      EntryBadgeChip(label: badge),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Covers are 2:3; all cards share one extent so the row never jitters.
const double _coverWidth = 104;
const double _coverHeight = 156;

/// Cover, title (2 lines) and an optional rating chip.
const double _cardExtent = _coverHeight + 64;
