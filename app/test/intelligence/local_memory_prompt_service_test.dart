import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/intelligence/local_conversation_prompt_service.dart';

void main() {
  const service = LocalConversationPromptService();

  test('routes a photo meal caption to everyday and reflective questions', () {
    final result = service.promptsFor(
      _memory(
        format: MemoryFormat.photo,
        caption: '  sunday   dinner with grandma and her famous soup ',
      ),
    );

    expect(
      result.everyday,
      'What was on the table that everyone kept reaching for?',
    );
    expect(
      result.reflective,
      'Which family tradition would you like this meal to become?',
    );
  });

  test('routes travel and outdoors captions deterministically', () {
    final result = service.promptsFor(
      _memory(
        format: MemoryFormat.text,
        caption: 'A hike near the lake during our trip',
      ),
    );

    expect(result.everyday.toLowerCase(), contains('place'));
    expect(result.reflective.toLowerCase(), contains('journey'));
  });

  test('routes celebration captions to milestone questions', () {
    final celebration = service.promptsFor(
      _memory(format: MemoryFormat.text, text: 'birthday celebration'),
    );

    expect(celebration.everyday.toLowerCase(), contains('celebrat'));
    expect(celebration.reflective.toLowerCase(), contains('milestone'));
  });

  test('routes work and school captions to growing-together questions', () {
    final work = service.promptsFor(
      _memory(format: MemoryFormat.text, text: 'first day at school'),
    );

    expect(work.everyday, 'What was the small detail everyone noticed?');
    expect(
      work.reflective,
      'What did this moment teach your family about growing together?',
    );
  });

  test('uses photo-specific questions when a photo has no text', () {
    final result = service.promptsFor(
      _memory(format: MemoryFormat.photo),
    );

    expect(result.everyday.toLowerCase(), contains('photo'));
    expect(result.reflective.toLowerCase(), contains('notice'));
  });

  test('uses a safe generic fallback and never unsafe framing', () {
    final result = service.promptsFor(
      _memory(format: MemoryFormat.voice, caption: 'a quiet moment'),
    );
    final questions = '${result.everyday} ${result.reflective}'.toLowerCase();

    expect(result.everyday, isNotEmpty);
    expect(result.reflective, isNotEmpty);
    expect(questions, isNot(contains('i ')));
    expect(questions, isNot(contains('you should')));
    expect(questions, isNot(contains('must')));
    expect(questions, isNot(contains('diagnos')));
  });

  test('returns an immutable pair with concise questions', () {
    final result = service.promptsFor(
      _memory(format: MemoryFormat.text, text: 'garden'),
    );

    expect(result, isA<ConversationPromptSet>());
    expect(result.everyday.length, lessThanOrEqualTo(100));
    expect(result.reflective.length, lessThanOrEqualTo(100));
  });
}

OpenedMemory _memory({
  required MemoryFormat format,
  String? text,
  String? caption,
}) {
  return OpenedMemory(
    metadata: VaultEntryMetadata(
      id: 'memory-1',
      familyId: 'family-1',
      authorId: 'member-1',
      createdAt: DateTime.utc(2026, 1, 1),
      format: format,
      privacy: PrivacyTier.journal,
      blobRef: 'local://memory-1',
      state: 'kept',
    ),
    payload: EntryPayload(
      format: format,
      primaryBytes: format == MemoryFormat.photo
          ? Uint8List.fromList([1, 2])
          : null,
      text: text,
      caption: caption,
      mediaExtension: format == MemoryFormat.photo ? 'jpg' : null,
      mediaDurationMs: null,
    ),
  );
}
