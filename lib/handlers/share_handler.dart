import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';
import '../services/supabase_service.dart';
import '../services/quiz_session_manager.dart';
import '../models/quiz.dart';

/// Handler for quiz sharing functionality
class ShareHandler {
  final SupabaseService supabaseService;
  final QuizSessionManager sessionManager;

  ShareHandler(this.supabaseService, this.sessionManager);

  /// Handle /share command
  Future<void> handleShare(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    try {
      // Check if user has active session
      final session = sessionManager.getSession(userId);

      if (session != null && session.quiz.shareCode != null) {
        await _showShareOptions(ctx, userId, session.quiz.shareCode!);
        return;
      }

      // Get user's quizzes
      final quizzes = await supabaseService.getUserQuizzes(userId);

      if (quizzes.isEmpty) {
        await ctx.reply(
          '📚 *Sizda quizlar yo\'q!*\n\n'
              'Avval quiz yarating: /start',
          parseMode: ParseMode.markdown,
        );
        return;
      }

      // Show quiz list for sharing
      final buttons = <List<InlineKeyboardButton>>[];

      for (int i = 0; i < quizzes.length && i < 10; i++) {
        final quiz = quizzes[i];
        final quizId = quiz['id'];
        final subjectName = quiz['subject_name'] ?? 'Noma\'lum';
        final hasStored = quiz['has_stored_questions'] == true;

        if (!hasStored) continue;

        buttons.add([
          InlineKeyboardButton(
            text: '📤 $subjectName',
            callbackData: 'share_select:$quizId',
          ),
        ]);
      }

      if (buttons.isEmpty) {
        await ctx.reply(
          '⚠️ *Ulashish uchun quizlar yo\'q!*\n\n'
              'Faqat to\'liq saqlangan quizlarni ulashish mumkin.',
          parseMode: ParseMode.markdown,
        );
        return;
      }

      await ctx.reply(
        '📤 *Qaysi quizni ulashmoqchisiz?*\n\n'
            'Quizni tanlang:',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(inlineKeyboard: buttons),
      );
    } catch (e) {
      print('❌ Share error: $e');
      await ctx.reply('❌ Xatolik yuz berdi!');
    }
  }

  /// Handle share selection callback
  Future<void> handleShareCallback(Context ctx, int quizId) async {
    try {
      await ctx.answerCallbackQuery(text: '📤 Ulashish havolasi yaratilmoqda...');

      final shareCode = await supabaseService.generateShareCode(quizId);

      final botUsername = (await ctx.api.getMe()).username;
      final shareUrl = 'https://t.me/$botUsername?start=quiz_$shareCode';

      final quizData = await supabaseService.getQuizWithQuestions(quizId);
      final subjectName = quizData?['subject_name'] ?? 'Quiz';

      await ctx.editMessageText(
        '✅ *Ulashish havolasi yaratildi!*\n\n'
            '📚 Fan: *$subjectName*\n'
            '🔗 Havola: `$shareUrl`\n'
            '📋 Kod: `$shareCode`\n\n'
            '💡 *Foydalanish:*\n'
            '   • Havolani do\'stlaringizga yuboring\n'
            '   • Yoki kodni ulashing\n'
            '   • Ular aynan shu quizni yechishlari mumkin!\n\n'
            '📊 Ular o\'z natijalarini ko\'radilar, siz esa o\'zingizni.',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(
          inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: '📤 Telegram orqali ulashish',
                url: 'https://t.me/share/url?url=$shareUrl&text=🎯 $subjectName quizini yeching!',
              ),
            ],
            [
              InlineKeyboardButton(
                text: '📋 Havolani nusxalash',
                callbackData: 'copy_link:$shareUrl',
              ),
            ],
            [
              InlineKeyboardButton(
                text: '🔙 Orqaga',
                callbackData: 'back_to_quizzes',
              ),
            ],
          ],
        ),
      );

      await supabaseService.incrementQuizShares(quizId);
    } catch (e) {
      print('❌ Share callback error: $e');
      await ctx.editMessageText('❌ Xatolik yuz berdi!');
    }
  }

  /// Handle shared quiz start (via deep link)
  Future<void> handleSharedQuizStart(Context ctx, String shareCode) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    try {
      await ctx.reply('⏳ Quiz yuklanmoqda...');

      final quizData = await supabaseService.getQuizByShareCode(shareCode);

      if (quizData == null) {
        await ctx.reply(
          '❌ *Quiz topilmadi!*\n\n'
              'Kod noto\'g\'ri yoki quiz o\'chirilgan.',
          parseMode: ParseMode.markdown,
        );
        return;
      }

      // Check if user already has this quiz
      final existingSession = sessionManager.getSession(userId);
      if (existingSession != null) {
        sessionManager.endSession(userId);
      }

      // Create quiz from shared data
      final quiz = Quiz.fromSupabaseData(quizData);

      await ctx.reply(
        '📚 *Ulashilgan Quiz*\n\n'
            '📖 Fan: *${quiz.subjectName}*\n'
            '📊 Savollar: *${quiz.questions.length} ta*\n'
            '🔀 Aralashtirish: *${quiz.shuffled ? "Ha" : "Yo\'q"}*\n'
            '🎲 Javoblar: *${quiz.answersShuffled ? "Aralashgan" : "Ketma-ket"}*\n\n'
            '🚀 Testni boshlaysizmi?',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(
          inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: '✅ Boshlayman',
                callbackData: 'start_shared:$shareCode',
              ),
            ],
            [
              InlineKeyboardButton(
                text: '🔄 Sozlamalarni o\'zgartirish',
                callbackData: 'customize_shared:$shareCode',
              ),
            ],
            [
              InlineKeyboardButton(
                text: '❌ Bekor qilish',
                callbackData: 'cancel_shared',
              ),
            ],
          ],
        ),
      );
    } catch (e) {
      print('❌ Shared quiz start error: $e');
      await ctx.reply('❌ Xatolik yuz berdi!');
    }
  }

  /// Start shared quiz
  Future<void> startSharedQuiz(Context ctx, String shareCode, {bool customize = false}) async {
    final userId = ctx.from?.id;
    if (userId == null) return;

    try {
      final quizData = await supabaseService.getQuizByShareCode(shareCode);
      if (quizData == null) {
        await ctx.editMessageText('❌ Quiz topilmadi!');
        return;
      }

      final quiz = Quiz.fromSupabaseData(quizData);

      if (customize) {
        // Show shuffle options
        sessionManager.createSession(userId, quiz);

        await ctx.editMessageText(
          '🔀 *Aralashtirishni sozlang:*\n\n'
              'Asl: ${quiz.shuffled ? "Savollar aralash" : "Ketma-ket"}, '
              '${quiz.answersShuffled ? "Javoblar aralash" : "Javoblar ketma-ket"}',
          parseMode: ParseMode.markdown,
          replyMarkup: InlineKeyboard(
            inlineKeyboard: [
              [
                InlineKeyboardButton(
                  text: '🔀 Savollarni aralashtirish',
                  callbackData: 'customize_q:$shareCode',
                ),
              ],
              [
                InlineKeyboardButton(
                  text: '🎲 Javoblarni aralashtirish',
                  callbackData: 'customize_a:$shareCode',
                ),
              ],
              [
                InlineKeyboardButton(
                  text: '🔀🎲 Hammasini aralashtirish',
                  callbackData: 'customize_b:$shareCode',
                ),
              ],
              [
                InlineKeyboardButton(
                  text: '✅ Asl holatda boshlash',
                  callbackData: 'start_shared:$shareCode',
                ),
              ],
            ],
          ),
        );
      } else {
        // Start immediately
        sessionManager.createSession(userId, quiz);

        await ctx.editMessageText(
          '🚀 *Test boshlanmoqda...*',
          parseMode: ParseMode.markdown,
        );

        await Future.delayed(Duration(milliseconds: 500));
        await _sendFirstQuestion(ctx, userId);
      }
    } catch (e) {
      print('❌ Start shared quiz error: $e');
      await ctx.editMessageText('❌ Xatolik yuz berdi!');
    }
  }

  /// Show share options for current quiz
  Future<void> _showShareOptions(Context ctx, int userId, String shareCode) async {
    final botUsername = (await ctx.api.getMe()).username;
    final shareUrl = 'https://t.me/$botUsername?start=quiz_$shareCode';

    await ctx.reply(
      '📤 *Faol quizingiz*\n\n'
          '🔗 Havola: `$shareUrl`\n'
          '📋 Kod: `$shareCode`\n\n'
          '💡 Bu quizni do\'stlaringiz bilan ulashing!',
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard(
        inlineKeyboard: [
          [
            InlineKeyboardButton(
              text: '📤 Telegram orqali ulashish',
              url: 'https://t.me/share/url?url=$shareUrl&text=Bu quizni yeching!',
            ),
          ],
        ],
      ),
    );
  }

  /// Send first question
  Future<void> _sendFirstQuestion(Context ctx, int userId) async {
    final session = sessionManager.getSession(userId);
    if (session == null) return;

    final question = session.currentQuestion;

    final List<InputPollOption> pollOptions = [];
    for (final opt in question.options) {
      pollOptions.add(InputPollOption(text: _truncate(opt, 100)));
    }

    try {
      await ctx.api.sendPoll(
        ChatID(userId),
        '${session.progress} | ${_truncate(question.text, 300)}',
        pollOptions,
        isAnonymous: false,
        type: PollType.quiz,
        correctOptionId: question.correctOptionIndex,
        openPeriod: session.quiz.timePerQuestion > 0
            ? session.quiz.timePerQuestion
            : null,
      );
    } catch (e) {
      print('❌ Error sending question: $e');
      await ctx.api.sendMessage(
        ChatID(userId),
        '❌ Savol yuborishda xatolik!',
      );
    }
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }
}