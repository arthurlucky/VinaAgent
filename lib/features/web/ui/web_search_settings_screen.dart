import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/glass_tokens.dart';
import '../../../shared/widgets/glass_button.dart';
import '../application/web_search_controller.dart';
import '../data/web_search_service.dart';

class WebSearchSettingsScreen extends ConsumerStatefulWidget {
  const WebSearchSettingsScreen({super.key});

  @override
  ConsumerState<WebSearchSettingsScreen> createState() =>
      _WebSearchSettingsScreenState();
}

class _WebSearchSettingsScreenState
    extends ConsumerState<WebSearchSettingsScreen> {
  late WebSearchConfig _config;
  WebSearchProvider _provider = WebSearchProvider.duckduckgo;
  final _keyController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  WebSearchService get _service => ref.read(webSearchServiceProvider);

  @override
  void initState() {
    super.initState();
    _config = _service.config;
    _provider = _config.provider;
    _loadKey();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final key = await _service.readKey(_provider);
    if (!mounted) return;
    setState(() {
      _keyController.text = key ?? '';
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _service.saveConfig(_config.copyWith(provider: _provider));
      await _service.saveKey(_provider, _keyController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Web search settings saved.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      await _service.saveConfig(_config.copyWith(provider: _provider));
      await _service.saveKey(_provider, _keyController.text);
      final response = await _service.search(
        'Flutter latest release',
        provider: _provider,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.results.isEmpty
                ? '${_provider.label} connected, but returned no results.'
                : '${_provider.label} works — ${response.results.length} results.',
          ),
        ),
      );
    } on WebSearchException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Web Search', style: theme.textTheme.titleMedium),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.glassColor,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.glassBorder),
            ),
            child: Text(
              'Choose the backend used by the agent\'s web_search tool. '
              'DuckDuckGo works without a key; the others need an API key '
              'stored in the device keystore.',
              style: TextStyle(color: tokens.textSecondary, height: 1.45),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'PROVIDER',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: tokens.glassColor,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.glassBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<WebSearchProvider>(
                value: _provider,
                isExpanded: true,
                dropdownColor: theme.dialogTheme.backgroundColor,
                items: WebSearchProvider.values
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.label),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _provider = value);
                  _loadKey();
                },
              ),
            ),
          ),
          if (_provider.requiresKey) ...[
            const SizedBox(height: 18),
            Text(
              'API KEY',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: tokens.glassColor,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.glassBorder),
              ),
              child: TextField(
                controller: _keyController,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: _provider.hint,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'No API key required. DuckDuckGo HTML search may be rate-limited.',
              style: TextStyle(color: tokens.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MAX RESULTS',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: tokens.textSecondary,
                ),
              ),
              Text(
                '${_config.maxResults}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: _config.maxResults.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: tokens.accent,
            onChanged: (value) => setState(
              () => _config = _config.copyWith(maxResults: value.round()),
            ),
          ),
          const SizedBox(height: 18),
          GlassButton(
            label: _busy ? 'Working…' : 'Save settings',
            icon: Icons.save_outlined,
            expanded: true,
            onPressed: _busy ? null : _save,
          ),
          const SizedBox(height: 10),
          GlassButton(
            label: 'Test connection',
            icon: Icons.network_check,
            expanded: true,
            onPressed: _busy ? null : _test,
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.secondary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(
                color: tokens.secondary.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Provider notes',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• Tavily — generous free tier, best for agent research.\n'
                  '• Brave — independent index, fast.\n'
                  '• Serper — Google results via serper.dev.\n'
                  '• Exa — semantic/neural search with page text.\n'
                  '• DuckDuckGo — zero-config fallback.',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
