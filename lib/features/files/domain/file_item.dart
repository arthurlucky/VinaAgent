/// Represents a file in the app sandbox.
class FileItem {
  const FileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime modifiedAt;

  String get sizeDisplay {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
