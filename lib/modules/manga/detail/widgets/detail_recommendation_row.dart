import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
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
    this.onOpenAll,
  });

  final Manga manga;
  final DetailRecommendationFetcher fetcher;

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
    try {
      final results = await widget.fetcher(
        media,
        ref.read(algorithmWeightsStateProvider),
      );
      if (mounted) {
        setState(() {
          _data = results;
          _isLoading = false;
        });
      }
    } catch (_) {
      // A detail page is not the place to narrate an AniList/Trakt outage.
      // The full Recommendations screen still surfaces the real error.
      if (mounted) setState(() => _isLoading = false);
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
    // Nothing to show while loading (the page would jump when data arrives)
    // and nothing to show on an error or an empty match: no dead section.
    final data = _data;
    if (_isLoading || data == null || data.isEmpty) {
      return const SizedBox.shrink();
    }
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
              itemCount: data.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: ShioriSpace.s8),
              itemBuilder: (context, index) =>
                  _card(context, data[index], index),
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
    final coverUrl = rec.imgURLs.isNotEmpty ? rec.imgURLs.first : "";
    final rating = rec.rating;
    void open() => context.push(
      '/globalSearch',
      extra: (rec.searchTarget.query, rec.searchTarget.itemType),
    );

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
                      rec.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.text.meta.copyWith(
                        color: tokens.color.fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (rating != null) ...[
                      const SizedBox(height: 2),
                      EntryBadgeChip(label: rating.valueLabel),
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
