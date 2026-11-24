import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
import 'package:mangayomi/l10n/l10n_delegates.dart';
import 'package:mangayomi/main.dart' as app;
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/modules/manga/detail/widgets/detail_recommendation_row.dart';
import 'package:mangayomi/providers/storage_provider.dart';
import 'package:mangayomi/services/discovery/media_lookup_context.dart';
import 'package:mangayomi/services/discovery/search_target.dart';
import 'package:mangayomi/services/recommendation.dart';
import 'package:shiori/shiori.dart';

Manga _manga() => Manga(
  source: 'Demo',
  author: 'Author',
  artist: '',
  genre: const [],
  imageUrl: null,
  lang: 'en',
  link: '/series',
  name: 'Series',
  status: Status.ongoing,
  description: 'A description.',
  sourceId: null,
  favorite: false,
);

RecommendationResult _rec(String title) => RecommendationResult(
  id: 'anilist:1',
  provider: RecommendationProvider.anilist,
  kind: MediaKind.anime,
  searchTarget: SearchTarget(query: title, itemType: ItemType.anime),
  titleEnglish: title,
  imgURLs: const [],
  genres: const [],
);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  ProviderScope(
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
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  late Directory dir;
  late Isar db;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
    dir = await Directory.systemTemp.createTemp('mangayomi-recommendation-');
    db = await StorageProvider().initDB(dir.path);
    app.isar = db;
  });

  tearDownAll(() async {
    await db.close(deleteFromDisk: true);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  testWidgets('shows the heading and covers when recommendations arrive', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      DetailRecommendationRow(
        manga: _manga(),
        fetcher: (_, _) async => [_rec('One Piece'), _rec('Naruto')],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Recommendations'), findsOneWidget);
    expect(find.text('One Piece'), findsOneWidget);
    expect(find.text('Naruto'), findsOneWidget);
  });

  testWidgets('leaves no slot behind on an empty result or an outage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      DetailRecommendationRow(
        manga: _manga(),
        fetcher: (_, _) async => const [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recommendations'), findsNothing);

    await _pump(
      tester,
      DetailRecommendationRow(
        manga: _manga(),
        fetcher: (_, _) async => throw Exception('AniList down'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Recommendations'), findsNothing);
  });

  testWidgets('the heading opens the full recommendations screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var opened = false;
    await _pump(
      tester,
      DetailRecommendationRow(
        manga: _manga(),
        fetcher: (_, _) async => [_rec('One Piece')],
        onOpenAll: () => opened = true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recommendations'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });

  testWidgets('a local archive is never sent to the discovery services', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var called = false;
    final manga = _manga();
    manga.isLocalArchive = true;
    await _pump(
      tester,
      DetailRecommendationRow(
        manga: manga,
        fetcher: (_, _) async {
          called = true;
          return [_rec('One Piece')];
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Recommendations'), findsNothing);
  });
}
