import 'dart:io';
import 'file_text_extractor_service.dart';
import 'quiz_text_normalizer.dart';
import 'quiz_parser_service.dart';
import '../models/quiz.dart';

/// High-level service for quiz operations
class QuizService {
  final FileTextExtractorService extractor;
  final QuizTextNormalizer normalizer;
  final QuizParserService parser;

  QuizService()
      : extractor = FileTextExtractorService(),
        normalizer = QuizTextNormalizer(),
        parser = QuizParserService(QuizTextNormalizer());

  /// Process a file and return a Quiz object
  Future<Quiz> processFile(File file) async {
    // Extract text from file
    final rawText = await extractor.extractText(file);

    // Check if text contains quiz tokens
    if (!normalizer.hasQuizTokens(rawText)) {
      throw FormatException(
          'File does not contain valid quiz format. '
              'Expected tokens: +++++ (question), ===== (option), # (correct answer)'
      );
    }

    // Parse the quiz
    return parser.parseRawText(rawText);
  }

  /// Process raw text and return a Quiz object
  Quiz processText(String rawText) {
    if (!normalizer.hasQuizTokens(rawText)) {
      throw FormatException(
          'Text does not contain valid quiz format. '
              'Expected tokens: +++++ (question), ===== (option), # (correct answer)'
      );
    }

    return parser.parseRawText(rawText);
  }

  /// Validate a quiz
  bool validateQuiz(Quiz quiz) {
    return quiz.isValid;
  }

  /// Check if file is supported
  bool isSupportedFile(String filename) {
    return extractor.isSupportedFileType(filename);
  }
}