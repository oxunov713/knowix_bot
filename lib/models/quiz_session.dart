import 'quiz.dart';

/// Represents an active quiz session for a user
class QuizSession {
  final int userId;
  final Quiz quiz;
  int currentQuestionIndex;
  int correctAnswers;
  final DateTime startTime;
  String? currentPollId;

  // Session state for multi-step configuration
  String? pendingRawText;
  String? pendingSubjectName;
  bool? pendingShuffleChoice;

  QuizSession({
    required this.userId,
    required this.quiz,
    this.currentQuestionIndex = 0,
    this.correctAnswers = 0,
    DateTime? startTime,
    this.currentPollId,
    this.pendingRawText,
    this.pendingSubjectName,
    this.pendingShuffleChoice,
  }) : startTime = startTime ?? DateTime.now();

  /// Check if quiz is completed
  bool get isCompleted => currentQuestionIndex >= quiz.questions.length;

  /// Get current question
  get currentQuestion =>
      isCompleted ? null : quiz.questions[currentQuestionIndex];

  /// Get progress string
  String get progress => '${currentQuestionIndex + 1}/${quiz.questions.length}';

  /// Calculate score percentage
  double get scorePercentage {
    if (quiz.questions.isEmpty) return 0;
    return (correctAnswers / quiz.questions.length) * 100;
  }

  /// Get elapsed time
  Duration get elapsedTime => DateTime.now().difference(startTime);
}