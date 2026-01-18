import 'dart:io';
import 'file_text_extractor_service.dart';
import 'quiz_text_normalizer.dart';
import 'quiz_parser_service.dart';
import '../models/quiz.dart';

/// High-level service for quiz operations with error handling
class QuizService {
  final FileTextExtractorService extractor;
  final QuizTextNormalizer normalizer;
  final QuizParserService parser;

  QuizService()
      : extractor = FileTextExtractorService(),
        normalizer = QuizTextNormalizer(),
        parser = QuizParserService(QuizTextNormalizer());

  /// Process a file and return a Quiz object with robust error handling
  Future<Quiz> processFile(File file) async {
    try {
      print('🔄 Processing file: ${file.path}');

      // Extract text from file with timeout
      final rawText = await extractor.extractText(file).timeout(
        Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Fayl o\'qish juda ko\'p vaqt oldi (30s limit)');
        },
      );

      if (rawText.isEmpty) {
        throw FormatException('Fayl bo\'sh yoki o\'qib bo\'lmadi');
      }

      print('✅ Text extracted: ${rawText.length} characters');

      // Check if text contains quiz tokens
      if (!normalizer.hasQuizTokens(rawText)) {
        throw FormatException(
            'Faylda test formati topilmadi!\n\n'
                'Kerakli formatlar:\n'
                '+++++ (savol belgisi)\n'
                '===== (variant belgisi)\n'
                '# (to\'g\'ri javob belgisi)'
        );
      }

      print('✅ Quiz tokens detected');

      // Parse the quiz with error handling
      final quiz = parser.parseRawText(rawText);

      if (quiz.questions.isEmpty) {
        throw FormatException('Faylda to\'g\'ri formatdagi savollar topilmadi');
      }

      // Validate quiz
      if (!validateQuiz(quiz)) {
        throw FormatException('Quiz validatsiyadan o\'tmadi');
      }

      print('✅ Quiz parsed successfully: ${quiz.questions.length} questions');
      return quiz;

    } on TimeoutException catch (e) {
      print('❌ Timeout error: $e');
      throw FormatException('Fayl qayta ishlash juda uzoq davom etdi. Kichikroq fayl yuboring.');
    } on FormatException catch (e) {
      print('❌ Format error: $e');
      rethrow;
    } catch (e, stack) {
      print('❌ Unexpected error in processFile: $e');
      print('Stack trace: $stack');
      throw Exception('Faylni qayta ishlashda kutilmagan xatolik: ${e.toString()}');
    }
  }

  /// Process raw text and return a Quiz object
  Quiz processText(String rawText) {
    try {
      if (rawText.isEmpty) {
        throw FormatException('Matn bo\'sh');
      }

      if (!normalizer.hasQuizTokens(rawText)) {
        throw FormatException(
            'Matndagi test formati noto\'g\'ri!\n\n'
                'Kerakli formatlar:\n'
                '+++++ (savol)\n'
                '===== (variant)\n'
                '# (to\'g\'ri javob)'
        );
      }

      final quiz = parser.parseRawText(rawText);

      if (quiz.questions.isEmpty) {
        throw FormatException('Matndagi savollar topilmadi');
      }

      if (!validateQuiz(quiz)) {
        throw FormatException('Quiz noto\'g\'ri tuzilgan');
      }

      return quiz;
    } catch (e) {
      print('❌ Error in processText: $e');
      rethrow;
    }
  }

  /// Validate a quiz with detailed checks
  bool validateQuiz(Quiz quiz) {
    if (quiz.questions.isEmpty) {
      print('⚠️ Validation failed: No questions');
      return false;
    }

    for (var i = 0; i < quiz.questions.length; i++) {
      final question = quiz.questions[i];

      if (question.text.isEmpty) {
        print('⚠️ Validation failed: Question $i has empty text');
        return false;
      }

      if (question.options.length < 2) {
        print('⚠️ Validation failed: Question $i has less than 2 options');
        return false;
      }

      if (question.correctOptionIndex < 0 ||
          question.correctOptionIndex >= question.options.length) {
        print('⚠️ Validation failed: Question $i has invalid correct index');
        return false;
      }

      for (var opt in question.options) {
        if (opt.isEmpty) {
          print('⚠️ Validation failed: Question $i has empty option');
          return false;
        }
      }
    }

    return true;
  }

  /// Check if file is supported
  bool isSupportedFile(String filename) {
    return extractor.isSupportedFileType(filename);
  }

  /// Get supported file extensions
  List<String> getSupportedExtensions() {
    return ['.txt', '.doc', '.docx'];
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}