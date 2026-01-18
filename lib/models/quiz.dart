import 'dart:math';
import 'question.dart';

/// Quiz model with enhanced shuffle capabilities
class Quiz {
  final List<Question> questions;
  final String? subjectName;
  final int timePerQuestion;
  final bool shuffled;
  final bool answersShuffled;
  final String? shareCode; // NEW: For sharing quizzes

  Quiz({
    required this.questions,
    this.subjectName,
    this.timePerQuestion = 0,
    this.shuffled = false,
    this.answersShuffled = false,
    this.shareCode,
  });

  /// Validate quiz
  bool get isValid {
    return questions.isNotEmpty &&
        questions.every((q) => q.isValid());
  }

  /// Shuffle questions order
  Quiz shuffleQuestions() {
    final shuffledQuestions = List<Question>.from(questions);
    shuffledQuestions.shuffle(Random());

    return Quiz(
      questions: shuffledQuestions,
      subjectName: subjectName,
      timePerQuestion: timePerQuestion,
      shuffled: true,
      answersShuffled: answersShuffled,
      shareCode: shareCode,
    );
  }

  /// Shuffle answers for all questions
  Quiz shuffleAnswers() {
    final questionsWithShuffledAnswers = questions.map((q) {
      return q.shuffleOptions();
    }).toList();

    return Quiz(
      questions: questionsWithShuffledAnswers,
      subjectName: subjectName,
      timePerQuestion: timePerQuestion,
      shuffled: shuffled,
      answersShuffled: true,
      shareCode: shareCode,
    );
  }

  /// Shuffle both questions and answers
  Quiz shuffleBoth() {
    return shuffleQuestions().shuffleAnswers();
  }

  /// Copy with new values
  Quiz copyWith({
    List<Question>? questions,
    String? subjectName,
    int? timePerQuestion,
    bool? shuffled,
    bool? answersShuffled,
    String? shareCode,
  }) {
    return Quiz(
      questions: questions ?? this.questions,
      subjectName: subjectName ?? this.subjectName,
      timePerQuestion: timePerQuestion ?? this.timePerQuestion,
      shuffled: shuffled ?? this.shuffled,
      answersShuffled: answersShuffled ?? this.answersShuffled,
      shareCode: shareCode ?? this.shareCode,
    );
  }

  /// Convert to Supabase format
  Map<String, dynamic> toSupabaseFormat() {
    return {
      'questions': questions.map((q) => {
        'text': q.text,
        'options': q.options,
        'correctIndex': q.correctOptionIndex,
      }).toList(),
      'subject_name': subjectName,
      'total_questions': questions.length,
      'time_per_question': timePerQuestion,
      'is_shuffled': shuffled,
      'answers_shuffled': answersShuffled,
    };
  }

  /// Create from Supabase data
  static Quiz fromSupabaseData(Map<String, dynamic> data) {
    final questionsList = data['questions'] as List<dynamic>;

    final questions = questionsList.map((q) {
      return Question(
        text: q['text'] as String,
        options: List<String>.from(q['options'] as List),
        correctOptionIndex: q['correctIndex'] as int,
      );
    }).toList();

    return Quiz(
      questions: questions,
      subjectName: data['subject_name'] as String?,
      timePerQuestion: data['time_per_question'] as int? ?? 0,
      shuffled: data['is_shuffled'] as bool? ?? false,
      answersShuffled: data['answers_shuffled'] as bool? ?? false,
      shareCode: data['share_code'] as String?,
    );
  }
}