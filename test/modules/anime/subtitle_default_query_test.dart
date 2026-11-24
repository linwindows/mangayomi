import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/modules/anime/widgets/search_subtitles.dart';

void main() {
  group('extractJavCode', () {
    test('returns null for null or plain titles', () {
      expect(extractJavCode(null), isNull);
      expect(extractJavCode('庆余年 第二季'), isNull);
      expect(extractJavCode(''), isNull);
    });

    test('extracts code from a code-only title', () {
      expect(extractJavCode('SSNI-123'), 'SSNI-123');
      expect(extractJavCode('abp456'), 'ABP-456');
      expect(extractJavCode('ssni 123'), 'SSNI-123');
    });

    test('extracts code embedded in a longer title', () {
      expect(extractJavCode('SSNI-123 美しい女優 中文字幕'), 'SSNI-123');
      expect(extractJavCode('【无码】ABP-456 女优名 高清'), 'ABP-456');
    });
  });

  group('subtitleDefaultQuery', () {
    test('returns just the code when title contains one', () {
      expect(subtitleDefaultQuery('SSNI-123 美しい女優'), 'SSNI-123');
    });

    test('returns the trimmed full title when no code', () {
      expect(subtitleDefaultQuery('  庆余年  '), '庆余年');
    });

    test('handles null', () {
      expect(subtitleDefaultQuery(null), '');
    });
  });
}
