import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/modules/widgets/entry_title_tags.dart';

void main() {
  group('extractEntryTitleTags', () {
    test('picks up Chinese subtitle markers', () {
      expect(
        extractEntryTitleTags('SSNI-123 美しい女優 中文字幕'),
        [EntryTitleTag.chineseSubtitle],
      );
      expect(extractEntryTitleTags('ABP-456 女优 字幕'), [
        EntryTitleTag.chineseSubtitle,
      ]);
      expect(extractEntryTitleTags('MIAA-123 CHS'), [
        EntryTitleTag.chineseSubtitle,
      ]);
    });

    test('picks up uncensored markers, including bracketed ones', () {
      expect(extractEntryTitleTags('【无码】ABP-456 女优名 高清'), [
        EntryTitleTag.uncensored,
      ]);
      expect(extractEntryTitleTags('FC2-123 无修正 破解'), [
        EntryTitleTag.uncensored,
      ]);
      expect(extractEntryTitleTags('SSNI-123 uncensored'), [
        EntryTitleTag.uncensored,
      ]);
    });

    test('returns both tags in stable order when present', () {
      expect(extractEntryTitleTags('【无码破解】SSNI-123 中文字幕'), [
        EntryTitleTag.chineseSubtitle,
        EntryTitleTag.uncensored,
      ]);
    });

    test('returns empty for a plain title or null', () {
      expect(extractEntryTitleTags('SSNI-123 女优名'), isEmpty);
      expect(extractEntryTitleTags(null), isEmpty);
      expect(extractEntryTitleTags(''), isEmpty);
    });

    test('is case-insensitive for English markers', () {
      expect(extractEntryTitleTags('ABP-456 Uncensored CHS'), [
        EntryTitleTag.chineseSubtitle,
        EntryTitleTag.uncensored,
      ]);
    });

    test('reads markers from genre even when the title is plain', () {
      expect(
        extractEntryTitleTags('SSNI-123', const ['中文字幕', '无码']),
        [EntryTitleTag.chineseSubtitle, EntryTitleTag.uncensored],
      );
      expect(
        extractEntryTitleTags(null, const ['字幕', 'uncensored']),
        [EntryTitleTag.chineseSubtitle, EntryTitleTag.uncensored],
      );
    });

    test('deduplicates a marker found in both title and genre', () {
      expect(
        extractEntryTitleTags('SSNI-123 中文字幕', const ['中文字幕']),
        [EntryTitleTag.chineseSubtitle],
      );
    });

    test('reads markers from the URL slug (MissAV style)', () {
      // The source strips these suffixes from the title but keeps them in the
      // entry link, so a plain title still yields a tag when the link carries
      // the marker.
      expect(
        extractEntryTitleTags('ABCD-123 Some Title', null, '/en/abcd-123-chinese-subtitle'),
        [EntryTitleTag.chineseSubtitle],
      );
      expect(
        extractEntryTitleTags('ABCD-123 Some Title', null, '/en/abcd-123-uncensored-leak'),
        [EntryTitleTag.uncensored],
      );
      expect(
        extractEntryTitleTags('ABCD-123 Some Title', null, '/dm1/en/abcd-123-chinese-subtitle-uncensored-leak'),
        [EntryTitleTag.chineseSubtitle, EntryTitleTag.uncensored],
      );
      expect(
        extractEntryTitleTags('ABCD-123 Some Title', null, 'https://missav.ws/en/abcd-123-uncensored-leak'),
        [EntryTitleTag.uncensored],
      );
    });

    test('link markers dedupe with title/genre markers', () {
      expect(
        extractEntryTitleTags('ABCD-123 中文字幕', null, '/en/abcd-123-chinese-subtitle'),
        [EntryTitleTag.chineseSubtitle],
      );
      expect(
        extractEntryTitleTags(null, const ['无码'], '/en/abcd-123-uncensored-leak'),
        [EntryTitleTag.uncensored],
      );
    });

    test('returns empty when all fields are plain', () {
      expect(
        extractEntryTitleTags('ABCD-123 Some Title', const ['高清', '独家'], '/en/abcd-123'),
        isEmpty,
      );
    });

    test('each tag carries the source slug used as a search term', () {
      expect(EntryTitleTag.chineseSubtitle.searchTerm, 'chinese-subtitle');
      expect(EntryTitleTag.uncensored.searchTerm, 'uncensored-leak');
    });
  });
}
