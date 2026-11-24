import 'package:material_ui/material_ui.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/services/custom_subtitle_source_store.dart';
import 'package:mangayomi/services/fetch_subtitles.dart';
import 'package:shiori/shiori.dart';

class CustomSubtitleSourceEditor extends StatefulWidget {
  const CustomSubtitleSourceEditor({this.testQuery = '', super.key});

  final String testQuery;

  static Future<bool?> show(BuildContext context, {String testQuery = ''}) =>
      showShioriSheet<bool>(
        context,
        title: 'Custom online subtitle source',
        maxHeightFactor: 0.85,
        builder: (_) => CustomSubtitleSourceEditor(testQuery: testQuery),
      );

  @override
  State<CustomSubtitleSourceEditor> createState() =>
      _CustomSubtitleSourceEditorState();
}

class _CustomSubtitleSourceEditorState
    extends State<CustomSubtitleSourceEditor> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _queryController = TextEditingController();

  bool _enabled = false;
  bool _xunleiEnabled = true;
  bool _subtitleCatEnabled = true;
  bool _avSubtitlesEnabled = true;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _loadError;
  String? _testMessage;
  bool _testFailed = false;

  @override
  void initState() {
    super.initState();
    _queryController.text = widget.testQuery;
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _pathController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final source = await CustomSubtitleSourceStore.load();
      if (!mounted) return;
      _nameController.text = source.name;
      _urlController.text = source.url;
      _pathController.text = source.path;
      setState(() {
        _enabled = source.enabled;
        _xunleiEnabled = source.xunleiEnabled;
        _subtitleCatEnabled = source.subtitleCatEnabled;
        _avSubtitlesEnabled = source.avSubtitlesEnabled;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  bool get _hasPlaceholder => RegExp(
    r'\{(?:id|title|query)\}',
    caseSensitive: false,
  ).hasMatch(_urlController.text);

  bool get _validUrl {
    if (!_hasPlaceholder) return false;
    final expanded = _urlController.text.replaceAll(
      RegExp(r'\{(?:id|title|query)\}', caseSensitive: false),
      'test',
    );
    final uri = Uri.tryParse(expanded);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _testSource() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _testFailed = true;
        _testMessage = 'Enter a title or video code to test.';
      });
      return;
    }
    if (!_validUrl) {
      setState(() {
        _testFailed = true;
        _testMessage = 'Use an http(s) URL with {id}, {title}, or {query}.';
      });
      return;
    }

    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final results = await fetchCustomSubtitles(
        query: query,
        urlTemplate: _urlController.text.trim(),
        sourceName: _nameController.text.trim(),
        resultPath: _pathController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _testFailed = false;
        _testMessage = 'Request succeeded: ${results?.length ?? 0} result(s).';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testFailed = true;
        _testMessage = error.toString();
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await CustomSubtitleSourceStore.save(
        CustomSubtitleSource(
          enabled: _enabled,
          name: _nameController.text.trim(),
          url: _urlController.text.trim(),
          path: _pathController.text.trim(),
          xunleiEnabled: _xunleiEnabled,
          subtitleCatEnabled: _subtitleCatEnabled,
          avSubtitlesEnabled: _avSubtitlesEnabled,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _testFailed = true;
        _testMessage = 'Could not save source: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(ShioriSpace.s24),
        child: ShioriLoading(),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(ShioriSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_loadError!),
            const SizedBox(height: ShioriSpace.s12),
            TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _loadError = null;
                });
                _load();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ShioriSpace.s16,
        0,
        ShioriSpace.s16,
        ShioriSpace.s16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShioriSwitchRow(
            title: 'Enable custom source',
            subtitle: 'Use this JSON API when searching subtitles.',
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const Padding(
            padding: EdgeInsets.only(top: ShioriSpace.s12),
            child: Text(
              'Global default sources',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ShioriSwitchRow(
            title: '迅雷字幕 (Xunlei)',
            subtitle:
                'api-shoulei-ssl.xunlei.com/oracle/subtitle?name={id}',
            value: _xunleiEnabled,
            onChanged: (value) => setState(() => _xunleiEnabled = value),
          ),
          ShioriSwitchRow(
            title: 'SubtitleCat',
            subtitle: 'www.subtitlecat.com/index.php?search={id}',
            value: _subtitleCatEnabled,
            onChanged: (value) => setState(() => _subtitleCatEnabled = value),
          ),
          ShioriSwitchRow(
            title: 'AVSubtitles',
            subtitle: 'www.avsubtitles.com/search_results.php?search={id}',
            value: _avSubtitlesEnabled,
            onChanged: (value) => setState(() => _avSubtitlesEnabled = value),
          ),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Source name'),
          ),
          const SizedBox(height: ShioriSpace.s12),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search URL template',
              hintText: 'https://example.com/search?q={id}',
            ),
          ),
          const SizedBox(height: ShioriSpace.s12),
          TextField(
            controller: _pathController,
            decoration: const InputDecoration(
              labelText: 'Results path (optional)',
              hintText: 'data.items',
            ),
          ),
          const SizedBox(height: ShioriSpace.s12),
          TextField(
            controller: _queryController,
            decoration: const InputDecoration(
              labelText: 'Test title or video code',
            ),
          ),
          const SizedBox(height: ShioriSpace.s8),
          Text(
            'The endpoint must return JSON. Results should contain a subtitle URL, for example data.items[].url.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_testMessage != null) ...[
            const SizedBox(height: ShioriSpace.s8),
            Text(
              _testMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _testFailed
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: ShioriSpace.s16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing || !_validUrl ? null : _testSource,
                  child: Text(_testing ? 'Testing…' : 'Test source'),
                ),
              ),
              const SizedBox(width: ShioriSpace.s12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving || (_enabled && !_validUrl) ? null : _save,
                  child: Text(_saving ? 'Saving…' : l10n.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
