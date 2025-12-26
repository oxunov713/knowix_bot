/// Represents a single quiz question with multiple options
class Question {
  final String text;
  final List<String> options;
  final int correctOptionIndex;

  Question({
    required this.text,
    required this.options,
    required this.correctOptionIndex,
  });

  /// Validates that the question has valid data
  bool isValid() {
    return text.isNotEmpty &&
        options.length >= 2 &&
        options.length <= 10 && // Telegram limit
        correctOptionIndex >= 0 &&
        correctOptionIndex < options.length &&
        options.every((opt) => opt.isNotEmpty);
  }

  @override
  String toString() {
    return 'Question(text: $text, options: ${options.length}, correct: $correctOptionIndex)';
  }
}