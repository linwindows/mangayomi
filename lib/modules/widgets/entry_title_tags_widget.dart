import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mangayomi/eval/model/m_bridge.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/modules/library/library_screen.dart';
import 'package:mangayomi/modules/main_view/nav_groups.dart';
import 'package:mangayomi/modules/manga/detail/providers/state_providers.dart';
import 'package:mangayomi/modules/widgets/entry_badge_chip.dart';
import 'package:mangayomi/modules/widgets/entry_title_tags.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/utils/utils.dart';
import 'package:shiori/shiori.dart';

/// The subtitle/uncensored markers read from a card's title, genre tags and
/// entry link, laid out as a small row of badges. Renders nothing when none
/// of them carry those markers. The uncensored tag is accented so it stands
/// out; subtitles stay neutral.
///
/// Each badge is tappable and opens the same library/source search menu as
/// genre chips and actors. It searches using the tag's [EntryTitleTag.searchTerm]
/// (the slug the source actually stores in the URL), not the localized label,
/// so the search finds the tagged entries both in the library and at source.
class EntryTitleTagsWidget extends ConsumerWidget {
  const EntryTitleTagsWidget({
    super.key,
    this.title,
    this.genre,
    this.link,
    this.itemType,
    this.source,
    this.lang,
    this.sourceId,
  });

  final String? title;
  final List<String>? genre;
  final String? link;

  /// Search context. When [source] is null the source-search entry is omitted
  /// (still searchable in the library).
  final ItemType? itemType;
  final String? source;
  final String? lang;
  final int? sourceId;

  void _searchTag(
    BuildContext context,
    WidgetRef ref,
    EntryTitleTag tag,
    int value,
  ) {
    final l10n = l10nLocalizations(context)!;
    final term = tag.searchTerm;

    if (value == 0) {
      context.go(
        libraryRouteFor(itemType ?? ItemType.anime),
        extra: LibrarySearch(term),
      );
      return;
    }

    final src = getSource(lang ?? '', source ?? '', sourceId);
    if (src == null) {
      botToast(l10n.source_not_added);
      return;
    }
    // Leave the detail page clean for the page we are pushing on top.
    ref.read(isLongPressedStateProvider.notifier).update(false);
    ref.read(chaptersListStateProvider.notifier).clear();
    context.push('/mangaHomeGenre', extra: (src, term));
  }

  Widget _tagChip(
    BuildContext context,
    WidgetRef ref,
    EntryTitleTag tag,
  ) {
    final l10n = l10nLocalizations(context)!;
    final tone = tag == EntryTitleTag.uncensored
        ? EntryBadgeChip.accent(context)
        : null;

    return MenuAnchor(
      style: shioriMenuStyle(context),
      menuChildren: [
        ShioriMenuEntry(
          ShioriMenuItem(
            label: l10n.tag_search_library,
            icon: Symbols.collections_bookmark_rounded,
            onSelected: () => _searchTag(context, ref, tag, 0),
          ),
        ),
        if (source != null)
          ShioriMenuEntry(
            ShioriMenuItem(
              label: l10n.tag_search_source,
              icon: Symbols.travel_explore_rounded,
              onSelected: () => _searchTag(context, ref, tag, 1),
            ),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        onTap: () =>
            controller.isOpen ? controller.close() : controller.open(),
        borderRadius: BorderRadius.circular(ShioriShape.badge),
        child: EntryBadgeChip(label: tag.label, tone: tone),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = extractEntryTitleTags(title, genre, link);
    if (tags.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        for (final tag in tags) _tagChip(context, ref, tag),
      ],
    );
  }
}
