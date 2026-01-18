import 'package:televerse/televerse.dart';
import 'message_handler.dart';
import 'poll_answer_handler.dart';
import 'share_handler.dart';

/// Routes updates to appropriate handlers with share support
class UpdateHandler {
  final MessageHandler messageHandler;
  final PollAnswerHandler pollAnswerHandler;
  final ShareHandler shareHandler;

  UpdateHandler(
      this.messageHandler,
      this.pollAnswerHandler,
      this.shareHandler,
      );

  /// Setup all handlers
  void setupHandlers(Bot bot) {
    print('🔧 [UpdateHandler] Setting up handlers...');

    // Command handlers
    bot.command('start', (ctx) async {
      print('📍 [Handler] /start from ${ctx.from?.username ?? "unknown"}');

      // Check for deep link (shared quiz)
      final text = ctx.message?.text;
      if (text != null && text.contains(' ')) {
        final parts = text.split(' ');
        if (parts.length > 1 && parts[1].startsWith('quiz_')) {
          final shareCode = parts[1].substring(5);
          print('📤 [Handler] Shared quiz detected: $shareCode');
          await shareHandler.handleSharedQuizStart(ctx, shareCode);
          return;
        }
      }

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

    bot.command('quizlarim', (ctx) async {
      print('📍 [Handler] /quizlarim from ${ctx.from?.username ?? "unknown"}');
      await messageHandler.handleMyQuizzes(ctx);
    });

    bot.command('statistika', (ctx) async {
      print('📍 [Handler] /statistika from ${ctx.from?.username ?? "unknown"}');
      await messageHandler.handleStatistics(ctx);
    });

    bot.command('share', (ctx) async {
      print('📍 [Handler] /share from ${ctx.from?.username ?? "unknown"}');
      await shareHandler.handleShare(ctx);
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
            print('💬 [Handler] Text: ${text.length > 50 ? text.substring(0, 50) + "..." : text}');
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
        print('🔘 [Handler] Callback: $data');

        if (data == null) return;

        // Quiz control
        if (data == 'quiz_continue' || data == 'quiz_finish') {
          await pollAnswerHandler.handleQuizControl(ctx);
          return;
        }

        // Share callbacks
        if (data.startsWith('share_select:')) {
          final quizId = int.tryParse(data.substring(13));
          if (quizId != null) {
            await shareHandler.handleShareCallback(ctx, quizId);
          }
          return;
        }

        if (data.startsWith('start_shared:')) {
          final shareCode = data.substring(13);
          await shareHandler.startSharedQuiz(ctx, shareCode);
          return;
        }

        if (data.startsWith('customize_shared:')) {
          final shareCode = data.substring(17);
          await shareHandler.startSharedQuiz(ctx, shareCode, customize: true);
          return;
        }

        if (data.startsWith('customize_q:')) {
          final shareCode = data.substring(12);
          // Apply question shuffle
          await shareHandler.startSharedQuiz(ctx, shareCode);
          return;
        }

        if (data.startsWith('customize_a:')) {
          final shareCode = data.substring(12);
          // Apply answer shuffle
          await shareHandler.startSharedQuiz(ctx, shareCode);
          return;
        }

        if (data.startsWith('customize_b:')) {
          final shareCode = data.substring(12);
          // Apply both shuffles
          await shareHandler.startSharedQuiz(ctx, shareCode);
          return;
        }

        if (data == 'cancel_shared') {
          await ctx.answerCallbackQuery(text: '❌ Bekor qilindi');
          await ctx.editMessageText(
            '❌ *Bekor qilindi*\n\n'
                'Yangi quiz: /start',
            parseMode: ParseMode.markdown,
          );
          return;
        }

        if (data == 'back_to_quizzes') {
          await ctx.answerCallbackQuery(text: '🔙 Orqaga');
          await messageHandler.handleMyQuizzes(ctx);
          return;
        }

        // Default callback handling
        await messageHandler.handleCallback(ctx);

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
      print('❌ [UpdateHandler] Bot error:');
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