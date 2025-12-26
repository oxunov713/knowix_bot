import '../models/question.dart';
import '../models/quiz.dart';
import 'quiz_text_normalizer.dart';

/// Service for parsing normalized quiz text into Question objects
/// This is STAGE 2 of the two-stage parsing strategy
class QuizParserService {
  final QuizTextNormalizer normalizer;

  QuizParserService(this.normalizer);

  /// Parse normalized text into a Quiz object
  Quiz parseQuiz(String normalizedText) {
    final questions = _parseQuestions(normalizedText);

    if (questions.isEmpty) {
      throw FormatException('No valid questions found in the text');
    }

    print('✅ Successfully parsed ${questions.length} questions');
    return Quiz(questions: questions);
  }

  /// Parse questions using state machine approach
  List<Question> _parseQuestions(String text) {
    final questions = <Question>[];
    final lines = text.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();

    String? currentQuestionText;
    final currentOptions = <String>[];
    int? correctOptionIndex;

    void finalizeQuestion() {
      if (currentQuestionText != null && currentOptions.length >= 2) {
        // Validate exactly one correct answer
        if (correctOptionIndex == null) {
          // Skip silently - no correct answer marked
          currentQuestionText = null;
          currentOptions.clear();
          return;
        }

        final question = Question(
          text: currentQuestionText!,
          options: List.from(currentOptions),
          correctOptionIndex: correctOptionIndex!,
        );

        if (question.isValid()) {
          questions.add(question);
          print('📝 Question ${questions.length}: ${currentQuestionText!.substring(0, currentQuestionText!.length > 50 ? 50 : currentQuestionText!.length)}...');
        }
      }

      // Reset state
      currentQuestionText = null;
      currentOptions.clear();
      correctOptionIndex = null;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Skip PDF noise early
      if (_isPdfNoise(line)) {
        continue;
      }

      // STATE 1: New question token
      if (line == QuizTextNormalizer.questionToken) {
        // Finalize previous question if exists
        finalizeQuestion();

        // Next non-empty, non-token line is question text
        for (var j = i + 1; j < lines.length; j++) {
          final nextLine = lines[j];
          if (nextLine.isEmpty || _isPdfNoise(nextLine)) continue;
          if (_isToken(nextLine)) break;

          currentQuestionText = nextLine;
          i = j; // Skip to this line
          break;
        }
        continue;
      }

      // STATE 2: Option token
      if (line == QuizTextNormalizer.optionToken) {
        // Next non-empty, non-token line is option text
        for (var j = i + 1; j < lines.length; j++) {
          final nextLine = lines[j];
          if (nextLine.isEmpty || _isPdfNoise(nextLine)) continue;
          if (_isToken(nextLine)) break;

          // Check if this option has correct marker
          bool isCorrect = false;
          String optionText = nextLine;

          if (nextLine.startsWith(QuizTextNormalizer.correctMarker)) {
            isCorrect = true;
            optionText = nextLine.substring(1).trim();
          }

          if (optionText.isNotEmpty && !_isPdfNoise(optionText)) {
            if (isCorrect) {
              // Only set correct index if not already set (avoid multiple correct answers)
              if (correctOptionIndex == null) {
                correctOptionIndex = currentOptions.length;
              }
            }
            currentOptions.add(optionText);
          }

          i = j; // Skip to this line
          break;
        }
        continue;
      }

      // STATE 3: Correct marker (standalone)
      if (line == QuizTextNormalizer.correctMarker) {
        // Next non-empty, non-token line is the correct option
        for (var j = i + 1; j < lines.length; j++) {
          final nextLine = lines[j];
          if (nextLine.isEmpty || _isPdfNoise(nextLine)) continue;
          if (_isToken(nextLine)) break;

          // Only set correct index if not already set
          if (correctOptionIndex == null) {
            correctOptionIndex = currentOptions.length;
          }
          currentOptions.add(nextLine);

          i = j; // Skip to this line
          break;
        }
        continue;
      }

      // STATE 4: Handle lines that start with # (correct marker inline)
      if (line.startsWith(QuizTextNormalizer.correctMarker) &&
          line != QuizTextNormalizer.correctMarker) {
        final optionText = line.substring(1).trim();
        if (optionText.isNotEmpty && !_isPdfNoise(optionText)) {
          // Only set correct index if not already set
          if (correctOptionIndex == null) {
            correctOptionIndex = currentOptions.length;
          }
          currentOptions.add(optionText);
        }
        continue;
      }

      // STATE 5: Regular text (could be question or option depending on context)
      // If no question yet and no options, treat as question (but not if it's a token)
      if (currentQuestionText == null &&
          currentOptions.isEmpty &&
          !_isPdfNoise(line) &&
          !_isToken(line)) {
        currentQuestionText = line;
      }
    }

    // Finalize last question
    finalizeQuestion();

    return questions;
  }

  /// Check if a line is a token
  bool _isToken(String line) {
    return line == QuizTextNormalizer.questionToken ||
        line == QuizTextNormalizer.optionToken ||
        line == QuizTextNormalizer.correctMarker;
  }

  /// Check if a line is PDF noise/metadata
  bool _isPdfNoise(String line) {
    // Very basic check - only filter obvious PDF markers
    if (line.startsWith('%PDF')) return true;
    if (line.startsWith('<<') && line.endsWith('>>')) return true;
    if (line == 'obj' || line == 'endobj') return true;
    if (line.startsWith('/Type') || line.startsWith('/Filter')) return true;

    // Filter very long lines (likely binary)
    if (line.length > 300) return true;

    // Filter lines with lots of non-printable characters
    final nonPrintable = line.codeUnits.where((c) => c < 32 || c > 126).length;
    if (nonPrintable > line.length * 0.3) return true;

    return false;
  }

  /// Parse quiz with automatic normalization
  Quiz parseRawText(String rawText) {
    print('📄 Raw text length: ${rawText.length} characters');
    final normalized = normalizer.normalizeQuizText(rawText);
    print('📄 Normalized text length: ${normalized.length} characters');

    // Debug: Print first 500 characters of normalized text
    final preview = normalized.substring(0, normalized.length > 500 ? 500 : normalized.length);
    print('📄 Preview of normalized text:\n$preview\n---');

    return parseQuiz(normalized);
  }
}