/// Short markers readers look for on a video card, read from the title,
/// genre tags and the entry link. Sources vary: some pack these into the name
/// ("SSNI-123 女优名 中文字幕", "【无码】ABP-456"), others return them as genre
/// entries, and the MissAV source encodes them in the URL slug while stripping
/// them out of the displayed title ("/en/abcd-chinese-subtitle",
/// "/en/abcd-uncensored-leak"). All three are checked. Two families, in a
/// stable order: subtitles then uncensored.
enum EntryTitleTag {
  // [searchTerm] is the token the source actually uses in the entry URL slug
  // (see the MissAV extension's STRIP_SUB_REGEX). Tapping a badge searches for
  // that token, both in the library link field and at the source, so the
  // search really finds the tagged entries.
  chineseSubtitle('中文字幕', 'chinese-subtitle'),
  uncensored('无码破解', 'uncensored-leak');

  const EntryTitleTag(this.label, this.searchTerm);

  final String label;
  final String searchTerm;
}

/// The patterns that mark each tag. Matched case-insensitively; the Chinese
/// forms are the common ones on video sources, the English ones cover titles
/// and URL slugs that carry "uncensored" / "CHS" / "chinese-subtitle".
const Map<EntryTitleTag, List<Pattern>> _tagPatterns = {
  EntryTitleTag.chineseSubtitle: [
    '中文字幕',
    '中文',
    '字幕',
    'chs',
    'cht',
    'chinese subtitle',
    'chinese sub',
    'chinese-subtitle',
    'cn-subtitle',
  ],
  EntryTitleTag.uncensored: [
    '无码',
    '無碼',
    '无修正',
    '無修正',
    '破解',
    'uncensored',
    'uncensored-leak',
  ],
};

/// Extracts the tags present in [title], [genre] and [link], in
/// [EntryTitleTag] declaration order. Deduplicated by construction: each
/// family contributes at most one label even when it shows up in several of
/// the fields.
List<EntryTitleTag> extractEntryTitleTags(
  String? title, [
  List<String>? genre,
  String? link,
]) {
  final lower = <String>[
    if (title != null && title.isNotEmpty) title.toLowerCase(),
    ...?genre?.map((g) => g.toLowerCase()),
    if (link != null && link.isNotEmpty) link.toLowerCase(),
  ];
  if (lower.isEmpty) return const [];
  return EntryTitleTag.values.where((tag) {
    return _tagPatterns[tag]!.any(
      (pattern) =>
          lower.any((text) => text.contains(pattern.toString().toLowerCase())),
    );
  }).toList();
}
