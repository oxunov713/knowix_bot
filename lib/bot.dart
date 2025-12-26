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
    _bot = Bot(token);
    _quizService = QuizService();
    _sessionManager = QuizSessionManager();

    // Initialize handlers
    final messageHandler = MessageHandler(_quizService, _sessionManager);
    final pollAnswerHandler = PollAnswerHandler(_sessionManager);
    _updateHandler = UpdateHandler(messageHandler, pollAnswerHandler);

    // Setup handlers
    _updateHandler.setupHandlers(_bot);
  }

  /// Start the bot
  Future<void> start() async {
    print('🤖 Quiz Bot starting...');

    final me = await _bot.getMe();
    print('✅ Bot started: @${me.username}');
    print('📊 Active sessions: ${_sessionManager.sessionCount}');

    await _bot.start();
  }

  /// Stop the bot
  Future<void> stop() async {
    print('🛑 Stopping bot...');
    _sessionManager.clearAll();
    await _bot.stop();
    print('✅ Bot stopped');
  }
}