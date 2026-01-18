import 'package:televerse/televerse.dart';
import 'message_handler.dart';
import 'poll_answer_handler.dart';
import 'share_handler.dart';

/// Optimized update handler with comprehensive error handling
class UpdateHandler {
  final MessageHandler messageHandler;
  final PollAnswerHandler pollAnswerHandler;
  final ShareHandler shareHandler;

  UpdateHandler(
      this.messageHandler,
      this.pollAnswerHandler,
      this.shareHandler,
      );

  /// Setup all handlers with error handling
  void setupHandlers(Bot bot) {
    print('🔧 [UpdateHandler] Setting up handlers...');

    // Command: /start
    bot.command('start', (ctx) async {
      try {
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
      } catch (e, stack) {
        print('❌ [Handler] /start error: $e');
        print('Stack: $stack');
        await _sendErrorReply(ctx, 'Xatolik yuz berdi. Qaytadan urinib ko\'ring.');
      }
    });

    // Command: /help
    bot.command('help', (ctx) async {
      try {
        print('📍 [Handler] /help from ${ctx.from?.username ?? "unknown"}');
        await messageHandler.handleHelp(ctx);
      } catch (e) {
        print('❌ [Handler] /help error: $e');
        await _sendErrorReply(ctx, 'Yordam ko\'rsatishda xatolik.');
      }
    });

    // Command: /stop
    bot.command('stop', (ctx) async {
      try {
        print('📍 [Handler] /stop from ${ctx.from?.username ?? "unknown"}');
        await messageHandler.handleStop(ctx);
      } catch (e) {
        print('❌ [Handler] /stop error: $e');
        await _sendErrorReply(ctx, 'To\'xtatishda xatolik.');
      }
    });

    // Command: /quizlarim
    bot.command('quizlarim', (ctx) async {
      try {
        print('📍 [Handler] /quizlarim from ${ctx.from?.username ?? "unknown"}');
        await messageHandler.handleMyQuizzes(ctx);
      } catch (e) {
        print('❌ [Handler] /quizlarim error: $e');
        await _sendErrorReply(ctx, 'Quizlar yuklanmadi. Qaytadan urinib ko\'ring.');
      }
    });

    // Command: /statistika
    bot.command('statistika', (ctx) async {
      try {
        print('📍 [Handler] /statistika from ${ctx.from?.username ?? "unknown"}');
        await messageHandler.handleStatistics(ctx);
      } catch (e) {
        print('❌ [Handler] /statistika error: $e');
        await _sendErrorReply(ctx, 'Statistika yuklanmadi.');
      }
    });

    // Command: /share
    bot.command('share', (ctx) async {
      try {
        print('📍 [Handler] /share from ${ctx.from?.username ?? "unknown"}');
        await shareHandler.handleShare(ctx);
      } catch (e) {
        print('❌ [Handler] /share error: $e');
        await _sendErrorReply(ctx, 'Ulashishda xatolik yuz berdi.');
      }
    });

    print('✅ [UpdateHandler] Command handlers registered');

    // Message handler (documents and text)
    bot.onMessage((ctx) async {
      try {
        if (ctx.message?.document != null) {
          print('📄 [Handler] Document from ${ctx.from?.username ?? "unknown"}');
          await messageHandler.handleDocument(ctx);
        } else if (ctx.message?.text != null) {
          final text = ctx.message!.text!;
          if (!text.startsWith('/')) {
            final preview = text.length > 50 ? '${text.substring(0, 50)}...' : text;
            print('💬 [Handler] Text: $preview');
            await messageHandler.handleText(ctx);
          }
        }
      } catch (e, stack) {
        print('❌ [Handler] onMessage error: $e');
        print('Stack: $stack');
        await _sendErrorReply(ctx, 'Xatolik yuz berdi.');
      }
    });

    print('✅ [UpdateHandler] Message handler registered');

    // Callback query handler
    bot.onCallbackQuery((ctx) async {
      try {
        final data = ctx.callbackQuery?.data;
        print('🔘 [Handler] Callback: $data');

        if (data == null) {
          print('⚠️ [Handler] Callback data is null');
          return;
        }

        // Quiz control
        if (data == 'quiz_continue' || data == 'quiz_finish') {
          await pollAnswerHandler.handleQuizControl(ctx);
          return;
        }

        // Share quiz selection
        if (data.startsWith('share_select:')) {
          final quizId = int.tryParse(data.substring(13));
          if (quizId != null) {
            await shareHandler.handleShareCallback(ctx, quizId);
          } else {
            print('⚠️ [Handler] Invalid quiz ID in share_select');
          }
          return;
        }

        // Start shared quiz
        if (data.startsWith('start_shared:')) {
          final shareCode = data.substring(13);
          await shareHandler.startSharedQuiz(ctx, shareCode);
          return;
        }

        // Customize shared quiz
        if (data.startsWith('customize_shared:')) {
          final shareCode = data.substring(17);
          await shareHandler.startSharedQuiz(ctx, shareCode, customize: true);
          return;
        }

        // Cancel shared quiz
        if (data == 'cancel_shared') {
          await ctx.answerCallbackQuery(text: '❌ Bekor qilindi');
          await ctx.editMessageText(
            '❌ *Bekor qilindi*\n\nYangi quiz: /start',
            parseMode: ParseMode.markdown,
          );
          return;
        }

        // Back to quizzes
        if (data == 'back_to_quizzes') {
          await ctx.answerCallbackQuery(text: '🔙 Orqaga');
          await messageHandler.handleMyQuizzes(ctx);
          return;
        }

        // Default callback handling (shuffle, time, etc.)
        await messageHandler.handleCallback(ctx);

      } catch (e, stack) {
        print('❌ [Handler] onCallbackQuery error: $e');
        print('Stack: $stack');

        try {
          await ctx.answerCallbackQuery(text: '❌ Xatolik yuz berdi');
        } catch (e) {
          print('❌ [Handler] Failed to answer callback: $e');
        }
      }
    });

    print('✅ [UpdateHandler] Callback handler registered');

    // Poll answer handler
    bot.onPollAnswer((ctx) async {
      try {
        final username = ctx.from?.username ?? 'unknown';
        print('📊 [Handler] Poll answer from $username');
        await pollAnswerHandler.handlePollAnswer(ctx);
      } catch (e, stack) {
        print('❌ [Handler] onPollAnswer error: $e');
        print('Stack: $stack');
      }
    });

    print('✅ [UpdateHandler] Poll handler registered');

    // Error handler
    bot.onError((error) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('❌ [UpdateHandler] BOT ERROR:');
      print('   Type: ${error.error.runtimeType}');
      print('   Error: ${error.error}');
      if (error.stackTrace != null) {
        print('   Stack trace:');
        print('${error.stackTrace}'.split('\n').take(5).join('\n'));
      }
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    });

    print('✅ [UpdateHandler] Error handler registered');
    print('🎉 [UpdateHandler] All handlers setup complete!');
  }

  /// Send error reply safely
  Future<void> _sendErrorReply(Context ctx, String message) async {
    try {
      await ctx.reply(
        '❌ *Xatolik!*\n\n$message',
        parseMode: ParseMode.markdown,
      );
    } catch (e) {
      print('❌ Failed to send error reply: $e');
    }
  }
}