import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketstrike/features/memory/data/memory_vault.dart';

void main() {
  group('memory note parsing', () {
    test('extracts hashtags but ignores headings and code fences', () {
      const body = '''
# Project Alpha

#notememori #project/mobile

```
#ignored
```
''';
      final tags = MemoryVault.extractTags(body);
      expect(tags, contains('notememori'));
      expect(tags, contains('project/mobile'));
      expect(tags, isNot(contains('ignored')));
    });

    test('parses wiki links with aliases and anchors', () {
      final links = MemoryVault.outgoingLinks(
        'See [[Project Alpha|the plan]] and [[Notes#Ideas]].',
      );
      expect(links, containsAll(<String>['Project Alpha', 'Notes']));
    });

    test('strips the first heading for the editor body', () {
      expect(
        MemoryVault.stripTitleHeading('# My note\n\nSome body text'),
        'Some body text',
      );
    });

    test('builds a heading when one is missing', () {
      expect(
        MemoryVault.ensureHeading('My note', 'Some body text'),
        '# My note\n\nSome body text',
      );
    });

    test('slugifies titles safely', () {
      expect(MemoryVault.slugify('My Note: Ideas & Plans'), 'my-note-ideas-plans');
    });
  });

  group('memory vault', () {
    late Directory temp;
    late MemoryVault vault;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('vina_memory_test');
      vault = MemoryVault(rootProvider: () async => temp);
    });

    tearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    test('creates, searches and filters notes', () async {
      await vault.createNote(
        title: 'Project Alpha',
        body: 'Launch plan for the mobile app. #notememori',
      );
      await vault.createNote(
        title: 'Shopping',
        body: 'Milk and eggs.',
      );

      final hits = await vault.search('launch mobile');
      expect(hits, isNotEmpty);
      expect(hits.first.note.title, 'Project Alpha');

      final memoryOnly = await vault.search('milk', memoryOnly: true);
      expect(memoryOnly, isEmpty);

      final rag = await vault.buildRagContext('launch plan');
      expect(rag, contains('Project Alpha'));
      expect(rag, isNot(contains('Shopping')));
    });

    test('captures chat messages tagged #notememori', () async {
      final note = await vault.captureChatNote(
        'Remember the API key rotation #notememori',
      );
      expect(note, isNotNull);
      final saved = note!;
      expect(saved.isMemory, isTrue);
      expect(saved.body, contains('#notememori'));

      final duplicate = await vault.captureChatNote(
        'Remember the API key rotation #notememori',
      );
      expect(duplicate?.path, saved.path);
    });

    test('finds backlinks between notes', () async {
      await vault.createNote(
        title: 'Alpha',
        body: 'This references [[Beta]].',
      );
      await vault.createNote(
        title: 'Beta',
        body: 'Target note.',
      );

      final backlinks = await vault.backlinks('Beta');
      expect(backlinks.map((note) => note.title), contains('Alpha'));
    });
  });
}
