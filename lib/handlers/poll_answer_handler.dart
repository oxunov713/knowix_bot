import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';
import '../services/quiz_session_manager.dart';
import '../services/supabase_service.dart';

/// Poll javoblarini boshqaruvchi (Supabase integratsiyasi bilan)
class PollAnswerHandler {
  final QuizSessionManager sessionManager;
  final SupabaseService supabaseService;

  PollAnswerHandler(this.sessionManager, this.supabaseService);

  /// Poll javobini boshqarish
  Future<void> handlePollAnswer(Context ctx) async {
    final pollAnswer = ctx.pollAnswer;
    if (pollAnswer == null) return;

    final userId = pollAnswer.user!.id;
    final session = sessionManager.getSession(userId);

    if (session == null || session.isCompleted) return;

    final question = session.currentQuestion;
    final isCorrect = pollAnswer.optionIds.contains(question.correctOptionIndex);

    if (isCorrect) {
      sessionManager.recordCorrectAnswer(userId);
    } else {
      sessionManager.recordWrongAnswer(userId);
    }

    sessionManager.nextQuestion(userId);

    // Test tugaganmi?
    if (session.isCompleted) {
      await _sendResults(ctx, userId);
      return;
    }

    // Juda ko'p xato qildimi?
    if (sessionManager.hasExceededMissedLimit(userId)) {
      await _handleMissedLimit(ctx, userId);
      return;
    }

    // Keyingi savolni yuborish
    await _sendNextQuestion(ctx, userId);
  }

  /// Juda ko'p xato qilingan holat
  Future<void> _handleMissedLimit(Context ctx, int userId) async {
    final session = sessionManager.getSession(userId);
    if (session == null) return;

    final missedCount = sessionManager.getMissedCount(userId);
    final currentQuestion = session.currentQuestionIndex + 1;
    final totalQuestions = session.quiz.questions.length;

    await ctx.api.sendMessage(
      ChatID(userId),
      '⏸ *Test to\'xtatildi!*\n\n'
          '❌ Siz ketma-ket *$missedCount ta* savolga javob bermadingiz.\n\n'
          '📊 Hozirgi o\'rin: *$currentQuestion/$totalQuestions*\n\n'
          '🤔 Nima qilmoqchisiz?',
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard(
        inlineKeyboard: [
          [
            InlineKeyboardButton(
              text: '▶️ Testni davom ettirish',
              callbackData: 'quiz_continue',
            ),
          ],
          [
            InlineKeyboardButton(
              text: '🏁 Yakunlash va natijani ko\'rish',
              callbackData: 'quiz_finish',
            ),
          ],
        ],
      ),
    );
  }

  /// Davom ettirish/tugatish boshqaruvi
  Future<void> handleQuizControl(Context ctx) async {
    final query = ctx.callbackQuery;
    if (query == null) return;

    final userId = query.from.id;
    final data = query.data;

    if (data == 'quiz_continue') {
      sessionManager.resetMissedCount(userId);

      await ctx.answerCallbackQuery(text: 'Test davom ettirilmoqda...');
      await ctx.editMessageText(
        '▶️ *Test davom ettirilmoqda...*\n\n💪 Omad tilaymiz!',
        parseMode: ParseMode.markdown,
      );

      await Future.delayed(Duration(milliseconds: 500));
      await _sendNextQuestion(ctx, userId);

    } else if (data == 'quiz_finish') {
      await ctx.answerCallbackQuery(text: 'Test yakunlanmoqda...');
      await ctx.editMessageText(
        '🏁 *Test yakunlanmoqda...*',
        parseMode: ParseMode.markdown,
      );

      await Future.delayed(Duration(milliseconds: 500));
      await _sendResults(ctx, userId);
    }
  }

  /// Keyingi savolni yuborish - FIXED
  Future<void> _sendNextQuestion(Context ctx, int userId) async {
    final session = sessionManager.getSession(userId);
    if (session == null || session.isCompleted) return;

    final question = session.currentQuestion;
    final quiz = session.quiz;

    // FIXED: Explicit type casting
    final List<InputPollOption> pollOptions = [];
    for (final opt in question.options) {
      pollOptions.add(InputPollOption(text: _truncate(opt, 100)));
    }

    try {
      final pollMessage = await ctx.api.sendPoll(
        ChatID(userId),
        '${session.progress} | ${_truncate(question.text, 300)}',
        pollOptions,
        isAnonymous: false,
        type: PollType.quiz,
        correctOptionId: question.correctOptionIndex,
        openPeriod: quiz.timePerQuestion > 0 ? quiz.timePerQuestion : null,
      );

      sessionManager.updatePollId(userId, pollMessage.poll!.id);
    } catch (e) {
      print('❌ Error sending poll: $e');
      await ctx.api.sendMessage(
        ChatID(userId),
        '❌ Savol yuborishda xatolik!\n\nTest to\'xtatildi.',
      );
    }
  }

  /// Yakuniy natijalarni yuborish (Supabase ga saqlash bilan)
  Future<void> _sendResults(Context ctx, int userId) async {
    final session = sessionManager.endSession(userId);
    if (session == null) return;

    final score = session.correctAnswers;
    final answeredQuestions = session.currentQuestionIndex;
    final total = session.quiz.questions.length;
    final percentage = (score / answeredQuestions * 100);
    final elapsed = session.elapsedTime;

    // Supabase ga natijani saqlash
    try {
      final quizId = sessionManager.getQuizId(userId);
      if (quizId != null) {
        await supabaseService.saveQuizResult(
          quizId: quizId,
          correctAnswers: score,
          totalAnswered: answeredQuestions,
          totalQuestions: total,
          percentage: percentage,
          elapsedSeconds: elapsed.inSeconds,
          isCompleted: answeredQuestions == total,
        );
        print('✅ Quiz result saved to Supabase');
      }
    } catch (e) {
      print('⚠️ Error saving result to Supabase: $e');
    }

    String emoji;
    String message;
    String level;

    if (percentage >= 90) {
      emoji = '🏆';
      message = 'A\'lo!';
      level = 'Mukammal natija!';
    } else if (percentage >= 75) {
      emoji = '🌟';
      message = 'Yaxshi!';
      level = 'Juda yaxshi bilasiz!';
    } else if (percentage >= 60) {
      emoji = '👍';
      message = 'Yaxshi!';
      level = 'Yaxshi natija!';
    } else if (percentage >= 50) {
      emoji = '📚';
      message = 'Qoniqarli';
      level = 'Yana mashq qiling!';
    } else {
      emoji = '💪';
      message = 'Yaxshiroq bo\'ladi!';
      level = 'Tayyorgarlik ko\'ring!';
    }

    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;

    final completionStatus = answeredQuestions == total
        ? '✅ Test yakunlandi!'
        : '🏁 Test to\'xtatildi!';

    final gradeValue = (percentage / 20).floorToDouble();
    final grade = gradeValue >= 4.5 ? '5' :
    gradeValue >= 3.5 ? '4' :
    gradeValue >= 2.5 ? '3' : '2';

    await ctx.api.sendMessage(
      ChatID(userId),
      '$emoji *$completionStatus*\n\n'
          '━━━━━━━━━━━━━━━━━\n'
          '📊 *NATIJALAR*\n'
          '━━━━━━━━━━━━━━━━━\n\n'
          '✅ To\'g\'ri javoblar: *$score/$answeredQuestions*\n'
          '📈 Foiz: *${percentage.toStringAsFixed(1)}%*\n'
          '🎯 Baho: *$grade*\n'
          '⏱ Sarflangan vaqt: *${minutes}d ${seconds}s*\n'
          '${answeredQuestions < total ? "📝 Javob berilgan: *$answeredQuestions/$total*\n" : ""}'
          '${session.quiz.subjectName != null ? "📚 Fan: *${session.quiz.subjectName}*\n" : ""}'
          '\n━━━━━━━━━━━━━━━━━\n'
          '$message $level\n\n'
          '📚 Quizlarim: /quizlarim\n'
          '📊 Statistikam: /statistika\n'
          '🔄 Yangi test: /start',
      parseMode: ParseMode.markdown,
    );
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }
}