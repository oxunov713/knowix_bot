
import '../models/question.dart';
import '../models/quiz.dart';
import 'quiz_text_normalizer.dart';

/// Service for parsing normalized quiz text - IMPROVED VERSION
class QuizParserService {
  final QuizTextNormalizer normalizer;

  QuizParserService(this.normalizer);

  /// Parse normalized text into a Quiz object
  Quiz parseQuiz(String normalizedText) {
    final questions = _parseQuestions(normalizedText);

    if (questions.isEmpty) {
      throw FormatException('Faylda to\'g\'ri formatdagi savollar topilmadi.\n\n'
          'Format:\n'
          '+++++ Savol matni\n'
          '===== Variant 1\n'
          '===== #To\'g\'ri javob\n'
          '===== Variant 3\n');
    }

    print('✅ Muvaffaqiyatli parse qilindi: ${questions.length} ta savol');
    return Quiz(questions: questions);
  }

  /// Parse questions using IMPROVED state machine approach
  List<Question> _parseQuestions(String text) {
    final questions = <Question>[];
    final lines = text.split('\n').map((line) => line.trim()).toList();

    print('📊 Jami qatorlar: ${lines.length}');

    String? currentQuestionText;
    String? currentQuestionHint;
    final currentOptions = <String>[];
    int? correctOptionIndex;

    // State machine variables
    bool inQuestion = false;
    bool expectingQuestionText = false;
    bool expectingOption = false;
    int consecutiveEmptyLines = 0;

    void finalizeQuestion() {
      if (currentQuestionText != null && currentOptions.length >= 2) {
        // If no correct answer marked, try to find from hint or default to first
        if (correctOptionIndex == null) {
          if (currentQuestionHint != null) {
            correctOptionIndex = normalizer.parseCorrectAnswerFromHint(
              currentQuestionHint!,
              currentOptions.length,
            );
          }

          if (correctOptionIndex == null) {
            print(
                '⚠️ To\'g\'ri javob topilmadi, birinchi variantni tanlaymiz: '
                    '${_truncate(currentQuestionText!, 50)}');
            correctOptionIndex = 0;
          }
        }

        // Validate correct index
        if (correctOptionIndex! >= currentOptions.length) {
          print('⚠️ To\'g\'ri javob indeksi noto\'g\'ri, to\'g\'rilanmoqda');
          correctOptionIndex = 0;
        }

        final question = Question(
          text: currentQuestionText!,
          options: List.from(currentOptions),
          correctOptionIndex: correctOptionIndex!,
        );

        if (question.isValid()) {
          questions.add(question);
          print('📝 Savol ${questions.length}: ${_truncate(currentQuestionText!, 50)} '
              '[${currentOptions.length} variant, To\'g\'ri: ${correctOptionIndex! + 1}]');
        } else {
          print('⚠️ Noto\'g\'ri savol e\'tiborsiz qoldirildi: ${_truncate(currentQuestionText!, 30)}');
        }
      } else if (currentQuestionText != null) {
        print('⚠️ Savol kamida 2 ta variant bo\'lishi kerak: ${_truncate(currentQuestionText!, 30)} (${currentOptions.length} variant)');
      }

      // Reset state
      currentQuestionText = null;
      currentQuestionHint = null;
      currentOptions.clear();
      correctOptionIndex = null;
      inQuestion = false;
      expectingQuestionText = false;
      expectingOption = false;
      consecutiveEmptyLines = 0;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Skip truly empty lines but track them
      if (line.isEmpty) {
        consecutiveEmptyLines++;
        // If too many empty lines, might be end of question
        if (consecutiveEmptyLines > 2 && inQuestion && currentOptions.isNotEmpty) {
          finalizeQuestion();
        }
        continue;
      }

      consecutiveEmptyLines = 0;

      // Skip noise
      if (_isNoise(line)) {
        continue;
      }

      // STATE 1: Question token detected
      if (line == QuizTextNormalizer.questionToken) {
        // Finalize previous question if any
        if (inQuestion) {
          finalizeQuestion();
        }
        inQuestion = true;
        expectingQuestionText = true;
        expectingOption = false;
        continue;
      }

      // STATE 2: Option token detected
      if (line == QuizTextNormalizer.optionToken) {
        expectingOption = true;
        expectingQuestionText = false;
        continue;
      }

      // STATE 3: Correct marker detected
      if (line.startsWith(QuizTextNormalizer.correctMarker)) {
        final optionText = line.substring(1).trim();

        if (optionText.isNotEmpty && !_isNoise(optionText)) {
          // Mark this as correct option
          if (correctOptionIndex == null) {
            correctOptionIndex = currentOptions.length;
          } else {
            print('⚠️ Ikkinchi to\'g\'ri javob topildi, birinchisini saqlaymiz');
          }
          currentOptions.add(optionText);
        }
        expectingOption = false;
        continue;
      }

      // STATE 4: Expecting question text
      if (expectingQuestionText && currentQuestionText == null) {
        if (!_isToken(line) && !_isNoise(line)) {
          final (cleanQuestion, hint) = normalizer.extractCorrectAnswerHint(line);
          currentQuestionText = cleanQuestion;
          currentQuestionHint = hint;
          expectingQuestionText = false;
          print('   📄 Savol matni: ${_truncate(cleanQuestion, 60)}');
        }
        continue;
      }

      // STATE 5: Expecting option text
      if (expectingOption) {
        if (!_isToken(line) && !_isNoise(line)) {
          currentOptions.add(line);
          expectingOption = false;
          print('      ✓ Variant ${currentOptions.length}: ${_truncate(line, 40)}');
        }
        continue;
      }

      // STATE 6: We have question but no options yet - collect options
      if (inQuestion && currentQuestionText != null && currentOptions.isEmpty) {
        // Sometimes first option comes without ===== token
        if (!_isToken(line) && !_isNoise(line) && line.length < 300) {
          // Check if it's likely an option (shorter than question, no question mark)
          if (line.length < currentQuestionText!.length * 0.8 && !line.contains('?')) {
            currentOptions.add(line);
            print('      ✓ Variant ${currentOptions.length} (token siz): ${_truncate(line, 40)}');
          }
        }
        continue;
      }

      // STATE 7: Collecting more options
      if (inQuestion && currentQuestionText != null && currentOptions.isNotEmpty) {
        if (!_isToken(line) && !_isNoise(line) && currentOptions.length < 8) {
          // Add as option if reasonable length
          if (line.length < 300 && line.length > 1) {
            currentOptions.add(line);
            print('      ✓ Variant ${currentOptions.length} (davomi): ${_truncate(line, 40)}');
          }
        }
        continue;
      }

      // STATE 8: No active question, but this might be start of new question
      if (!inQuestion && !_isToken(line) && !_isNoise(line)) {
        // Check if it looks like a question
        if (line.contains('?') || line.length > 30) {
          inQuestion = true;
          final (cleanQuestion, hint) = normalizer.extractCorrectAnswerHint(line);
          currentQuestionText = cleanQuestion;
          currentQuestionHint = hint;
          print('   📄 Savol (token siz): ${_truncate(cleanQuestion, 60)}');
        }
      }
    }

    // Finalize last question
    if (inQuestion) {
      finalizeQuestion();
    }

    print('✅ Jami topilgan savollar: ${questions.length}');

    // Additional validation
    if (questions.length < 10) {
      print('⚠️ Ogohlantirish: Juda kam savol topildi (${questions.length} ta)');
    }

    return questions;
  }

  /// Check if a line is a token
  bool _isToken(String line) {
    return line == QuizTextNormalizer.questionToken ||
        line == QuizTextNormalizer.optionToken ||
        line.startsWith(QuizTextNormalizer.correctMarker);
  }

  /// Check if a line is noise/metadata - IMPROVED
  bool _isNoise(String line) {
    // Very short lines
    if (line.length < 2) return true;

    // Lines with only special characters
    if (RegExp(r'^[\s\-_\.\,\:\;\!\?\(\)\[\]\{\}\/\\]+$').hasMatch(line)) {
      return true;
    }

    // Lines that are just page numbers or similar
    if (RegExp(r'^\d+$').hasMatch(line) && line.length < 4) return true;

    // Lines with mostly numbers and spaces (metadata)
    final digitsAndSpaces =
        line.codeUnits.where((c) => (c >= 48 && c <= 57) || c == 32).length;
    if (digitsAndSpaces > line.length * 0.7 && line.length > 10) return true;

    // Lines with lots of non-printable or special unicode characters
    final weirdChars = line.codeUnits.where((c) =>
    c < 32 || (c > 126 && c < 1040) || c > 1200
    ).length;
    if (weirdChars > line.length * 0.3) return true;

    // Very long lines (likely corrupted data)
    if (line.length > 800) return true;

    // Lines that are just repeated characters
    if (RegExp(r'^(.)\1{5,}$').hasMatch(line)) return true;

    return false;
  }

  /// Truncate text for logging
  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// Parse quiz with automatic normalization
  Quiz parseRawText(String rawText) {
    print('📄 Xom matn uzunligi: ${rawText.length} belgi');

    final normalized = normalizer.normalizeQuizText(rawText);
    print('📄 Normallashtirilgan matn: ${normalized.length} belgi');

    // Debug: Count tokens
    final questionTokens = RegExp(r'\+{5}').allMatches(normalized).length;
    final optionTokens = RegExp(r'={5}').allMatches(normalized).length;
    final correctMarkers = normalized.split('#').length - 1;

    print('📊 Tokenlar: $questionTokens ta savol, $optionTokens ta variant, $correctMarkers ta # belgisi');

    // Show preview
    final preview = normalized.substring(
        0, normalized.length > 2000 ? 2000 : normalized.length);
    print('📄 Ko\'rinish (birinchi 2000 belgi):\n$preview\n---');

    return parseQuiz(normalized);
  }
}