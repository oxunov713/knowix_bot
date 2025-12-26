import 'package:televerse/televerse.dart';
import 'services/quiz_service.dart';
import 'services/quiz_session_manager.dart';
import 'handlers/update_handler.dart';
import 'handlers/message_handler.dart';
import 'handlers/poll_answer_handler.dart';

/// Main bot class with MVVM architecture
class QuizBot {
  late final Bot _bot;
  late final QuizService _quizService;
  late final QuizSessionManager _sessionManager;
  late final UpdateHandler _updateHandler;

  QuizBot(String token) {
    print('🔧 [Bot] Creating Bot instance...');

    // POLLING rejimini aniq belgilash
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

    print('✅ [Bot] Bot instance created with LongPolling');

    _quizService = QuizService();
    _sessionManager = QuizSessionManager();
    print('✅ [Bot] Services initialized');

    // Initialize handlers
    final messageHandler = MessageHandler(_quizService, _sessionManager);
    final pollAnswerHandler = PollAnswerHandler(_sessionManager);
    _updateHandler = UpdateHandler(messageHandler, pollAnswerHandler);
    print('✅ [Bot] Handlers created');

    // Setup handlers
    _updateHandler.setupHandlers(_bot);
    print('✅ [Bot] Handlers registered to bot');

    // Global error handler with logging
    _bot.onError((BotError err) {
      print('❌ [Bot] Error occurred:');
      print('   Type: ${err.error.runtimeType}');
      print('   Message: ${err.error}');
      if (err.stackTrace != null) {
        print('   Stack: ${err.stackTrace}');
      }
    });

    print('✅ [Bot] Error handler registered');
  }

  /// Start the bot
  Future<void> start() async {
    print('🤖 [Bot] Starting bot polling...');

    try {
      // Test connection first
      print('🔍 [Bot] Testing connection to Telegram...');
      final me = await _bot.getMe();
      print('✅ [Bot] Connected successfully!');
      print('   Username: @${me.username}');
      print('   Name: ${me.firstName}');
      print('   ID: ${me.id}');
      print('📊 [Bot] Active sessions: ${_sessionManager.sessionCount}');

      // Add a simple test handler
      var messageCount = 0;
      _bot.onMessage((ctx) {
        messageCount++;
        final from = ctx.from?.username ?? ctx.from?.firstName ?? 'unknown';
        final text = ctx.message?.text ?? '[no text]';
        print('📨 [Bot] Message #$messageCount from @$from: $text');
      });

      // Start polling
      print('🔄 [Bot] Starting long polling loop...');
      print('⏳ [Bot] Waiting for updates from Telegram...');

      await _bot.start();

      print('🛑 [Bot] Polling loop ended (this should not happen)');

    } catch (e, stackTrace) {
      print('❌ [Bot] Fatal error during start:');
      print('   Error: $e');
      print('   Stack trace:');
      print(stackTrace);
      rethrow;
    }
  }

  /// Stop the bot
  Future<void> stop() async {
    print('🛑 [Bot] Stopping bot...');
    _sessionManager.clearAll();
    await _bot.stop();
    print('✅ [Bot] Bot stopped');
  }
}