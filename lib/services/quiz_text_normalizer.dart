/// Service for normalizing quiz text by injecting newlines around tokens
/// This is STAGE 1 of the two-stage parsing strategy
class QuizTextNormalizer {
  // Quiz format tokens
  static const String questionToken = '+++++';
  static const String optionToken = '=====';
  static const String correctMarker = '#';

  /// Normalize quiz text by injecting newlines around tokens
  /// This ensures consistent line-based structure regardless of original formatting
  String normalizeQuizText(String rawText) {
    if (rawText.isEmpty) return '';

    String normalized = rawText;

    // STEP 0: Fix common encoding issues first
    normalized = _fixEncodingIssues(normalized);

    // STEP 1: Handle inline correct answer markers in questions
    // Pattern: "++++ Question text #to'g'ri javob X ==== option"
    // We need to remove the "#to'g'ri javob X" part from questions
    normalized = normalized.replaceAllMapped(
      RegExp(r'(\+{5}[^\+\=]*?)#[^=\+]*?(={5})', multiLine: true),
          (match) {
        // Keep the question token and first option token, remove the # marker part
        return '${match.group(1)}\n${match.group(2)}';
      },
    );

    // STEP 2: Inject newlines around question token (+++++)
    // Replace any whitespace before/after with single newline
    normalized = normalized.replaceAllMapped(
      RegExp(r'\s*\+{5}\s*'),
          (match) => '\n$questionToken\n',
    );

    // STEP 3: Inject newlines around option token (=====)
    // Replace any whitespace before/after with single newline
    normalized = normalized.replaceAllMapped(
      RegExp(r'\s*={5}\s*'),
          (match) => '\n$optionToken\n',
    );

    // STEP 4: Handle correct marker (#) that appears at start of option
    // Pattern 1: Standalone # followed by text
    normalized = normalized.replaceAllMapped(
      RegExp(r'\n\s*#\s*([^\n]+)'),
          (match) {
        final optionText = match.group(1)?.trim() ?? '';
        return '\n$correctMarker\n$optionText';
      },
    );

    // Pattern 2: # at very beginning of text
    normalized = normalized.replaceAllMapped(
      RegExp(r'^\s*#\s*([^\n]+)'),
          (match) {
        final optionText = match.group(1)?.trim() ?? '';
        return '$correctMarker\n$optionText';
      },
    );

    // STEP 5: Collapse multiple consecutive newlines into single newline
    normalized = normalized.replaceAll(RegExp(r'\n\s*\n+'), '\n');

    // STEP 6: Collapse multiple spaces into single space (but preserve newlines)
    normalized = normalized.replaceAllMapped(
      RegExp(r'[^\S\n]+'),
          (match) => ' ',
    );

    // STEP 7: Trim each line
    final lines = normalized.split('\n');
    normalized = lines.map((line) => line.trim()).join('\n');

    // STEP 8: Remove leading/trailing newlines
    normalized = normalized.trim();

    return normalized;
  }

  /// Fix common encoding issues in text
  String _fixEncodingIssues(String text) {
    var result = text;

    // Fix Cyrillic quotes and apostrophes
    result = result.replaceAll('â', "'");
    result = result.replaceAll('Â«', '"');
    result = result.replaceAll('Â»', '"');
    result = result.replaceAll('`', "'");

    // Fix specific Uzbek words
    result = result.replaceAll('toâgâri', "to'g'ri");
    result = result.replaceAll('togâri', "to'g'ri");
    result = result.replaceAll('oâ', "o'");
    result = result.replaceAll('gâ', "g'");

    // Normalize line endings
    result = result.replaceAll('\r\n', '\n');
    result = result.replaceAll('\r', '\n');

    return result;
  }

  /// Check if text contains quiz tokens
  bool hasQuizTokens(String text) {
    return text.contains(questionToken) ||
        text.contains(optionToken) ||
        text.contains(correctMarker);
  }

  /// Validate that text has minimum required structure
  bool hasMinimumStructure(String text) {
    // Should have at least one question token and one option token
    return text.contains(questionToken) && text.contains(optionToken);
  }

  /// Extract correct answer hint from question text if present
  /// Returns cleaned question text and extracted hint
  (String cleanQuestion, String? hint) extractCorrectAnswerHint(String questionText) {
    if (!questionText.contains('#')) {
      return (questionText, null);
    }

    final parts = questionText.split('#');
    if (parts.length < 2) {
      return (questionText, null);
    }

    final cleanQuestion = parts[0].trim();
    final hint = parts[1].trim();

    return (cleanQuestion, hint);
  }

  /// Try to parse correct answer from hint text
  /// Examples: "to'g'ri javob b", "correct: C", "answer is 2"
  int? parseCorrectAnswerFromHint(String hint, int optionCount) {
    final lowerHint = hint.toLowerCase();

    // Pattern 1: Single letter (a, b, c, d or Cyrillic а, б, в, г)
    final letterMatch = RegExp(r'\b([a-d]|[а-г])\b', caseSensitive: false).firstMatch(lowerHint);
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
      final index = number - 1; // Convert to 0-based index
      if (index >= 0 && index < optionCount) {
        return index;
      }
    }

    // Pattern 3: "b va v" or "b and c" - multiple answers, take first
    final multiMatch = RegExp(r'\b([a-d]|[а-г])\b.*?\b(va|and|,)\b.*?\b([a-d]|[а-г])\b',
        caseSensitive: false).firstMatch(lowerHint);
    if (multiMatch != null) {
      print('⚠️ Multiple correct answers detected in hint: "$hint" - using first option');
      final letter = multiMatch.group(1)!.toLowerCase();
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

    return null;
  }
}