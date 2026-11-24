import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
import 'package:mangayomi/l10n/l10n_delegates.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/modules/anime/providers/subtitle_search_state_provider.dart';
import 'package:mangayomi/modules/anime/widgets/search_subtitles.dart';
import 'package:mangayomi/services/fetch_subtitles.dart';
import 'package:shiori/shiori.dart';

Chapter _chapter() => Chapter(mangaId: 1, name: 'Episode 1');

ImdbSubtitle _subtitle(String name) => ImdbSubtitle(
  id: name,
  url: 'https://example.com/$name.srt',
  name: name,
  displayLang: 'English',
  source: 'TestSource',
  isHearingImpaired: false,
);

Widget _sheet(ProviderContainer container, Chapter chapter) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildShioriTheme(
          brightness: Brightness.dark,
          colors: FlexColor.schemesList[2].dark,
          tintSurfaces: false,
          blendLevel: 10,
          density: ShioriDensity.phone,
        ),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SubtitlesWidgetSearch(chapter: chapter, isLocal: false),
        ),
      ),
    );

void main() {
  testWidgets('reopening the sheet restores the last search results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final chapter = _chapter();
    final key = subtitleSearchCacheKey(chapter);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Seed a completed search, as if the first open already searched.
    container.read(subtitleSearchStateProvider(key).notifier).update(
      (s) => s.copyWith(
        query: 'Series',
        titles: const [],
        subtitles: [_subtitle('Episode 1.srt')],
        searched: true,
        isLoading: false,
      ),
    );

    // First open.
    await tester.pumpWidget(_sheet(container, chapter));
    await tester.pumpAndSettle();
    expect(find.text('Episode 1.srt'), findsOneWidget);

    // Dismiss the sheet (the widget is disposed).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // Reopen the same chapter's sheet: the result is still there and no new
    // search ran (a fresh search would have cleared it and shown a spinner).
    await tester.pumpWidget(_sheet(container, chapter));
    await tester.pumpAndSettle();
    expect(find.text('Episode 1.srt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the cached query is restored into the search field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final chapter = _chapter();
    final key = subtitleSearchCacheKey(chapter);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(subtitleSearchStateProvider(key).notifier).update(
      (s) => s.copyWith(query: 'Previous query', searched: true, isLoading: false),
    );

    await tester.pumpWidget(_sheet(container, chapter));
    await tester.pumpAndSettle();

    expect(find.text('Previous query'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fresh chapter starts with an automatic search', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final chapter = _chapter();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final key = subtitleSearchCacheKey(chapter);

    expect(container.read(subtitleSearchStateProvider(key)).searched, isFalse);

    // The initState schedules a search after the first frame. We don't let the
    // network resolve here; the assertion is that the state was marked as
    // loading by the automatic search.
    await tester.pumpWidget(_sheet(container, chapter));
    await tester.pump();

    expect(container.read(subtitleSearchStateProvider(key)).isLoading, isTrue);
  });
}
