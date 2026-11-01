import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/prefs_provider.dart';
import '../../../core/storage/secure_keys.dart';
import '../data/web_search_service.dart';

/// Shared configurable web search service (settings + agent tool).
final webSearchServiceProvider = Provider<WebSearchService>((ref) {
  return WebSearchService(
    prefs: ref.watch(sharedPreferencesProvider),
    keys: ref.watch(secureKeyStoreProvider),
  );
});
