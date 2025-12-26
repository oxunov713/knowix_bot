/// Service for normalizing quiz text by injecting newlines around tokens
/// This is STAGE 1 of the two-stage parsing strategy
class QuizTextNormalizer {
  // Quiz format tokens
  static const String questionToken = '+++++';
  static const String optionToken = '=====';
  static const String correctMarker = '#';

  /// Normalize quiz text by injecting newlines around tokens
  String normalizeQuizText(String rawText) {
    if (rawText.isEmpty) return '';

    String normalized = rawText;

    print('📝 Normalizatsiya boshlandi: ${normalized.length} belgi');

    // STEP 0: Fix common encoding issues first
    normalized = _fixEncodingIssues(normalized);

    // STEP 1: Normalize line endings
    normalized = normalized.replaceAll('\r\n', '\n');
    normalized = normalized.replaceAll('\r', '\n');

    // STEP 2: Remove university metadata and headers (birinchi bir necha qator)
    normalized = _removeMetadata(normalized);

    // STEP 3: Inject newlines around question token (++++)
    // 4 yoki 5 ta + belgisini qidirish
    normalized = normalized.replaceAllMapped(
      RegExp(r'\s*\+{4,5}\s*'),
          (match) => '\n$questionToken\n',
    );

    // STEP 4: Inject newlines around option token (====)
    // 4 yoki 5 ta = belgisini qidirish
    normalized = normalized.replaceAllMapped(
      RegExp(r'\s*={4,5}\s*'),
          (match) => '\n$optionToken\n',
    );

    // STEP 5: Handle correct marker (#) carefully
    // Pattern 1: # at start of line followed by text
    normalized = normalized.replaceAllMapped(
      RegExp(r'^\s*#\s*([^\n]+)', multiLine: true),
          (match) {
        final optionText = match.group(1)?.trim() ?? '';
        return '$correctMarker$optionText';
      },
    );

    // Pattern 2: # in middle of text (e.g., after option token)
    normalized = normalized.replaceAllMapped(
      RegExp(r'($optionToken)\s*#\s*([^\n]+)'),
          (match) {
        final optionText = match.group(2)?.trim() ?? '';
        return '${match.group(1)}\n$correctMarker$optionText';
      },
    );

    // STEP 6: Remove inline correct answer hints from questions
    // Pattern: "++++ Question text #to'g'ri javob X ===="
    normalized = normalized.replaceAllMapped(
      RegExp(r'($questionToken[^\+\=]*?)#[^=\+\n]*?($optionToken)',
          multiLine: true,
          dotAll: true),
          (match) {
        return '${match.group(1)}\n${match.group(2)}';
      },
    );

    // STEP 7: Clean up variant labels (A), B), C), D) or A. B. C. D.)
    // Bu label-larni olib tashlaymiz, chunki ular Telegramda keraksiz
    normalized = normalized.replaceAllMapped(
      RegExp(r'^([A-Da-d][\)\.])\s*', multiLine: true),
          (match) => '',
    );

    // STEP 8: Collapse multiple consecutive newlines
    normalized = normalized.replaceAll(RegExp(r'\n\s*\n+'), '\n');

    // STEP 9: Collapse multiple spaces into single space
    normalized = normalized.replaceAllMapped(
      RegExp(r'[^\S\n]+'),
          (match) => ' ',
    );

    // STEP 10: Trim each line
    final lines = normalized.split('\n');
    normalized = lines.map((line) => line.trim()).join('\n');

    // STEP 11: Remove leading/trailing newlines
    normalized = normalized.trim();

    print('📝 Normalizatsiya tugadi: ${normalized.length} belgi');

    return normalized;
  }

  /// Remove university metadata and headers
  String _removeMetadata(String text) {
    final lines = text.split('\n');
    final cleanLines = <String>[];
    bool foundFirstQuestion = false;

    for (final line in lines) {
      // Agar birinchi savol topilsa, barcha qatorlarni qo'shamiz
      if (foundFirstQuestion) {
        cleanLines.add(line);
        continue;
      }

      // Birinchi savol belgisini qidiramiz
      if (line.contains(RegExp(r'\+{4,5}'))) {
        foundFirstQuestion = true;
        cleanLines.add(line);
        continue;
      }

      // Metadatani o'tkazib yuboramiz
      if (_isMetadata(line)) {
        continue;
      }

      // Agar savol boshlanmagan bo'lsa, potentsial metadatani o'tkazib yuboramiz
      if (!foundFirstQuestion && line.trim().isNotEmpty) {
        if (line.length < 100 && !line.contains('?')) {
          continue;
        }
      }

      cleanLines.add(line);
    }

    return cleanLines.join('\n');
  }

  /// Check if line is metadata
  bool _isMetadata(String line) {
    final lowerLine = line.toLowerCase().trim();

    // Bo'sh qator
    if (lowerLine.isEmpty) return true;

    // Universitet nomlari
    if (lowerLine.contains('universitet') ||
        lowerLine.contains('institute') ||
        lowerLine.contains('university')) return true;

    // Sana va vaqt
    if (RegExp(r'\d{1,2}[./-]\d{1,2}[./-]\d{2,4}').hasMatch(lowerLine)) return true;

    // Kurs, guruh va boshqa ma'lumotlar
    if (lowerLine.contains('kurs') ||
        lowerLine.contains('guruh') ||
        lowerLine.contains('group') ||
        lowerLine.contains('kafedra') ||
        lowerLine.contains('department')) return true;

    // Test raqami, variant
    if (RegExp(r'(test|variant|versiya)\s*[№#:]\s*\d+', caseSensitive: false)
        .hasMatch(lowerLine)) return true;

    // Juda qisqa qatorlar (3 so'zdan kam)
    if (lowerLine.split(RegExp(r'\s+')).length < 3) return true;

    return false;
  }

  /// Fix common encoding issues in text
  String _fixEncodingIssues(String text) {
    var result = text;

    // Fix Cyrillic quotes and apostrophes
    result = result.replaceAll('â', "'");
    result = result.replaceAll('Â«', '"');
    result = result.replaceAll('Â»', '"');
    result = result.replaceAll('`', "'");
    result = result.replaceAll(''', "'");
    result = result.replaceAll(''', "'");
    result = result.replaceAll('"', '"');
    result = result.replaceAll('"', '"');

    // Fix specific Uzbek words
    result = result.replaceAll('toâgâri', "to'g'ri");
    result = result.replaceAll('togâri', "to'g'ri");
    result = result.replaceAll('toʻgʻri', "to'g'ri");
    result = result.replaceAll('oâ', "o'");
    result = result.replaceAll('gâ', "g'");
    result = result.replaceAll('oʻ', "o'");
    result = result.replaceAll('gʻ', "g'");

    return result;
  }

  /// Check if text contains quiz tokens
  bool hasQuizTokens(String text) {
    return RegExp(r'\+{4,5}').hasMatch(text) ||
        RegExp(r'={4,5}').hasMatch(text) ||
        text.contains(correctMarker);
  }

  /// Validate that text has minimum required structure
  bool hasMinimumStructure(String text) {
    return RegExp(r'\+{4,5}').hasMatch(text) &&
        RegExp(r'={4,5}').hasMatch(text);
  }

  /// Extract correct answer hint from question text if present
  (String cleanQuestion, String? hint) extractCorrectAnswerHint(String questionText) {
    if (!questionText.contains('#')) {
      return (questionText, null);
    }

    final parts = questionText.split('#');
    if (parts.length < 2) {
      return (questionText, null);
    }

    final cleanQuestion = parts[0].trim();
    final hint = parts.sublist(1).join('#').trim();

    return (cleanQuestion, hint);
  }

  /// Try to parse correct answer from hint text
  int? parseCorrectAnswerFromHint(String hint, int optionCount) {
    final lowerHint = hint.toLowerCase();

    // Pattern 1: Single letter (a, b, c, d or Cyrillic а, б, в, г)
    final letterMatch = RegExp(r'\b([a-d]|[а-г])\b', caseSensitive: false)
        .firstMatch(lowerHint);
    if (letterMatch != null) {
      final letter = letterMatch.group(1)!.toLowerCase();
      final letterMap = {
        'a': 0, 'а': 0,
        'b': 1, 'б': 1,
        'c': 2, 'в': 2,
        'd': 3, 'г': 3,
      };
      final index = letterMap[letter];
      if (index != null && index < optionCount) {
        return index;
      }
    }

    // Pattern 2: Number (1, 2, 3, 4)
    final numberMatch = RegExp(r'\b([1-4])\b').firstMatch(lowerHint);
    if (numberMatch != null) {
      final number = int.parse(numberMatch.group(1)!);
      final index = number - 1;
      if (index >= 0 && index < optionCount) {
        return index;
      }
    }

    return null;
  }
}