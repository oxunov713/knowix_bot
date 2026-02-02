import 'dart:io';
import 'file_text_extractor_service.dart';
import 'quiz_text_normalizer.dart';
import 'quiz_parser_service.dart';
import '../models/quiz.dart';

/// High-level service for quiz operations with multi-format support
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
      print('🔄 Fayl qayta ishlanmoqda: ${file.path}');

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

      print('✅ Matn ajratildi: ${rawText.length} belgi');

      // Detect format
      final format = normalizer.detectQuizFormat(rawText);
      print('📋 Aniqlangan format: $format');

      if (format == 'unknown') {
        throw FormatException(
            'Faylda test formati topilmadi!\n\n'
                'Qo\'llab-quvvatlanuvchi formatlar:\n\n'
                '1️⃣ Raqamli format:\n'
                '1. Savol matni?\n'
                '# To\'g\'ri javob\n'
                '- Noto\'g\'ri variant 1\n'
                '- Noto\'g\'ri variant 2\n\n'
                '2️⃣ Hemis format:\n'
                '+++++ Savol matni\n'
                '===== Variant 1\n'
                '===== #To\'g\'ri javob\n'
                '===== Variant 3'
        );
      }

      print('✅ Format aniqlandi: $format');

      // Parse the quiz with error handling
      final quiz = parser.parseRawText(rawText);

      if (quiz.questions.isEmpty) {
        throw FormatException('Faylda to\'g\'ri formatdagi savollar topilmadi');
      }

      // Validate quiz
      if (!validateQuiz(quiz)) {
        throw FormatException('Quiz validatsiyadan o\'tmadi');
      }

      print('✅ Quiz muvaffaqiyatli parse qilindi: ${quiz.questions.length} ta savol');
      return quiz;

    } on TimeoutException catch (e) {
      print('❌ Timeout xatosi: $e');
      throw FormatException('Fayl qayta ishlash juda uzoq davom etdi. Kichikroq fayl yuboring.');
    } on FormatException catch (e) {
      print('❌ Format xatosi: $e');
      rethrow;
    } catch (e, stack) {
      print('❌ Kutilmagan xatolik: $e');
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

      final format = normalizer.detectQuizFormat(rawText);

      if (format == 'unknown') {
        throw FormatException(
            'Matndagi test formati noto\'g\'ri!\n\n'
                'Qo\'llab-quvvatlanuvchi formatlar:\n\n'
                '1️⃣ Raqamli format:\n'
                '1. Savol?\n'
                '# To\'g\'ri javob\n'
                '- Noto\'g\'ri variant\n\n'
                '2️⃣ Hemis format:\n'
                '+++++ Savol\n'
                '===== Variant\n'
                '===== #To\'g\'ri'
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
      print('❌ processText xatosi: $e');
      rethrow;
    }
  }

  /// Validate a quiz with detailed checks
  bool validateQuiz(Quiz quiz) {
    if (quiz.questions.isEmpty) {
      print('⚠️ Validatsiya muvaffaqiyatsiz: Savollar yo\'q');
      return false;
    }

    for (var i = 0; i < quiz.questions.length; i++) {
      final question = quiz.questions[i];

      if (question.text.isEmpty) {
        print('⚠️ Validatsiya muvaffaqiyatsiz: Savol $i matni bo\'sh');
        return false;
      }

      if (question.options.length < 2) {
        print('⚠️ Validatsiya muvaffaqiyatsiz: Savol $i da 2 tadan kam variant');
        return false;
      }

      if (question.correctOptionIndex < 0 ||
          question.correctOptionIndex >= question.options.length) {
        print('⚠️ Validatsiya muvaffaqiyatsiz: Savol $i da noto\'g\'ri javob indeksi');
        return false;
      }

      for (var opt in question.options) {
        if (opt.isEmpty) {
          print('⚠️ Validatsiya muvaffaqiyatsiz: Savol $i da bo\'sh variant');
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

  /// Get format info for user
  String getFormatInfo() {
    return '''
📋 Qo'llab-quvvatlanuvchi formatlar:

1️⃣ RAQAMLI FORMAT (yangi):
━━━━━━━━━━━━━━━━━━━━━
1. Birinchi savol matni?
# To'g'ri javob
- Noto'g'ri variant 1
- Noto'g'ri variant 2
- Noto'g'ri variant 3

2. Ikkinchi savol matni?
# To'g'ri javob
- Noto'g'ri variant 1
- Noto'g'ri variant 2

2️⃣ HEMIS FORMAT (eski):
━━━━━━━━━━━━━━━━━━━━━
+++++ Birinchi savol matni
===== Variant 1
===== #To'g'ri javob
===== Variant 3
===== Variant 4

+++++ Ikkinchi savol matni
===== Variant 1
===== Variant 2
===== #To'g'ri javob

💡 Eslatma:
• Raqamli formatda # - to'g'ri javob, - - noto'g'ri javob
• Hemis formatda # - to'g'ri javobni belgilaydi
• Har ikki format ham qo'llab-quvvatlanadi!
''';
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}