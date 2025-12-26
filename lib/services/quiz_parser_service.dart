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

  /// Parse questions using improved state machine approach
  List<Question> _parseQuestions(String text) {
    final questions = <Question>[];
    final lines = text.split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    print('📊 Jami qatorlar: ${lines.length}');

    String? currentQuestionText;
    String? currentQuestionHint;
    final currentOptions = <String>[];
    int? correctOptionIndex;
    bool expectingQuestionText = false;
    bool expectingOption = false;

    void finalizeQuestion() {
      if (currentQuestionText != null && currentOptions.length >= 2) {

        // MUHIM: Agar hech qanday to'g'ri javob belgilanmagan bo'lsa,
        // birinchi variantni to'g'ri deb belgilash
        if (correctOptionIndex == null) {
          // Hint dan topishga harakat
          if (currentQuestionHint != null) {
            correctOptionIndex = normalizer.parseCorrectAnswerFromHint(
              currentQuestionHint!,
              currentOptions.length,
            );
          }

          // Hali ham topilmasa, birinchi variantni tanlash
          if (correctOptionIndex == null) {
            print('⚠️ To\'g\'ri javob topilmadi, birinchi variantni tanlaymiz: '
                '${currentQuestionText!.substring(0, currentQuestionText!.length > 50 ? 50 : currentQuestionText!.length)}...');
            correctOptionIndex = 0;
          }
        }

        final question = Question(
          text: currentQuestionText!,
          options: List.from(currentOptions),
          correctOptionIndex: correctOptionIndex!,
        );

        if (question.isValid()) {
          questions.add(question);
          print('📝 Savol ${questions.length}: ${currentQuestionText!.substring(0, currentQuestionText!.length > 50 ? 50 : currentQuestionText!.length)}... [To\'g\'ri: ${correctOptionIndex! + 1}]');
        } else {
          print('⚠️ Noto\'g\'ri savol e\'tiborsiz qoldirildi');
        }
      }

      // Reset state
      currentQuestionText = null;
      currentQuestionHint = null;
      currentOptions.clear();
      correctOptionIndex = null;
      expectingQuestionText = false;
      expectingOption = false;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Skip empty and noise
      if (line.isEmpty || _isNoise(line)) {
        continue;
      }

      // STATE 1: Question token detected
      if (line == QuizTextNormalizer.questionToken) {
        finalizeQuestion();
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

      // STATE 3: Correct marker (standalone or inline)
      if (line.startsWith(QuizTextNormalizer.correctMarker)) {
        final optionText = line.substring(1).trim();

        if (optionText.isNotEmpty && !_isNoise(optionText)) {
          if (correctOptionIndex == null) {
            correctOptionIndex = currentOptions.length;
          } else {
            print('⚠️ Bir nechta to\'g\'ri javob topildi, birinchisini ishlatamiz');
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
        }
        continue;
      }

      // STATE 5: Expecting option text
      if (expectingOption) {
        if (!_isToken(line) && !_isNoise(line)) {
          currentOptions.add(line);
          expectingOption = false;
        }
        continue;
      }

      // STATE 6: Heuristic - if we have a question but no options yet,
      // and this line looks like an option, treat it as one
      if (currentQuestionText != null && currentOptions.isEmpty) {
        if (!_isToken(line) && !_isNoise(line) && line.length < 200) {
          currentOptions.add(line);
        }
        continue;
      }

      // STATE 7: Continue adding options if we're in a question
      if (currentQuestionText != null && currentOptions.isNotEmpty) {
        if (!_isToken(line) && !_isNoise(line) && currentOptions.length < 6) {
          currentOptions.add(line);
        }
        continue;
      }

      // STATE 8: Start new question if we see question-like text
      if (currentQuestionText == null && !_isToken(line) && !_isNoise(line)) {
        // Check if it looks like a question
        if (line.contains('?') || line.length > 20) {
          final (cleanQuestion, hint) = normalizer.extractCorrectAnswerHint(line);
          currentQuestionText = cleanQuestion;
          currentQuestionHint = hint;
        }
      }
    }

    // Finalize last question
    finalizeQuestion();

    print('✅ Jami topilgan savollar: ${questions.length}');
    return questions;
  }

  /// Check if a line is a token
  bool _isToken(String line) {
    return line == QuizTextNormalizer.questionToken ||
        line == QuizTextNormalizer.optionToken ||
        line == QuizTextNormalizer.correctMarker;
  }

  /// Check if a line is noise/metadata
  bool _isNoise(String line) {
    // Very short lines
    if (line.length < 2) return true;

    // Lines with only special characters
    if (RegExp(r'^[\s\-_\.\,\:\;\!\?\(\)\[\]\{\}]+$').hasMatch(line)) return true;

    // Lines with lots of numbers and spaces (likely metadata)
    final digitsAndSpaces = line.codeUnits.where((c) =>
    (c >= 48 && c <= 57) || c == 32).length;
    if (digitsAndSpaces > line.length * 0.7 && line.length > 10) return true;

    // Lines with lots of non-printable characters
    final nonPrintable = line.codeUnits.where((c) => c < 32 || c > 126).length;
    if (nonPrintable > line.length * 0.3) return true;

    // Very long lines (likely binary data)
    if (line.length > 500) return true;

    return false;
  }

  /// Parse quiz with automatic normalization
  Quiz parseRawText(String rawText) {
    print('📄 Xom matn uzunligi: ${rawText.length} belgi');

    final normalized = normalizer.normalizeQuizText(rawText);
    print('📄 Normallashtirilgan matn: ${normalized.length} belgi');

    // Debug: Print first 1000 characters
    final preview = normalized.substring(
        0, normalized.length > 1000 ? 1000 : normalized.length);
    print('📄 Ko\'rinish:\n$preview\n---');

    return parseQuiz(normalized);
  }
}