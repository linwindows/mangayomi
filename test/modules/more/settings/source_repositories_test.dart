import 'package:bot_toast/bot_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shiori/shiori.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
import 'package:mangayomi/l10n/l10n_delegates.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:mangayomi/modules/more/settings/browse/source_repositories.dart';

void main() {
  testWidgets('saves a repository and closes the add dialog cleanly', (
    tester,
  ) async {
    _SavedRepoState.saved.clear();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          extensionsRepoStateProvider(ItemType.anime)
              .overrideWith(_SavedRepoState.new),
          getRepoInfosProvider(jsonUrl: _newRepoUrl).overrideWith(
            (ref) async => Repo(name: 'Test repo', jsonUrl: _newRepoUrl),
          ),
        ],
        child: MaterialApp(
          builder: BotToastInit(),
          navigatorObservers: [BotToastNavigatorObserver()],
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SourceRepositories(itemType: ItemType.anime),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), _newRepoUrl);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(ShioriDialog),
        matching: find.text('Add'),
      ),
    );
    await tester.pumpAndSettle();

    expect(_SavedRepoState.saved[ItemType.anime]?.single.jsonUrl, _newRepoUrl);
    expect(find.text('Test repo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a neutral icon for GitHub repositories', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          extensionsRepoStateProvider(ItemType.anime)
              .overrideWith(_GitHubRepoState.new),
        ],
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SourceRepositories(itemType: ItemType.anime),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Curated extensions'), findsOneWidget);
    expect(find.byKey(const Key('repository-icon')), findsOneWidget);
    expect(find.byIcon(Symbols.source_rounded), findsOneWidget);
  });

  testWidgets('says how many sources a repository offers', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          extensionsRepoStateProvider(ItemType.anime)
              .overrideWith(_GitHubRepoState.new),
          repoSourceCountsProvider(ItemType.anime)
              .overrideWith((ref) => Stream.value({_url: 12})),
        ],
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SourceRepositories(itemType: ItemType.anime),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('12 sources · $_url'), findsOneWidget);
  });
}

const _url =
    'https://raw.githubusercontent.com/example/extensions/main/anime_index.json';
const _newRepoUrl = 'https://example.com/extensions.json';

class _SavedRepoState extends ExtensionsRepoState {
  static final saved = <ItemType, List<Repo>>{};

  @override
  List<Repo> build(ItemType itemType) => const [];

  @override
  Future<void> set(List<Repo> value) async {
    saved[itemType] = value;
    state = value;
  }
}

class _GitHubRepoState extends ExtensionsRepoState {
  @override
  List<Repo> build(ItemType itemType) => [
    Repo(name: 'Curated extensions', jsonUrl: _url),
  ];
}
