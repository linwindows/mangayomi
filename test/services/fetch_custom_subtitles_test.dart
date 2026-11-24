import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/services/custom_subtitle_source_store.dart';
import 'package:mangayomi/services/fetch_subtitles.dart';

void main() {
  test('uses the script sources as enabled global defaults', () {
    final source = CustomSubtitleSource.fromJson({'enabled': false});

    expect(source.xunleiEnabled, isTrue);
    expect(source.subtitleCatEnabled, isTrue);
    expect(source.avSubtitlesEnabled, isTrue);
  });

  test('recognizes video codes in plain text and page URLs', () {
    expect(isSubtitleVideoCode('IPX-123'), isTrue);
    expect(
      normalizeSubtitleSearchId('https://example.com/watch/fc2-ppv-12345'),
      'FC2-PPV-12345',
    );
    expect(isSubtitleVideoCode('Attack on Titan'), isFalse);
  });

  test('maps a JSON result path and resolves relative subtitle URLs', () {
    final subtitles = parseCustomSubtitleResponse(
      jsonDecode('''
        {
          "data": {
            "items": [
              {
                "download_url": "files/episode.srt",
                "title": "Episode subtitle",
                "lang": "zh-CN"
              }
            ]
          }
        }
        '''),
      responseUri: Uri.parse('https://example.com/search?q=ABC-123'),
      sourceName: 'Example source',
      resultPath: 'data.items',
    );

    expect(subtitles, hasLength(1));
    expect(subtitles.single.url, 'https://example.com/files/episode.srt');
    expect(subtitles.single.name, 'Episode subtitle');
    expect(subtitles.single.language, 'zh-CN');
    expect(subtitles.single.source, 'Example source');
    expect(subtitles.single.format, 'srt');
  });

  test('supports array indexes in the configured result path', () {
    final subtitles = parseCustomSubtitleResponse(
      jsonDecode('''
        {
          "payload": {
            "groups": [
              {
                "subtitles": [
                  {"src": "/subs/one.ass", "language": "en"}
                ]
              }
            ]
          }
        }
        '''),
      responseUri: Uri.parse('https://example.com/api/search'),
      sourceName: 'Example source',
      resultPath: 'payload.groups[0].subtitles',
    );

    expect(subtitles, hasLength(1));
    expect(subtitles.single.url, 'https://example.com/subs/one.ass');
    expect(subtitles.single.format, 'ass');
  });

  test('reports an invalid configured result path', () {
    expect(
      () => parseCustomSubtitleResponse(
        {'data': <String, dynamic>{}},
        responseUri: Uri.parse('https://example.com/search'),
        sourceName: 'Example source',
        resultPath: 'data.items',
      ),
      throwsFormatException,
    );
  });
}
