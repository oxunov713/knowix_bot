import '../models/quiz_session.dart';
import '../models/quiz.dart';
import 'dart:async';

/// Manages active quiz sessions for users
class QuizSessionManager {
  final Map<int, QuizSession> _sessions = {};
  final Map<int, Timer> _timeoutTimers = {};
  final Map<int, int> _missedQuestions = {};

  static const int maxMissedQuestions = 3;
  static const Duration timeoutDuration = Duration(minutes: 2);

  /// Create a new session
  QuizSession createSession(int userId, Quiz quiz) {
    // Clear any existing session and timer
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
    return _sessions.remove(userId);
  }

  /// Clear all sessions
  void clearAll() {
    // Cancel all timers
    for (final timer in _timeoutTimers.values) {
      timer.cancel();
    }
    _timeoutTimers.clear();
    _missedQuestions.clear();
    _sessions.clear();
  }

  /// Get session count
  int get sessionCount => _sessions.length;

  /// Update pending raw text (for configuration flow)
  void setPendingRawText(int userId, String rawText) {
    var session = _sessions[userId];
    if (session == null) {
      // Create temporary session for configuration
      session = QuizSession(
        userId: userId,
        quiz: Quiz(questions: []), // Empty quiz
        pendingRawText: rawText,
      );
      _sessions[userId] = session;
    } else {
      session.pendingRawText = rawText;
    }
  }

  /// Update pending subject name
  void setPendingSubjectName(int userId, String subjectName) {
    final session = _sessions[userId];
    if (session != null) {
      session.pendingSubjectName = subjectName;
    }
  }

  /// Update pending shuffle choice
  void setPendingShuffleChoice(int userId, bool shuffle) {
    final session = _sessions[userId];
    if (session != null) {
      session.pendingShuffleChoice = shuffle;
    }
  }
}