import 'dart:convert';

import 'package:mangayomi/services/http/m_client.dart';
import 'package:mangayomi/utils/constant.dart';
import 'package:mangayomi/utils/error_toast.dart';

Future<List<ImdbTitle>> fetchImdbTitles(String query) async {
  final http = MClient.init(reqcopyWith: {'useDartHttpClient': true});
  try {
    final url = "https://api.imdbapi.dev/search/titles?query=$query";
    final res = await http.get(
      Uri.parse(url),
      headers: {
        "Accept": "application/json",
        "User-Agent": metadataApiUserAgent,
      },
    );
    final data = json.decode(res.body) as Map<String, dynamic>;
    return (data["titles"] as List?)
            ?.map((e) => ImdbTitle.fromJson(e))
            .toList() ??
        [];
  } catch (error, stackTrace) {
    recordError(error, stack: stackTrace, source: 'fetch_subtitles');
    return [];
  }
}

Future<List<ImdbEpisode>?> fetchImdbEpisodes(String imdbId) async {
  final http = MClient.init(reqcopyWith: {'useDartHttpClient': true});
  try {
    final url = "https://api.imdbapi.dev/titles/$imdbId/episodes";
    final res = await http.get(
      Uri.parse(url),
      headers: {
        "Accept": "application/json",
        "User-Agent": metadataApiUserAgent,
      },
    );
    final data = json.decode(res.body) as Map<String, dynamic>;
    return (data["episodes"] as List?)
        ?.map((e) => ImdbEpisode.fromJson(e))
        .toList();
  } catch (error, stackTrace) {
    recordError(error, stack: stackTrace, source: 'fetch_subtitles');
    return null;
  }
}

Future<List<ImdbSubtitle>?> fetchImdbSubtitles(String imdbId) async {
  final http = MClient.init(reqcopyWith: {'useDartHttpClient': true});
  try {
    final url = "https://wyzie.mangayomi.workers.dev/search?id=$imdbId";
    final res = await http.get(
      Uri.parse(url),
      headers: {
        "Accept": "application/json",
        "User-Agent": metadataApiUserAgent,
      },
    );
    final data = json.decode(res.body) as List?;
    return data
        ?.map((e) => ImdbSubtitle.fromJson(e))
        .where((e) => e.url != null)
        .toList();
  } catch (error, stackTrace) {
    recordError(error, stack: stackTrace, source: 'fetch_subtitles');
    return null;
  }
}

/// Searches a third-party JSON API using the URL template from Settings.
/// Supported placeholders:
/// - `{id}`: a video code extracted from the query when possible
/// - `{title}` and `{query}`: the entered query
Future<List<ImdbSubtitle>?> fetchCustomSubtitles({
  required String query,
  required String urlTemplate,
  required String sourceName,
  String? resultPath,
}) async {
  final requestUri = _customSubtitleSearchUri(query, urlTemplate);

  final http = MClient.init(reqcopyWith: {'useDartHttpClient': true});
  try {
    final response = await http.get(
      requestUri,
      headers: {
        "Accept": "application/json",
        "User-Agent": metadataApiUserAgent,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException(
        'Subtitle API returned HTTP ${response.statusCode}',
      );
    }
    return parseCustomSubtitleResponse(
      json.decode(response.body),
      responseUri: requestUri,
      sourceName: sourceName,
      resultPath: resultPath,
    );
  } catch (error, stackTrace) {
    recordError(error, stack: stackTrace, source: 'fetch_custom_subtitles');
    rethrow;
  }
}

Future<List<ImdbSubtitle>> fetchDefaultSubtitleSources({
  required String query,
  bool xunleiEnabled = true,
  bool subtitleCatEnabled = true,
  bool avSubtitlesEnabled = true,
}) async {
  final id = _normalizeSubtitleSearchId(query);
  if (id.isEmpty) return const [];

  final failures = <Object>[];
  Future<List<ImdbSubtitle>> run(
    String source,
    Future<List<ImdbSubtitle>> Function() search,
  ) async {
    try {
      return await search();
    } catch (error, stackTrace) {
      failures.add(error);
      recordError(error, stack: stackTrace, source: 'subtitle_source_$source');
      return const [];
    }
  }

  final tasks = <Future<List<ImdbSubtitle>>>[
    if (xunleiEnabled) run('xunlei', () => _searchXunleiSubtitles(id)),
    if (subtitleCatEnabled) run('subtitlecat', () => _searchSubtitleCat(id)),
    if (avSubtitlesEnabled) run('avsubtitles', () => _searchAvSubtitles(id)),
  ];
  final sourceResults = await Future.wait(tasks);
  if (tasks.isNotEmpty && failures.length == tasks.length) {
    throw FormatException(
      'All subtitle sources failed: ${failures.map((error) => error.toString()).join('; ')}',
    );
  }

  final unique = <String, ImdbSubtitle>{};
  for (final subtitle in sourceResults.expand((results) => results)) {
    final key = subtitle.url?.toLowerCase();
    if (key != null && key.isNotEmpty) unique.putIfAbsent(key, () => subtitle);
  }
  return unique.values.toList();
}

Future<List<int>> fetchAvSubtitleFile(String subtitlePageUrl) async {
  final client = MClient.init(reqcopyWith: {'useDartHttpClient': true});
  final headers = {
    'Accept': 'text/plain, application/x-subrip, */*',
    'User-Agent': metadataApiUserAgent,
  };
  final pageUri = Uri.parse(subtitlePageUrl);
  final page = await client.get(pageUri, headers: headers);
  if (page.statusCode < 200 || page.statusCode >= 300) {
    throw FormatException('AVSubtitles returned HTTP ${page.statusCode}');
  }
  final subId = RegExp(
    r'name="subid"\s+value="(\d+)"',
    caseSensitive: false,
  ).firstMatch(page.body)?.group(1);
  final revisionId = RegExp(
    r'name="revid"\s+value="(\d+)"',
    caseSensitive: false,
  ).firstMatch(page.body)?.group(1);
  if (subId == null || revisionId == null) {
    throw const FormatException('AVSubtitles subtitle token was not found');
  }

  final downloadPageUri = pageUri.replace(
    path: '/download_page.php',
    queryParameters: {'subid': subId, 'revid': revisionId},
  );
  final downloadPage = await client.get(downloadPageUri, headers: headers);
  if (downloadPage.statusCode < 200 || downloadPage.statusCode >= 300) {
    throw FormatException(
      'AVSubtitles download page returned HTTP ${downloadPage.statusCode}',
    );
  }

  final downloadUri = pageUri.replace(
    path: '/download_sub.php',
    queryParameters: {'subid': subId, 'revid': revisionId},
  );
  final response = await client.get(downloadUri, headers: headers);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw FormatException(
      'AVSubtitles download returned HTTP ${response.statusCode}',
    );
  }
  return response.bodyBytes;
}

Future<List<ImdbSubtitle>> _searchXunleiSubtitles(String id) async {
  final uri = Uri.https('api-shoulei-ssl.xunlei.com', '/oracle/subtitle', {
    'name': id,
  });
  final response = await MClient.init(reqcopyWith: {'useDartHttpClient': true})
      .get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': metadataApiUserAgent,
        },
      );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw FormatException('Xunlei returned HTTP ${response.statusCode}');
  }

  final payload = json.decode(response.body);
  if (payload is! Map || payload['code'] != 0 || payload['data'] is! List) {
    throw const FormatException('Xunlei returned an invalid response');
  }
  final subtitles = <ImdbSubtitle>[];
  for (final item in payload['data'] as List) {
    if (item is! Map) continue;
    final row = _stringKeyedMap(item);
    final url = _firstString(row, const ['url']);
    final name = _firstString(row, const ['name']);
    if (url == null || name == null || !_matchesSubtitleCode(name, id)) {
      continue;
    }
    subtitles.add(
      ImdbSubtitle(
        id: 'xunlei_${subtitles.length}',
        url: url,
        format: _subtitleFormat(Uri.tryParse(url) ?? Uri()),
        language: _firstString(row, const ['language']),
        displayLang: _firstString(row, const ['language']),
        name: name,
        source: '迅雷字幕',
        isHearingImpaired: false,
      ),
    );
  }
  return subtitles;
}

Future<List<ImdbSubtitle>> _searchSubtitleCat(String id) async {
  final searchUri = Uri.https('www.subtitlecat.com', '/index.php', {
    'search': id,
  });
  final html = await _getSubtitleSourcePage(searchUri);
  if (_isCloudflareChallenge(html)) {
    throw const FormatException(
      'SubtitleCat is asking for browser verification',
    );
  }
  final pageLinks = RegExp(
    r'href="([^"]*subs/[^"]+\.html)"',
    caseSensitive: false,
  ).allMatches(html).map((match) => match[1]!).toSet().toList();
  if (pageLinks.isEmpty) return const [];

  final exactLinks = pageLinks
      .where((link) => _matchesSubtitleCode(link, id))
      .toList();
  final candidates = (exactLinks.isNotEmpty ? exactLinks : pageLinks).take(2);
  final results = <ImdbSubtitle>[];
  for (final link in candidates) {
    final pageUri = searchUri.resolve(link);
    final pageHtml = await _getSubtitleSourcePage(pageUri);
    final fileLinks = RegExp(
      r'href="(/subs/\d+/([^"]+)\.srt)"',
      caseSensitive: false,
    ).allMatches(pageHtml);
    for (final match in fileLinks) {
      final fileUri = pageUri.resolve(match[1]!);
      final fileName = _decodeSubtitlePath(match[2]!);
      final language = _subtitleLanguage(fileName);
      results.add(
        ImdbSubtitle(
          id: 'subtitlecat_${results.length}',
          url: fileUri.toString(),
          format: 'srt',
          language: language,
          displayLang: language,
          name: '$fileName.srt',
          source: 'SubtitleCat',
          isHearingImpaired: false,
        ),
      );
    }
  }
  return results;
}

Future<List<ImdbSubtitle>> _searchAvSubtitles(String id) async {
  final searchUri = Uri.https('www.avsubtitles.com', '/search_results.php', {
    'search': id,
  });
  final html = await _getSubtitleSourcePage(searchUri);
  if (_isCloudflareChallenge(html)) {
    throw const FormatException(
      'AVSubtitles is asking for browser verification',
    );
  }
  final movieLinks = RegExp(
    r'href="(/movie\d+/[^"#]+)"',
    caseSensitive: false,
  ).allMatches(html).map((match) => match[1]!).toSet().toList();
  if (movieLinks.isEmpty) return const [];

  final movieLink = movieLinks.firstWhere(
    (link) => _matchesSubtitleCode(link, id),
    orElse: () => movieLinks.first,
  );
  final movieUri = searchUri.resolve(movieLink);
  final movieHtml = await _getSubtitleSourcePage(movieUri);
  final subtitleLinks = RegExp(
    r'href="(/movie\d+/[^/]+/subtitles/([a-z]{2})/(\d+))"',
    caseSensitive: false,
  ).allMatches(movieHtml);
  final movieName = _decodeSubtitlePath(movieLink.split('/').last);
  final subtitles = <ImdbSubtitle>[];
  for (final match in subtitleLinks) {
    final language = _subtitleLanguageCode(match[2]!);
    subtitles.add(
      ImdbSubtitle(
        id: 'avsubtitles_${subtitles.length}',
        url: movieUri.resolve(match[1]!).toString(),
        format: 'srt',
        language: language,
        displayLang: language,
        name: '[$movieName] $language',
        source: 'AVSubtitles',
        isHearingImpaired: false,
      ),
    );
  }
  return subtitles;
}

Future<String> _getSubtitleSourcePage(Uri uri) async {
  final response = await MClient.init(reqcopyWith: {'useDartHttpClient': true})
      .get(
        uri,
        headers: {
          'Accept': 'text/html,application/xhtml+xml',
          'User-Agent': metadataApiUserAgent,
        },
      );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw FormatException(
      'Subtitle source ${uri.host} returned HTTP ${response.statusCode}',
    );
  }
  return response.body;
}

bool _isCloudflareChallenge(String html) => RegExp(
  r'Attention Required!|Just a moment\.\.\.|cf-chl-|cf-turnstile',
  caseSensitive: false,
).hasMatch(html);

bool _matchesSubtitleCode(String text, String code) {
  final compactText = text.replaceAll(RegExp(r'[-_\s]'), '').toUpperCase();
  final compactCode = code.replaceAll(RegExp(r'[-_\s]'), '').toUpperCase();
  return compactCode.isNotEmpty && compactText.contains(compactCode);
}

String _decodeSubtitlePath(String value) {
  try {
    return Uri.decodeComponent(value);
  } on FormatException {
    return value;
  }
}

String _subtitleLanguage(String value) {
  if (RegExp(r'zh-cn|chs|simple|简体', caseSensitive: false).hasMatch(value)) {
    return '简中';
  }
  if (RegExp(
    r'zh-tw|cht|traditional|繁体',
    caseSensitive: false,
  ).hasMatch(value)) {
    return '繁中';
  }
  if (RegExp(r'zh|chinese|中文', caseSensitive: false).hasMatch(value)) {
    return '中文';
  }
  if (RegExp(r'en|eng|english', caseSensitive: false).hasMatch(value)) {
    return '英文';
  }
  if (RegExp(r'ja|jap|japanese', caseSensitive: false).hasMatch(value)) {
    return '日文';
  }
  return '其他';
}

String _subtitleLanguageCode(String code) => switch (code.toLowerCase()) {
  'zh' => '中文',
  'en' => '英文',
  'ja' => '日文',
  _ => '其他',
};

Uri _customSubtitleSearchUri(String query, String urlTemplate) {
  final template = urlTemplate.trim();
  if (template.isEmpty ||
      !RegExp(
        r'\{(?:id|title|query)\}',
        caseSensitive: false,
      ).hasMatch(template)) {
    throw const FormatException(
      'Search URL must be an http(s) template containing {id}, {title}, or {query}',
    );
  }

  final id = Uri.encodeComponent(_normalizeSubtitleSearchId(query));
  final encodedQuery = Uri.encodeComponent(query.trim());
  final expanded = template
      .replaceAll(RegExp(r'\{id\}', caseSensitive: false), id)
      .replaceAll(RegExp(r'\{title\}', caseSensitive: false), encodedQuery)
      .replaceAll(RegExp(r'\{query\}', caseSensitive: false), encodedQuery);
  final uri = Uri.tryParse(expanded);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw const FormatException('Search URL must be a valid http(s) URL');
  }
  return uri;
}

String _normalizeSubtitleSearchId(String query) {
  var value = query.trim();
  final uri = Uri.tryParse(value);
  if (uri != null &&
      uri.hasScheme &&
      uri.host.isNotEmpty &&
      uri.pathSegments.isNotEmpty) {
    value = uri.pathSegments.last;
  }
  try {
    value = Uri.decodeComponent(value);
  } on FormatException {
    // Keep the original text if it contains an invalid percent escape.
  }
  value = value.replaceFirst(
    RegExp(r'\.(?:srt|ass|ssa|vtt|mkv|mp4)$', caseSensitive: false),
    '',
  );
  value = value.replaceAll(
    RegExp(
      r'[\s_-]+(?:chinese[\s_-]?subtitle|subtitle|chinese|sub|chs|cht|中文字幕|字幕|中文)$',
      caseSensitive: false,
    ),
    '',
  );

  final code = RegExp(
    r'^(fc2(?:-ppv)?-[0-9]+|[a-z0-9]+-[a-z0-9]+)',
    caseSensitive: false,
  ).firstMatch(value);
  return code?.group(1)?.toUpperCase() ?? value.trim();
}

String normalizeSubtitleSearchId(String query) =>
    _normalizeSubtitleSearchId(query);

bool isSubtitleVideoCode(String query) => RegExp(
  r'^(?:fc2(?:-ppv)?-[0-9]+|[a-z0-9]+-[a-z0-9]+)',
  caseSensitive: false,
).hasMatch(_normalizeSubtitleSearchId(query));

List<ImdbSubtitle> parseCustomSubtitleResponse(
  dynamic decoded, {
  required Uri responseUri,
  required String sourceName,
  String? resultPath,
}) {
  final items = _resolveSubtitleItems(decoded, resultPath?.trim());
  final results = <ImdbSubtitle>[];
  final baseName = sourceName.trim().isEmpty ? 'Custom' : sourceName.trim();

  for (final item in items) {
    final map = item is Map ? _stringKeyedMap(item) : const <String, dynamic>{};
    final rawUrl = item is String
        ? item.trim()
        : _firstString(map, const [
            'url',
            'downloadUrl',
            'download_url',
            'subtitleUrl',
            'subtitle_url',
            'src',
            'file',
            'link',
          ]);
    if (rawUrl == null || rawUrl.isEmpty) continue;

    final resolvedUrl = responseUri.resolve(rawUrl);
    if (resolvedUrl.scheme != 'http' && resolvedUrl.scheme != 'https') {
      continue;
    }
    final name =
        _firstString(map, const [
          'name',
          'title',
          'label',
          'media',
          'filename',
        ]) ??
        _subtitleFileName(resolvedUrl) ??
        baseName;
    final language = _firstString(map, const [
      'language',
      'lang',
      'displayLang',
      'display',
      'languageCode',
    ]);

    results.add(
      ImdbSubtitle(
        id: '${baseName}_${results.length}',
        url: resolvedUrl.toString(),
        format:
            _firstString(map, const ['format', 'extension', 'fileType']) ??
            _subtitleFormat(resolvedUrl),
        encoding: _firstString(map, const ['encoding', 'charset']),
        displayLang: language,
        language: language,
        name: name,
        source: baseName,
        isHearingImpaired:
            map['isHearingImpaired'] == true || map['hearingImpaired'] == true,
      ),
    );
  }
  return results;
}

List<dynamic> _resolveSubtitleItems(dynamic decoded, String? resultPath) {
  if (resultPath != null && resultPath.isNotEmpty) {
    final configured = _valueAtPath(decoded, resultPath);
    if (configured is List) return configured;
    if (configured is Map && _looksLikeSubtitle(_stringKeyedMap(configured))) {
      return [configured];
    }
    throw FormatException(
      'Results path "$resultPath" did not resolve to subtitles',
    );
  }

  if (decoded is List) return decoded;
  if (decoded is Map) {
    final direct = _stringKeyedMap(decoded);
    if (_looksLikeSubtitle(direct)) return [direct];

    for (final key in const ['data', 'results', 'items', 'subtitles']) {
      final candidate = _valueAtPath(direct, key);
      if (candidate is List) return candidate;
      if (candidate is Map && _looksLikeSubtitle(_stringKeyedMap(candidate))) {
        return [candidate];
      }
    }

    final candidates = <dynamic>[];
    void visit(dynamic value) {
      if (value is List) {
        for (final item in value) {
          if (item is String ||
              (item is Map && _looksLikeSubtitle(_stringKeyedMap(item)))) {
            candidates.add(item);
          } else {
            visit(item);
          }
        }
      } else if (value is Map) {
        for (final child in value.values) {
          visit(child);
        }
      }
    }

    visit(direct);
    return candidates;
  }
  return const [];
}

dynamic _valueAtPath(dynamic data, String path) {
  final normalized = path
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (match) => '.${match[1]}')
      .replaceFirst(RegExp(r'^\.'), '');
  if (normalized.isEmpty) return data;

  dynamic value = data;
  for (final segment in normalized.split('.')) {
    if (value is Map) {
      value = value[segment];
    } else if (value is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= value.length) return null;
      value = value[index];
    } else {
      return null;
    }
  }
  return value;
}

Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> value) =>
    Map<String, dynamic>.fromEntries(
      value.entries.map((entry) => MapEntry(entry.key.toString(), entry.value)),
    );

bool _looksLikeSubtitle(Map<String, dynamic> item) =>
    _firstString(item, const [
      'url',
      'downloadUrl',
      'download_url',
      'subtitleUrl',
      'subtitle_url',
      'src',
      'file',
      'link',
    ]) !=
    null;

String? _firstString(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return null;
}

String? _subtitleFileName(Uri uri) {
  for (final segment in uri.pathSegments.reversed) {
    if (segment.isNotEmpty) {
      try {
        return Uri.decodeComponent(segment);
      } on FormatException {
        return segment;
      }
    }
  }
  return null;
}

String? _subtitleFormat(Uri uri) {
  final name = _subtitleFileName(uri);
  if (name == null) return null;
  final dot = name.lastIndexOf('.');
  return dot < 0 || dot == name.length - 1
      ? null
      : name.substring(dot + 1).toLowerCase();
}

class ImdbTitle {
  final String id;
  final String? type;
  final String primaryTitle;
  final String? originalTitle;
  final String? primaryImage;
  final int? startYear;
  final int? endYear;
  final double? aggregateRating;
  final int? voteCount;

  ImdbTitle({
    required this.id,
    this.type,
    required this.primaryTitle,
    this.originalTitle,
    this.primaryImage,
    this.startYear,
    this.endYear,
    this.aggregateRating,
    this.voteCount,
  });

  factory ImdbTitle.fromJson(Map<String, dynamic> json) {
    return ImdbTitle(
      id: json["id"],
      type: json["type"],
      primaryTitle: json["primaryTitle"] ?? "???",
      originalTitle: json["originalTitle"],
      primaryImage: json["primaryImage"]?["url"],
      startYear: json["startYear"],
      endYear: json["endYear"],
      aggregateRating: json["rating"]?["aggregateRating"] is int
          ? (json["rating"]?["aggregateRating"] as int).toDouble()
          : json["rating"]?["aggregateRating"],
      voteCount: json["rating"]?["voteCount"],
    );
  }
}

class ImdbEpisode {
  final String id;
  final String title;
  final String? primaryImage;
  final String season;
  final String episode;

  ImdbEpisode({
    required this.id,
    required this.title,
    this.primaryImage,
    required this.season,
    required this.episode,
  });

  factory ImdbEpisode.fromJson(Map<String, dynamic> json) {
    return ImdbEpisode(
      id: json["id"],
      title: json["title"] ?? "???",
      primaryImage: json["primaryImage"]?["url"],
      season: json["season"] ?? "?",
      episode: (json["episodeNumber"] as int?)?.toString() ?? "?",
    );
  }
}

class ImdbSubtitle {
  final String id;
  final String? url;
  final String? flagUrl;
  final String? format;
  final String? encoding;
  final String? displayLang;
  final String? language;
  final String? name;
  final String? source;
  final bool isHearingImpaired;

  ImdbSubtitle({
    required this.id,
    this.url,
    this.flagUrl,
    this.format,
    this.encoding,
    this.displayLang,
    this.language,
    this.name,
    this.source,
    required this.isHearingImpaired,
  });

  factory ImdbSubtitle.fromJson(Map<String, dynamic> json) {
    return ImdbSubtitle(
      id: json["id"],
      url: json["url"],
      flagUrl: json["flagUrl"],
      format: json["format"],
      encoding: json["encoding"],
      displayLang: json["display"],
      language: json["language"],
      name: json["media"],
      source: json["source"],
      isHearingImpaired: json["isHearingImpaired"] ?? false,
    );
  }
}
