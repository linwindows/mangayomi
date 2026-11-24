import 'package:material_ui/material_ui.dart';
import 'package:shiori/shiori.dart';
import 'package:mangayomi/utils/platform_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/eval/model/m_bridge.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/models/source.dart';
import 'package:mangayomi/repositories/source_repository.dart';
import 'package:mangayomi/services/extension_update.dart';
import 'package:mangayomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/services/fetch_item_sources.dart';
import 'package:mangayomi/utils/error_toast.dart';
import 'package:mangayomi/services/external_browser.dart';

/// How many sources each repository offers, by its index URL; follows the
/// sources as a refresh adds or drops some.
final repoSourceCountsProvider =
    StreamProvider.family<Map<String?, int>, ItemType>((ref, itemType) {
      return sourceRepository.watchByItemType(itemType).map((sources) {
        final counts = <String?, int>{};
        for (final source in sources) {
          final url = source.repo?.jsonUrl;
          counts[url] = (counts[url] ?? 0) + 1;
        }
        return counts;
      });
    });

class SourceRepositories extends ConsumerStatefulWidget {
  final ItemType itemType;
  const SourceRepositories({required this.itemType, super.key});

  @override
  ConsumerState<SourceRepositories> createState() => _SourceRepositoriesState();
}

class _SourceRepositoriesState extends ConsumerState<SourceRepositories> {
  bool isRefreshing = false;

  Future<void> _launchInBrowser(Uri url) async {
    if (!await ExternalBrowser.open(url.toString())) {
      throw 'Could not launch $url';
    }
  }

  /// The repository's name, or the last part of its URL when it has none.
  String _name(Repo repo) {
    if (repo.name != null &&
        repo.name!.isNotEmpty &&
        !repo.name!.endsWith('.json')) {
      return repo.name!;
    }
    if (repo.jsonUrl == null) return "Invalid source - remove it";
    return repo.jsonUrl!
            .replaceAll(RegExp(r'/[^/]+\.json$'), '')
            .split('/')
            .where((s) => s.isNotEmpty)
            .lastOrNull ??
        repo.jsonUrl!;
  }

  Future<void> _refresh() async {
    setState(() => isRefreshing = true);
    final sources = fetchItemSourcesListProvider(
      id: null,
      reFresh: true,
      itemType: widget.itemType,
    );
    ref.invalidate(sources);
    await ref.read(sources.future);
    if (mounted) setState(() => isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final repositories = ref.watch(
      extensionsRepoStateProvider(widget.itemType),
    );
    final sourceCounts =
        ref.watch(repoSourceCountsProvider(widget.itemType)).asData?.value ??
        const {};
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.itemType) {
          ItemType.manga => l10n.manage_manga_repo_urls,
          ItemType.anime => l10n.manage_anime_repo_urls,
          _ => l10n.manage_novel_repo_urls,
        }),
        actions: [
          if (isRefreshing)
            const Padding(
              padding: EdgeInsets.all(ShioriSpace.s16),
              child: ShioriLoading.inline(),
            )
          else
            IconButton(
              tooltip: l10n.refresh,
              onPressed: _refresh,
              icon: const Icon(Symbols.refresh_rounded),
            ),
        ],
      ),
      body: repositories.isEmpty
          ? ShioriEmptyState(
              icon: Symbols.source_rounded,
              title: l10n.empty_extensions_repo,
              actionLabel: l10n.add_extensions_repo,
              onAction: () => _showAddRepoDialog(context),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: ShioriSpace.s48 * 2),
              itemCount: repositories.length,
              itemBuilder: (context, index) {
                final repo = repositories[index];
                final isHidden = repo.hidden ?? false;
                final count = sourceCounts[repo.jsonUrl] ?? 0;
                return ShioriListRow(
                  leading: const Icon(
                    Symbols.source_rounded,
                    key: Key('repository-icon'),
                  ),
                  title: _name(repo),
                  // What it brings, then where it is.
                  subtitle: [l10n.n_sources(count), ?repo.jsonUrl].join(' · '),
                  // A hidden repository's sources are left out of Browse.
                  dimmed: isHidden,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: isHidden
                            ? l10n.show_repository
                            : l10n.hide_repository,
                        isSelected: !isHidden,
                        onPressed: () => ref
                            .read(
                              extensionsRepoStateProvider(widget.itemType)
                                  .notifier,
                            )
                            .setVisibility(repo, !isHidden),
                        icon: Icon(
                          isHidden
                              ? Symbols.visibility_off_rounded
                              : Symbols.visibility_rounded,
                        ),
                      ),
                      ShioriMenuButton(
                        tooltip: MaterialLocalizations.of(context)
                            .moreButtonTooltip,
                        items: [
                          if (repo.website != null)
                            ShioriMenuItem(
                              label: l10n.open_in_browser,
                              icon: Symbols.open_in_new_rounded,
                              onSelected: () =>
                                  _launchInBrowser(Uri.parse(repo.website!)),
                            ),
                          if (repo.jsonUrl != null)
                            ShioriMenuItem(
                              label: MaterialLocalizations.of(context)
                                  .copyButtonLabel,
                              icon: Symbols.content_copy_rounded,
                              onSelected: () => Clipboard.setData(
                                ClipboardData(text: repo.jsonUrl!),
                              ),
                            ),
                          null,
                          ShioriMenuItem(
                            label: MaterialLocalizations.of(context)
                                .deleteButtonTooltip,
                            icon: Symbols.delete_rounded,
                            destructive: true,
                            onSelected: () => _removeRepo(repo),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddRepoDialog(context),
        icon: const Icon(Symbols.add_rounded),
        label: Text(l10n.add),
      ),
    );
  }

  /// #774: when a repo is removed, drop its *not-installed* sources so they
  /// don't linger as placeholders with a dead install button. Installed
  /// sources (non-empty [Source.sourceCode]) are kept so users don't lose them.
  ///
  /// The address is compared as [isSameRepo] does: a trailing slash or a
  /// capital letter left the listings behind.
  Future<void> _removeOrphanSources(Repo removedRepo) async {
    if (removedRepo.jsonUrl == null) return;
    final orphanIds = sourceRepository
        .getByItemType(widget.itemType)
        .where(
          (s) =>
              isSameRepo(s.repo, removedRepo) &&
              (s.sourceCode?.isEmpty ?? true),
        )
        .map((s) => s.id!)
        .toList();
    if (orphanIds.isNotEmpty) {
      await sourceRepository.deleteAll(orphanIds);
    }
  }

  Future<void> _removeRepo(Repo removedRepo) async {
    final l10n = context.l10n;
    final confirmed = await showShioriConfirm(
      context,
      title: l10n.remove_extensions_repo,
      message: _name(removedRepo),
      confirmLabel: l10n.remove,
      destructive: true,
    );
    if (!confirmed) return;
    final repos = ref
        .read(extensionsRepoStateProvider(widget.itemType))
        .where((r) => r != removedRepo)
        .toList();
    await ref
        .read(extensionsRepoStateProvider(widget.itemType).notifier)
        .set(repos);
    await _removeOrphanSources(removedRepo);
  }

  Future<void> _showAddRepoDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AddRepositoryDialog(itemType: widget.itemType),
    );
  }
}

class _AddRepositoryDialog extends ConsumerStatefulWidget {
  const _AddRepositoryDialog({required this.itemType});

  final ItemType itemType;

  @override
  ConsumerState<_AddRepositoryDialog> createState() =>
      _AddRepositoryDialogState();
}

class _AddRepositoryDialogState extends ConsumerState<_AddRepositoryDialog> {
  late final TextEditingController _controller;
  bool _isLoading = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _containsRepoUrl(List<Repo> repos, String url) {
    final clean = url.trim().toLowerCase();
    return repos.any((repo) {
      final repoUrl = repo.jsonUrl?.trim().toLowerCase();
      if (repoUrl == null) return false;
      return repoUrl == clean || repoUrl == '$clean/' || '$repoUrl/' == clean;
    });
  }

  Future<void> _addRepository(String text) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final currentRepos = ref.read(
        extensionsRepoStateProvider(widget.itemType),
      );
      final repo = await ref.read(getRepoInfosProvider(jsonUrl: text).future);
      if (!mounted || _cancelled) return;

      if (repo == null) {
        setState(() => _isLoading = false);
        botToast(context.l10n.unsupported_repo);
        return;
      }

      final repoUrl = repo.jsonUrl?.trim().toLowerCase();
      final clean = text.trim().toLowerCase();
      final isDuplicate = currentRepos.any((existing) {
        final existingUrl = existing.jsonUrl?.trim().toLowerCase();
        return (existingUrl != null &&
                (existingUrl == repoUrl ||
                    existingUrl == clean ||
                    existingUrl == '$clean/' ||
                    '$existingUrl/' == clean ||
                    (repoUrl != null &&
                        (existingUrl == '$repoUrl/' ||
                            '$existingUrl/' == repoUrl)))) ||
            existing == repo;
      });
      if (isDuplicate) {
        setState(() => _isLoading = false);
        botToast(context.l10n.repo_already_exists);
        return;
      }

      await ref.read(extensionsRepoStateProvider(widget.itemType).notifier).set(
        [...currentRepos, repo],
      );
      if (!mounted || _cancelled) return;

      botToast(context.l10n.repo_added);
      Navigator.pop(context);
    } catch (e, s) {
      if (!mounted || _cancelled) return;
      setState(() => _isLoading = false);
      toastError(e, stack: s, source: 'sourceRepositories');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final repositories = ref.watch(
      extensionsRepoStateProvider(widget.itemType),
    );
    final text = _controller.text.trim();
    final alreadyExists = _containsRepoUrl(repositories, text);
    final isValid =
        text.isNotEmpty &&
        !alreadyExists &&
        Uri.tryParse(text)?.isAbsolute == true;

    return ShioriDialog(
      title: l10n.add_extensions_repo,
      content: TextFormField(
        controller: _controller,
        // On Android TV, don't autofocus: it instantly pops the full-screen
        // leanback keyboard over the dialog before the user can see its actions.
        autofocus: !isTv,
        keyboardType: TextInputType.url,
        onChanged: (_) => setState(() {}),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return l10n.url_cannot_be_empty;
          }
          try {
            final uri = Uri.parse(value.trim());
            if (!uri.isAbsolute ||
                (uri.scheme != 'http' && uri.scheme != 'https')) {
              return l10n.invalid_url_format;
            }
            if (_containsRepoUrl(repositories, value)) {
              return l10n.repo_already_exists;
            }
            return null;
          } catch (e) {
            return l10n.invalid_url_format;
          }
        },
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(
          labelText: l10n.url,
          hintText: l10n.url_must_end_with_dot_json_or_dot_pb,
        ),
      ),
      actions: [
        ShioriButton.quiet(
          label: l10n.cancel,
          onPressed: () {
            _cancelled = true;
            Navigator.pop(context);
          },
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(ShioriSpace.s8),
            child: ShioriLoading.inline(),
          )
        else
          ShioriButton(
            label: l10n.add,
            onPressed: isValid ? () => _addRepository(text) : null,
          ),
      ],
    );
  }
}
