import 'dart:io';
import 'package:televerse/telegram.dart' show InlineKeyboardButton, InputPollOption;
import 'package:televerse/televerse.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../services/quiz_service.dart';
import '../services/quiz_session_manager.dart';
import '../models/quiz.dart';

/// Handles incoming messages
class MessageHandler {
  final QuizService quizService;
  final QuizSessionManager sessionManager;

  MessageHandler(this.quizService, this.sessionManager);

  /// Handle start command
  Future<void> handleStart(Context ctx) async {
    await ctx.reply(
      '👋 Welcome to Quiz Bot!\n\n'
          'Send me a file (TXT, PDF, DOC, DOCX) containing quiz questions.\n\n'
          '📝 Format:\n'
          '+++++ Question text\n'
          '===== Option 1\n'
          '===== #Correct option\n'
          '===== Option 3\n\n'
          'The # symbol marks the correct answer.\n'
          'Tokens can be on the same line or separate lines.',
    );
  }

  /// Handle help command
  Future<void> handleHelp(Context ctx) async {
    await ctx.reply(
      '📚 Quiz Bot Help\n\n'
          '1️⃣ Upload a file with quiz questions\n'
          '2️⃣ Enter subject name\n'
          '3️⃣ Choose shuffle option\n'
          '4️⃣ Set time per question\n'
          '5️⃣ Answer quiz questions\n\n'
          '📝 File Format:\n'
          '• +++++ starts a new question\n'
          '• ===== starts a new option\n'
          '• # marks the correct answer\n\n'
          '✅ Supported files: TXT, PDF, DOC, DOCX',
    );
  }

  /// Handle document upload
  Future<void> handleDocument(Context ctx) async {
    final document = ctx.message?.document;
    if (document == null) return;

    final fileName = document.fileName ?? 'unknown';

    // Check file type
    if (!quizService.isSupportedFile(fileName)) {
      await ctx.reply(
        '❌ Unsupported file type.\n'
            'Please send TXT, PDF, DOC, or DOCX files.',
      );
      return;
    }

    await ctx.reply('⏳ Processing file...');

    try {
      // Download file
      final file = await _downloadFile(ctx.api, document.fileId, fileName);

      // Process file
      final quiz = await quizService.processFile(file);

      // Clean up temp file
      await file.delete();

      // Create temporary session with quiz
      final userId = ctx.message!.from!.id;
      sessionManager.createSession(userId, quiz);

      await ctx.reply(
        '✅ File processed successfully!\n'
            'Found ${quiz.questions.length} questions.\n\n'
            'Please enter the subject name:',
      );

    } catch (e) {
      await ctx.reply(
        '❌ Error processing file:\n${e.toString()}\n\n'
            'Please check the file format and try again.',
      );
    }
  }

  /// Handle text message (for subject name and time input)
  Future<void> handleText(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    final text = ctx.message?.text;
    if (text == null || text.isEmpty) return;

    // Ignore commands
    if (text.startsWith('/')) return;

    final session = sessionManager.getSession(userId);

    // STATE 1: Waiting for subject name (session exists but no subject set)
    if (session != null && session.quiz.subjectName == null) {
      print('📚 User $userId entered subject: $text');

      // Update quiz with subject name
      final updatedQuiz = session.quiz.copyWith(subjectName: text);
      sessionManager.createSession(userId, updatedQuiz);

      // Ask about shuffling
      await ctx.reply(
        '📚 Subject: $text\n\n'
            'Would you like to shuffle the questions?',
        replyMarkup: InlineKeyboard(
          inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: '🔀 Yes, shuffle',
                callbackData: 'shuffle:yes',
              ),
            ],
            [
              InlineKeyboardButton(
                text: '📋 No, keep order',
                callbackData: 'shuffle:no',
              ),
            ],
          ],
        ),
      );
      return;
    }

    // STATE 2: Waiting for time input (shuffle choice already made)
    if (session != null &&
        session.pendingShuffleChoice != null &&
        session.quiz.timePerQuestion == 0) {

      print('⏱ User $userId entered time: $text');

      // Parse time
      final time = int.tryParse(text);
      if (time == null || time < 0) {
        await ctx.reply('❌ Please enter a valid number (0 for no timer):');
        return;
      }

      if (time > 0 && time < 5) {
        await ctx.reply('❌ Minimum time is 5 seconds. Please enter 0 for no timer or 5+ seconds:');
        return;
      }

      if (time > 600) {
        await ctx.reply('❌ Maximum time is 600 seconds (10 minutes). Please enter a lower value:');
        return;
      }

      // Start quiz
      await _startQuiz(ctx, userId, time);
      return;
    }
  }

  /// Download file from Telegram
  Future<File> _downloadFile(RawAPI api, String fileId, String fileName) async {
    final file = await api.getFile(fileId);
    final filePath = file.filePath!;
    final url = 'https://api.telegram.org/file/bot${api.token}/$filePath';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download file');
    }

    final tempDir = Directory.systemTemp;
    final tempFile = File(path.join(tempDir.path, fileName));
    await tempFile.writeAsBytes(response.bodyBytes);

    return tempFile;
  }

  /// Start the quiz after all configuration
  Future<void> _startQuiz(Context ctx, int userId, int timePerQuestion) async {
    final session = sessionManager.getSession(userId);
    if (session == null) return;

    print('🚀 Starting quiz for user $userId');

    // Apply configuration
    var quiz = session.quiz.copyWith(timePerQuestion: timePerQuestion);

    if (session.pendingShuffleChoice == true) {
      print('🔀 Shuffling questions');
      quiz = quiz.shuffleQuestions();
    }

    // Update session with configured quiz
    sessionManager.createSession(userId, quiz);

    await ctx.reply(
      '🎯 Starting Quiz: ${quiz.subjectName}\n'
          '📊 Questions: ${quiz.questions.length}\n'
          '🔀 Shuffled: ${quiz.shuffled ? "Yes" : "No"}\n'
          '⏱ Time per question: ${timePerQuestion > 0 ? "${timePerQuestion}s" : "No limit"}\n\n'
          'Let\'s begin! 🚀',
    );

    // Send first question
    await _sendQuestion(ctx, userId);
  }

  /// Truncate text to fit Telegram poll option length limit (100 chars)
  String _truncateOption(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  /// Send current question as poll
  Future<void> _sendQuestion(Context ctx, int userId) async {
    final session = sessionManager.getSession(userId);
    if (session == null || session.isCompleted) return;

    final question = session.currentQuestion;
    final quiz = session.quiz;

    print('📮 Sending question ${session.currentQuestionIndex + 1}/${quiz.questions.length}');

    // Truncate question if too long (Telegram limit: 300 chars for question)
    final questionText = _truncateOption(question.text, 300);

    // Convert options to InputPollOption format with length limit
    final pollOptions = question.options
        .map((opt) => InputPollOption(text: _truncateOption(opt, 100)))
        .toList()
        .cast<InputPollOption>();

    await ctx.replyWithPoll(
      '${session.progress} | $questionText',
      pollOptions,
      isAnonymous: false,
      type: PollType.quiz,
      correctOptionId: question.correctOptionIndex,
      openPeriod: quiz.timePerQuestion > 0 ? quiz.timePerQuestion : null,
    );
  }

  /// Handle callback queries (shuffle choice)
  Future<void> handleCallback(Context ctx) async {
    final query = ctx.callbackQuery;
    if (query == null) return;

    final userId = query.from.id;
    final data = query.data;

    if (data?.startsWith('shuffle:') == true) {
      final shuffle = data == 'shuffle:yes';

      print('🔄 User $userId chose shuffle: $shuffle');

      sessionManager.setPendingShuffleChoice(userId, shuffle);

      await ctx.answerCallbackQuery();
      await ctx.editMessageText(
        '${shuffle ? "🔀" : "📋"} Questions will ${shuffle ? "" : "not "}be shuffled.\n\n'
            'Enter time per question in seconds (0 for no timer):',
      );
    }
  }
}