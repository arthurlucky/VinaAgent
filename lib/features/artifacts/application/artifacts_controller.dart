import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/features/artifacts/data/artifact_store.dart';
import 'package:pocketstrike/features/artifacts/domain/artifact.dart';

/// Versioned artifact store rooted in the app sandbox.
final artifactStoreProvider = Provider<ArtifactStore>((ref) {
  return const ArtifactStore();
});

/// Every saved artifact, newest first.
final artifactsProvider = FutureProvider<List<Artifact>>((ref) async {
  return ref.watch(artifactStoreProvider).list();
});

/// Content of one artifact version.
final artifactVersionProvider =
    FutureProvider.family<String, ({String id, int number})>((ref, args) async {
  return ref.watch(artifactStoreProvider).readVersion(args.id, args.number);
});
