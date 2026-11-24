import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/eval/model/m_manga.dart';
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
        sourceFetcher: (_, _) async => const [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recommendations'), findsNothing);

    await _pump(
      tester,
      DetailRecommendationRow(
        manga: _manga(),
        fetcher: (_, _) async => throw Exception('AniList down'),
        sourceFetcher: (_, _) async => throw Exception('source down'),
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

  testWidgets('falls back to the title source when catalogs find nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var sourceCalled = false;
    await _pump(
      tester,
      DetailRecommendationRow(
        manga: _manga(),
        fetcher: (_, _) async => throw Exception('AniList 404'),
        sourceFetcher: (_, _) async {
          sourceCalled = true;
          return [MManga(name: '庆余年 第二季', link: '/s2')];
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(sourceCalled, isTrue);
    expect(find.text('Recommendations'), findsOneWidget);
    expect(find.text('庆余年 第二季'), findsOneWidget);
  });

  testWidgets('catalog results win and skip the source search', (
    tester,
  ) async {
    var sourceCalled = false;
    await _pump(
      tester,
      DetailRecommendationRow(
        manga: _manga(),
        fetcher: (_, _) async => [_rec('One Piece')],
        sourceFetcher: (_, _) async {
          sourceCalled = true;
          return const [];
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(sourceCalled, isFalse);
  });

  test('relatedSearchQuery strips season and year noise', () {
    expect(relatedSearchQuery('庆余年 第二季'), '庆余年');
    expect(relatedSearchQuery('Dune (2021)'), 'Dune');
    expect(relatedSearchQuery('Reacher Season 2'), 'Reacher');
    expect(relatedSearchQuery('【HD】'), '【HD】');
  });

  test('a normal title searches by its cleaned title first', () {
    final m = Manga(
      source: 'Demo',
      author: 'Jane Doe',
      artist: '',
      genre: const ['Drama'],
      imageUrl: null,
      lang: 'en',
      link: '/series',
      name: '庆余年 第二季',
      status: Status.ongoing,
      description: '',
      sourceId: null,
      favorite: false,
    );
    expect(relatedSearchCandidates(m).first, '庆余年');
  });

  test('a code title skips the code and searches actress then tag', () {
    final m = Manga(
      source: 'MissAV',
      author: 'Some Actress',
      artist: 'Studio X',
      genre: const ['Tag A', 'Tag B'],
      imageUrl: null,
      lang: 'en',
      link: '/v/SSNI-123',
      name: 'SSNI-123',
      status: Status.ongoing,
      description: '',
      sourceId: null,
      favorite: false,
    );
    final candidates = relatedSearchCandidates(m);
    // The bare code is never searched as the primary term.
    expect(candidates.first, 'Some Actress');
    expect(candidates, isNot(contains('SSNI-123')));
    expect(candidates, contains('Studio X'));
    expect(candidates, contains('Tag A'));
  });

  test('a code title with no metadata yields no candidates', () {
    final m = Manga(
      source: 'MissAV',
      author: '',
      artist: '',
      genre: const [],
      imageUrl: null,
      lang: 'en',
      link: '/v/abp456',
      name: 'ABP-456',
      status: Status.ongoing,
      description: '',
      sourceId: null,
      favorite: false,
    );
    // The bare code is never searched (it only finds itself), so with no
    // actress or tag there is nothing to search and the rail stays empty.
    expect(relatedSearchCandidates(m), isEmpty);
  });

  test('splitMetaTerms splits multi-value fields and drops aliases', () {
    expect(splitMetaTerms('赤井彗星, Real Works'), ['赤井彗星', 'Real Works']);
    expect(splitMetaTerms('天宫まりん (天宮まりん)'), ['天宫まりん']);
    expect(splitMetaTerms('A、B/C'), ['A', 'B', 'C']);
    expect(splitMetaTerms(null), isEmpty);
    expect(splitMetaTerms('  '), isEmpty);
  });

  test('a multi-value author is split so each term is searchable', () {
    final candidates = relatedSearchCandidatesFrom(
      name: 'RLMP-029',
      author: '赤井彗星, Real Works',
      artist: '九井スナオ (九井すなお)',
      genre: const ['羞辱'],
    );
    expect(candidates, contains('赤井彗星'));
    expect(candidates, contains('Real Works'));
    expect(candidates, contains('九井スナオ'));
    expect(candidates, isNot(contains('赤井彗星, Real Works')));
    expect(candidates, isNot(contains('九井スナオ (九井すなお)')));
  });

  test('relatedSearchCandidatesFrom reuses detail metadata for a code', () {
    // Simulates metadata fetched via getDetail for an entry stored name-only.
    final candidates = relatedSearchCandidatesFrom(
      name: 'ABP-456',
      author: 'Fetched Actress',
      artist: 'Fetched Studio',
      genre: const ['Fetched Tag'],
    );
    expect(candidates.first, 'Fetched Actress');
    expect(candidates, isNot(contains('ABP-456')));
    expect(candidates, contains('Fetched Studio'));
    expect(candidates, contains('Fetched Tag'));
  });

  test('relatedSearchCandidatesFrom is empty when detail has no metadata', () {
    expect(
      relatedSearchCandidatesFrom(name: 'ABP-456'),
      isEmpty,
    );
  });

  test('an embedded code title is treated as a code title', () {
    final m = Manga(
      source: 'MissAV',
      author: 'Some Actress',
      artist: '',
      genre: const ['Tag A'],
      imageUrl: null,
      lang: 'en',
      link: '/v/ssni123',
      name: 'SSNI-123 美しい女優 中文字幕',
      status: Status.ongoing,
      description: '',
      sourceId: null,
      favorite: false,
    );
    final candidates = relatedSearchCandidates(m);
    // The noisy full title is never searched; actress comes first.
    expect(candidates.first, 'Some Actress');
    expect(candidates, isNot(contains('SSNI-123 美しい女優 中文字幕')));
    expect(candidates, contains('Tag A'));
  });

  test('embedded code with no metadata yields no candidates', () {
    final m = Manga(
      source: 'MissAV',
      author: '',
      artist: '',
      genre: const [],
      imageUrl: null,
      lang: 'en',
      link: '/v/ssni123',
      name: 'SSNI-123 中文字幕 高清',
      status: Status.ongoing,
      description: '',
      sourceId: null,
      favorite: false,
    );
    // No actress/tag and the code must not search itself → empty rail.
    expect(relatedSearchCandidates(m), isEmpty);
  });
}
