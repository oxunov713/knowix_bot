import 'dart:math';

/// Question model with shuffle capability
class Question {
  final String text;
  final List<String> options;
  final int correctOptionIndex;

  Question({
    required this.text,
    required this.options,
    required this.correctOptionIndex,
  });

  /// Validate question
  bool isValid() {
    return text.isNotEmpty &&
        options.length >= 2 &&
        correctOptionIndex >= 0 &&
        correctOptionIndex < options.length &&
        options.every((opt) => opt.isNotEmpty);
  }

  /// Shuffle options while maintaining correct answer
  Question shuffleOptions() {
    // Store correct answer
    final correctAnswer = options[correctOptionIndex];

    // Create shuffled list
    final shuffledOptions = List<String>.from(options);
    shuffledOptions.shuffle(Random());

    // Find new index of correct answer
    final newCorrectIndex = shuffledOptions.indexOf(correctAnswer);

    return Question(
      text: text,
      options: shuffledOptions,
      correctOptionIndex: newCorrectIndex,
    );
  }

  /// Copy with new values
  Question copyWith({
    String? text,
    List<String>? options,
    int? correctOptionIndex,
  }) {
    return Question(
      text: text ?? this.text,
      options: options ?? this.options,
      correctOptionIndex: correctOptionIndex ?? this.correctOptionIndex,
    );
  }

  @override
  String toString() {
    return 'Question(text: $text, options: ${options.length}, correct: $correctOptionIndex)';
  }
}