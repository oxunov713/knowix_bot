import 'package:supabase/supabase.dart';

/// Supabase bilan integratsiya servisi - HYBRID STORAGE
class SupabaseService {
  late final SupabaseClient _client;
  static SupabaseService? _instance;
  static const int MAX_STORED_QUIZZES_PER_USER = 1; // Faqat 1 ta quiz

  SupabaseService._internal();

  factory SupabaseService() {
    return _instance ??= SupabaseService._internal();
  }

  /// Supabase-ni initialize qilish
  Future<void> initialize(String supabaseUrl, String supabaseKey) async {
    try {
      _client = SupabaseClient(supabaseUrl, supabaseKey);
      await _client.from('users').select('id').limit(1);
      print('✅ Supabase initialized');
    } catch (e) {
      print('❌ Supabase init error: $e');
      rethrow;
    }
  }

  SupabaseClient get client => _client;

  // ==================== UTILITY METHODS ====================

  int _safeResponseLength(dynamic response) {
    if (response is List) return response.length;
    return 0;
  }

  String _toIsoString(DateTime date) => date.toIso8601String();

  // ==================== USER OPERATIONS ====================

  Future<Map<String, dynamic>> upsertUser({
    required int telegramId,
    required String username,
    String? firstName,
    String? lastName,
  }) async {
    try {
      final data = {
        'telegram_id': telegramId,
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'last_active': _toIsoString(DateTime.now()),
        'is_active': true,
      };

      final response = await _client
          .from('users')
          .upsert(data, onConflict: 'telegram_id')
          .select()
          .single();

      print('✅ User saved: $username');
      return response;
    } catch (e) {
      print('❌ Error saving user: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getUser(int telegramId) async {
    try {
      final response = await _client
          .from('users')
          .select()
          .eq('telegram_id', telegramId)
          .maybeSingle();
      return response;
    } catch (e) {
      print('❌ Error getting user: $e');
      return null;
    }
  }

  Future<int?> getUserIdByTelegramId(int telegramId) async {
    final user = await getUser(telegramId);
    return user?['id'] as int?;
  }

  Future<void> updateUserActivity(int telegramId) async {
    try {
      await _client.from('users').update({
        'last_active': _toIsoString(DateTime.now()),
        'is_active': true,
      }).eq('telegram_id', telegramId);
    } catch (e) {
      print('❌ Error updating activity: $e');
    }
  }

  Future<int> getActiveUsersCount() async {
    try {
      final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
      final response = await _client
          .from('users')
          .select('id')
          .gte('last_active', _toIsoString(oneDayAgo));
      return _safeResponseLength(response);
    } catch (e) {
      print('❌ Error getting active users: $e');
      return 0;
    }
  }

  Future<int> getTotalUsersCount() async {
    try {
      final response = await _client.from('users').select('id');
      return _safeResponseLength(response);
    } catch (e) {
      print('❌ Error getting total users: $e');
      return 0;
    }
  }

  // ==================== QUIZ OPERATIONS - HYBRID ====================

  /// Yangi quiz saqlash (SAVOLLAR BILAN!)
  Future<Map<String, dynamic>> saveQuiz({
    required int telegramId,
    required String subjectName,
    required int totalQuestions,
    required bool isShuffled,
    required int timePerQuestion,
    required String fileName,
    required List<Map<String, dynamic>> questions, // YANGI!
  }) async {
    try {
      final userId = await getUserIdByTelegramId(telegramId);
      if (userId == null) throw Exception('User not found');

      // 1. Eski quizlarni tozalash (faqat 1 ta qoladi)
      await _cleanupOldQuizzes(userId);

      // 2. Quiz metadata saqlash
      final quizData = {
        'user_id': userId,
        'subject_name': subjectName,
        'total_questions': totalQuestions,
        'is_shuffled': isShuffled,
        'time_per_question': timePerQuestion,
        'file_name': fileName,
        'has_stored_questions': true, // MUHIM!
        'created_at': _toIsoString(DateTime.now()),
      };

      final quizResponse =
      await _client.from('quizzes').insert(quizData).select().single();

      final quizId = quizResponse['id'] as int;

      // 3. Savollarni batch insert qilish
      final questionsData = questions.asMap().entries.map((entry) {
        final index = entry.key;
        final q = entry.value;
        return {
          'quiz_id': quizId,
          'question_text': q['text'],
          'options': q['options'], // JSON array
          'correct_index': q['correctIndex'],
          'question_order': index,
        };
      }).toList();

      await _client.from('quiz_questions').insert(questionsData);

      print('✅ Quiz saved: $subjectName (${questions.length} questions stored)');
      return quizResponse;
    } catch (e) {
      print('❌ Error saving quiz: $e');
      rethrow;
    }
  }

  /// Eski quizlarni tozalash
  Future<void> _cleanupOldQuizzes(int userId) async {
    try {
      final quizzes = await _client
          .from('quizzes')
          .select('id, created_at')
          .eq('user_id', userId)
          .eq('has_stored_questions', true)
          .order('created_at', ascending: false);

      final quizList = List<Map<String, dynamic>>.from(quizzes as List);

      if (quizList.length >= MAX_STORED_QUIZZES_PER_USER) {
        // Eng eskisini topish
        final oldQuizzes = quizList.skip(MAX_STORED_QUIZZES_PER_USER - 1);

        for (final quiz in oldQuizzes) {
          final quizId = quiz['id'];

          // Savollarni o'chirish (CASCADE bilan avtomatik)
          await _client.from('quiz_questions').delete().eq('quiz_id', quizId);

          // Flag o'zgartirish
          await _client
              .from('quizzes')
              .update({'has_stored_questions': false}).eq('id', quizId);

          print('🗑 Cleaned up old quiz: $quizId');
        }
      }
    } catch (e) {
      print('⚠️ Cleanup error: $e');
    }
  }

  /// Quiz ID bo'yicha olish (SAVOLLAR BILAN!)
  Future<Map<String, dynamic>?> getQuizWithQuestions(int quizId) async {
    try {
      // 1. Quiz metadata
      final quizData =
      await _client.from('quizzes').select().eq('id', quizId).single();

      // 2. Savollar bormi?
      if (quizData['has_stored_questions'] != true) {
        return {
          ...quizData,
          'questions': null,
          'can_restart': false,
        };
      }

      // 3. Savollarni yuklash
      final questions = await _client
          .from('quiz_questions')
          .select()
          .eq('quiz_id', quizId)
          .order('question_order', ascending: true);

      final questionsList = List<Map<String, dynamic>>.from(questions as List);

      return {
        ...quizData,
        'questions': questionsList,
        'can_restart': true,
      };
    } catch (e) {
      print('❌ Error loading quiz: $e');
      return null;
    }
  }

  /// User quizlarini olish
  Future<List<Map<String, dynamic>>> getUserQuizzes(int telegramId) async {
    try {
      final userId = await getUserIdByTelegramId(telegramId);
      if (userId == null) return [];

      final response = await _client
          .from('quizzes')
          .select('id, subject_name, total_questions, is_shuffled, '
          'time_per_question, has_stored_questions, created_at, '
          'quiz_results(percentage, is_completed)')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(20);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error getting user quizzes: $e');
      return [];
    }
  }

  /// Quiz natijasini saqlash
  Future<Map<String, dynamic>> saveQuizResult({
    required int quizId,
    required int correctAnswers,
    required int totalAnswered,
    required int totalQuestions,
    required double percentage,
    required int elapsedSeconds,
    required bool isCompleted,
  }) async {
    try {
      final data = {
        'quiz_id': quizId,
        'correct_answers': correctAnswers,
        'total_answered': totalAnswered,
        'total_questions': totalQuestions,
        'percentage': percentage,
        'elapsed_seconds': elapsedSeconds,
        'is_completed': isCompleted,
        'completed_at': _toIsoString(DateTime.now()),
      };

      final response =
      await _client.from('quiz_results').insert(data).select().single();

      print('✅ Quiz result saved');
      return response;
    } catch (e) {
      print('❌ Error saving quiz result: $e');
      rethrow;
    }
  }

  // ==================== ENHANCED STATISTICS ====================

  /// Batafsil user statistikasi
  Future<Map<String, dynamic>> getDetailedUserStats(int telegramId) async {
    try {
      final user = await getUser(telegramId);
      if (user == null) return {};

      final userId = user['id'] as int;

      // User quizlari
      final quizzesResponse =
      await _client.from('quizzes').select('id').eq('user_id', userId);

      final userQuizIds = List.from(quizzesResponse as List)
          .map<int>((q) => q['id'] as int)
          .toList();

      if (userQuizIds.isEmpty) return {};

      // Natijalar
      final resultsResponse = await _client
          .from('quiz_results')
          .select('percentage, correct_answers, total_answered, elapsed_seconds')
          .eq('is_completed', true)
          .inFilter('quiz_id', userQuizIds);

      final results = List<Map<String, dynamic>>.from(resultsResponse as List);

      if (results.isEmpty) return {};

      // Hisoblashlar
      final percentages = results.map((r) => r['percentage'] as double).toList();
      final bestScore = percentages.reduce((a, b) => a > b ? a : b);
      final worstScore = percentages.reduce((a, b) => a < b ? a : b);

      final totalAnswered = results.fold<int>(
        0,
            (sum, r) => sum + (r['total_answered'] as int),
      );

      final totalCorrect = results.fold<int>(
        0,
            (sum, r) => sum + (r['correct_answers'] as int),
      );

      final totalTime = results.fold<int>(
        0,
            (sum, r) => sum + (r['elapsed_seconds'] as int),
      );

      final avgTimePerQuiz = (totalTime / results.length).round();

      return {
        'best_score': bestScore,
        'worst_score': worstScore,
        'total_questions_answered': totalAnswered,
        'total_correct_answers': totalCorrect,
        'total_time_spent': totalTime,
        'avg_time_per_quiz': avgTimePerQuiz,
      };
    } catch (e) {
      print('❌ Error getting detailed stats: $e');
      return {};
    }
  }

  /// Oxirgi natijalar
  Future<List<Map<String, dynamic>>> getRecentResults(
      int telegramId, {
        int limit = 5,
      }) async {
    try {
      final userId = await getUserIdByTelegramId(telegramId);
      if (userId == null) return [];

      final response = await _client
          .from('quiz_results')
          .select('percentage, completed_at, quiz_id, quizzes!inner(subject_name)')
          .eq('quizzes.user_id', userId)
          .eq('is_completed', true)
          .order('completed_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error getting recent results: $e');
      return [];
    }
  }

  /// Top natijalar
  Future<List<Map<String, dynamic>>> getTopResults(
      int telegramId, {
        int limit = 10,
      }) async {
    try {
      final userId = await getUserIdByTelegramId(telegramId);
      if (userId == null) return [];

      final response = await _client
          .from('quiz_results')
          .select('percentage, completed_at, quiz_id, quizzes!inner(subject_name)')
          .eq('quizzes.user_id', userId)
          .eq('is_completed', true)
          .order('percentage', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error getting top results: $e');
      return [];
    }
  }

  /// Fanlar bo'yicha statistika
  Future<List<Map<String, dynamic>>> getStatsBySubject(int telegramId) async {
    try {
      final userId = await getUserIdByTelegramId(telegramId);
      if (userId == null) return [];

      // Supabase'da group by qilish
      final response = await _client.rpc(
        'get_stats_by_subject',
        params: {'p_user_id': userId},
      );

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error getting stats by subject: $e');
      // Fallback: Dart'da group by
      return await _getStatsBySubjectFallback(telegramId);
    }
  }

  /// Fallback: Dart'da fanlar bo'yicha statistika
  Future<List<Map<String, dynamic>>> _getStatsBySubjectFallback(
      int telegramId) async {
    try {
      final userId = await getUserIdByTelegramId(telegramId);
      if (userId == null) return [];

      final response = await _client
          .from('quiz_results')
          .select('percentage, quizzes!inner(subject_name)')
          .eq('quizzes.user_id', userId)
          .eq('is_completed', true);

      final results = List<Map<String, dynamic>>.from(response as List);

      // Group by subject
      final Map<String, List<double>> subjectScores = {};

      for (final result in results) {
        final subject = result['quizzes']['subject_name'] as String;
        final percentage = result['percentage'] as double;

        subjectScores.putIfAbsent(subject, () => []).add(percentage);
      }

      // Calculate averages
      final statsList = subjectScores.entries.map((entry) {
        final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
        return {
          'subject_name': entry.key,
          'avg_percentage': avg,
          'test_count': entry.value.length,
        };
      }).toList();

      // Sort by average
      statsList.sort((a, b) =>
          (b['avg_percentage'] as double).compareTo(a['avg_percentage'] as double));

      return statsList;
    } catch (e) {
      print('❌ Error in fallback: $e');
      return [];
    }
  }

  /// User statistikasini olish
  Future<Map<String, dynamic>> getUserStats(int telegramId) async {
    try {
      final user = await getUser(telegramId);
      if (user == null) return {};

      final userId = user['id'] as int;

      final quizzesResponse =
      await _client.from('quizzes').select('id').eq('user_id', userId);
      final quizzesCount = _safeResponseLength(quizzesResponse);

      final userQuizIds = List.from(quizzesResponse as List)
          .map<int>((q) => q['id'] as int)
          .toList();

      if (userQuizIds.isEmpty) {
        return {
          'total_quizzes': 0,
          'completed_tests': 0,
          'average_percentage': 0.0,
          'user': user,
        };
      }

      final resultsResponse = await _client
          .from('quiz_results')
          .select('percentage')
          .eq('is_completed', true)
          .inFilter('quiz_id', userQuizIds);

      final results = List<Map<String, dynamic>>.from(resultsResponse as List);
      final completedTests = results.length;

      double avgPercentage = 0;
      if (completedTests > 0) {
        final totalPercentage = results.fold<double>(
          0,
              (sum, item) => sum + (item['percentage'] as num).toDouble(),
        );
        avgPercentage = totalPercentage / completedTests;
      }

      return {
        'total_quizzes': quizzesCount,
        'completed_tests': completedTests,
        'average_percentage': avgPercentage,
        'user': user,
      };
    } catch (e) {
      print('❌ Error getting user stats: $e');
      return {};
    }
  }

  // ==================== ADMIN STATISTICS ====================

  Future<Map<String, dynamic>> getAdminStats() async {
    try {
      final futures = await Future.wait([
        getTotalUsersCount(),
        getActiveUsersCount(),
        _getTotalQuizzesCount(),
        _getTotalCompletedTestsCount(),
        _getNewUsersTodayCount(),
        _getStoredQuestionsCount(),
      ]);

      return {
        'total_users': futures[0],
        'active_users_24h': futures[1],
        'total_quizzes': futures[2],
        'total_completed_tests': futures[3],
        'new_users_today': futures[4],
        'stored_questions': futures[5],
      };
    } catch (e) {
      print('❌ Error getting admin stats: $e');
      return {};
    }
  }

  Future<int> _getTotalQuizzesCount() async {
    try {
      final response = await _client.from('quizzes').select('id');
      return _safeResponseLength(response);
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getTotalCompletedTestsCount() async {
    try {
      final response =
      await _client.from('quiz_results').select('id').eq('is_completed', true);
      return _safeResponseLength(response);
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getNewUsersTodayCount() async {
    try {
      final todayStart = DateTime.now().copyWith(
        hour: 0,
        minute: 0,
        second: 0,
        millisecond: 0,
        microsecond: 0,
      );

      final response = await _client
          .from('users')
          .select('id')
          .gte('created_at', _toIsoString(todayStart));
      return _safeResponseLength(response);
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getStoredQuestionsCount() async {
    try {
      final response = await _client.from('quiz_questions').select('id');
      return _safeResponseLength(response);
    } catch (e) {
      return 0;
    }
  }

  void dispose() {
    _instance = null;
  }
}