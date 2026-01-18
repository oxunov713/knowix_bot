import 'dart:io';
import 'package:televerse/televerse.dart';

import 'handlers/message_handler.dart';
import 'handlers/poll_answer_handler.dart';
import 'handlers/share_handler.dart';
import 'handlers/update_handler.dart';
import 'services/quiz_service.dart';
import 'services/quiz_session_manager.dart';
import 'services/supabase_service.dart';

/// Production-ready Quiz Bot with comprehensive error handling
class QuizBot {
  late final Bot _bot;
  late final QuizService _quizService;
  late final QuizSessionManager _sessionManager;
  late final SupabaseService _supabaseService;
  late final UpdateHandler _updateHandler;
  bool _isRunning = false;
  int _messageCount = 0;

  QuizBot(String token, String supabaseUrl, String supabaseKey) {
    print('🔧 [QuizBot] Initializing...');

    try {
      _bot = Bot(
        token,
        fetcher: LongPolling(
          limit: 100,
          timeout: 30,
          allowedUpdates: [
            UpdateType.message,
            UpdateType.callbackQuery,
            UpdateType.pollAnswer,
          ],
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
    } catch (e, stack) {
      print('❌ [QuizBot] Initialization failed: $e');
      print('Stack trace: $stack');
      rethrow;
    }
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

      final me = await _bot.getMe().timeout(
        Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Bot connection timeout');
        },
      );

      print('✅ [QuizBot] Connected as: @${me.username}');
      print('📋 [QuizBot] Bot name: ${me.firstName}');
      print('🆔 [QuizBot] Bot ID: ${me.id}');

      _isRunning = true;

      // Message counter with logging
      _bot.onMessage((ctx) {
        _messageCount++;
        final username = ctx.from?.username ?? 'unknown';
        final type = ctx.message?.document != null
            ? '[📄 document]'
            : ctx.message?.text ?? '[media]';

        if (_messageCount % 10 == 0) {
          print('📊 [QuizBot] Total messages processed: $_messageCount');
        }

        print('📨 [$_messageCount] $username: $type');
      });

      print('🚀 [QuizBot] Starting polling...');

      // Start polling with error handling
      _bot.start().then((_) {
        print('⚠️  [QuizBot] Polling ended normally');
        _isRunning = false;
      }).catchError((e, stack) {
        print('❌ [QuizBot] Polling error: $e');
        print('Stack trace: $stack');
        _isRunning = false;
      });

      print('✅ [QuizBot] Bot is now running!');
      _printBotInfo();

    } catch (e, stack) {
      print('❌ [QuizBot] Start failed: $e');
      print('Stack trace: $stack');
      _isRunning = false;
      rethrow;
    }
  }

  /// Print bot information
  void _printBotInfo() {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🎯 HEMIS Quiz Bot - Production Ready');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('✨ Features:');
    print('   🔀 Smart question shuffling');
    print('   🎲 Answer shuffling with tracking');
    print('   📤 Quiz sharing via deep links');
    print('   💾 Hybrid storage (5 quizzes)');
    print('   📊 Statistics & analytics');
    print('   ⏱️  Custom time limits');
    print('   🔄 Pause & resume');
    print('   🛡️  Comprehensive error handling');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📡 Waiting for updates...\n');
  }

  /// Stop the bot
  Future<void> stop() async {
    print('🛑 [QuizBot] Stopping...');

    try {
      _isRunning = false;
      _sessionManager.clearAll();
      await _bot.stop();
      print('✅ [QuizBot] Stopped successfully');
      print('📊 Total messages processed: $_messageCount');
    } catch (e) {
      print('❌ [QuizBot] Error during stop: $e');
    }
  }

  /// Get bot statistics
  Future<Map<String, dynamic>> getStats() async {
    try {
      final supabaseStats = await _supabaseService.getAdminStats();

      return {
        'bot_running': _isRunning,
        'active_sessions': _sessionManager.sessionCount,
        'total_messages': _messageCount,
        'uptime_seconds': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ...supabaseStats,
      };
    } catch (e) {
      print('⚠️  [QuizBot] Stats error: $e');
      return {
        'bot_running': _isRunning,
        'active_sessions': _sessionManager.sessionCount,
        'total_messages': _messageCount,
        'error': e.toString(),
      };
    }
  }

  /// Check bot health
  Future<bool> healthCheck() async {
    try {
      await _bot.getMe().timeout(Duration(seconds: 5));
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
        'is_running': _isRunning,
        'message_count': _messageCount,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'is_running': _isRunning,
        'message_count': _messageCount,
      };
    }
  }

  /// Restart bot (useful for Railway deployments)
  Future<void> restart() async {
    print('🔄 [QuizBot] Restarting...');

    try {
      await stop();
      await Future.delayed(Duration(seconds: 2));
      await start();
      print('✅ [QuizBot] Restart complete');
    } catch (e) {
      print('❌ [QuizBot] Restart failed: $e');
      rethrow;
    }
  }

  /// Get current status
  String getStatus() {
    return _isRunning ? 'Running ✅' : 'Stopped ❌';
  }

  /// Get session count
  int getSessionCount() {
    return _sessionManager.sessionCount;
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}