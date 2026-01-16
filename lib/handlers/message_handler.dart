import 'dart:io';
import 'package:televerse/telegram.dart' show InlineKeyboardButton, InputPollOption;
import 'package:televerse/televerse.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../services/quiz_service.dart';
import '../services/quiz_session_manager.dart';
import '../services/supabase_service.dart';
import '../helpers/quiz_restore_helper.dart';
import '../handlers/enhanced_statistics_handler.dart'; // YANGI

/// Xabarlarni boshqaruvchi - HYBRID STORAGE
class MessageHandler {
  final QuizService quizService;
  final QuizSessionManager sessionManager;
  final SupabaseService supabaseService;
  final EnhancedStatisticsHandler statisticsHandler; // YANGI

  MessageHandler(
      this.quizService,
      this.sessionManager,
      this.supabaseService,
      ) : statisticsHandler = EnhancedStatisticsHandler(supabaseService); // YANGI

  /// Start buyrug'ini boshqarish
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
          '   • /help - Yordam\n'
          '   • /stop - Testni to\'xtatish',
      parseMode: ParseMode.markdown,
    );
  }

  /// Quizlarim buyrug'i - HYBRID STORAGE
  Future<void> handleMyQuizzes(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    try {
      await supabaseService.updateUserActivity(userId);
    } catch (e) {
      print('⚠️ Error updating activity: $e');
    }

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

      // Inline keyboard yaratish
      final buttons = <List<InlineKeyboardButton>>[];

      for (int i = 0; i < quizzes.length && i < 10; i++) {
        final quiz = quizzes[i];
        final quizId = quiz['id'];
        final subjectName = quiz['subject_name'] ?? 'Noma\'lum fan';
        final totalQuestions = quiz['total_questions'] ?? 0;
        final hasStored = quiz['has_stored_questions'] == true;

        // Emoji: ✅ = saqlangan, 📄 = faqat metadata
        final emoji = hasStored ? '✅' : '📄';

        buttons.add([
          InlineKeyboardButton(
            text: '$emoji $subjectName ($totalQuestions ta savol)',
            callbackData: 'start_quiz:$quizId',
          ),
        ]);
      }

      await ctx.reply(
        '📚 *Sizning quizlaringiz:*\n\n'
            '✅ = Instant qayta boshlash\n'
            '📄 = Faqat tarix (fayl kerak)\n\n'
            'Tanlang:',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(inlineKeyboard: buttons),
      );
    } catch (e) {
      print('❌ Error getting quizzes: $e');
      await ctx.reply(
        '❌ Quizlarni yuklashda xatolik yuz berdi.',
        parseMode: ParseMode.markdown,
      );
    }
  }

  /// Statistika buyrug'i
  Future<void> handleStatistics(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    try {
      final stats = await supabaseService.getUserStats(userId);

      if (stats.isEmpty) {
        await ctx.reply(
          '📊 *Statistika yo\'q!*\n\n'
              'Birinchi quizni yarating.',
          parseMode: ParseMode.markdown,
        );
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln('📊 *Sizning statistikangiz:*\n');
      buffer.writeln('📚 Jami quizlar: *${stats['total_quizzes']}*');
      buffer.writeln('✅ Yakunlangan testlar: *${stats['completed_tests']}*');

      if (stats['completed_tests'] > 0) {
        buffer.writeln(
            '📈 O\'rtacha natija: *${stats['average_percentage'].toStringAsFixed(1)}%*');
      }

      await ctx.reply(buffer.toString(), parseMode: ParseMode.markdown);
    } catch (e) {
      print('❌ Error getting stats: $e');
      await ctx.reply('❌ Statistikani yuklashda xatolik yuz berdi.');
    }
  }

  /// Stop buyrug'ini boshqarish
  Future<void> handleStop(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    final session = sessionManager.getSession(userId);

    if (session == null) {
      await ctx.reply(
        '❌ *Sizda faol test yo\'q!*\n\n'
            '📚 Test boshlash uchun: /start',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    final currentQuestion = session.currentQuestionIndex + 1;
    final totalQuestions = session.quiz.questions.length;
    final correctAnswers = session.correctAnswers;

    await ctx.reply(
      '⏸ *Test to\'xtatildi!*\n\n'
          '📊 *Hozirgi holat:*\n'
          '   • Savol: *$currentQuestion/$totalQuestions*\n'
          '   • To\'g\'ri javoblar: *$correctAnswers*\n\n'
          '🤔 Nima qilmoqchisiz?',
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
              text: '🏁 Natijani ko\'rish',
              callbackData: 'quiz_finish',
            ),
          ],
          [
            InlineKeyboardButton(
              text: '🔄 Qaytadan boshlash',
              callbackData: 'quiz_restart',
            ),
          ],
        ],
      ),
    );
  }

  /// Yordam buyrug'i
  Future<void> handleHelp(Context ctx) async {
    await ctx.reply(
      '📚 *HEMIS Quiz Bot - Yo\'riqnoma*\n\n'
          '🎯 *Bot qanday ishlaydi?*\n'
          '1️⃣ HEMIS formatidagi DOCX/DOC/TXT fayl yuklang\n'
          '2️⃣ Fan nomini kiriting\n'
          '3️⃣ Savollarni aralashtirish variantini tanlang\n'
          '4️⃣ Vaqtni button orqali tanlang\n'
          '5️⃣ Testni boshlang va javob bering!\n\n'
          '⚙️ *Buyruqlar:*\n'
          '   • /start - Botni boshlash\n'
          '   • /quizlarim - Mening quizlarim\n'
          '   • /statistika - Statistikam\n'
          '   • /stop - Testni to\'xtatish\n'
          '   • /help - Yordam\n\n'
          '📝 *HEMIS fayl formati:*\n'
          '`+++++ Savol matni`\n'
          '`===== Variant A`\n'
          '`===== \\#To\'g\'ri javob`\n'
          '`===== Variant C`\n'
          '`===== Variant D`',
      parseMode: ParseMode.markdown,
    );
  }

  /// Hujjatni yuklashni boshqarish
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
        '❌ *Xatolik yuz berdi!*\n\n${e.toString()}',
        parseMode: ParseMode.markdown,
      );
    }
  }

  /// Matnli xabarni boshqarish
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
            '🔀 Savollarni tasodifiy tartibda berishni xohlaysizmi?',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(
          inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: '🔀 Ha, aralashtirsin',
                callbackData: 'shuffle:yes',
              ),
            ],
            [
              InlineKeyboardButton(
                text: '📋 Yo\'q, ketma-ketlikda',
                callbackData: 'shuffle:no',
              ),
            ],
          ],
        ),
      );
    }
  }

  /// Callback so'rovlarini boshqarish - HYBRID STORAGE
  Future<void> handleCallback(Context ctx) async {
    final query = ctx.callbackQuery;
    if (query == null) return;

    final userId = query.from.id;
    final data = query.data;

    // Mavjud quizni tanlash
    if (data?.startsWith('start_quiz:') == true) {
      final quizId = int.tryParse(data!.substring(11));
      if (quizId == null) return;

      await ctx.answerCallbackQuery(text: '⏳ Quiz yuklanmoqda...');

      try {
        final quizData = await supabaseService.getQuizWithQuestions(quizId);
        if (quizData == null) {
          await ctx.editMessageText('❌ Quiz topilmadi!');
          return;
        }

        final canRestart = quizData['can_restart'] == true;
        final hasStored = quizData['has_stored_questions'] == true;

        if (!canRestart || !hasStored) {
          // Faqat metadata
          await ctx.editMessageText(
            '📄 *${quizData['subject_name']}*\n\n'
                '⚠️ *Bu quizni qayta boshlash uchun faylni yuklang*\n\n'
                'Eski quizlar faqat tarix sifatida saqlanadi.\n'
                'Faqat oxirgi quiz to\'liq saqlanadi va uni instant qayta boshlash mumkin.\n\n'
                '💡 Yangi quiz yaratish: /start',
            parseMode: ParseMode.markdown,
          );
          return;
        }

        // Quizni tasdiqlash
        await ctx.editMessageText(
          '📚 *${quizData['subject_name']}*\n\n'
              '📊 Savollar: ${quizData['total_questions']} ta\n'
              '🔀 Aralashtirish: ${quizData['is_shuffled'] ? "Ha" : "Yo'q"}\n'
              '⏱ Vaqt: ${quizData['time_per_question'] == 0 ? "Cheksiz" : "${quizData['time_per_question']}s"}\n\n'
              '🚀 Testni boshlaysizmi?',
          parseMode: ParseMode.markdown,
          replyMarkup: InlineKeyboard(
            inlineKeyboard: [
              [
                InlineKeyboardButton(
                  text: '✅ Ha, boshlayman',
                  callbackData: 'confirm_start:$quizId',
                ),
              ],
              [
                InlineKeyboardButton(
                  text: '❌ Yo\'q, orqaga',
                  callbackData: 'cancel_start',
                ),
              ],
            ],
          ),
        );
      } catch (e) {
        print('❌ Error loading quiz: $e');
        await ctx.editMessageText('❌ Xatolik yuz berdi!');
      }
      return;
    }

    // Quizni tasdiqlash va boshlash
    if (data?.startsWith('confirm_start:') == true) {
      final quizId = int.tryParse(data!.substring(14));
      if (quizId == null) return;

      await ctx.answerCallbackQuery(text: '🚀 Test boshlanmoqda...');

      try {
        final quizData = await supabaseService.getQuizWithQuestions(quizId);
        if (quizData == null || quizData['questions'] == null) {
          await ctx.editMessageText('❌ Quiz topilmadi!');
          return;
        }

        // Quizni qayta tiklash
        await _restoreAndStartQuiz(ctx, userId, quizData);
      } catch (e) {
        print('❌ Error: $e');
        await ctx.editMessageText('❌ Xatolik yuz berdi!');
      }
      return;
    }

    // Bekor qilish
    if (data == 'cancel_start') {
      await ctx.answerCallbackQuery(text: '❌ Bekor qilindi');
      await ctx.editMessageText(
        '📚 Boshqa quiz tanlash uchun: /quizlarim',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    if (data?.startsWith('shuffle:') == true) {
      final shuffle = data == 'shuffle:yes';
      sessionManager.setPendingShuffleChoice(userId, shuffle);

      await ctx.answerCallbackQuery();
      await ctx.editMessageText(
        '${shuffle ? "🔀" : "📋"} Savollar ${shuffle ? "aralashtiriladi" : "ketma-ketlikda beriladi"}.',
        parseMode: ParseMode.markdown,
      );

      await Future.delayed(Duration(milliseconds: 300));
      await _showTimeSelection(ctx, userId);
      return;
    }

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

    // Statistika callback'lari - EnhancedStatisticsHandler'ga yo'naltirish
    if (data == 'stats_detailed') {
      await statisticsHandler.handleDetailedStats(ctx);
      return;
    }

    if (data == 'stats_top') {
      await statisticsHandler.handleTopResults(ctx);
      return;
    }

    if (data == 'stats_subjects') {
      await statisticsHandler.handleStatsBySubject(ctx);
      return;
    }

    if (data == 'stats_main') {
      await statisticsHandler.handleStatistics(ctx);
      return;
    }

    if (data == 'quiz_restart') {
      final session = sessionManager.getSession(userId);
      if (session != null) {
        sessionManager.endSession(userId);
        await ctx.answerCallbackQuery(text: '🔄 Sessiya tozalandi');
        await ctx.editMessageText(
          '🔄 *Sessiya tugadi!*\n\n'
              '📚 Yangi test boshlash uchun: /start',
          parseMode: ParseMode.markdown,
        );
      }
    }
  }

  /// Quizni restore qilish va boshlash - TO'LIQ IMPLEMENT
  Future<void> _restoreAndStartQuiz(
      Context ctx,
      int userId,
      Map<String, dynamic> quizData,
      ) async {
    try {
      await ctx.editMessageText(
        '⏳ *Quiz tiklanmoqda...*\n\n'
            'Iltimos kuting...',
        parseMode: ParseMode.markdown,
      );

      // Debug
      QuizRestoreHelper.debugPrintQuizData(quizData);

      // Validate
      if (!QuizRestoreHelper.validateQuizData(quizData)) {
        throw Exception('Invalid quiz data structure');
      }

      // Restore quiz
      final quiz = QuizRestoreHelper.fromSupabaseData(quizData);

      // Session yaratish
      sessionManager.createSession(userId, quiz);
      sessionManager.setQuizId(userId, quizData['id'] as int);

      print('✅ Quiz session created for user $userId');

      await ctx.editMessageText(
        '🎯 *Test boshlandi!*\n\n'
            '📚 Fan: *${quiz.subjectName}*\n'
            '📊 Savollar: *${quiz.questions.length} ta*\n'
            '🔀 Aralashtirish: *${quiz.shuffled ? "Ha" : "Yo'q"}*\n'
            '⏱ Vaqt: *${quiz.timePerQuestion > 0 ? "${quiz.timePerQuestion}s" : "Cheksiz"}*',
        parseMode: ParseMode.markdown,
      );

      await Future.delayed(Duration(milliseconds: 500));
      await _sendQuestion(ctx, userId);

    } catch (e, stackTrace) {
      print('❌ Restore error: $e');
      print('Stack trace: $stackTrace');

      await ctx.editMessageText(
        '❌ *Quizni tiklashda xatolik!*\n\n'
            'Xatolik: ${e.toString()}\n\n'
            '💡 Faylni qaytadan yuklab, yangi quiz yarating.',
        parseMode: ParseMode.markdown,
      );
    }
  }

  /// Vaqt tanlash tugmalari
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

  /// Yangi quiz saqlash - HYBRID STORAGE
  Future<void> _startQuiz(Context ctx, int userId, int timePerQuestion) async {
    final session = sessionManager.getSession(userId);
    if (session == null) return;

    var quiz = session.quiz.copyWith(timePerQuestion: timePerQuestion);

    if (session.pendingShuffleChoice == true) {
      quiz = quiz.shuffleQuestions();
    }

    sessionManager.createSession(userId, quiz);

    // Supabase ga quiz saqlash (SAVOLLAR BILAN!)
    try {
      final fileName = sessionManager.getFileName(userId);

      // Savollarni format qilish
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
        timePerQuestion: timePerQuestion,
        fileName: fileName ?? 'unknown',
        questions: questions, // MUHIM!
      );

      sessionManager.setQuizId(userId, quizData['id']);
      print('✅ Quiz saved with questions to database');
    } catch (e) {
      print('⚠️ Error saving quiz to Supabase: $e');
    }

    await ctx.reply(
      '🎯 *Test boshlandi!*\n\n'
          '📚 Fan: *${quiz.subjectName}*\n'
          '📊 Savollar: *${quiz.questions.length} ta*\n'
          '🔀 Aralashtirish: *${quiz.shuffled ? "Ha" : "Yo'q"}*\n'
          '⏱ Vaqt: *${timePerQuestion > 0 ? "$timePerQuestion soniya" : "Cheksiz"}*',
      parseMode: ParseMode.markdown,
    );

    await Future.delayed(Duration(milliseconds: 500));
    await _sendQuestion(ctx, userId);
  }

  /// Savolni yuborish
  Future<void> _sendQuestion(Context ctx, int userId) async {
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

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  Future<File> _downloadFile(
      RawAPI api, String fileId, String fileName) async {
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