import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';
import '../services/supabase_service.dart';
import '../services/quiz_session_manager.dart';
import '../models/quiz.dart';
import '../models/question.dart';

/// Enhanced share handler with improved error handling
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
        await _showShareInfo(ctx, session.quiz.shareCode!);
        return;
      }

      // Get user's quizzes
      final quizzes = await supabaseService.getUserQuizzes(userId);

      if (quizzes.isEmpty) {
        await ctx.reply(
          '❌ *Ulashadigan quizlar yo\'q!*\n\n'
              'Avval test yarating: /start',
          parseMode: ParseMode.markdown,
        );
        return;
      }

      final buttons = <List<InlineKeyboardButton>>[];

      for (int i = 0; i < quizzes.length && i < 10; i++) {
        final quiz = quizzes[i];
        final quizId = quiz['id'];
        final subjectName = quiz['subject_name'] ?? 'Noma\'lum';
        final totalQuestions = quiz['total_questions'] ?? 0;

        buttons.add([
          InlineKeyboardButton(
            text: '📚 $subjectName ($totalQuestions ta savol)',
            callbackData: 'share_select:$quizId',
          ),
        ]);
      }

      await ctx.reply(
        '📤 *Qaysi quizni ulashmoqchisiz?*\n\n'
            'Tanlang:',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(inlineKeyboard: buttons),
      );
    } catch (e) {
      print('❌ handleShare error: $e');
      await ctx.reply(
        '❌ *Xatolik yuz berdi!*\n\n'
            'Qaytadan urinib ko\'ring.',
        parseMode: ParseMode.markdown,
      );
    }
  }

  /// Handle share callback
  Future<void> handleShareCallback(Context ctx, int quizId) async {
    try {
      await ctx.answerCallbackQuery(text: 'Havola yaratilmoqda...');

      final shareCode = await supabaseService.generateShareCode(quizId);

      await ctx.editMessageText(
        '⏳ Ulashish havolasi tayyorlanmoqda...',
        parseMode: ParseMode.markdown,
      );

      await Future.delayed(Duration(milliseconds: 300));
      await _showShareInfo(ctx, shareCode);
    } catch (e) {
      print('❌ handleShareCallback error: $e');
      await ctx.answerCallbackQuery(text: '❌ Xatolik yuz berdi');

      try {
        await ctx.editMessageText(
          '❌ *Ulashish havolasi yaratilmadi!*\n\n'
              'Qaytadan urinib ko\'ring: /share',
          parseMode: ParseMode.markdown,
        );
      } catch (e) {
        print('❌ Failed to edit message: $e');
      }
    }
  }

  /// Show share information
  Future<void> _showShareInfo(Context ctx, String shareCode) async {
    try {
      final botUsername = (await ctx.api.getMe()).username;
      final shareUrl = 'https://t.me/$botUsername?start=quiz_$shareCode';

      await ctx.reply(
        '📤 *Quiz ulashish havolasi tayyor!*\n\n'
            '🔗 *Havola:*\n`$shareUrl`\n\n'
            '📋 *Kod:* `$shareCode`\n\n'
            '💡 *Qanday ishlaydi:*\n'
            '1️⃣ Havolani yuboring\n'
            '2️⃣ Do\'stlaringiz bosadi\n'
            '3️⃣ Ular sizning quizingizni yechadi!\n\n'
            '🔄 Kod abadiy amal qiladi',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(
          inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: '📤 Telegram orqali ulashish',
                url: 'https://t.me/share/url?url=$shareUrl&text=Bu quizni yeching! 🎯',
              ),
            ],
            [
              InlineKeyboardButton(
                text: '🔙 Quizlarimga qaytish',
                callbackData: 'back_to_quizzes',
              ),
            ],
          ],
        ),
      );
    } catch (e) {
      print('❌ _showShareInfo error: $e');
      await ctx.reply(
        '❌ Havola yaratildi lekin ko\'rsatishda xatolik!\n\n'
            'Kod: `$shareCode`',
        parseMode: ParseMode.markdown,
      );
    }
  }

  /// Handle shared quiz start via deep link
  Future<void> handleSharedQuizStart(Context ctx, String shareCode) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    try {
      // Clear any existing session
      sessionManager.clearUserData(userId);

      // Update user activity
      try {
        await supabaseService.updateUserActivity(userId);
      } catch (e) {
        print('⚠️ Failed to update activity: $e');
      }

      // Get quiz by share code
      final quizData = await supabaseService.getQuizByShareCode(shareCode);

      if (quizData == null) {
        await ctx.reply(
          '❌ *Quiz topilmadi!*\n\n'
              'Kod noto\'g\'ri yoki quiz o\'chirilgan.\n\n'
              'Yangi test: /start',
          parseMode: ParseMode.markdown,
        );
        return;
      }

      final subjectName = quizData['subject_name'] ?? 'Ulashilgan quiz';
      final totalQuestions = quizData['total_questions'] ?? 0;
      final creatorName = quizData['creator_username'] ?? 'Foydalanuvchi';

      await ctx.reply(
        '📤 *Ulashilgan quiz!*\n\n'
            '📚 Fan: *$subjectName*\n'
            '📊 Savollar: *$totalQuestions ta*\n'
            '👤 Muallif: @$creatorName\n\n'
            '🔀 Sozlamalarni tanlang:',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(
          inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: '🚀 Darhol boshlash',
                callbackData: 'start_shared:$shareCode',
              ),
            ],
            [
              InlineKeyboardButton(
                text: '⚙️ Sozlamalarni o\'zgartirish',
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
      print('❌ handleSharedQuizStart error: $e');
      await ctx.reply(
        '❌ *Xatolik yuz berdi!*\n\n'
            'Quiz yuklanmadi: ${e.toString()}\n\n'
            'Qaytadan urinib ko\'ring.',
        parseMode: ParseMode.markdown,
      );
    }
  }

  /// Start shared quiz with optional customization
  Future<void> startSharedQuiz(
      Context ctx,
      String shareCode, {
        bool customize = false,
      }) async {
    final userId = ctx.callbackQuery?.from.id;
    if (userId == null) return;

    try {
      await ctx.answerCallbackQuery(text: 'Quiz yuklanmoqda...');

      // Get quiz data
      final quizData = await supabaseService.getQuizByShareCode(shareCode);

      if (quizData == null) {
        await ctx.editMessageText(
          '❌ *Quiz topilmadi!*\n\n'
              'Kod noto\'g\'ri yoki quiz o\'chirilgan.',
          parseMode: ParseMode.markdown,
        );
        return;
      }

      // Check if quiz has stored questions
      if (quizData['questions'] == null || quizData['questions'].isEmpty) {
        await ctx.editMessageText(
          '❌ *Quiz savollari topilmadi!*\n\n'
              'Bu quiz yaratilganidan keyin savollar o\'chirilgan.\n\n'
              'Yangi test: /start',
          parseMode: ParseMode.markdown,
        );
        return;
      }

      // Parse questions
      final questionsList = quizData['questions'] as List;
      final questions = questionsList.map((q) {
        return Question(
          text: q['text'] as String,
          options: List<String>.from(q['options'] as List),
          correctOptionIndex: q['correctIndex'] as int,
        );
      }).toList();

      if (questions.isEmpty) {
        await ctx.editMessageText(
          '❌ *Savollar noto\'g\'ri formatda!*\n\n'
              'Bu quizni ishlatib bo\'lmaydi.',
          parseMode: ParseMode.markdown,
        );
        return;
      }

      // Create quiz object
      final quiz = Quiz(
        questions: questions,
        subjectName: quizData['subject_name'] as String?,
        shareCode: shareCode,
      );

      // Create session
      sessionManager.createSession(userId, quiz);

      if (customize) {
        // Show customization options
        await ctx.editMessageText(
          '⚙️ *Sozlamalarni tanlang:*\n\n'
              '🔀 Aralashtirishni sozlang:',
          parseMode: ParseMode.markdown,
          replyMarkup: InlineKeyboard(
            inlineKeyboard: [
              [
                InlineKeyboardButton(
                  text: '🔀 Savollarni aralashtirish',
                  callbackData: 'shuffle:questions',
                ),
              ],
              [
                InlineKeyboardButton(
                  text: '🎲 Javoblarni aralashtirish',
                  callbackData: 'shuffle:answers',
                ),
              ],
              [
                InlineKeyboardButton(
                  text: '🔀🎲 Hammasini aralashtirish',
                  callbackData: 'shuffle:both',
                ),
              ],
              [
                InlineKeyboardButton(
                  text: '📋 Aralashtirishsiz',
                  callbackData: 'shuffle:none',
                ),
              ],
            ],
          ),
        );
      } else {
        // Start immediately with default settings
        sessionManager.setShuffleChoice(userId, 'none');

        await ctx.editMessageText(
          '🚀 *Quiz tayyor!*\n\n'
              'Vaqtni tanlang:',
          parseMode: ParseMode.markdown,
        );

        await Future.delayed(Duration(milliseconds: 300));
        await _showTimeSelection(ctx, userId);
      }
    } catch (e) {
      print('❌ startSharedQuiz error: $e');
      await ctx.answerCallbackQuery(text: '❌ Xatolik yuz berdi');

      try {
        await ctx.editMessageText(
          '❌ *Quiz boshlanmadi!*\n\n'
              'Xatolik: ${e.toString()}\n\n'
              'Qaytadan urinib ko\'ring: /start',
          parseMode: ParseMode.markdown,
        );
      } catch (e) {
        print('❌ Failed to edit message: $e');
      }
    }
  }

  /// Show time selection for shared quiz
  Future<void> _showTimeSelection(Context ctx, int userId) async {
    try {
      await ctx.reply(
        '⏱ *Har bir savol uchun vaqtni tanlang:*',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(
          inlineKeyboard: [
            [
              InlineKeyboardButton(text: '⚡️ 10s', callbackData: 'time:10'),
              InlineKeyboardButton(text: '⏱ 20s', callbackData: 'time:20'),
              InlineKeyboardButton(text: '🕐 30s', callbackData: 'time:30'),
            ],
            [
              InlineKeyboardButton(text: '⏰ 60s', callbackData: 'time:60'),
              InlineKeyboardButton(text: '🕰 90s', callbackData: 'time:90'),
              InlineKeyboardButton(text: '⏳ 120s', callbackData: 'time:120'),
            ],
            [
              InlineKeyboardButton(text: '♾ Cheksiz', callbackData: 'time:0'),
            ],
          ],
        ),
      );
    } catch (e) {
      print('❌ _showTimeSelection error: $e');
      await ctx.reply(
        '❌ Xatolik yuz berdi. /start ni bosing.',
        parseMode: ParseMode.markdown,
      );
    }
  }
}