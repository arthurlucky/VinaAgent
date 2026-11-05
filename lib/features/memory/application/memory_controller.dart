import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/memory_vault.dart';
import '../domain/memory_note.dart';

/// Local Markdown vault used by the memory UI, RAG retrieval and agent tools.
final memoryVaultProvider = Provider<MemoryVault>((ref) => MemoryVault());

/// All notes in the vault, newest first.
final memoryNotesProvider = FutureProvider<List<MemoryNote>>((ref) {
  return ref.watch(memoryVaultProvider).listNotes();
});

/// Full-text search used by the vault screen.
final memorySearchProvider =
    FutureProvider.family<List<MemorySearchHit>, String>((ref, query) {
  if (query.trim().isEmpty) {
    return Future.value(const <MemorySearchHit>[]);
  }
  return ref.watch(memoryVaultProvider).search(query);
});
