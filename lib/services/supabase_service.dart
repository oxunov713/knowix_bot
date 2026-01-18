import 'package:supabase/supabase.dart';
import 'dart:math';

/// Enhanced Supabase service with share functionality
class SupabaseService {
  late final SupabaseClient _client;
  static SupabaseService? _instance;
  static const int MAX_STORED_QUIZZES_PER_USER = 5;
  bool _initialized = false; // ✅ Track initialization

  SupabaseService._internal();

  factory SupabaseService() {
    return _instance ??= SupabaseService._internal();
  }

  Future<void> initialize(String supabaseUrl, String supabaseKey) async {
    try {
      _client = SupabaseClient(supabaseUrl, supabaseKey);
      await _client.from('users').select('id').limit(1);
      _initialized = true; // ✅ Mark as initialized
      print('✅ Supabase initialized');
    } catch (e) {
      print('❌ Supabase init error: $e');
      _initialized = false;
      rethrow;
    }
  }

  SupabaseClient get client => _client;

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

  // ==================== QUIZ OPERATIONS ====================

  Future<Map<String, dynamic>> saveQuiz({
    required int telegramId,
    required String subjectName,
    required int totalQuestions,
    required bool isShuffled,
    required bool answersShuffled,
    required int timePerQuestion,
    required String fileName,
    required List<Map<String, dynamic>> questions,
    String? shareCode,
  }) async {
    try {
      final userId = await getUserIdByTelegramId(telegramId);
      if (userId == null) throw Exception('User not found');

      await _cleanupOldQuizzes(userId);

      final quizData = {
        'user_id': userId,
        'subject_name': subjectName,
        'total_questions': totalQuestions,
        'is_shuffled': isShuffled,
        'answers_shuffled': answersShuffled,
        'time_per_question': timePerQuestion,
        'file_name': fileName,
        'has_stored_questions': true,
        'share_code': shareCode,
        'is_public': shareCode != null,
        'created_at': _toIsoString(DateTime.now()),
      };

      final quizResponse = await _client
          .from('quizzes')
          .insert(quizData)
          .select()
          .single();

      final quizId = quizResponse['id'] as int;

      final questionsData = questions.asMap().entries.map((entry) {
        final index = entry.key;
        final q = entry.value;
        return {
          'quiz_id': quizId,
          'question_text': q['text'],
          'options': q['options'],
          'correct_index': q['correctIndex'],
          'question_order': index,
        };
      }).toList();

      await _client.from('quiz_questions').insert(questionsData);

      print('✅ Quiz saved: $subjectName (${questions.length} questions, share: $shareCode)');
      return quizResponse;
    } catch (e) {
      print('❌ Error saving quiz: $e');
      rethrow;
    }
  }

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
        final oldQuizzes = quizList.skip(MAX_STORED_QUIZZES_PER_USER - 1);

        for (final quiz in oldQuizzes) {
          final quizId = quiz['id'];
          await _client.from('quiz_questions').delete().eq('quiz_id', quizId);
          await _client.from('quizzes')
              .update({'has_stored_questions': false})
              .eq('id', quizId);
          print('🗑 Cleaned up old quiz: $quizId');
        }
      }
    } catch (e) {
      print('⚠️ Cleanup error: $e');
    }
  }

  Future<Map<String, dynamic>?> getQuizWithQuestions(int quizId) async {
    try {
      final quizData = await _client
          .from('quizzes')
          .select()
          .eq('id', quizId)
          .single();

      if (quizData['has_stored_questions'] != true) {
        return {
          ...quizData,
          'questions': null,
          'can_restart': false,
        };
      }

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

  Future<List<Map<String, dynamic>>> getUserQuizzes(int telegramId) async {
    try {
      final userId = await getUserIdByTelegramId(telegramId);
      if (userId == null) return [];

      final response = await _client
          .from('quizzes')
          .select('id, subject_name, total_questions, is_shuffled, '
          'answers_shuffled, time_per_question, has_stored_questions, '
          'share_code, is_public, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(20);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error getting user quizzes: $e');
      return [];
    }
  }

  // ==================== SHARE FUNCTIONALITY (IMPROVED) ====================

  /// ✅ NEW: Update quiz share code (for fallback)
  Future<void> updateQuizShareCode(int quizId, String shareCode) async {
    try {
      if (!_initialized) {
        print('⚠️ Supabase not initialized, skipping share code update');
        return;
      }

      await _client.from('quizzes').update({
        'share_code': shareCode,
        'is_public': true,
      }).eq('id', quizId);

      print('✅ Share code updated for quiz $quizId: $shareCode');
    } catch (e) {
      print('❌ Error updating share code: $e');
      rethrow;
    }
  }

  /// ✅ IMPROVED: Generate share code with null safety
  Future<String?> generateShareCode(int quizId) async {
    try {
      if (!_initialized) {
        print('⚠️ Supabase not initialized, returning null');
        return null;
      }

      // Check if quiz already has a share code
      final existing = await _client
          .from('quizzes')
          .select('share_code')
          .eq('id', quizId)
          .maybeSingle();

      if (existing == null) {
        print('⚠️ Quiz $quizId not found');
        return null;
      }

      // Return existing code if available
      final existingCode = existing['share_code'];
      if (existingCode != null && existingCode.toString().isNotEmpty) {
        print('✅ Using existing share code: $existingCode');
        return existingCode as String;
      }

      // Generate new share code
      final shareCode = _generateUniqueCode();

      await _client.from('quizzes').update({
        'share_code': shareCode,
        'is_public': true,
      }).eq('id', quizId);

      print('✅ Generated new share code for quiz $quizId: $shareCode');
      return shareCode;
    } catch (e) {
      print('❌ Error generating share code: $e');
      return null; // ✅ Return null instead of throwing
    }
  }

  /// ✅ IMPROVED: Better random code generation
  String _generateUniqueCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(8, (index) => chars[random.nextInt(chars.length)]).join();
  }

  /// ✅ IMPROVED: Get quiz by share code with better error handling
  Future<Map<String, dynamic>?> getQuizByShareCode(String shareCode) async {
    try {
      if (!_initialized) {
        print('⚠️ Supabase not initialized');
        return null;
      }

      if (shareCode.isEmpty) {
        print('⚠️ Empty share code provided');
        return null;
      }

      print('🔍 Looking up quiz with share code: $shareCode');

      // ✅ Get quiz with user info
      final quizData = await _client
          .from('quizzes')
          .select('*, users!inner(username, telegram_id)')
          .eq('share_code', shareCode)
          .eq('is_public', true)
          .maybeSingle();

      if (quizData == null) {
        print('⚠️ Quiz not found for code: $shareCode');
        return null;
      }

      final quizId = quizData['id'] as int;

      // Get questions
      final questions = await _client
          .from('quiz_questions')
          .select('question_text, options, correct_index, question_order')
          .eq('quiz_id', quizId)
          .order('question_order', ascending: true);

      final questionsList = List<Map<String, dynamic>>.from(questions as List);

      // ✅ Transform questions to expected format
      final transformedQuestions = questionsList.map((q) {
        return {
          'text': q['question_text'],
          'options': List<String>.from(q['options'] as List),
          'correctIndex': q['correct_index'],
        };
      }).toList();

      // ✅ Extract username safely
      String? creatorUsername;
      if (quizData['users'] != null) {
        final users = quizData['users'];
        if (users is Map) {
          creatorUsername = users['username'] as String?;
        } else if (users is List && users.isNotEmpty) {
          final firstUser = users[0] as Map;
          creatorUsername = firstUser['username'] as String?;
        }
      }

      print('✅ Quiz found: ${quizData['subject_name']} (${transformedQuestions.length} questions)');

      return {
        'id': quizData['id'],
        'subject_name': quizData['subject_name'],
        'total_questions': quizData['total_questions'],
        'questions': transformedQuestions, // ✅ Use transformed questions
        'is_shuffled': quizData['is_shuffled'],
        'answers_shuffled': quizData['answers_shuffled'],
        'time_per_question': quizData['time_per_question'],
        'creator_username': creatorUsername ?? 'Unknown',
        'has_stored_questions': transformedQuestions.isNotEmpty,
      };
    } catch (e, stack) {
      print('❌ Error getting quiz by share code: $e');
      print('Stack: $stack');
      return null;
    }
  }

  Future<void> incrementQuizShares(int quizId) async {
    try {
      if (!_initialized) return;

      await _client.rpc('increment_quiz_shares', params: {'p_quiz_id': quizId});
    } catch (e) {
      print('⚠️ Error incrementing shares: $e');
    }
  }

  // ==================== QUIZ RESULTS ====================

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

      final response = await _client
          .from('quiz_results')
          .insert(data)
          .select()
          .single();

      print('✅ Quiz result saved');
      return response;
    } catch (e) {
      print('❌ Error saving quiz result: $e');
      rethrow;
    }
  }

  // ==================== STATISTICS ====================

  Future<Map<String, dynamic>> getUserStats(int telegramId) async {
    try {
      final user = await getUser(telegramId);
      if (user == null) return {};

      final userId = user['id'] as int;

      final quizzesResponse = await _client
          .from('quizzes')
          .select('id')
          .eq('user_id', userId);

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

  Future<Map<String, dynamic>> getAdminStats() async {
    try {
      final futures = await Future.wait([
        getTotalUsersCount(),
        getActiveUsersCount(),
        _getTotalQuizzesCount(),
        _getTotalCompletedTestsCount(),
        _getStoredQuestionsCount(),
        _getTotalSharedQuizzes(),
      ]);

      return {
        'total_users': futures[0],
        'active_users_24h': futures[1],
        'total_quizzes': futures[2],
        'total_completed_tests': futures[3],
        'stored_questions': futures[4],
        'shared_quizzes': futures[5],
      };
    } catch (e) {
      print('❌ Error getting admin stats: $e');
      return {};
    }
  }

  Future<int> getTotalUsersCount() async {
    try {
      final response = await _client.from('users').select('id');
      return _safeResponseLength(response);
    } catch (e) {
      return 0;
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
      return 0;
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
      final response = await _client
          .from('quiz_results')
          .select('id')
          .eq('is_completed', true);
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

  Future<int> _getTotalSharedQuizzes() async {
    try {
      final response = await _client
          .from('quizzes')
          .select('id')
          .eq('is_public', true);
      return _safeResponseLength(response);
    } catch (e) {
      return 0;
    }
  }

  void dispose() {
    _instance = null;
    _initialized = false;
  }
}