/// A versioned, self-contained output produced by the agent.
class Artifact {
  const Artifact({
    required this.id,
    required this.title,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    required this.versions,
    this.language = '',
  });

  final String id;
  final String title;

  /// markdown | html | code | text | json | csv
  final String type;
  final String language;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ArtifactVersion> versions;

  ArtifactVersion get latest => versions.last;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'language': language,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'versions': versions.map((v) => v.toJson()).toList(),
      };

  factory Artifact.fromJson(Map<String, dynamic> json) => Artifact(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Untitled artifact',
        type: json['type'] as String? ?? 'markdown',
        language: json['language'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        versions: (json['versions'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ArtifactVersion.fromJson)
            .toList(),
      );
}

class ArtifactVersion {
  const ArtifactVersion({
    required this.number,
    required this.file,
    required this.createdAt,
    this.note = '',
  });

  final int number;
  final String file;
  final DateTime createdAt;
  final String note;

  Map<String, dynamic> toJson() => {
        'number': number,
        'file': file,
        'createdAt': createdAt.toIso8601String(),
        'note': note,
      };

  factory ArtifactVersion.fromJson(Map<String, dynamic> json) =>
      ArtifactVersion(
        number: (json['number'] as num?)?.toInt() ?? 1,
        file: json['file'] as String? ?? 'v1.md',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        note: json['note'] as String? ?? '',
      );
}
