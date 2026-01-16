import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';

import '../services/supabase_service.dart';
import 'question.dart';

/// Represents a complete quiz with all questions
class Quiz {
  final List<Question> questions;
  final String? subjectName;
  final bool shuffled;
  final int timePerQuestion; // in seconds, 0 means no timer

  Quiz({
    required this.questions,
    this.subjectName,
    this.shuffled = false,
    this.timePerQuestion = 0,
  });

  /// Creates a shuffled copy of this quiz
  Quiz shuffleQuestions() {
    final shuffledQuestions = List<Question>.from(questions)..shuffle();
    return Quiz(
      questions: shuffledQuestions,
      subjectName: subjectName,
      shuffled: true,
      timePerQuestion: timePerQuestion,
    );
  }

  /// Creates a copy with updated metadata
  Quiz copyWith({
    List<Question>? questions,
    String? subjectName,
    bool? shuffled,
    int? timePerQuestion,
  }) {
    return Quiz(
      questions: questions ?? this.questions,
      subjectName: subjectName ?? this.subjectName,
      shuffled: shuffled ?? this.shuffled,
      timePerQuestion: timePerQuestion ?? this.timePerQuestion,
    );
  }

  bool get isValid => questions.isNotEmpty && questions.every((q) => q.isValid());
}


