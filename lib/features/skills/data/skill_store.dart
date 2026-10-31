import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/agent_skill.dart';
import 'skill_parser.dart';

/// Filesystem-backed skill library with progressive disclosure.
///
/// On device the layout is:
///
/// ```
/// <app documents>/skills/<name>/SKILL.md
/// <app documents>/skills/<name>/references/...
/// ```
///
/// Bundled skills are copied out of `assets/skills/` on first run so users can
/// edit them and the agent can add new skills at runtime.
class SkillStore {
  SkillStore(this._prefs);

  static const String _assetRoot = 'assets/skills/';
  static const String _enabledPrefix = 'skill_enabled_';
  static const String _globalEnabledKey = 'skills_enabled';
  static const String _bundledMarker = '.bundled';
  static const int _maxResourceChars = 16000;
  static final RegExp _validName = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');

  final SharedPreferences _prefs;

  /// Master switch for the whole skill system.
  bool get globallyEnabled => _prefs.getBool(_globalEnabledKey) ?? true;

  Future<void> setGloballyEnabled(bool enabled) async {
    await _prefs.setBool(_globalEnabledKey, enabled);
  }

  bool isEnabled(String name) =>
      _prefs.getBool('$_enabledPrefix$name') ?? true;

  Future<void> setEnabled(String name, bool enabled) async {
    await _prefs.setBool('$_enabledPrefix$name', enabled);
  }

  Future<Directory> _root() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(documents.path, 'skills'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copies bundled skills onto disk without overwriting user edits.
  Future<void> ensureSeeded() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest
          .listAssets()
          .where((asset) => asset.startsWith(_assetRoot))
          .toList();
      if (assets.isEmpty) return;

      final root = await _root();
      for (final asset in assets) {
        final relative = asset.substring(_assetRoot.length);
        if (relative.isEmpty) continue;

        final target = File(p.join(root.path, relative));
        if (!await target.exists()) {
          await target.parent.create(recursive: true);
          final data = await rootBundle.load(asset);
          await target.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
        }

        final skillName = relative.split('/').first;
        final marker = File(p.join(root.path, skillName, _bundledMarker));
        if (!await marker.exists()) {
          await marker.writeAsString('1', flush: true);
        }
      }
    } catch (_) {
      // Bundled skills are optional; user-created skills still work.
    }
  }

  /// All skills currently installed on the device.
  Future<List<AgentSkill>> listSkills() async {
    final root = await _root();
    final skills = <AgentSkill>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final skill = await _readSkill(entity);
      if (skill != null) skills.add(skill);
    }
    skills.sort((a, b) => a.name.compareTo(b.name));
    return skills;
  }

  /// Looks a skill up by its directory name.
  Future<AgentSkill?> findSkill(String name) async {
    if (!_validName.hasMatch(name)) return null;
    final root = await _root();
    final dir = Directory(p.join(root.path, name));
    if (!await dir.exists()) return null;
    return _readSkill(dir);
  }

  Future<AgentSkill?> _readSkill(Directory dir) async {
    final file = File(p.join(dir.path, 'SKILL.md'));
    if (!await file.exists()) return null;

    try {
      final raw = await file.readAsString();
      final parsed = SkillParser.parse(raw, fallbackName: p.basename(dir.path));
      final resources = await _listResources(dir);
      final marker = File(p.join(dir.path, _bundledMarker));

      return AgentSkill(
        name: parsed.name,
        description: parsed.description,
        body: parsed.body,
        directory: dir.path,
        resources: resources,
        bundled: await marker.exists(),
        enabled: isEnabled(parsed.name),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _listResources(Directory dir) async {
    final base = p.canonicalize(dir.path);
    final resources = <String>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final canonical = p.canonicalize(entity.path);
      if (!canonical.startsWith('$base${p.separator}')) continue;
      final relative = p.relative(canonical, from: base).replaceAll('\\', '/');
      if (relative == 'SKILL.md' || relative == _bundledMarker) continue;
      resources.add(relative);
    }

    resources.sort();
    return resources;
  }

  /// Reads a reference file (Level 3) belonging to [skillName].
  ///
  /// Returns null when the skill or file does not exist, or when the path
  /// escapes the skill directory.
  Future<String?> readResource(String skillName, String relativePath) async {
    final skill = await findSkill(skillName);
    if (skill == null) return null;

    final normalized = p.normalize(relativePath.trim()).replaceAll('\\', '/');
    if (normalized.isEmpty || normalized.startsWith('..') || p.isAbsolute(normalized)) {
      return null;
    }

    final base = p.canonicalize(skill.directory);
    final file = File(p.join(base, normalized));
    final canonical = p.canonicalize(file.path);
    if (!canonical.startsWith('$base${p.separator}')) return null;
    if (!await file.exists()) return null;

    final content = await file.readAsString();
    if (content.length <= _maxResourceChars) return content;
    return '${content.substring(0, _maxResourceChars)}\n\n'
        '[... truncated at $_maxResourceChars characters]';
  }

  /// Creates a new skill directory from raw instructions.
  Future<AgentSkill> createSkill({
    required String name,
    required String description,
    required String instructions,
  }) async {
    final normalized = _normalizeName(name);
    if (!_validName.hasMatch(normalized)) {
      throw SkillFormatException(
        'Invalid skill name "$name". Use lowercase letters, numbers and hyphens.',
      );
    }

    final trimmedDescription = description.trim();
    if (trimmedDescription.isEmpty) {
      throw SkillFormatException('A skill description is required.');
    }
    if (trimmedDescription.length > 1024) {
      throw SkillFormatException('Description must be 1024 characters or less.');
    }

    final trimmedInstructions = instructions.trim();
    if (trimmedInstructions.isEmpty) {
      throw SkillFormatException('Skill instructions cannot be empty.');
    }

    final root = await _root();
    final dir = Directory(p.join(root.path, normalized));
    if (await dir.exists()) {
      throw SkillFormatException('A skill named "$normalized" already exists.');
    }
    await dir.create(recursive: true);

    final title = normalized
        .split('-')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');

    final contents = '---\n'
        'name: $normalized\n'
        'description: ${jsonEncode(trimmedDescription)}\n'
        '---\n\n'
        '# $title\n\n'
        '$trimmedInstructions\n';

    await File(p.join(dir.path, 'SKILL.md'))
        .writeAsString(contents, flush: true);

    final skill = await _readSkill(dir);
    if (skill == null) {
      throw SkillFormatException('Could not read the new skill back from disk.');
    }
    return skill;
  }

  /// Deletes a skill directory. Bundled skills can be restored by re-seeding.
  Future<void> deleteSkill(String name) async {
    final skill = await findSkill(name);
    if (skill == null) return;
    await Directory(skill.directory).delete(recursive: true);
    await _prefs.remove('$_enabledPrefix$name');
  }

  /// Builds the Level-1 catalog injected into the agent system prompt.
  Future<String> buildCatalogPrompt() async {
    if (!globallyEnabled) return '';

    final skills = (await listSkills()).where((skill) => skill.enabled).toList();
    if (skills.isEmpty) return '';

    final buffer = StringBuffer()
      ..writeln('## Agent Skills')
      ..writeln()
      ..writeln(
        'Reusable skills are installed on this device. Only their name and '
        'description are listed below (progressive disclosure). When a task '
        'matches a skill, call `load_skill` with its name BEFORE acting, then '
        'follow its instructions. Use `read_skill_resource` for files a skill '
        'references. Save new reusable procedures with `create_skill`.',
      )
      ..writeln()
      ..writeln('Available skills:');

    for (final skill in skills) {
      buffer.writeln(skill.catalogLine);
    }
    return buffer.toString().trim();
  }

  String _normalizeName(String raw) {
    var name = raw.trim().toLowerCase();
    name = name.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    name = name.replaceAll(RegExp(r'-+'), '-');
    name = name.replaceAll(RegExp(r'^-+|-+$'), '');
    if (name.length > 64) {
      name = name.substring(0, 64);
      name = name.replaceAll(RegExp(r'-+$'), '');
    }
    return name;
  }
}
