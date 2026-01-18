import 'dart:io';
import 'dart:math';
import 'package:televerse/telegram.dart' show InlineKeyboardButton, InputPollOption;
import 'package:televerse/televerse.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../services/quiz_service.dart';
import '../services/quiz_session_manager.dart';
import '../services/supabase_service.dart';

/// Enhanced message handler with shuffle and share functionality
class MessageHandler {
  final QuizService quizService;
  final QuizSessionManager sessionManager;
  final SupabaseService supabaseService;

  MessageHandler(
      this.quizService,
      this.sessionManager,
      this.supabaseService,
      );

  /// Generate unique share code
  String _generateShareCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(8, (index) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> handleStart(Context ctx) async {
    final userId = ctx.message?.from?.id;
    final username = ctx.message?.from?.username ?? 'unknown';
    final firstName = ctx.message?.from?.firstName;
    final lastName = ctx.message?.from?.lastName;

    if (userId != null) {
      sessionManager.endSession(userId);

      try {
        await supabaseService.upsertUser(
          telegramId: userId,
          username: username,
          firstName: firstName,
          lastName: lastName,
        );
      } catch (e) {
        print('⚠️ Supabase error: $e');
      }
    }

    await ctx.reply(
      '👋 *HEMIS Quiz Botga xush kelibsiz!*\n\n'
          '📚 HEMIS tizimidan eksport qilingan test fayllarini yuboring.\n\n'
          '📄 *Qo\'llab-quvvatlanadigan formatlar:*\n'
          '   • DOCX (tavsiya etiladi) ✅\n'
          '   • DOC\n'
          '   • TXT\n\n'
          '❌ *MUHIM:* PDF format qo\'llab-quvvatlanmaydi!\n\n'
          '💡 *Buyruqlar:*\n'
          '   • /quizlarim - Mening quizlarim\n'
          '   • /statistika - Mening statistikam\n'
          '   • /share - Quizni ulashish\n'
          '   • /help - Yordam\n'
          '   • /stop - Testni to\'xtatish',
      parseMode: ParseMode.markdown,
    );
  }

  Future<void> handleDocument(Context ctx) async {
    final document = ctx.message?.document;
    if (document == null) return;

    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    final fileName = document.fileName ?? 'noma\'lum';

    try {
      await supabaseService.updateUserActivity(userId);
    } catch (e) {
      print('⚠️ Error updating activity: $e');
    }

    if (!quizService.isSupportedFile(fileName)) {
      final extension = path.extension(fileName).toLowerCase();
      String errorMsg = '❌ *Fayl turi qo\'llab-quvvatlanmaydi!*\n\n';

      if (extension == '.pdf') {
        errorMsg += '🚫 *PDF format ishlamaydi!*\n\n'
            '💡 *Yechim:* HEMIS\'dan DOCX formatda eksport qiling.';
      } else {
        errorMsg += '📄 Faqat DOCX, DOC, TXT formatlar qo\'llab-quvvatlanadi.';
      }

      await ctx.reply(errorMsg, parseMode: ParseMode.markdown);
      return;
    }

    if (document.fileSize != null && document.fileSize! > 10 * 1024 * 1024) {
      await ctx.reply(
        '❌ *Fayl juda katta!* (Max: 10 MB)',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    final loadingMsg = await ctx.reply('⏳ Fayl qayta ishlanmoqda...');

    try {
      final file = await _downloadFile(ctx.api, document.fileId, fileName);
      final quiz = await quizService.processFile(file);
      await file.delete();

      if (quiz.questions.isEmpty) {
        throw Exception('Faylda to\'g\'ri formatdagi savollar topilmadi!');
      }

      sessionManager.createSession(userId, quiz);
      sessionManager.setFileName(userId, fileName);

      await ctx.api.editMessageText(
        ChatID(userId),
        loadingMsg.messageId,
        '✅ *Fayl muvaffaqiyatli qayta ishlandi!*\n\n'
            '📊 Topilgan savollar: *${quiz.questions.length} ta*\n\n'
            '📚 Iltimos, *fan nomini* kiriting:',
        parseMode: ParseMode.markdown,
      );
    } catch (e) {
      print('❌ Xatolik: $e');
      await ctx.api.editMessageText(
        ChatID(userId),
        loadingMsg.messageId,
        '❌ *Xatolik yuz berdi!*\n\n'
            'Xatolik: ${e.toString()}\n\n'
            '💡 Fayl formatini tekshiring:\n'
            '   • Savollar: +++++\n'
            '   • Variantlar: =====\n'
            '   • To\'g\'ri javob: #',
        parseMode: ParseMode.markdown,
      );
    }
  }

  Future<void> handleText(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    final text = ctx.message?.text;
    if (text == null || text.isEmpty || text.startsWith('/')) return;

    final session = sessionManager.getSession(userId);

    if (session != null && session.quiz.subjectName == null) {
      final updatedQuiz = session.quiz.copyWith(subjectName: text);
      sessionManager.createSession(userId, updatedQuiz);

      await ctx.reply(
        '📚 *Fan:* $text\n\n'
            '🔀 *Aralashtirishni sozlang:*',
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
    }
  }

  Future<void> handleCallback(Context ctx) async {
    final query = ctx.callbackQuery;
    if (query == null) return;

    final userId = query.from.id;
    final data = query.data;

    // Shuffle options
    if (data?.startsWith('shuffle:') == true) {
      final shuffleType = data!.substring(8);

      await ctx.answerCallbackQuery(
        text: _getShuffleMessage(shuffleType),
      );

      await ctx.editMessageText(
        '${_getShuffleEmoji(shuffleType)} ${_getShuffleDescription(shuffleType)}',
        parseMode: ParseMode.markdown,
      );

      // Store shuffle choice
      sessionManager.setShuffleChoice(userId, shuffleType);

      await Future.delayed(Duration(milliseconds: 300));
      await _showTimeSelection(ctx, userId);
      return;
    }

    // Time selection
    if (data?.startsWith('time:') == true) {
      final timeStr = data!.substring(5);
      final time = int.tryParse(timeStr);
      if (time == null) return;

      await ctx.answerCallbackQuery(
        text: time == 0 ? '♾ Cheksiz vaqt' : '⏱ $time soniya',
      );

      await ctx.editMessageText(
        '⏱ Tanlangan vaqt: *${time == 0 ? "Cheksiz" : "$time soniya"}*\n\n'
            '🚀 Test tayyorlanmoqda...',
        parseMode: ParseMode.markdown,
      );

      await Future.delayed(Duration(milliseconds: 500));
      await _startQuiz(ctx, userId, time);
      return;
    }

    // Quiz control
    if (data == 'quiz_continue') {
      sessionManager.resetMissedCount(userId);
      await ctx.answerCallbackQuery(text: 'Test davom ettirilmoqda...');
      await ctx.editMessageText(
        '▶️ *Test davom ettirilmoqda...*\n\n💪 Omad tilaymiz!',
        parseMode: ParseMode.markdown,
      );
      await Future.delayed(Duration(milliseconds: 500));
      await _sendQuestion(ctx, userId);
      return;
    }

    if (data == 'quiz_finish') {
      await ctx.answerCallbackQuery(text: 'Test yakunlanmoqda...');
      sessionManager.endSession(userId);
      await ctx.editMessageText(
        '🏁 *Test yakunlandi!*\n\n'
            '📊 Natijangizni ko\'rish uchun: /statistika',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    // Share quiz
    if (data?.startsWith('share_quiz:') == true) {
      final quizId = int.tryParse(data!.substring(11));
      if (quizId == null) return;

      try {
        final shareCode = await supabaseService.generateShareCode(quizId);

        await ctx.answerCallbackQuery(
          text: '📤 Ulashish havolasi yaratildi!',
        );

        final botUsername = (await ctx.api.getMe()).username;
        final shareUrl = 'https://t.me/$botUsername?start=quiz_$shareCode';

        await ctx.reply(
          '📤 *Quiz ulashish*\n\n'
              '🔗 Havola: `$shareUrl`\n\n'
              '📋 Kodni ulashing: `$shareCode`\n\n'
              '💡 Do\'stlaringiz ushbu havola orqali aynan shu quizni yechishlari mumkin!',
          parseMode: ParseMode.markdown,
          replyMarkup: InlineKeyboard(
            inlineKeyboard: [
              [
                InlineKeyboardButton(
                  text: '📤 Ulashish',
                  url: 'https://t.me/share/url?url=$shareUrl&text=Bu quizni yeching!',
                ),
              ],
            ],
          ),
        );
      } catch (e) {
        print('❌ Share error: $e');
        await ctx.answerCallbackQuery(
          text: '❌ Xatolik yuz berdi',
        );
      }
      return;
    }
  }

  String _getShuffleMessage(String type) {
    switch (type) {
      case 'questions':
        return '🔀 Faqat savollar aralashtiriladi';
      case 'answers':
        return '🎲 Faqat javoblar aralashtiriladi';
      case 'both':
        return '🔀🎲 Hammasi aralashtiriladi';
      default:
        return '📋 Aralashtirishsiz';
    }
  }

  String _getShuffleEmoji(String type) {
    switch (type) {
      case 'questions':
        return '🔀';
      case 'answers':
        return '🎲';
      case 'both':
        return '🔀🎲';
      default:
        return '📋';
    }
  }

  String _getShuffleDescription(String type) {
    switch (type) {
      case 'questions':
        return 'Savollar tasodifiy tartibda beriladi';
      case 'answers':
        return 'Javoblar tasodifiy tartibda beriladi';
      case 'both':
        return 'Savollar va javoblar aralashtiriladi';
      default:
        return 'Ketma-ket tartibda';
    }
  }

  Future<void> _showTimeSelection(Context ctx, int userId) async {
    await ctx.reply(
      '⏱ *Har bir savol uchun vaqtni tanlang:*',
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard(
        inlineKeyboard: [
          [
            InlineKeyboardButton(text: '⚡️ 10 soniya', callbackData: 'time:10'),
            InlineKeyboardButton(text: '⏱ 20 soniya', callbackData: 'time:20'),
          ],
          [
            InlineKeyboardButton(text: '🕐 30 soniya', callbackData: 'time:30'),
            InlineKeyboardButton(text: '⏰ 60 soniya', callbackData: 'time:60'),
          ],
          [
            InlineKeyboardButton(text: '🕰 90 soniya', callbackData: 'time:90'),
            InlineKeyboardButton(text: '⏳ 120 soniya', callbackData: 'time:120'),
          ],
          [
            InlineKeyboardButton(text: '♾ Cheksiz', callbackData: 'time:0'),
          ],
        ],
      ),
    );
  }

  Future<void> _startQuiz(Context ctx, int userId, int timePerQuestion) async {
    final session = sessionManager.getSession(userId);
    if (session == null) return;

    var quiz = session.quiz.copyWith(timePerQuestion: timePerQuestion);

    // Apply shuffle based on user choice
    final shuffleChoice = sessionManager.getShuffleChoice(userId);

    switch (shuffleChoice) {
      case 'questions':
        quiz = quiz.shuffleQuestions();
        break;
      case 'answers':
        quiz = quiz.shuffleAnswers();
        break;
      case 'both':
        quiz = quiz.shuffleBoth();
        break;
      default:
      // No shuffle
        break;
    }

    sessionManager.createSession(userId, quiz);

    // Generate share code
    final shareCode = _generateShareCode();
    quiz = quiz.copyWith(shareCode: shareCode);
    sessionManager.createSession(userId, quiz);

    // Save to Supabase
    try {
      final fileName = sessionManager.getFileName(userId);

      final questions = quiz.questions.map((q) {
        return {
          'text': q.text,
          'options': q.options,
          'correctIndex': q.correctOptionIndex,
        };
      }).toList();

      final quizData = await supabaseService.saveQuiz(
        telegramId: userId,
        subjectName: quiz.subjectName!,
        totalQuestions: quiz.questions.length,
        isShuffled: quiz.shuffled,
        answersShuffled: quiz.answersShuffled,
        timePerQuestion: timePerQuestion,
        fileName: fileName ?? 'unknown',
        questions: questions,
        shareCode: shareCode,
      );

      sessionManager.setQuizId(userId, quizData['id']);
      print('✅ Quiz saved with share code: $shareCode');
    } catch (e) {
      print('⚠️ Error saving quiz: $e');
    }

    await ctx.reply(
      '🎯 *Test boshlandi!*\n\n'
          '📚 Fan: *${quiz.subjectName}*\n'
          '📊 Savollar: *${quiz.questions.length} ta*\n'
          '🔀 Aralashtirish: *${_getShuffleDescription(shuffleChoice ?? 'none')}*\n'
          '⏱ Vaqt: *${timePerQuestion > 0 ? "$timePerQuestion soniya" : "Cheksiz"}*\n\n'
          '💡 Quizni ulashish: /share',
      parseMode: ParseMode.markdown,
    );

    await Future.delayed(Duration(milliseconds: 500));
    await _sendQuestion(ctx, userId);
  }

  Future<void> _sendQuestion(Context ctx, int userId) async {
    final session = sessionManager.getSession(userId);
    if (session == null || session.isCompleted) return;

    final question = session.currentQuestion;
    final quiz = session.quiz;

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
        openPeriod: quiz.timePerQuestion > 0 ? quiz.timePerQuestion : null,
      );
    } catch (e) {
      print('❌ Error sending poll: $e');
      await ctx.api.sendMessage(
        ChatID(userId),
        '❌ Savol yuborishda xatolik!\n\nXatolik: $e',
      );
    }
  }

  Future<void> handleMyQuizzes(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    try {
      final quizzes = await supabaseService.getUserQuizzes(userId);

      if (quizzes.isEmpty) {
        await ctx.reply(
          '📚 *Sizda hali quizlar yo\'q!*\n\n'
              'Yangi quiz yaratish uchun HEMIS faylini yuboring.',
          parseMode: ParseMode.markdown,
        );
        return;
      }

      final buttons = <List<InlineKeyboardButton>>[];

      for (int i = 0; i < quizzes.length && i < 10; i++) {
        final quiz = quizzes[i];
        final quizId = quiz['id'];
        final subjectName = quiz['subject_name'] ?? 'Noma\'lum fan';
        final totalQuestions = quiz['total_questions'] ?? 0;
        final hasStored = quiz['has_stored_questions'] == true;

        final emoji = hasStored ? '✅' : '📄';

        buttons.add([
          InlineKeyboardButton(
            text: '$emoji $subjectName ($totalQuestions ta)',
            callbackData: 'start_quiz:$quizId',
          ),
          InlineKeyboardButton(
            text: '📤',
            callbackData: 'share_quiz:$quizId',
          ),
        ]);
      }

      await ctx.reply(
        '📚 *Sizning quizlaringiz:*\n\n'
            '✅ = Instant qayta boshlash\n'
            '📄 = Faqat tarix\n'
            '📤 = Ulashish\n\n'
            'Tanlang:',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(inlineKeyboard: buttons),
      );
    } catch (e) {
      print('❌ Error: $e');
      await ctx.reply('❌ Xatolik yuz berdi!');
    }
  }

  Future<void> handleStatistics(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    try {
      final stats = await supabaseService.getUserStats(userId);

      if (stats.isEmpty || stats['completed_tests'] == 0) {
        await ctx.reply(
          '📊 *Statistika yo\'q!*\n\n'
              'Birinchi testni yakunlang.',
          parseMode: ParseMode.markdown,
        );
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln('📊 *SIZNING STATISTIKANGIZ*\n');
      buffer.writeln('━━━━━━━━━━━━━━━━━\n');
      buffer.writeln('📚 Jami quizlar: *${stats['total_quizzes']}*');
      buffer.writeln('✅ Yakunlangan: *${stats['completed_tests']}*');
      buffer.writeln('📈 O\'rtacha: *${stats['average_percentage'].toStringAsFixed(1)}%*');

      await ctx.reply(buffer.toString(), parseMode: ParseMode.markdown);
    } catch (e) {
      print('❌ Error: $e');
      await ctx.reply('❌ Xatolik yuz berdi!');
    }
  }

  Future<void> handleStop(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    final session = sessionManager.getSession(userId);

    if (session == null) {
      await ctx.reply(
        '❌ *Faol test yo\'q!*\n\n'
            'Test boshlash: /start',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    await ctx.reply(
      '⏸ *Test to\'xtatildi!*\n\n'
          'Nima qilmoqchisiz?',
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard(
        inlineKeyboard: [
          [
            InlineKeyboardButton(
              text: '▶️ Davom ettirish',
              callbackData: 'quiz_continue',
            ),
          ],
          [
            InlineKeyboardButton(
              text: '🏁 Tugatish',
              callbackData: 'quiz_finish',
            ),
          ],
        ],
      ),
    );
  }

  Future<void> handleHelp(Context ctx) async {
    await ctx.reply(
      '📚 *HEMIS Quiz Bot*\n\n'
          '🎯 *Qanday ishlaydi:*\n'
          '1️⃣ DOCX/DOC/TXT fayl yuklang\n'
          '2️⃣ Fan nomini kiriting\n'
          '3️⃣ Aralashtirish sozlamalarini tanlang\n'
          '4️⃣ Vaqtni belgilang\n'
          '5️⃣ Testni boshlang!\n\n'
          '🔀 *Aralashtirish:*\n'
          '   • Savollarni aralashtirish\n'
          '   • Javoblarni aralashtirish\n'
          '   • Ikkalasini ham\n\n'
          '⚙️ *Buyruqlar:*\n'
          '   /start - Boshlash\n'
          '   /quizlarim - Quizlarim\n'
          '   /statistika - Statistika\n'
          '   /share - Ulashish\n'
          '   /stop - To\'xtatish\n'
          '   /help - Yordam',
      parseMode: ParseMode.markdown,
    );
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  Future<File> _downloadFile(RawAPI api, String fileId, String fileName) async {
    final file = await api.getFile(fileId);
    final filePath = file.filePath!;
    final url = 'https://api.telegram.org/file/bot${api.token}/$filePath';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Faylni yuklab bo\'lmadi');
    }

    final tempDir = Directory.systemTemp;
    final tempFile = File(path.join(tempDir.path, fileName));
    await tempFile.writeAsBytes(response.bodyBytes);

    return tempFile;
  }
}