import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mangayomi/eval/model/m_bridge.dart';
import 'package:mangayomi/eval/model/m_manga.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/modules/library/library_screen.dart';
import 'package:mangayomi/modules/library/widgets/category_selection_dialog.dart';
import 'package:mangayomi/modules/main_view/nav_groups.dart';
import 'package:mangayomi/modules/manga/detail/manga_detail_view.dart';
import 'package:mangayomi/modules/manga/detail/providers/state_providers.dart';
import 'package:mangayomi/modules/manga/detail/widgets/detail_header_action.dart';
import 'package:mangayomi/modules/manga/detail/widgets/detail_recommendation_row.dart';
import 'package:mangayomi/modules/widgets/entry_title_tags_widget.dart';
import 'package:mangayomi/modules/mass_migration/services/mass_migration_service.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/repositories/category_repository.dart';
import 'package:mangayomi/repositories/manga_repository.dart';
import 'package:mangayomi/repositories/source_repository.dart';
import 'package:mangayomi/services/get_detail.dart';
import 'package:mangayomi/utils/constant.dart';
import 'package:mangayomi/utils/utils.dart';
import 'package:shiori/shiori.dart';

enum _DuplicateLibraryAction { addAnyway, migrate }

class MangaDetailsView extends ConsumerStatefulWidget {
  final Manga manga;
  final bool sourceExist;
  final Function(bool) checkForUpdate;
  const MangaDetailsView({
    super.key,
    required this.sourceExist,
    required this.manga,
    required this.checkForUpdate,
  });

  @override
  ConsumerState<MangaDetailsView> createState() => _MangaDetailsViewState();
}

class _MangaDetailsViewState extends ConsumerState<MangaDetailsView> {
  /// "Add to library" entry point: checks whether this exact title is
  /// already favorited under a different source first, so the same manga
  /// can't end up as two separate library entries by accident. Only warns —
  /// the underlying add still runs unchanged when there's no duplicate, or
  /// once the user picks Add Anyway.
  Future<void> _onAddToLibraryPressed(BuildContext context) async {
    final model = widget.manga;
    final duplicates = (await mangaRepository.findFavoritesByItemTypeAndName(
      model.itemType,
      model.name,
    )).where((m) => m.id != model.id).toList();

    if (duplicates.isNotEmpty) {
      final oldManga = duplicates.first;
      final oldSource = oldManga.sourceId != null
          ? sourceRepository.getById(oldManga.sourceId!)
          : null;
      if (!context.mounted) return;
      final action = await _showAlreadyInLibraryDialog(
        context,
        model,
        oldSource?.name ?? '',
      );
      if (action == null) return;
      if (!context.mounted) return;
      if (action == _DuplicateLibraryAction.migrate) {
        await _migrateExistingToThisSource(context, oldManga, model);
        return;
      }
      // addAnyway falls through to the normal add below.
    }
    if (context.mounted) await _addToLibrary(context, model);
  }

  Future<void> _addToLibrary(BuildContext context, Manga model) async {
    final checkCategoryList = categoryRepository.isNotEmptyByItemType(
      model.itemType,
    );
    if (checkCategoryList) {
      showCategorySelectionDialog(
        context: context,
        ref: ref,
        itemType: model.itemType,
        singleManga: model,
      );
    } else {
      model.favorite = true;
      model.dateAdded = DateTime.now().millisecondsSinceEpoch;
      await mangaRepository.save(model);
    }
  }

  Future<_DuplicateLibraryAction?> _showAlreadyInLibraryDialog(
    BuildContext context,
    Manga model,
    String oldSourceName,
  ) {
    final l10n = l10nLocalizations(context)!;
    return showDialog<_DuplicateLibraryAction>(
      context: context,
      builder: (ctx) => ShioriDialog(
        title: model.name ?? '',
        content: Text(l10n.already_in_library(oldSourceName, model.name ?? '')),
        actions: [
          ShioriButton.quiet(
            label: l10n.cancel,
            onPressed: () => Navigator.pop(ctx),
          ),
          ShioriButton.secondary(
            label: l10n.add_anyway,
            onPressed: () =>
                Navigator.pop(ctx, _DuplicateLibraryAction.addAnyway),
          ),
          ShioriButton(
            label: l10n.migrate,
            onPressed: () =>
                Navigator.pop(ctx, _DuplicateLibraryAction.migrate),
          ),
        ],
      ),
    );
  }

  /// Rewrites [oldManga] (the existing library entry) to track this source
  /// instead, folding in its chapters/progress via the same path the manual
  /// Migrate screen uses, then drops [newManga] — the row for the page
  /// currently open — since its data is now redundant with the migrated
  /// [oldManga].
  Future<void> _migrateExistingToThisSource(
    BuildContext context,
    Manga oldManga,
    Manga newManga,
  ) async {
    if (newManga.sourceId == null || newManga.link == null) return;
    final destinationSource = sourceRepository.getById(newManga.sourceId!);
    if (destinationSource == null) return;

    final selectedManga = MManga(
      name: newManga.name,
      link: newManga.link,
      imageUrl: newManga.imageUrl,
    );
    final preview = await ref.read(
      getDetailProvider(url: newManga.link!, source: destinationSource).future,
    );
    await migrateLibraryItem(
      ref: ref,
      oldManga: oldManga,
      selectedManga: selectedManga,
      preview: preview,
      destinationSource: destinationSource,
    );
    await mangaRepository.deleteLibrarySourceGroup([newManga]);
    if (context.mounted) Navigator.pop(context);
  }

  Size measureText(String text, TextStyle style) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return textPainter.size;
  }

  double calculateDynamicButtonWidth(
    String text,
    TextStyle textStyle,
    double padding,
  ) {
    final textSize = measureText(text, textStyle);
    return textSize.width + padding;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nLocalizations(context)!;
    bool? isLocalArchive = widget.manga.isLocalArchive ?? false;
    return Scaffold(
      body: MangaDetailView(
        titleDescription: Builder(
          builder: (context) {
            final tokens = context.shiori;
            final meta = tokens.text.meta.copyWith(color: tokens.color.fgMuted);
            final iconSize = tokens.scaled(14);
            return Padding(
              padding: const EdgeInsets.only(top: ShioriSpace.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  // Subtitle / uncensored markers live in the source URL slug
                  // (the source strips them from the title), so read them from
                  // name, genre and link just like the list cards do.
                  EntryTitleTagsWidget(
                    title: widget.manga.name,
                    genre: widget.manga.genre,
                    link: widget.manga.link,
                    itemType: widget.manga.itemType,
                    source: widget.manga.source,
                    lang: widget.manga.lang,
                    sourceId: widget.manga.sourceId,
                  ),
                  _ActorRow(manga: widget.manga, l10n: l10n),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: ShioriSpace.s4,
                    children: [
                      Icon(
                        getMangaStatusIcon(widget.manga.status),
                        size: iconSize,
                        color: tokens.color.fgMuted,
                      ),
                      Text(
                        [
                          getMangaStatusName(widget.manga.status, context),
                          if (!isLocalArchive)
                            '${widget.manga.source!} (${widget.manga.lang!.toUpperCase()})',
                        ].join(' · '),
                        style: meta,
                      ),
                      // The source is no longer installed.
                      if (!isLocalArchive && !widget.sourceExist)
                        Icon(
                          Symbols.warning_rounded,
                          color: tokens.color.offline.foreground,
                          size: iconSize,
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        action: widget.manga.favorite!
            ? DetailHeaderAction(
                icon: Symbols.favorite_rounded,
                label: l10n.in_library,
                active: true,
                onPressed: () async {
                  final model = widget.manga;
                  model.favorite = false;
                  model.dateAdded = 0;
                  await mangaRepository.save(model);
                },
                // As in Mihon: a tap takes it out, a long press keeps it and
                // changes its categories.
                onLongPress: () => showCategorySelectionDialog(
                  context: context,
                  ref: ref,
                  itemType: widget.manga.itemType,
                  singleManga: widget.manga,
                ),
              )
            : DetailHeaderAction(
                icon: Symbols.favorite_rounded,
                label: l10n.add_to_library,
                onPressed: () => _onAddToLibraryPressed(context),
              ),
        manga: widget.manga,
        sourceExist: widget.sourceExist,
        checkForUpdate: widget.checkForUpdate,
        itemType: widget.manga.itemType,
      ),
    );
  }
}

/// The author field holds the cast on video sources. Render each actor as a
/// tappable label that opens the same library/source search menu as genre
/// chips, so tapping an actor finds the rest of their work. Multi-value
/// strings ("赤井彗星, Real Works") are split and cleaned before display.
class _ActorRow extends ConsumerWidget {
  const _ActorRow({required this.manga, required this.l10n});

  final Manga manga;
  final AppLocalizations l10n;

  void _searchActor(BuildContext context, WidgetRef ref, String actor, int value) {
    if (value == 0) {
      context.go(
        libraryRouteFor(manga.itemType),
        extra: LibrarySearch(actor),
      );
      return;
    }

    final source = getSource(
      manga.lang ?? '',
      manga.source ?? '',
      manga.sourceId,
    );
    if (source == null) {
      botToast(l10n.source_not_added);
      return;
    }
    // Leave the detail page clean for the page we are pushing on top.
    ref.read(isLongPressedStateProvider.notifier).update(false);
    ref.read(chaptersListStateProvider.notifier).clear();
    context.push('/mangaHomeGenre', extra: (source, actor));
  }

  Widget _actorChip(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) {
    final tokens = context.shiori;
    return MenuAnchor(
      style: shioriMenuStyle(context),
      menuChildren: [
        ShioriMenuEntry(
          ShioriMenuItem(
            label: l10n.actor_search_library,
            icon: Symbols.collections_bookmark_rounded,
            onSelected: () => _searchActor(context, ref, name, 0),
          ),
        ),
        ShioriMenuEntry(
          ShioriMenuItem(
            label: l10n.actor_search_source,
            icon: Symbols.travel_explore_rounded,
            onSelected: () => _searchActor(context, ref, name, 1),
          ),
        ),
      ],
      builder: (context, controller, _) => InkWell(
        onTap: () =>
            controller.isOpen ? controller.close() : controller.open(),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
          child: Text(
            name,
            style: tokens.text.row.copyWith(
              color: tokens.color.fg,
              decoration: TextDecoration.underline,
              decorationColor: tokens.color.fgMuted,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.shiori;
    final actors = splitMetaTerms(manga.author);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: ShioriSpace.s4,
      children: [
        Icon(
          Symbols.person_rounded,
          size: tokens.scaled(14),
          color: tokens.color.fgMuted,
        ),
        if (actors.isEmpty)
          Text(
            l10n.unknown,
            style: tokens.text.row.copyWith(color: tokens.color.fg),
          )
        else
          for (final actor in actors) _actorChip(context, ref, actor),
      ],
    );
  }
}
