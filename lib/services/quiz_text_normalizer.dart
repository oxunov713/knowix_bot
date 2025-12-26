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

    // STEP 1: Inject newlines around question token (+++++)
    // Replace any whitespace before/after with single newline
    normalized = normalized.replaceAllMapped(
      RegExp(r'\s*\+{5}\s*'),
          (match) => '\n$questionToken\n',
    );

    // STEP 2: Inject newlines around option token (=====)
    // Replace any whitespace before/after with single newline
    normalized = normalized.replaceAllMapped(
      RegExp(r'\s*={5}\s*'),
          (match) => '\n$optionToken\n',
    );

    // STEP 3: Handle correct marker (#)
    // Only inject newlines for # that appears at start of option (answer marker)
    // We need to be careful: # inside text should not trigger newlines
    // Strategy: Add newline before # that follows whitespace or option token
    normalized = normalized.replaceAllMapped(
      RegExp(r'(\n|^)\s*#'),
          (match) => '\n$correctMarker',
    );

    // STEP 4: Collapse multiple consecutive newlines into single newline
    normalized = normalized.replaceAll(RegExp(r'\n\s*\n+'), '\n');

    // STEP 5: Collapse multiple spaces into single space (but preserve newlines)
    normalized = normalized.replaceAllMapped(
      RegExp(r'[^\S\n]+'),
          (match) => ' ',
    );

    // STEP 6: Trim each line
    final lines = normalized.split('\n');
    normalized = lines.map((line) => line.trim()).join('\n');

    // STEP 7: Remove leading/trailing newlines
    normalized = normalized.trim();

    return normalized;
  }

  /// Check if text contains quiz tokens
  bool hasQuizTokens(String text) {
    return text.contains(questionToken) ||
        text.contains(optionToken) ||
        text.contains(correctMarker);
  }

  /// Validate that text has minimum required structure
  bool hasMinimumStructure(String text) {
    // Should have at least one option token and one correct marker
    return text.contains(optionToken) && text.contains(correctMarker);
  }
}