import 'dart:async';
import 'package:televerse/televerse.dart';
import 'services/quiz_service.dart';
import 'services/quiz_session_manager.dart';
import 'handlers/update_handler.dart';
import 'handlers/message_handler.dart';
import 'handlers/poll_answer_handler.dart';

class QuizBot {
  late final Bot _bot;
  late final QuizService _quizService;
  late final QuizSessionManager _sessionManager;
  late final UpdateHandler _updateHandler;
  bool _isRunning = false;

  QuizBot(String token) {
    print('🔧 Bot init...');

    _bot = Bot(
      token,
      fetcher: LongPolling(
        limit: 100,
        timeout: 30,
      ),
    );

    _quizService = QuizService();
    _sessionManager = QuizSessionManager();

    final messageHandler = MessageHandler(_quizService, _sessionManager);
    final pollAnswerHandler = PollAnswerHandler(_sessionManager);
    _updateHandler = UpdateHandler(messageHandler, pollAnswerHandler);

    _updateHandler.setupHandlers(_bot);

    print('✅ Bot ready');
  }

  Future<void> start() async {
    if (_isRunning) {
      print('⚠️ Bot already running');
      return;
    }

    try {
      print('🔍 Testing Telegram connection...');
      final me = await _bot.getMe();
      print('✅ Connected: @${me.username}');

      _isRunning = true;

      // Test message handler
      var msgCount = 0;
      _bot.onMessage((ctx) {
        msgCount++;
        print('📨 #$msgCount: ${ctx.from?.username ?? "?"} - ${ctx.message?.text ?? "[media]"}');
      });

      print('🔄 Polling started');

      // Start polling WITHOUT await to prevent blocking
      _bot.start().then((_) {
        print('⚠️ Polling ended unexpectedly');
        _isRunning = false;
      }).catchError((e) {
        print('❌ Polling error: $e');
        _isRunning = false;
      });

      // Return immediately
      print('✅ Bot is now polling in background');

    } catch (e, stack) {
      print('❌ Start error: $e');
      print(stack);
      _isRunning = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    print('🛑 Stopping...');
    _isRunning = false;
    _sessionManager.clearAll();
    await _bot.stop();
    print('✅ Stopped');
  }
}