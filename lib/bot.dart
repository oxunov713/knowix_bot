import 'dart:io';
import 'dart:async';
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
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;

  QuizBot(String token, String supabaseUrl, String supabaseKey) {
    print('🔧 [QuizBot] Initializing...');

    try {
      // ✅ FIX: Better LongPolling configuration
      _bot = Bot(
        token,
        fetcher: LongPolling(
          limit: 50, // ✅ Reduced from 100 (less load)
          timeout: 25, // ✅ Reduced from 30 (faster recovery)
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

  /// Start the bot with auto-reconnect
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
      _reconnectAttempts = 0;

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

      // ✅ FIX: Start polling with error recovery
      _startPollingWithRecovery();

      print('✅ [QuizBot] Bot is now running!');
      _printBotInfo();

    } catch (e, stack) {
      print('❌ [QuizBot] Start failed: $e');
      print('Stack trace: $stack');
      _isRunning = false;

      // ✅ Auto-retry on start failure
      if (_reconnectAttempts < maxReconnectAttempts) {
        _scheduleReconnect();
      }
    }
  }

  /// ✅ NEW: Start polling with automatic recovery
  void _startPollingWithRecovery() {
    _bot.start().then((_) {
      print('⚠️  [QuizBot] Polling ended normally');
      _isRunning = false;

      // Auto-reconnect if it wasn't a manual stop
      if (_reconnectAttempts < maxReconnectAttempts) {
        _scheduleReconnect();
      }
    }).catchError((e, stack) {
      print('❌ [QuizBot] Polling error: $e');
      print('Stack trace: $stack');
      _isRunning = false;

      // ✅ Handle specific errors
      if (e is SocketException) {
        print('🌐 [QuizBot] Network error - will retry');
      } else if (e is TimeoutException) {
        print('⏰ [QuizBot] Timeout error - will retry');
      } else if (e.toString().contains('409')) {
        print('⚠️  [QuizBot] Conflict error (another bot instance?) - stopping');
        return; // Don't retry on conflict
      }

      // Auto-reconnect
      if (_reconnectAttempts < maxReconnectAttempts) {
        _scheduleReconnect();
      } else {
        print('❌ [QuizBot] Max reconnect attempts reached. Manual restart needed.');
      }
    });
  }

  /// ✅ NEW: Schedule reconnection with exponential backoff
  void _scheduleReconnect() {
    _reconnectAttempts++;

    // Exponential backoff: 5s, 10s, 20s, 40s, 60s
    final delaySeconds = (5 * (1 << (_reconnectAttempts - 1))).clamp(5, 60);

    print('🔄 [QuizBot] Reconnecting in ${delaySeconds}s (attempt $_reconnectAttempts/$maxReconnectAttempts)...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      print('🔄 [QuizBot] Attempting reconnection...');
      start();
    });
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
    print('   🔌 Auto-reconnect on network errors');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📡 Waiting for updates...\n');
  }

  /// Stop the bot
  Future<void> stop() async {
    print('🛑 [QuizBot] Stopping...');

    try {
      _isRunning = false;
      _reconnectTimer?.cancel();
      _reconnectAttempts = maxReconnectAttempts; // Prevent auto-reconnect

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
        'reconnect_attempts': _reconnectAttempts,
        'uptime_seconds': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ...supabaseStats,
      };
    } catch (e) {
      print('⚠️  [QuizBot] Stats error: $e');
      return {
        'bot_running': _isRunning,
        'active_sessions': _sessionManager.sessionCount,
        'total_messages': _messageCount,
        'reconnect_attempts': _reconnectAttempts,
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
        'reconnect_attempts': _reconnectAttempts,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'is_running': _isRunning,
        'message_count': _messageCount,
        'reconnect_attempts': _reconnectAttempts,
      };
    }
  }

  /// Restart bot (useful for Railway deployments)
  Future<void> restart() async {
    print('🔄 [QuizBot] Restarting...');

    try {
      await stop();
      await Future.delayed(Duration(seconds: 2));
      _reconnectAttempts = 0; // Reset counter
      await start();
      print('✅ [QuizBot] Restart complete');
    } catch (e) {
      print('❌ [QuizBot] Restart failed: $e');
      rethrow;
    }
  }

  /// ✅ NEW: Force reconnect
  Future<void> forceReconnect() async {
    print('🔄 [QuizBot] Force reconnecting...');
    _reconnectAttempts = 0;
    await restart();
  }

  /// Get current status
  String getStatus() {
    if (_isRunning) {
      return 'Running ✅';
    } else if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      return 'Reconnecting... 🔄';
    } else {
      return 'Stopped ❌';
    }
  }

  /// Get session count
  int getSessionCount() {
    return _sessionManager.sessionCount;
  }

  /// ✅ NEW: Cleanup and dispose
  void dispose() {
    _reconnectTimer?.cancel();
    _sessionManager.clearAll();
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}