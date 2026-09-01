import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';

/// The two concise questions selected for one memory in a Weekly ritual.
final class ConversationPromptSet {
  const ConversationPromptSet({
    required this.everyday,
    required this.reflective,
  });

  final String everyday;
  final String reflective;
}

/// Selects family-conversation prompts entirely from an already opened memory.
///
/// This service has no persistence or transport dependencies. Callers pass the
/// locally decrypted [OpenedMemory]; only its caption, text, and format are
/// inspected while selecting a fixed prompt pair.
final class LocalConversationPromptService {
  const LocalConversationPromptService();

  ConversationPromptSet promptsFor(OpenedMemory memory) {
    final text = _normalizedText(memory);
    if (text.isEmpty && memory.metadata.format == MemoryFormat.photo) {
      return const ConversationPromptSet(
        everyday: 'What small detail in this photo stands out today?',
        reflective: 'What do you notice here that helps your family remember?',
      );
    }

    if (_matches(text, _foodWords)) {
      return const ConversationPromptSet(
        everyday: 'What was on the table that everyone kept reaching for?',
        reflective:
            'Which family tradition would you like this meal to become?',
      );
    }
    if (_matches(text, _placeWords)) {
      return const ConversationPromptSet(
        everyday: 'What place or detail from the journey made you smile?',
        reflective: 'What did this journey open up for your family?',
      );
    }
    if (_matches(text, _celebrationWords)) {
      return const ConversationPromptSet(
        everyday: 'What was the most joyful part of the celebration?',
        reflective: 'What made this milestone meaningful for your family?',
      );
    }
    if (_matches(text, _workSchoolWords)) {
      return const ConversationPromptSet(
        everyday: 'What was the small detail everyone noticed?',
        reflective:
            'What did this moment teach your family about growing together?',
      );
    }

    return const ConversationPromptSet(
      everyday: 'What detail from this memory would you enjoy sharing?',
      reflective: 'What does this memory help your family hold onto?',
    );
  }

  String _normalizedText(OpenedMemory memory) =>
      '${memory.payload.caption ?? ''} ${memory.payload.text ?? ''}'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toLowerCase();

  bool _matches(String text, Set<String> words) {
    for (final word in words) {
      if (RegExp(r'\b' + word + r'\b').hasMatch(text)) return true;
    }
    return false;
  }
}

const _foodWords = {
  'food',
  'meal',
  'dinner',
  'lunch',
  'breakfast',
  'supper',
  'table',
  'recipe',
  'cook',
  'cooking',
  'soup',
  'cake',
  'kitchen',
};

const _placeWords = {
  'trip',
  'travel',
  'journey',
  'place',
  'beach',
  'lake',
  'mountain',
  'hike',
  'hiking',
  'park',
  'outdoors',
  'outside',
  'holiday',
};

const _celebrationWords = {
  'birthday',
  'celebration',
  'celebrate',
  'anniversary',
  'graduation',
  'milestone',
  'wedding',
  'festival',
  'party',
};

const _workSchoolWords = {
  'work',
  'office',
  'job',
  'project',
  'meeting',
  'school',
  'class',
  'homework',
  'teacher',
  'lesson',
  'exam',
};
