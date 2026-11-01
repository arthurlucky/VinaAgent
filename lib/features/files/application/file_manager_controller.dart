import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_sandbox.dart';
import '../data/file_manager_service.dart';
import '../domain/file_item.dart';

final fileManagerProvider = Provider<FileManagerService>((ref) {
  return const FileManagerService();
});

final filesInFolderProvider =
    FutureProvider.family<List<FileItem>, String>((ref, folderPath) async {
  return ref.watch(fileManagerProvider).listFiles(folderPath);
});

final sandboxRootProvider = FutureProvider<String>((ref) async {
  return (await AppSandbox.root()).path;
});
