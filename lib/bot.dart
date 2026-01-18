import 'dart:io';
import 'package:televerse/televerse.dart';

import 'handlers/message_handler.dart';
import 'handlers/poll_answer_handler.dart';
import 'handlers/share_handler.dart';
import 'handlers/update_handler.dart';
import 'services/quiz_service.dart';
import 'services/quiz_session_manager.dart';
import 'services/supabase_service.dart';

/// Enhanced Quiz Bot with shuffle and share functionality
class QuizBot {
  late final Bot _bot;
  late final QuizService _quizService;
  late final QuizSessionManager _sessionManager;
  late final SupabaseService _supabaseService;
  late final UpdateHandler _updateHandler;
  bool _isRunning = false;

  QuizBot(String token, String supabaseUrl, String supabaseKey) {
    print('🔧 [QuizBot] Initializing...');

    _bot = Bot(
      token,
      fetcher: LongPolling(
        limit: 100,
        timeout: 30,
      ),
    );

    _quizService = QuizService();
    _sessionManager = QuizSessionManager();
    _supabaseService = SupabaseService();

    // Initialize Supabase
    _initializeSupabase(supabaseUrl, supabaseKey);

    // Create handlers
    final messageHandler = MessageHandler(
      _quizService,
      _sessionManager,
      _supabaseService,
    );

    final pollAnswerHandler = PollAnswerHandler(
      _sessionManager,
      _supabaseService,
    );

    final shareHandler = ShareHandler(
      _supabaseService,
      _sessionManager,
    );

    _updateHandler = UpdateHandler(
      messageHandler,
      pollAnswerHandler,
      shareHandler,
    );

    _updateHandler.setupHandlers(_bot);

    print('✅ [QuizBot] Initialization complete');
  }

  /// Initialize Supabase connection
  Future<void> _initializeSupabase(String url, String key) async {
    try {
      await _supabaseService.initialize(url, key);
      print('✅ [QuizBot] Supabase connected');
    } catch (e) {
      print('❌ [QuizBot] Supabase error: $e');
      print('⚠️  [QuizBot] Running without database (features limited)');
    }
  }

  /// Start the bot
  Future<void> start() async {
    if (_isRunning) {
      print('⚠️  [QuizBot] Already running');
      return;
    }

    try {
      print('🔍 [QuizBot] Testing connection...');
      final me = await _bot.getMe();
      print('✅ [QuizBot] Connected as: @${me.username}');
      print('📋 [QuizBot] Bot name: ${me.firstName}');
      print('🆔 [QuizBot] Bot ID: ${me.id}');

      _isRunning = true;

      // Message counter
      var messageCount = 0;
      _bot.onMessage((ctx) {
        messageCount++;
        final username = ctx.from?.username ?? 'unknown';
        final type = ctx.message?.document != null ? '[📄 document]'
            : ctx.message?.text ?? '[media]';
        print('📨 [$messageCount] $username: $type');
      });

      print('🚀 [QuizBot] Starting polling...');

      // Start polling in background
      _bot.start().then((_) {
        print('⚠️  [QuizBot] Polling ended');
        _isRunning = false;
      }).catchError((e) {
        print('❌ [QuizBot] Polling error: $e');
        _isRunning = false;
      });

      print('✅ [QuizBot] Bot is now running!');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🎯 Bot Features:');
      print('   🔀 Smart question shuffling');
      print('   🎲 Answer shuffling with tracking');
      print('   📤 Quiz sharing via links');
      print('   💾 Hybrid storage (5 quizzes)');
      print('   📊 Statistics & analytics');
      print('   ⏱️  Custom time limits');
      print('   🔄 Pause & resume');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📡 Waiting for updates...\n');

    } catch (e, stack) {
      print('❌ [QuizBot] Start failed: $e');
      print(stack);
      _isRunning = false;
      rethrow;
    }
  }

  /// Stop the bot
  Future<void> stop() async {
    print('🛑 [QuizBot] Stopping...');
    _isRunning = false;
    _sessionManager.clearAll();
    await _bot.stop();
    print('✅ [QuizBot] Stopped successfully');
  }

  /// Get bot statistics
  Future<Map<String, dynamic>> getStats() async {
    try {
      final supabaseStats = await _supabaseService.getAdminStats();

      return {
        'bot_running': _isRunning,
        'active_sessions': _sessionManager.sessionCount,
        ...supabaseStats,
      };
    } catch (e) {
      print('⚠️  [QuizBot] Stats error: $e');
      return {
        'bot_running': _isRunning,
        'active_sessions': _sessionManager.sessionCount,
        'error': e.toString(),
      };
    }
  }

  /// Check bot health
  Future<bool> healthCheck() async {
    try {
      await _bot.getMe();
      return true;
    } catch (e) {
      print('❌ [QuizBot] Health check failed: $e');
      return false;
    }
  }

  /// Get bot info
  Future<Map<String, dynamic>> getInfo() async {
    try {
      final me = await _bot.getMe();
      return {
        'id': me.id,
        'username': me.username,
        'first_name': me.firstName,
        'is_bot': me.isBot,
        'can_join_groups': me.canJoinGroups,
        'can_read_all_group_messages': me.canReadAllGroupMessages,
        'supports_inline_queries': me.supportsInlineQueries,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}

