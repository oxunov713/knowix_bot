/// Service for normalizing quiz text - IMPROVED VERSION
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

    // STEP 2: Remove university metadata and headers
    normalized = _removeMetadata(normalized);

    // STEP 3: Inject newlines around question token (++++)
    // MUHIM: Har xil variantlarni qo'llab-quvvatlash
    normalized = normalized.replaceAllMapped(
      RegExp(r'(\+{4,})'),
          (match) {
        final plusCount = match.group(0)!.length;
        // 4 yoki 5 ta + ni standart formatga keltirish
        return '\n$questionToken\n';
      },
    );

    // STEP 4: Inject newlines around option token (====)
    normalized = normalized.replaceAllMapped(
      RegExp(r'(={4,})'),
          (match) {
        return '\n$optionToken\n';
      },
    );

    // STEP 5: Handle correct marker (#) more carefully
    // Pattern 1: ===== #Variant - bu eng keng tarqalgan format
    normalized = normalized.replaceAllMapped(
      RegExp(r'($optionToken)\s*#\s*([^\n]+)', multiLine: true),
          (match) {
        final optionText = match.group(2)?.trim() ?? '';
        if (optionText.isNotEmpty) {
          return '${match.group(1)}\n$correctMarker$optionText';
        }
        return match.group(0)!;
      },
    );

    // Pattern 2: # at start of line
    normalized = normalized.replaceAllMapped(
      RegExp(r'^\s*#\s*([^\n]+)', multiLine: true),
          (match) {
        final optionText = match.group(1)?.trim() ?? '';
        if (optionText.isNotEmpty && !_isToken(optionText)) {
          return '$correctMarker$optionText';
        }
        return match.group(0)!;
      },
    );

    // STEP 6: Remove inline correct answer hints from questions
    // +++++ Question text #javob X ===== -> +++++ Question text \n =====
    normalized = normalized.replaceAllMapped(
      RegExp(
        r'($questionToken[^\+\=]*?)#[^=\+\n]*?($optionToken)',
        multiLine: true,
        dotAll: true,
      ),
          (match) {
        return '${match.group(1)?.trim()}\n${match.group(2)}';
      },
    );

    // STEP 7: Clean up variant labels MORE CAREFULLY
    // Faqat ===== dan keyin kelgan A), B), C), D) ni olib tashlash
    normalized = normalized.replaceAllMapped(
      RegExp(r'($optionToken)\s*\n\s*([A-Da-dА-Га-г][\)\.])\s*([^\n]+)',
          multiLine: true),
          (match) {
        final content = match.group(3)?.trim() ?? '';
        return '${match.group(1)}\n$content';
      },
    );

    // STEP 8: Handle cases where question and first option are on same line
    // +++++ Question? ===== Option1
    normalized = normalized.replaceAllMapped(
      RegExp(r'($questionToken)([^\n]+)($optionToken)', multiLine: true),
          (match) {
        final questionText = match.group(2)?.trim() ?? '';
        if (questionText.isNotEmpty) {
          return '${match.group(1)}\n$questionText\n${match.group(3)}';
        }
        return match.group(0)!;
      },
    );

    // STEP 9: Handle cases where options are on same line
    // ===== Option1 ===== Option2
    normalized = normalized.replaceAllMapped(
      RegExp(r'($optionToken)([^\n]+?)($optionToken)', multiLine: true),
          (match) {
        final optionText = match.group(2)?.trim() ?? '';
        if (optionText.isNotEmpty) {
          return '${match.group(1)}\n$optionText\n${match.group(3)}';
        }
        return match.group(0)!;
      },
    );

    // STEP 10: Fix cases where # is separated from option token
    // ===== \n # Option -> ===== \n #Option
    normalized = normalized.replaceAllMapped(
      RegExp(r'($optionToken)\s*\n\s*#\s*([^\n]+)', multiLine: true),
          (match) {
        final optionText = match.group(2)?.trim() ?? '';
        return '${match.group(1)}\n$correctMarker$optionText';
      },
    );

    // STEP 11: Collapse multiple consecutive newlines (but keep at least one)
    normalized = normalized.replaceAll(RegExp(r'\n\s*\n+'), '\n');

    // STEP 12: Collapse multiple spaces into single space
    normalized = normalized.replaceAllMapped(
      RegExp(r'[^\S\n]+'),
          (match) => ' ',
    );

    // STEP 13: Trim each line
    final lines = normalized.split('\n');
    normalized = lines.map((line) => line.trim()).where((line) => line.isNotEmpty).join('\n');

    // STEP 14: Remove leading/trailing newlines
    normalized = normalized.trim();

    // STEP 15: Final validation - ensure we have proper structure
    final questionCount = RegExp(r'\n\+{5}\n').allMatches(normalized).length;
    print('📝 Normalizatsiya tugadi: ${normalized.length} belgi, ~$questionCount ta savol');

    return normalized;
  }

  /// Remove university metadata and headers - IMPROVED
  String _removeMetadata(String text) {
    final lines = text.split('\n');
    final cleanLines = <String>[];
    bool foundFirstQuestion = false;
    int headerLineCount = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Skip empty lines
      if (line.isEmpty) continue;

      // Check if this is the first question marker
      if (line.contains(RegExp(r'\+{4,}'))) {
        foundFirstQuestion = true;
        cleanLines.add(line);
        continue;
      }

      // If we found first question, add all subsequent lines
      if (foundFirstQuestion) {
        cleanLines.add(line);
        continue;
      }

      // Before first question, filter out metadata
      if (!foundFirstQuestion) {
        headerLineCount++;

        // Skip obvious metadata (first 50 lines)
        if (headerLineCount <= 50 && _isMetadata(line)) {
          continue;
        }

        // If line looks like part of a question, keep it
        if (line.length > 20 || line.contains('?') || line.contains(RegExp(r'={4,}'))) {
          cleanLines.add(line);
        }
      }
    }

    return cleanLines.join('\n');
  }

  /// Check if line is metadata - IMPROVED
  bool _isMetadata(String line) {
    final lowerLine = line.toLowerCase().trim();

    // Very short lines (less than 5 characters)
    if (lowerLine.length < 5) return true;

    // Common header keywords (Uzbek and Russian)
    final metadataKeywords = [
      'universitet',
      'institute',
      'university',
      'respublika',
      'vazirligi',
      'kafedra',
      'department',
      'tasdiqlayman',
      'prorekt',
      'mudiri',
      'tuzuvchi',
      'muhokama',
      'tasdiqlash',
      'sentyabr',
      'oktabr',
      'noyabr',
      'dekabr',
      'yanvar',
      'fevral',
      'toshkent',
      'kafolat',
      'xati',
      'zimma',
      'ma\'sul',
      'o\'quv',
      'kunduzgi',
      'sirtqi',
      'kurs',
      'guruh',
      'fan',
      'maqsad',
    ];

    for (final keyword in metadataKeywords) {
      if (lowerLine.contains(keyword)) return true;
    }

    // Date patterns
    if (RegExp(r'\d{1,2}[./-]\d{1,2}[./-]\d{2,4}').hasMatch(lowerLine)) {
      return true;
    }

    // Phone numbers
    if (RegExp(r'\+?\d{1,3}[-\s]?\(?\d{2,3}\)?[-\s]?\d{3}[-\s]?\d{2}[-\s]?\d{2}')
        .hasMatch(lowerLine)) {
      return true;
    }

    // Lines with mostly underscores or dashes
    final specialChars = line.codeUnits.where((c) => c == 95 || c == 45).length;
    if (specialChars > line.length * 0.5) return true;

    // Lines that are just numbers and spaces
    final digitsAndSpaces =
        line.codeUnits.where((c) => (c >= 48 && c <= 57) || c == 32).length;
    if (digitsAndSpaces > line.length * 0.8 && line.length > 5) return true;

    return false;
  }

  /// Fix common encoding issues in text
  String _fixEncodingIssues(String text) {
    var result = text;

    // Fix Cyrillic quotes and apostrophes
    final replacements = {
      'â': "'",
      'Â«': '"',
      'Â»': '"',
      '`': "'",
      ''': "'",
      ''': "'",
      '"': '"',
      '"': '"',
      'â€™': "'",
      'â€œ': '"',
      'â€': '"',
      // Uzbek specific
      'toâgâri': "to'g'ri",
      'togâri': "to'g'ri",
      'toʻgʻri': "to'g'ri",
      'oâ': "o'",
      'gâ': "g'",
      'oʻ': "o'",
      'gʻ': "g'",
      'oʼ': "o'",
      'gʼ': "g'",
    };

    replacements.forEach((key, value) {
      result = result.replaceAll(key, value);
    });

    return result;
  }

  /// Check if text is a token
  bool _isToken(String text) {
    return text == questionToken ||
        text == optionToken ||
        text.startsWith(correctMarker);
  }

  /// Check if text contains quiz tokens
  bool hasQuizTokens(String text) {
    return RegExp(r'\+{4,}').hasMatch(text) ||
        RegExp(r'={4,}').hasMatch(text) ||
        text.contains(correctMarker);
  }

  /// Validate that text has minimum required structure
  bool hasMinimumStructure(String text) {
    final questionMatches = RegExp(r'\+{4,}').allMatches(text).length;
    final optionMatches = RegExp(r'={4,}').allMatches(text).length;

    return questionMatches > 0 && optionMatches >= questionMatches * 2;
  }

  /// Extract correct answer hint from question text if present
  (String cleanQuestion, String? hint) extractCorrectAnswerHint(
      String questionText) {
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
    final letterMatch = RegExp(r'\b([a-dа-г])\b', caseSensitive: false)
        .firstMatch(lowerHint);
    if (letterMatch != null) {
      final letter = letterMatch.group(1)!.toLowerCase();
      final letterMap = {
        'a': 0,
        'а': 0,
        'b': 1,
        'б': 1,
        'c': 2,
        'в': 2,
        'd': 3,
        'г': 3,
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