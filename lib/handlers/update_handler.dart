import 'package:televerse/televerse.dart';
import 'message_handler.dart';
import 'poll_answer_handler.dart';

/// Routes updates to appropriate handlers
class UpdateHandler {
  final MessageHandler messageHandler;
  final PollAnswerHandler pollAnswerHandler;

  UpdateHandler(this.messageHandler, this.pollAnswerHandler);

  /// Setup all handlers
  void setupHandlers(Bot bot) {
    print('🔧 [UpdateHandler] Setting up handlers...');

    // Command handlers
    bot.command('start', (ctx) async {
      print('📍 [Handler] /start from ${ctx.from?.username ?? "unknown"}');
      await messageHandler.handleStart(ctx);
    });

    bot.command('help', (ctx) async {
      print('📍 [Handler] /help from ${ctx.from?.username ?? "unknown"}');
      await messageHandler.handleHelp(ctx);
    });

    bot.command('stop', (ctx) async {
      print('📍 [Handler] /stop from ${ctx.from?.username ?? "unknown"}');
      await messageHandler.handleStop(ctx);
    });

    // YANGI: Quizlarim buyrug'i
    bot.command('quizlarim', (ctx) async {
      print('📍 [Handler] /quizlarim from ${ctx.from?.username ?? "unknown"}');
      await messageHandler.handleMyQuizzes(ctx);
    });

    // YANGI: Statistika buyrug'i
    bot.command('statistika', (ctx) async {
      print('📍 [Handler] /statistika from ${ctx.from?.username ?? "unknown"}');
      await messageHandler.handleStatistics(ctx);
    });

    print('✅ [UpdateHandler] Command handlers registered');

    // Document and text message handler
    bot.onMessage((ctx) async {
      try {
        if (ctx.message!.document != null) {
          print('📄 [Handler] Document from ${ctx.from?.username ?? "unknown"}');
          await messageHandler.handleDocument(ctx);
        } else if (ctx.message!.text != null) {
          final text = ctx.message!.text!;
          if (!text.startsWith('/')) {
            print('💬 [Handler] Text message from ${ctx.from?.username ?? "unknown"}: ${text.length > 50 ? text.substring(0, 50) + "..." : text}');
            await messageHandler.handleText(ctx);
          }
        }
      } catch (e) {
        print('❌ [Handler] onMessage error: $e');
      }
    });

    print('✅ [UpdateHandler] Message handler registered');

    // Callback query handler
    bot.onCallbackQuery((ctx) async {
      try {
        final data = ctx.callbackQuery?.data;
        print('🔘 [Handler] Callback from ${ctx.from?.username ?? "unknown"}: $data');

        if (data == 'quiz_continue' ||
            data == 'quiz_finish' ||
            data == 'quiz_restart') {
          await pollAnswerHandler.handleQuizControl(ctx);
        } else {
          await messageHandler.handleCallback(ctx);
        }
      } catch (e) {
        print('❌ [Handler] onCallbackQuery error: $e');
      }
    });

    print('✅ [UpdateHandler] Callback handler registered');

    // Poll answer handler
    bot.onPollAnswer((ctx) async {
      try {
        print('📊 [Handler] Poll answer from ${ctx.from?.username ?? "unknown"}');
        await pollAnswerHandler.handlePollAnswer(ctx);
      } catch (e) {
        print('❌ [Handler] onPollAnswer error: $e');
      }
    });

    print('✅ [UpdateHandler] Poll handler registered');

    // Error handler
    bot.onError((error) {
      print('❌ [UpdateHandler] Bot error captured:');
      print('   Error: ${error.error}');
      print('   Type: ${error.error.runtimeType}');
      if (error.stackTrace != null) {
        print('   Stack: ${error.stackTrace}');
      }
    });

    print('✅ [UpdateHandler] Error handler registered');
    print('🎉 [UpdateHandler] All handlers setup complete!');
  }
}