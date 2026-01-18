import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';
import '../services/quiz_session_manager.dart';
import '../services/supabase_service.dart';

/// Enhanced poll answer handler with robust error handling
class PollAnswerHandler {
  final QuizSessionManager sessionManager;
  final SupabaseService supabaseService;

  // Track last processed poll to prevent duplicates
  final Map<int, String> _lastProcessedPoll = {};

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

      // ✅ FIX 1: Prevent duplicate poll processing
      final currentPollId = pollAnswer.pollId;
      if (_lastProcessedPoll[userId] == currentPollId) {
        print('⚠️ Duplicate poll answer ignored for user $userId');
        return;
      }

      // ✅ FIX 2: Validate poll belongs to current question
      final expectedPollId = sessionManager.getCurrentPollId(userId);
      if (expectedPollId != null && currentPollId != expectedPollId) {
        print('⚠️ Old poll answer ignored for user $userId (expected: $expectedPollId, got: $currentPollId)');
        return;
      }

      // Mark poll as processed
      _lastProcessedPoll[userId] = currentPollId;

      final question = session.currentQuestion;
      final isCorrect = pollAnswer.optionIds.contains(question.correctOptionIndex);

      if (isCorrect) {
        sessionManager.recordCorrectAnswer(userId);
        print('✅ User $userId answered correctly (${session.correctAnswers}/${session.currentQuestionIndex + 1})');
      } else {
        sessionManager.recordWrongAnswer(userId);
        print('❌ User $userId answered incorrectly');
      }

      // ✅ FIX 3: Add delay before moving to next question
      await Future.delayed(Duration(milliseconds: 500));

      // Move to next question
      final hasMore = sessionManager.nextQuestion(userId);

      // Check if quiz is completed
      if (session.isCompleted || !hasMore) {
        print('🏁 Quiz completed for user $userId');
        _lastProcessedPoll.remove(userId); // Cleanup
        await _sendResults(ctx, userId);
        return;
      }

      // Check if user exceeded missed limit
      if (sessionManager.hasExceededMissedLimit(userId)) {
        print('⏸ User $userId exceeded missed limit');
        await _handleMissedLimit(ctx, userId);
        return;
      }

      // ✅ FIX 4: Add delay before sending next question
      await Future.delayed(Duration(milliseconds: 800));

      // Send next question
      await _sendNextQuestion(ctx, userId);
    } catch (e, stack) {
      print('❌ handlePollAnswer error: $e');
      print('Stack trace: $stack');

      try {
        final userId = ctx.pollAnswer?.user?.id;
        if (userId != null) {
          _lastProcessedPoll.remove(userId); // Cleanup on error
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
        _lastProcessedPoll.remove(userId); // Reset tracking

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

        _lastProcessedPoll.remove(userId); // Cleanup
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
      if (session == null) {
        print('⚠️ Cannot send question: session is null');
        return;
      }

      if (session.isCompleted) {
        print('⚠️ Cannot send question: session is completed');
        await _sendResults(ctx, userId);
        return;
      }

      final question = session.currentQuestion;
      final quiz = session.quiz;

      // ✅ FIX 5: Validate question before sending
      if (question.options.length < 2) {
        print('❌ Invalid question: less than 2 options');
        throw Exception('Savol noto\'g\'ri: kamida 2 ta variant bo\'lishi kerak');
      }

      if (question.correctOptionIndex < 0 ||
          question.correctOptionIndex >= question.options.length) {
        print('❌ Invalid correct index: ${question.correctOptionIndex}');
        throw Exception('Noto\'g\'ri javob indeksi: ${question.correctOptionIndex}');
      }

      // Create poll options
      final List<InputPollOption> pollOptions = [];
      for (int i = 0; i < question.options.length; i++) {
        final optionText = _truncate(question.options[i], 100);
        if (optionText.trim().isEmpty) {
          throw Exception('Variant $i bo\'sh');
        }
        pollOptions.add(InputPollOption(text: optionText));
      }

      // ✅ FIX 6: Validate and fix openPeriod (5-600 seconds)
      int? openPeriod;
      if (quiz.timePerQuestion > 0) {
        if (quiz.timePerQuestion < 5) {
          openPeriod = 5; // Minimum 5 seconds
          print('⚠️ Time adjusted to minimum: 5s');
        } else if (quiz.timePerQuestion > 600) {
          openPeriod = 600; // Maximum 600 seconds (10 minutes)
          print('⚠️ Time adjusted to maximum: 600s');
        } else {
          openPeriod = quiz.timePerQuestion;
        }
      }

      print('📤 Sending question ${session.currentQuestionIndex + 1}/${quiz.questions.length} to user $userId');

      // ✅ FIX 7: Add retry logic for poll sending
      Message? pollMessage;
      int retries = 0;
      const maxRetries = 3;

      while (retries < maxRetries) {
        try {
          pollMessage = await ctx.api.sendPoll(
            ChatID(userId),
            '${session.progress} | ${_truncate(question.text, 300)}',
            pollOptions,
            isAnonymous: false,
            type: PollType.quiz,
            correctOptionId: question.correctOptionIndex,
            openPeriod: openPeriod,
          ).timeout(
            Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Poll yuborish timeout');
            },
          );

          break; // Success
        } catch (e) {
          retries++;
          if (retries >= maxRetries) {
            throw Exception('Poll yuborish muvaffaqiyatsiz ($maxRetries urinish): $e');
          }
          print('⚠️ Retry ${retries}/$maxRetries for user $userId: $e');
          await Future.delayed(Duration(seconds: 1 * retries));
        }
      }

      // Update poll ID
      if (pollMessage?.poll != null) {
        sessionManager.updatePollId(userId, pollMessage!.poll!.id);
        print('✅ Question sent successfully. Poll ID: ${pollMessage.poll!.id}');
      } else {
        print('⚠️ Poll message sent but poll is null');
      }

    } catch (e, stack) {
      print('❌ _sendNextQuestion error: $e');
      print('Stack trace: $stack');

      try {
        final session = sessionManager.getSession(userId);
        if (session != null) {
          await ctx.api.sendMessage(
            ChatID(userId),
            '❌ *Savol yuborishda xatolik!*\n\n'
                'Sabab: ${e.toString()}\n\n'
                '🔄 Qayta urinib ko\'ring: /start',
            parseMode: ParseMode.markdown,
          );
        }
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

      // ✅ FIX 8: Make Supabase save non-blocking
      try {
        final quizId = sessionManager.getQuizId(userId);
        if (quizId != null) {
          // Run in background without blocking results
          supabaseService.saveQuizResult(
            quizId: quizId,
            correctAnswers: score,
            totalAnswered: answeredQuestions,
            totalQuestions: total,
            percentage: percentage,
            elapsedSeconds: elapsed.inSeconds,
            isCompleted: answeredQuestions == total,
          ).then((_) {
            print('✅ Quiz result saved to Supabase');
          }).catchError((e) {
            print('⚠️ Failed to save result to Supabase: $e');
          });
        }
      } catch (e) {
        print('⚠️ Failed to initiate Supabase save: $e');
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
    final cleanText = text.trim();
    if (cleanText.length <= maxLength) return cleanText;
    return '${cleanText.substring(0, maxLength - 3)}...';
  }
}