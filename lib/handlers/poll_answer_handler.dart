import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';
import '../services/quiz_session_manager.dart';
import '../services/supabase_service.dart';

/// Enhanced poll answer handler with robust error handling
class PollAnswerHandler {
  final QuizSessionManager sessionManager;
  final SupabaseService supabaseService;

  PollAnswerHandler(this.sessionManager, this.supabaseService);

  /// Handle poll answer with comprehensive error handling
  Future<void> handlePollAnswer(Context ctx) async {
    try {
      final pollAnswer = ctx.pollAnswer;
      if (pollAnswer == null) {
        print('⚠️ Poll answer is null');
        return;
      }

      final userId = pollAnswer.user?.id;
      if (userId == null) {
        print('⚠️ User ID is null');
        return;
      }

      final session = sessionManager.getSession(userId);
      if (session == null) {
        print('⚠️ No session for user $userId');
        return;
      }

      if (session.isCompleted) {
        print('⚠️ Session already completed for user $userId');
        return;
      }

      final question = session.currentQuestion;
      final isCorrect = pollAnswer.optionIds.contains(question.correctOptionIndex);

      if (isCorrect) {
        sessionManager.recordCorrectAnswer(userId);
        print('✅ User $userId answered correctly');
      } else {
        sessionManager.recordWrongAnswer(userId);
        print('❌ User $userId answered incorrectly');
      }

      sessionManager.nextQuestion(userId);

      // Check if quiz is completed
      if (session.isCompleted) {
        print('🏁 Quiz completed for user $userId');
        await _sendResults(ctx, userId);
        return;
      }

      // Check if user exceeded missed limit
      if (sessionManager.hasExceededMissedLimit(userId)) {
        print('⏸ User $userId exceeded missed limit');
        await _handleMissedLimit(ctx, userId);
        return;
      }

      // Send next question
      await _sendNextQuestion(ctx, userId);
    } catch (e, stack) {
      print('❌ handlePollAnswer error: $e');
      print('Stack trace: $stack');

      try {
        final userId = ctx.pollAnswer?.user?.id;
        if (userId != null) {
          await ctx.api.sendMessage(
            ChatID(userId),
            '❌ *Xatolik yuz berdi!*\n\n'
                'Test to\'xtatildi. Qaytadan boshlang: /start',
            parseMode: ParseMode.markdown,
          );
        }
      } catch (e) {
        print('❌ Failed to send error message: $e');
      }
    }
  }

  /// Handle missed question limit
  Future<void> _handleMissedLimit(Context ctx, int userId) async {
    try {
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
    } catch (e) {
      print('❌ _handleMissedLimit error: $e');
    }
  }

  /// Handle quiz control (continue/finish)
  Future<void> handleQuizControl(Context ctx) async {
    try {
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
    } catch (e) {
      print('❌ handleQuizControl error: $e');

      try {
        await ctx.answerCallbackQuery(text: '❌ Xatolik yuz berdi');
      } catch (e) {
        print('❌ Failed to answer callback: $e');
      }
    }
  }

  /// Send next question with error handling
  Future<void> _sendNextQuestion(Context ctx, int userId) async {
    try {
      final session = sessionManager.getSession(userId);
      if (session == null || session.isCompleted) {
        print('⚠️ Cannot send question: session null or completed');
        return;
      }

      final question = session.currentQuestion;
      final quiz = session.quiz;

      if (question.options.length < 2) {
        print('❌ Invalid question: less than 2 options');
        throw Exception('Savol noto\'g\'ri: kamida 2 ta variant bo\'lishi kerak');
      }

      final List<InputPollOption> pollOptions = [];
      for (final opt in question.options) {
        pollOptions.add(InputPollOption(text: _truncate(opt, 100)));
      }

      final pollMessage = await ctx.api.sendPoll(
        ChatID(userId),
        '${session.progress} | ${_truncate(question.text, 300)}',
        pollOptions,
        isAnonymous: false,
        type: PollType.quiz,
        correctOptionId: question.correctOptionIndex,
        openPeriod: quiz.timePerQuestion > 0 ? quiz.timePerQuestion : null,
      );

      if (pollMessage.poll != null) {
        sessionManager.updatePollId(userId, pollMessage.poll!.id);
      }

      print('✅ Question sent to user $userId');
    } catch (e, stack) {
      print('❌ _sendNextQuestion error: $e');
      print('Stack trace: $stack');

      try {
        await ctx.api.sendMessage(
          ChatID(userId),
          '❌ *Savol yuborishda xatolik!*\n\n'
              'Test to\'xtatildi. Qaytadan boshlang: /start',
          parseMode: ParseMode.markdown,
        );
      } catch (e) {
        print('❌ Failed to send error message: $e');
      }
    }
  }

  /// Send final results with Supabase integration
  Future<void> _sendResults(Context ctx, int userId) async {
    try {
      final session = sessionManager.endSession(userId);
      if (session == null) {
        print('⚠️ Session not found for results');
        return;
      }

      final score = session.correctAnswers;
      final answeredQuestions = session.currentQuestionIndex;
      final total = session.quiz.questions.length;
      final percentage = answeredQuestions > 0
          ? (score / answeredQuestions * 100)
          : 0.0;
      final elapsed = session.elapsedTime;

      // Save to Supabase
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
        print('⚠️ Failed to save result to Supabase: $e');
      }

      // Determine grade and message
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

      final resultMessage = StringBuffer();
      resultMessage.writeln('$emoji *$completionStatus*\n');
      resultMessage.writeln('━━━━━━━━━━━━━━━━━');
      resultMessage.writeln('📊 *NATIJALAR*');
      resultMessage.writeln('━━━━━━━━━━━━━━━━━\n');
      resultMessage.writeln('✅ To\'g\'ri: *$score/$answeredQuestions*');
      resultMessage.writeln('📈 Foiz: *${percentage.toStringAsFixed(1)}%*');
      resultMessage.writeln('🎯 Baho: *$grade*');
      resultMessage.writeln('⏱ Vaqt: *${minutes}d ${seconds}s*');

      if (answeredQuestions < total) {
        resultMessage.writeln('📝 Javob berilgan: *$answeredQuestions/$total*');
      }

      if (session.quiz.subjectName != null) {
        resultMessage.writeln('📚 Fan: *${session.quiz.subjectName}*');
      }

      resultMessage.writeln('\n━━━━━━━━━━━━━━━━━');
      resultMessage.writeln('$message $level\n');
      resultMessage.writeln('📚 Quizlarim: /quizlarim');
      resultMessage.writeln('📊 Statistikam: /statistika');
      resultMessage.writeln('🔄 Yangi test: /start');

      await ctx.api.sendMessage(
        ChatID(userId),
        resultMessage.toString(),
        parseMode: ParseMode.markdown,
      );

      print('✅ Results sent to user $userId');
    } catch (e, stack) {
      print('❌ _sendResults error: $e');
      print('Stack trace: $stack');

      try {
        await ctx.api.sendMessage(
          ChatID(userId),
          '❌ *Natijalarni yuborishda xatolik!*\n\n'
              'Statistikangizni ko\'ring: /statistika',
          parseMode: ParseMode.markdown,
        );
      } catch (e) {
        print('❌ Failed to send error message: $e');
      }
    }
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }
}