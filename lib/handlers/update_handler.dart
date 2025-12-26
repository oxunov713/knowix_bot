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
    // Command handlers
    bot.command('start', messageHandler.handleStart);
    bot.command('help', messageHandler.handleHelp);
    bot.command('stop', messageHandler.handleStop);

    // Document and text message handler
    bot.onMessage((ctx) async {
      if (ctx.message!.document != null) {
        await messageHandler.handleDocument(ctx);
      } else if (ctx.message!.text != null) {
        final text = ctx.message!.text!;
        // Ignore commands (already handled by bot.command)
        if (!text.startsWith('/')) {
          await messageHandler.handleText(ctx);
        }
      }
    });

    // Callback query handler
    bot.onCallbackQuery((ctx) async {
      final data = ctx.callbackQuery?.data;

      // Quiz control callbacks (continue/finish/restart)
      if (data == 'quiz_continue' ||
          data == 'quiz_finish' ||
          data == 'quiz_restart') {
        await pollAnswerHandler.handleQuizControl(ctx);
      }
      // Shuffle choice and time selection callbacks
      else {
        await messageHandler.handleCallback(ctx);
      }
    });

    // Poll answer handler
    bot.onPollAnswer((ctx) async {
      await pollAnswerHandler.handlePollAnswer(ctx);
    });

    // Error handler
    bot.onError((error) {
      print('❌ Bot error: $error');
    });
  }
}