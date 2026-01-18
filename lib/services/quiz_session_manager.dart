import '../models/quiz_session.dart';
import '../models/quiz.dart';
import 'dart:async';

/// Enhanced quiz session manager with shuffle tracking
class QuizSessionManager {
  final Map<int, QuizSession> _sessions = {};
  final Map<int, Timer> _timeoutTimers = {};
  final Map<int, int> _missedQuestions = {};
  final Map<int, String> _fileNames = {};
  final Map<int, int> _quizIds = {};
  final Map<int, String> _shuffleChoices = {}; // NEW: Track shuffle choices

  static const int maxMissedQuestions = 3;
  static const Duration timeoutDuration = Duration(minutes: 2);

  /// Create a new session
  QuizSession createSession(int userId, Quiz quiz) {
    _cancelTimer(userId);

    final session = QuizSession(
      userId: userId,
      quiz: quiz,
    );
    _sessions[userId] = session;
    _missedQuestions[userId] = 0;

    return session;
  }

  /// Get active session for user
  QuizSession? getSession(int userId) {
    return _sessions[userId];
  }

  /// Check if user has active session
  bool hasSession(int userId) {
    return _sessions.containsKey(userId);
  }

  /// Update session with poll ID and start timeout timer
  void updatePollId(int userId, String pollId) {
    final session = _sessions[userId];
    if (session != null) {
      session.currentPollId = pollId;
      _startTimeoutTimer(userId);
    }
  }

  /// Record correct answer and reset missed count
  void recordCorrectAnswer(int userId) {
    final session = _sessions[userId];
    if (session != null) {
      session.correctAnswers++;
      _missedQuestions[userId] = 0;
      _cancelTimer(userId);
    }
  }

  /// Record wrong answer and reset missed count
  void recordWrongAnswer(int userId) {
    _missedQuestions[userId] = 0;
    _cancelTimer(userId);
  }

  /// Handle timeout (user didn't answer)
  void _handleTimeout(int userId) {
    final missed = (_missedQuestions[userId] ?? 0) + 1;
    _missedQuestions[userId] = missed;
    print('⏰ User $userId missed question (${missed}/${maxMissedQuestions})');
  }

  /// Check if user has exceeded missed question limit
  bool hasExceededMissedLimit(int userId) {
    return (_missedQuestions[userId] ?? 0) >= maxMissedQuestions;
  }

  /// Get missed question count
  int getMissedCount(int userId) {
    return _missedQuestions[userId] ?? 0;
  }

  /// Reset missed count
  void resetMissedCount(int userId) {
    _missedQuestions[userId] = 0;
  }

  /// Start timeout timer for current question
  void _startTimeoutTimer(int userId) {
    _cancelTimer(userId);

    _timeoutTimers[userId] = Timer(timeoutDuration, () {
      _handleTimeout(userId);
    });
  }

  /// Cancel timeout timer
  void _cancelTimer(int userId) {
    _timeoutTimers[userId]?.cancel();
    _timeoutTimers.remove(userId);
  }

  /// Move to next question
  void nextQuestion(int userId) {
    final session = _sessions[userId];
    if (session != null) {
      session.currentQuestionIndex++;
      session.currentPollId = null;
      _cancelTimer(userId);
    }
  }

  /// End and remove session
  QuizSession? endSession(int userId) {
    _cancelTimer(userId);
    _missedQuestions.remove(userId);
    _fileNames.remove(userId);
    _quizIds.remove(userId);
    _shuffleChoices.remove(userId);
    return _sessions.remove(userId);
  }

  /// Clear all sessions
  void clearAll() {
    for (final timer in _timeoutTimers.values) {
      timer.cancel();
    }
    _timeoutTimers.clear();
    _missedQuestions.clear();
    _sessions.clear();
    _fileNames.clear();
    _quizIds.clear();
    _shuffleChoices.clear();
  }

  /// Get session count
  int get sessionCount => _sessions.length;

  /// Set file name for user
  void setFileName(int userId, String fileName) {
    _fileNames[userId] = fileName;
  }

  /// Get file name for user
  String? getFileName(int userId) {
    return _fileNames[userId];
  }

  /// Set quiz ID for user
  void setQuizId(int userId, int quizId) {
    _quizIds[userId] = quizId;
  }

  /// Get quiz ID for user
  int? getQuizId(int userId) {
    return _quizIds[userId];
  }

  /// Set shuffle choice for user
  void setShuffleChoice(int userId, String choice) {
    _shuffleChoices[userId] = choice;
  }

  /// Get shuffle choice for user
  String? getShuffleChoice(int userId) {
    return _shuffleChoices[userId];
  }

  /// Clear user data completely
  void clearUserData(int userId) {
    endSession(userId);
    _fileNames.remove(userId);
    _quizIds.remove(userId);
    _shuffleChoices.remove(userId);
  }
}