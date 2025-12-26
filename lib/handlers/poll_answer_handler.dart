import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';
import '../services/quiz_session_manager.dart';

/// Handles poll answers
class PollAnswerHandler {
  final QuizSessionManager sessionManager;

  PollAnswerHandler(this.sessionManager);

  /// Truncate text to fit Telegram poll option length limit (100 chars)
  String _truncateOption(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  /// Handle poll answer
  Future<void> handlePollAnswer(Context ctx) async {
    final pollAnswer = ctx.pollAnswer;
    if (pollAnswer == null) return;

    final userId = pollAnswer.user!.id;
    final session = sessionManager.getSession(userId);

    if (session == null || session.isCompleted) return;

    // Check if answer is correct
    final question = session.currentQuestion;
    final isCorrect = pollAnswer.optionIds.contains(question.correctOptionIndex);

    if (isCorrect) {
      sessionManager.recordCorrectAnswer(userId);
    } else {
      sessionManager.recordWrongAnswer(userId);
    }

    // Move to next question
    sessionManager.nextQuestion(userId);

    // Check if quiz is completed
    if (session.isCompleted) {
      await _sendResults(ctx, userId);
      return;
    }

    // Check if user exceeded missed question limit
    if (sessionManager.hasExceededMissedLimit(userId)) {
      await _handleMissedLimit(ctx, userId);
      return;
    }

    // Send next question
    await _sendNextQuestion(ctx, userId);
  }

  /// Handle case when user missed too many questions
  Future<void> _handleMissedLimit(Context ctx, int userId) async {
    final session = sessionManager.getSession(userId);
    if (session == null) return;

    final missedCount = sessionManager.getMissedCount(userId);
    final currentQuestion = session.currentQuestionIndex + 1;
    final totalQuestions = session.quiz.questions.length;

    await ctx.api.sendMessage(
      ChatID(userId),
      '⏸ Quiz Paused!\n\n'
          'You missed $missedCount questions in a row.\n'
          'Current progress: $currentQuestion/$totalQuestions\n\n'
          'What would you like to do?',
      replyMarkup: InlineKeyboard(
        inlineKeyboard: [
          [
            InlineKeyboardButton(
              text: '▶️ Continue Quiz',
              callbackData: 'quiz_continue',
            ),
          ],
          [
            InlineKeyboardButton(
              text: '🏁 Finish & See Results',
              callbackData: 'quiz_finish',
            ),
          ],
        ],
      ),
    );
  }

  /// Handle continue/finish callback
  Future<void> handleQuizControl(Context ctx) async {
    final query = ctx.callbackQuery;
    if (query == null) return;

    final userId = query.from.id;
    final data = query.data;

    if (data == 'quiz_continue') {
      // Reset missed count and continue
      sessionManager.resetMissedCount(userId);

      await ctx.answerCallbackQuery(text: 'Continuing quiz...');
      await ctx.editMessageText('▶️ Continuing quiz...');

      await _sendNextQuestion(ctx, userId);
    } else if (data == 'quiz_finish') {
      await ctx.answerCallbackQuery(text: 'Finishing quiz...');
      await ctx.editMessageText('🏁 Finishing quiz...');

      await _sendResults(ctx, userId);
    }
  }

  /// Send next question
  Future<void> _sendNextQuestion(Context ctx, int userId) async {
    final session = sessionManager.getSession(userId);
    if (session == null || session.isCompleted) return;

    final question = session.currentQuestion;
    final quiz = session.quiz;

    // Truncate question if too long (Telegram limit: 300 chars for question)
    final questionText = _truncateOption(question.text, 300);

    // Convert options to InputPollOption format with length limit
    final pollOptions = question.options
        .map((opt) => InputPollOption(text: _truncateOption(opt, 100)))
        .toList()
        .cast<InputPollOption>();

    final pollMessage = await ctx.api.sendPoll(
      ChatID(userId),
      '${session.progress} | $questionText',
      pollOptions,
      isAnonymous: false,
      type: PollType.quiz,
      correctOptionId: question.correctOptionIndex,
      openPeriod: quiz.timePerQuestion > 0 ? quiz.timePerQuestion : null,
    );

    // Track poll for timeout
    sessionManager.updatePollId(userId, pollMessage.poll!.id);
  }

  /// Send final results
  Future<void> _sendResults(Context ctx, int userId) async {
    final session = sessionManager.endSession(userId);
    if (session == null) return;

    final score = session.correctAnswers;
    final answeredQuestions = session.currentQuestionIndex;
    final total = session.quiz.questions.length;
    final percentage = (score / answeredQuestions * 100);
    final elapsed = session.elapsedTime;

    String emoji;
    String message;

    if (percentage >= 90) {
      emoji = '🏆';
      message = 'Outstanding!';
    } else if (percentage >= 75) {
      emoji = '🌟';
      message = 'Great job!';
    } else if (percentage >= 60) {
      emoji = '👍';
      message = 'Good work!';
    } else if (percentage >= 50) {
      emoji = '📚';
      message = 'Keep practicing!';
    } else {
      emoji = '💪';
      message = 'Don\'t give up!';
    }

    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;

    final completionStatus = answeredQuestions == total
        ? '✅ Quiz Completed!'
        : '🏁 Quiz Finished Early!';

    await ctx.api.sendMessage(
      ChatID(userId),
      '$emoji $completionStatus\n\n'
          '📊 Results:\n'
          '✅ Correct: $score/$answeredQuestions\n'
          '📈 Score: ${percentage.toStringAsFixed(1)}%\n'
          '⏱ Time: ${minutes}m ${seconds}s\n'
          '${answeredQuestions < total ? "📝 Answered: $answeredQuestions/$total questions\n" : ""}'
          '${session.quiz.subjectName != null ? "📚 Subject: ${session.quiz.subjectName}\n" : ""}'
          '\n$message\n\n'
          'Send /start to take another quiz!',
    );
  }
}