/// Service for normalizing quiz text - IMPROVED VERSION with NUMBERED FORMAT support
class QuizTextNormalizer {
  // Quiz format tokens (Hemis format)
  static const String questionToken = '+++++';
  static const String optionToken = '=====';
  static const String correctMarker = '#';

  /// Detect quiz format type
  String detectQuizFormat(String text) {
    final hasNumbered = _hasNumberedFormat(text);
    final hasTokens = hasQuizTokens(text);

    if (hasNumbered && text.contains(RegExp(r'^[-#]\s+', multiLine: true))) {
      return 'numbered'; // Yangi format: 1. Question \n - Option \n # Correct
    } else if (hasTokens) {
      return 'hemis'; // Eski format: +++++ \n ===== \n #
    }
    return 'unknown';
  }

  /// Check if text uses numbered question format (1. 2. 3. ...)
  bool _hasNumberedFormat(String text) {
    // Check for pattern: number followed by period and question text
    return RegExp(r'^\s*\d+\.\s+.{10,}', multiLine: true).hasMatch(text);
  }

  /// Normalize quiz text based on detected format
  String normalizeQuizText(String rawText) {
    if (rawText.isEmpty) return '';

    print('📝 Format aniqlanmoqda...');
    final format = detectQuizFormat(rawText);
    print('📝 Aniqlangan format: $format');

    if (format == 'numbered') {
      return _normalizeNumberedFormat(rawText);
    } else if (format == 'hemis') {
      return _normalizeHemisFormat(rawText);
    } else {
      throw FormatException('Noma\'lum format! Qo\'llab-quvvatlanuvchi formatlar:\n'
          '1) Raqamli format: "1. Savol\\n# To\'g\'ri\\n- Noto\'g\'ri"\n'
          '2) Hemis format: "+++++ Savol\\n===== Variant\\n===== #To\'g\'ri"');
    }
  }

  /// Normalize numbered format quiz text
  String _normalizeNumberedFormat(String rawText) {
    print('📝 Raqamli format normalizatsiyasi boshlandi');

    String normalized = rawText;

    // Fix encoding issues
    normalized = _fixEncodingIssues(normalized);

    // Normalize line endings
    normalized = normalized.replaceAll('\r\n', '\n');
    normalized = normalized.replaceAll('\r', '\n');

    // Convert numbered format to standard token format
    final lines = normalized.split('\n');
    final result = StringBuffer();

    bool inQuestion = false;
    String? currentQuestion;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Skip empty lines
      if (line.isEmpty) continue;

      // Check if this is a new question (starts with number.)
      final questionMatch = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(line);
      if (questionMatch != null) {
        // Save previous question if exists
        if (inQuestion && currentQuestion != null) {
          result.writeln(); // Add spacing between questions
        }

        inQuestion = true;
        currentQuestion = questionMatch.group(2)!.trim();

        // Write question in standard format
        result.writeln(questionToken);
        result.writeln(currentQuestion);
        continue;
      }

      // Check if this is a correct answer (starts with #)
      if (line.startsWith('#')) {
        final optionText = line.substring(1).trim();
        if (optionText.isNotEmpty && !_isNoise(optionText)) {
          result.writeln(optionToken);
          result.writeln('$correctMarker$optionText');
        }
        continue;
      }

      // Check if this is an incorrect answer (starts with -)
      if (line.startsWith('-')) {
        final optionText = line.substring(1).trim();
        if (optionText.isNotEmpty && !_isNoise(optionText)) {
          result.writeln(optionToken);
          result.writeln(optionText);
        }
        continue;
      }
    }

    final output = result.toString().trim();
    print('📝 Raqamli format normalizatsiyasi tugadi: ${output.length} belgi');

    return output;
  }

  /// Normalize Hemis format quiz text (original implementation)
  String _normalizeHemisFormat(String rawText) {
    print('📝 Hemis format normalizatsiyasi boshlandi: ${rawText.length} belgi');

    String normalized = rawText;

    // STEP 0: Fix common encoding issues first
    normalized = _fixEncodingIssues(normalized);

    // STEP 1: Normalize line endings
    normalized = normalized.replaceAll('\r\n', '\n');
    normalized = normalized.replaceAll('\r', '\n');

    // STEP 2: Remove university metadata and headers
    normalized = _removeMetadata(normalized);

    // STEP 3: Inject newlines around question token (++++)
    normalized = normalized.replaceAllMapped(
      RegExp(r'(\+{4,})'),
          (match) {
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

    // STEP 6: Pattern 2: # at start of line
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

    // STEP 7: Remove inline correct answer hints from questions
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

    // STEP 8: Clean up variant labels
    normalized = normalized.replaceAllMapped(
      RegExp(r'($optionToken)\s*\n\s*([A-Da-dА-Га-г][\)\.])\s*([^\n]+)',
          multiLine: true),
          (match) {
        final content = match.group(3)?.trim() ?? '';
        return '${match.group(1)}\n$content';
      },
    );

    // STEP 9: Handle cases where question and first option are on same line
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

    // STEP 10: Handle cases where options are on same line
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

    // STEP 11: Fix cases where # is separated from option token
    normalized = normalized.replaceAllMapped(
      RegExp(r'($optionToken)\s*\n\s*#\s*([^\n]+)', multiLine: true),
          (match) {
        final optionText = match.group(2)?.trim() ?? '';
        return '${match.group(1)}\n$correctMarker$optionText';
      },
    );

    // STEP 12: Collapse multiple consecutive newlines
    normalized = normalized.replaceAll(RegExp(r'\n\s*\n+'), '\n');

    // STEP 13: Collapse multiple spaces into single space
    normalized = normalized.replaceAllMapped(
      RegExp(r'[^\S\n]+'),
          (match) => ' ',
    );

    // STEP 14: Trim each line
    final lines = normalized.split('\n');
    normalized = lines.map((line) => line.trim()).where((line) => line.isNotEmpty).join('\n');

    // STEP 15: Remove leading/trailing newlines
    normalized = normalized.trim();

    final questionCount = RegExp(r'\n\+{5}\n').allMatches(normalized).length;
    print('📝 Hemis format normalizatsiyasi tugadi: ${normalized.length} belgi, ~$questionCount ta savol');

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

      if (line.isEmpty) continue;

      if (line.contains(RegExp(r'\+{4,}'))) {
        foundFirstQuestion = true;
        cleanLines.add(line);
        continue;
      }

      if (foundFirstQuestion) {
        cleanLines.add(line);
        continue;
      }

      if (!foundFirstQuestion) {
        headerLineCount++;

        if (headerLineCount <= 50 && _isMetadata(line)) {
          continue;
        }

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

    if (lowerLine.length < 5) return true;

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

    if (RegExp(r'\d{1,2}[./-]\d{1,2}[./-]\d{2,4}').hasMatch(lowerLine)) {
      return true;
    }

    if (RegExp(r'\+?\d{1,3}[-\s]?\(?\d{2,3}\)?[-\s]?\d{3}[-\s]?\d{2}[-\s]?\d{2}')
        .hasMatch(lowerLine)) {
      return true;
    }

    final specialChars = line.codeUnits.where((c) => c == 95 || c == 45).length;
    if (specialChars > line.length * 0.5) return true;

    final digitsAndSpaces =
        line.codeUnits.where((c) => (c >= 48 && c <= 57) || c == 32).length;
    if (digitsAndSpaces > line.length * 0.8 && line.length > 5) return true;

    return false;
  }

  /// Fix common encoding issues in text
  String _fixEncodingIssues(String text) {
    var result = text;

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

  /// Check if text contains quiz tokens (Hemis format)
  bool hasQuizTokens(String text) {
    return RegExp(r'\+{4,}').hasMatch(text) ||
        RegExp(r'={4,}').hasMatch(text) ||
        text.contains(correctMarker);
  }

  /// Check if line is noise
  bool _isNoise(String line) {
    if (line.length < 2) return true;

    if (RegExp(r'^[\s\-_\.\,\:\;\!\?\(\)\[\]\{\}\/\\]+$').hasMatch(line)) {
      return true;
    }

    if (RegExp(r'^\d+$').hasMatch(line) && line.length < 4) return true;

    final digitsAndSpaces =
        line.codeUnits.where((c) => (c >= 48 && c <= 57) || c == 32).length;
    if (digitsAndSpaces > line.length * 0.7 && line.length > 10) return true;

    final weirdChars = line.codeUnits.where((c) =>
    c < 32 || (c > 126 && c < 1040) || c > 1200
    ).length;
    if (weirdChars > line.length * 0.3) return true;

    if (line.length > 800) return true;

    if (RegExp(r'^(.)\1{5,}$').hasMatch(line)) return true;

    return false;
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