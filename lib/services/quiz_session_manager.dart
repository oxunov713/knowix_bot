import '../models/quiz_session.dart';
import '../models/quiz.dart';
import 'dart:async';

/// Production-ready quiz session manager with comprehensive management
class QuizSessionManager {
  final Map<int, QuizSession> _sessions = {};
  final Map<int, Timer> _timeoutTimers = {};
  final Map<int, int> _missedQuestions = {};
  final Map<int, String> _fileNames = {};
  final Map<int, int> _quizIds = {};
  final Map<int, String> _shuffleChoices = {};

  static const int maxMissedQuestions = 3;
  static const Duration timeoutDuration = Duration(minutes: 2);

  /// Create a new session with validation
  QuizSession createSession(int userId, Quiz quiz) {
    try {
      // Cancel any existing timer
      _cancelTimer(userId);

      // Validate quiz
      if (quiz.questions.isEmpty) {
        throw ArgumentError('Cannot create session with empty quiz');
      }

      final session = QuizSession(
        userId: userId,
        quiz: quiz,
      );

      _sessions[userId] = session;
      _missedQuestions[userId] = 0;

      print('✅ Session created for user $userId (${quiz.questions.length} questions)');
      return session;
    } catch (e) {
      print('❌ Failed to create session for user $userId: $e');
      rethrow;
    }
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
      print('✅ Poll ID updated for user $userId');
    } else {
      print('⚠️ No session found for user $userId when updating poll ID');
    }
  }

  /// Record correct answer and reset missed count
  void recordCorrectAnswer(int userId) {
    final session = _sessions[userId];
    if (session != null) {
      session.correctAnswers++;
      _missedQuestions[userId] = 0;
      _cancelTimer(userId);
      print('✅ Correct answer recorded for user $userId (Total: ${session.correctAnswers})');
    }
  }

  /// Record wrong answer and reset missed count
  void recordWrongAnswer(int userId) {
    _missedQuestions[userId] = 0;
    _cancelTimer(userId);
    print('❌ Wrong answer recorded for user $userId');
  }

  /// Handle timeout (user didn't answer)
  void _handleTimeout(int userId) {
    final missed = (_missedQuestions[userId] ?? 0) + 1;
    _missedQuestions[userId] = missed;
    print('⏰ User $userId missed question ($missed/$maxMissedQuestions)');
  }

  /// Check if user has exceeded missed question limit
  bool hasExceededMissedLimit(int userId) {
    final missed = _missedQuestions[userId] ?? 0;
    return missed >= maxMissedQuestions;
  }

  /// Get missed question count
  int getMissedCount(int userId) {
    return _missedQuestions[userId] ?? 0;
  }

  /// Reset missed count
  void resetMissedCount(int userId) {
    _missedQuestions[userId] = 0;
    print('🔄 Missed count reset for user $userId');
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
    final timer = _timeoutTimers[userId];
    if (timer != null) {
      timer.cancel();
      _timeoutTimers.remove(userId);
    }
  }
// Add this to QuizSessionManager
  String? getCurrentPollId(int userId) {
    return _sessions[userId]?.currentPollId;
  }

// Update this in QuizSessionManager
  bool nextQuestion(int userId) {
    final session = _sessions[userId];
    if (session != null) {
      session.currentQuestionIndex++;
      session.currentPollId = null;
      _cancelTimer(userId);

      // Return true if there are more questions
      return session.currentQuestionIndex < session.quiz.questions.length;
    }
    return false;
  }
 QuizSession? endSession(int userId) {
    try {
      _cancelTimer(userId);
      _missedQuestions.remove(userId);
      _fileNames.remove(userId);
      _quizIds.remove(userId);
      _shuffleChoices.remove(userId);

      final session = _sessions.remove(userId);
      if (session != null) {
        print('🏁 Session ended for user $userId');
      }

      return session;
    } catch (e) {
      print('❌ Error ending session for user $userId: $e');
      return null;
    }
  }

  /// Clear all sessions (used on bot shutdown)
  void clearAll() {
    try {
      print('🧹 Clearing all sessions...');

      // Cancel all timers
      for (final timer in _timeoutTimers.values) {
        timer.cancel();
      }

      final sessionCount = _sessions.length;

      _timeoutTimers.clear();
      _missedQuestions.clear();
      _sessions.clear();
      _fileNames.clear();
      _quizIds.clear();
      _shuffleChoices.clear();

      print('✅ Cleared $sessionCount sessions');
    } catch (e) {
      print('❌ Error clearing sessions: $e');
    }
  }

  /// Get session count
  int get sessionCount => _sessions.length;

  /// Set file name for user
  void setFileName(int userId, String fileName) {
    _fileNames[userId] = fileName;
    print('📄 File name set for user $userId: $fileName');
  }

  /// Get file name for user
  String? getFileName(int userId) {
    return _fileNames[userId];
  }

  /// Set quiz ID for user
  void setQuizId(int userId, int quizId) {
    _quizIds[userId] = quizId;
    print('🆔 Quiz ID set for user $userId: $quizId');
  }

  /// Get quiz ID for user
  int? getQuizId(int userId) {
    return _quizIds[userId];
  }

  /// Set shuffle choice for user
  void setShuffleChoice(int userId, String choice) {
    if (!['questions', 'answers', 'both', 'none'].contains(choice)) {
      print('⚠️ Invalid shuffle choice for user $userId: $choice');
      return;
    }

    _shuffleChoices[userId] = choice;
    print('🔀 Shuffle choice set for user $userId: $choice');
  }

  /// Get shuffle choice for user
  String? getShuffleChoice(int userId) {
    return _shuffleChoices[userId];
  }

  /// Clear user data completely
  void clearUserData(int userId) {
    try {
      endSession(userId);
      _fileNames.remove(userId);
      _quizIds.remove(userId);
      _shuffleChoices.remove(userId);
      print('🧹 User data cleared for user $userId');
    } catch (e) {
      print('❌ Error clearing user data for $userId: $e');
    }
  }

  /// Get all active user IDs
  List<int> getActiveUserIds() {
    return _sessions.keys.toList();
  }

  /// Get session statistics
  Map<String, dynamic> getSessionStats() {
    final stats = <String, dynamic>{
      'total_sessions': _sessions.length,
      'active_timers': _timeoutTimers.length,
      'users_with_missed_questions': _missedQuestions.length,
      'users_with_files': _fileNames.length,
      'users_with_quiz_ids': _quizIds.length,
    };

    // Calculate average progress
    if (_sessions.isNotEmpty) {
      var totalProgress = 0.0;
      for (final session in _sessions.values) {
        final progress = session.currentQuestionIndex / session.quiz.questions.length;
        totalProgress += progress;
      }
      stats['average_progress'] = (totalProgress / _sessions.length * 100).toStringAsFixed(1);
    }

    return stats;
  }

  /// Cleanup stale sessions (sessions without activity for 1 hour)
  void cleanupStaleSessions() {
    try {
      print('🧹 Cleaning up stale sessions...');

      final now = DateTime.now();
      final staleUserIds = <int>[];

      for (final entry in _sessions.entries) {
        final userId = entry.key;
        final session = entry.value;

        // If session has been inactive for over 1 hour
        final elapsed = now.difference(session.startTime);
        if (elapsed.inHours >= 1) {
          staleUserIds.add(userId);
        }
      }

      for (final userId in staleUserIds) {
        clearUserData(userId);
      }

      if (staleUserIds.isNotEmpty) {
        print('✅ Cleaned up ${staleUserIds.length} stale sessions');
      }
    } catch (e) {
      print('❌ Error cleaning stale sessions: $e');
    }
  }

  /// Print current state (for debugging)
  void printState() {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 Session Manager State:');
    print('   Active sessions: ${_sessions.length}');
    print('   Active timers: ${_timeoutTimers.length}');
    print('   Users with missed questions: ${_missedQuestions.length}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }
}