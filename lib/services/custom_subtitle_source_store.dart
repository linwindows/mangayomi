import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class CustomSubtitleSource {
  final bool enabled;
  final String name;
  final String url;
  final String path;
  final bool xunleiEnabled;
  final bool subtitleCatEnabled;
  final bool avSubtitlesEnabled;

  const CustomSubtitleSource({
    this.enabled = false,
    this.name = 'Custom',
    this.url = '',
    this.path = '',
    this.xunleiEnabled = true,
    this.subtitleCatEnabled = true,
    this.avSubtitlesEnabled = true,
  });

  factory CustomSubtitleSource.fromJson(Map<String, dynamic> json) =>
      CustomSubtitleSource(
        enabled: json['enabled'] == true,
        name: json['name']?.toString().trim().isNotEmpty == true
            ? json['name'].toString().trim()
            : 'Custom',
        url: json['url']?.toString() ?? '',
        path: json['path']?.toString() ?? '',
        xunleiEnabled: json['xunleiEnabled'] != false,
        subtitleCatEnabled: json['subtitleCatEnabled'] != false,
        avSubtitlesEnabled: json['avSubtitlesEnabled'] != false,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'name': name,
    'url': url,
    'path': path,
    'xunleiEnabled': xunleiEnabled,
    'subtitleCatEnabled': subtitleCatEnabled,
    'avSubtitlesEnabled': avSubtitlesEnabled,
  };
}

class CustomSubtitleSourceStore {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'custom_subtitle_source.json'));
  }

  static Future<CustomSubtitleSource> load() async {
    final file = await _file();
    if (!await file.exists()) return const CustomSubtitleSource();
    final json = jsonDecode(await file.readAsString());
    if (json is! Map) {
      throw const FormatException(
        'Custom subtitle source settings are invalid',
      );
    }
    return CustomSubtitleSource.fromJson(json.cast<String, dynamic>());
  }

  static Future<void> save(CustomSubtitleSource source) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(source.toJson()));
  }
}
