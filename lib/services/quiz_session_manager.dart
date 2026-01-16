import '../models/quiz_session.dart';
import '../models/quiz.dart';
import 'dart:async';

/// Manages active quiz sessions for users (Supabase integratsiyasi uchun yaxshilangan)
class QuizSessionManager {
  final Map<int, QuizSession> _sessions = {};
  final Map<int, Timer> _timeoutTimers = {};
  final Map<int, int> _missedQuestions = {};

  // Qo'shimcha ma'lumotlar Supabase uchun
  final Map<int, String> _fileNames = {};
  final Map<int, int> _quizIds = {};

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
  }

  /// Get session count
  int get sessionCount => _sessions.length;

  /// Update pending shuffle choice
  void setPendingShuffleChoice(int userId, bool shuffle) {
    final session = _sessions[userId];
    if (session != null) {
      session.pendingShuffleChoice = shuffle;
    }
  }

  // ==================== SUPABASE UCHUN QOSHIMCHA METODLAR ====================

  /// Fayl nomini saqlash
  void setFileName(int userId, String fileName) {
    _fileNames[userId] = fileName;
  }

  /// Fayl nomini olish
  String? getFileName(int userId) {
    return _fileNames[userId];
  }

  /// Quiz ID ni saqlash (Supabase dan)
  void setQuizId(int userId, int quizId) {
    _quizIds[userId] = quizId;
  }

  /// Quiz ID ni olish
  int? getQuizId(int userId) {
    return _quizIds[userId];
  }

  /// Session ma'lumotlarini to'liq tozalash
  void clearUserData(int userId) {
    endSession(userId);
    _fileNames.remove(userId);
    _quizIds.remove(userId);
  }
}