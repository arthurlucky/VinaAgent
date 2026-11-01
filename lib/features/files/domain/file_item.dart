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

  bool get isZip => !isDirectory && name.toLowerCase().endsWith('.zip');

  String get sizeDisplay {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Represents an entry inside a .zip archive.
class ZipEntryItem {
  const ZipEntryItem({
    required this.name,
    required this.sizeBytes,
    required this.isDirectory,
  });

  final String name;
  final int sizeBytes;
  final bool isDirectory;

  String get sizeDisplay {
    if (isDirectory) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
