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

  /// Creates a copy of this question with updated values
  Question copyWith({
    String? text,
    List<String>? options,
    int? correctOptionIndex,
  }) {
    return Question(
      text: text ?? this.text,
      options: options ?? List.from(this.options),
      correctOptionIndex: correctOptionIndex ?? this.correctOptionIndex,
    );
  }

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