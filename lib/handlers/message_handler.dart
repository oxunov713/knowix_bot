import 'dart:io';
import 'package:televerse/telegram.dart' show InlineKeyboardButton, InputPollOption;
import 'package:televerse/televerse.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../services/quiz_service.dart';
import '../services/quiz_session_manager.dart';

/// Xabarlarni boshqaruvchi
class MessageHandler {
  final QuizService quizService;
  final QuizSessionManager sessionManager;

  MessageHandler(this.quizService, this.sessionManager);

  /// Start buyrug'ini boshqarish
  Future<void> handleStart(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId != null) {
      // Mavjud sessiyani tozalash
      sessionManager.endSession(userId);
    }

    await ctx.reply(
      '👋 *HEMIS Quiz Botga xush kelibsiz!*\n\n'
          '📚 HEMIS tizimidan eksport qilingan test fayllarini yuboring.\n\n'
          '📄 *Qo\'llab-quvvatlanadigan formatlar:*\n'
          '   • DOCX (tavsiya etiladi) ✅\n'
          '   • DOC\n'
          '   • TXT\n\n'
          '❌ *MUHIM:* PDF format qo\'llab-quvvatlanmaydi!\n\n'
          '💡 *HEMIS\'dan fayl olish:*\n'
          '1️⃣ HEMIS tizimiga kiring\n'
          '2️⃣ Test bo\'limiga o\'ting\n'
          '3️⃣ "Eksport" tugmasini bosing\n'
          '4️⃣ *DOCX formatni* tanlang\n'
          '5️⃣ Faylni bu yerga yuboring\n\n'
          '🔰 Yordam uchun: /help\n'
          '⏸ Testni to\'xtatish: /stop',
      parseMode: ParseMode.markdown,
    );
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

    // Hozirgi holatni ko'rsatish
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
          '   • /stop - Testni to\'xtatish\n'
          '   • /help - Yordam\n\n'
          '📝 *HEMIS fayl formati:*\n'
          '`+++++ Savol matni`\n'
          '`===== Variant A`\n'
          '`===== \\#To\'g\'ri javob`\n'
          '`===== Variant C`\n'
          '`===== Variant D`\n\n'
          '⏸ *Testni to\'xtatish:*\n'
          '   • /stop buyrug\'i yoki\n'
          '   • 3 ta savolga javob bermasangiz avtomatik to\'xtatiladi\n'
          '   • Keyin davom ettirish yoki natijani ko\'rish mumkin\n\n'
          '💡 *Maslahatlar:*\n'
          '   • DOCX format eng yaxshi ishlaydi\n'
          '   • \\# belgisi to\'g\'ri javobni ko\'rsatadi\n'
          '   • Agar \\# yo\'q bo\'lsa, birinchi variant to\'g\'ri deb olinadi\n'
          '   • Kamida 2 ta variant bo\'lishi kerak\n'
          '   • PDF ishlamaydi, faqat DOCX yuboring!\n\n'
          '❓ Savollaringiz bo\'lsa: @support\\_username',
      parseMode: ParseMode.markdown,
    );
  }

  /// Hujjatni yuklashni boshqarish
  Future<void> handleDocument(Context ctx) async {
    final document = ctx.message?.document;
    if (document == null) return;

    final fileName = document.fileName ?? 'noma\'lum';

    // Fayl turini tekshirish
    if (!quizService.isSupportedFile(fileName)) {
      final extension = path.extension(fileName).toLowerCase();

      String errorMsg = '❌ *Fayl turi qo\'llab-quvvatlanmaydi!*\n\n';

      if (extension == '.pdf') {
        errorMsg += '🚫 *PDF format ishlamaydi!*\n\n'
            '💡 *Yechim:*\n'
            '1️⃣ HEMIS\'da testni qayta oching\n'
            '2️⃣ "Eksport" tugmasini bosing\n'
            '3️⃣ *DOCX formatni* tanlang\n'
            '4️⃣ Yangi faylni bu yerga yuboring\n\n'
            '✅ DOCX format 100% ishlaydi va barcha savollarni topadi!';
      } else {
        errorMsg += '📄 Iltimos, quyidagi formatdagi fayllarni yuboring:\n'
            '   • DOCX (tavsiya etiladi) ✅\n'
            '   • DOC\n'
            '   • TXT\n\n'
            '⚠️ PDF qo\'llab-quvvatlanmaydi!';
      }

      await ctx.reply(errorMsg, parseMode: ParseMode.markdown);
      return;
    }

    // Fayl hajmini tekshirish (10MB limit)
    if (document.fileSize != null && document.fileSize! > 10 * 1024 * 1024) {
      await ctx.reply(
        '❌ *Fayl juda katta!*\n\n'
            'Maksimal hajm: 10 MB\n'
            'Sizning fayl: ${(document.fileSize! / 1024 / 1024).toStringAsFixed(1)} MB\n\n'
            '💡 Kichikroq fayl yuboring yoki faylni bo\'lib yuboring.',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    final loadingMsg = await ctx.reply('⏳ Fayl qayta ishlanmoqda...\n\n'
        '📊 Iltimos kuting, bu bir necha soniya davom etishi mumkin...');

    try {
      // Faylni yuklash
      final file = await _downloadFile(ctx.api, document.fileId, fileName);

      print('📁 Fayl yuklandi: ${file.path}');

      // Faylni qayta ishlash
      final quiz = await quizService.processFile(file);

      // Vaqtinchalik faylni o'chirish
      await file.delete();

      // Sessiya yaratish
      final userId = ctx.message!.from!.id;
      sessionManager.createSession(userId, quiz);

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

      String errorMsg = '❌ *Xatolik yuz berdi!*\n\n';

      final errorStr = e.toString();

      if (errorStr.contains('No valid questions') ||
          errorStr.contains('topilmadi')) {
        errorMsg += '📝 Faylda to\'g\'ri formatdagi savollar topilmadi.\n\n'
            '🔍 *Tekshiring:*\n'
            '   • HEMIS formatida ekanligiga\n'
            '   • +++++ va ===== belgilari borligiga\n'
            '   • Kamida 2 ta variant borligiga\n\n'
            '💡 /help buyrug\'i orqali formatni ko\'ring.';
      } else if (errorStr.contains('Qo\'llab-quvvatlanmaydigan')) {
        errorMsg += errorStr.replaceAll('Exception: ', '').replaceAll('UnsupportedError: ', '');
      } else {
        errorMsg += 'Sabab: ${errorStr.replaceAll('Exception: ', '')}\n\n'
            '💡 *Qaytadan urinib ko\'ring:*\n'
            '   • DOCX formatda eksport qiling\n'
            '   • Fayl to\'g\'ri ochilishini tekshiring\n'
            '   • Agar muammo davom etsa, /help ko\'ring';
      }

      await ctx.api.editMessageText(
        ChatID(ctx.message!.from!.id),
        loadingMsg.messageId,
        errorMsg,
        parseMode: ParseMode.markdown,
      );
    }
  }

  /// Matnli xabarni boshqarish
  Future<void> handleText(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    final text = ctx.message?.text;
    if (text == null || text.isEmpty) return;

    // Buyruqlarni e'tiborsiz qoldirish
    if (text.startsWith('/')) return;

    final session = sessionManager.getSession(userId);

    // HOLAT 1: Fan nomi kutilmoqda
    if (session != null && session.quiz.subjectName == null) {
      print('📚 Foydalanuvchi $userId fan nomini kiritdi: $text');

      // Fan nomi bilan yangilash
      final updatedQuiz = session.quiz.copyWith(subjectName: text);
      sessionManager.createSession(userId, updatedQuiz);

      // Aralashtirish haqida so'rash
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
      return;
    }

    // HOLAT 2: Vaqt kutilmoqda (endi faqat callback orqali)
    // TextField orqali kiritish o'chirildi
  }

  /// Vaqt tanlash uchun buttonlarni ko'rsatish
  Future<void> _showTimeSelection(Context ctx, int userId) async {
    await ctx.reply(
      '⏱ *Har bir savol uchun vaqtni tanlang:*\n\n'
          '💡 Qulay variant tanlang yoki boshqa vaqtni kiriting',
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard(
        inlineKeyboard: [
          [
            InlineKeyboardButton(
              text: '⚡️ 10 soniya',
              callbackData: 'time:10',
            ),
            InlineKeyboardButton(
              text: '⏱ 20 soniya',
              callbackData: 'time:20',
            ),
          ],
          [
            InlineKeyboardButton(
              text: '🕐 30 soniya',
              callbackData: 'time:30',
            ),
            InlineKeyboardButton(
              text: '⏰ 60 soniya',
              callbackData: 'time:60',
            ),
          ],
          [
            InlineKeyboardButton(
              text: '🕰 90 soniya',
              callbackData: 'time:90',
            ),
            InlineKeyboardButton(
              text: '⏳ 120 soniya',
              callbackData: 'time:120',
            ),
          ],
          [
            InlineKeyboardButton(
              text: '♾ Cheksiz',
              callbackData: 'time:0',
            ),
          ],
        ],
      ),
    );
  }

  /// Faylni Telegram'dan yuklash
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

  /// Testni boshlash
  Future<void> _startQuiz(Context ctx, int userId, int timePerQuestion) async {
    final session = sessionManager.getSession(userId);
    if (session == null) return;

    print('🚀 Test boshlanmoqda: foydalanuvchi $userId');

    var quiz = session.quiz.copyWith(timePerQuestion: timePerQuestion);

    if (session.pendingShuffleChoice == true) {
      print('🔀 Savollar aralashtirilmoqda');
      quiz = quiz.shuffleQuestions();
    }

    sessionManager.createSession(userId, quiz);

    await ctx.reply(
      '🎯 *Test boshlandi!*\n\n'
          '📚 Fan: *${quiz.subjectName}*\n'
          '📊 Savollar soni: *${quiz.questions.length} ta*\n'
          '🔀 Aralashtirish: *${quiz.shuffled ? "Ha" : "Yo'q"}*\n'
          '⏱ Har bir savol uchun: *${timePerQuestion > 0 ? "$timePerQuestion soniya" : "Cheksiz"}*\n\n'
          '🚀 Omad tilaymiz!',
      parseMode: ParseMode.markdown,
    );

    await Future.delayed(Duration(milliseconds: 500));
    await _sendQuestion(ctx, userId);
  }

  /// Matnni qisqartirish
  String _truncateOption(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  /// Savolni yuborish
  Future<void> _sendQuestion(Context ctx, int userId) async {
    final session = sessionManager.getSession(userId);
    if (session == null || session.isCompleted) return;

    final question = session.currentQuestion;
    final quiz = session.quiz;

    print('📮 Savol yuborilmoqda ${session.currentQuestionIndex + 1}/${quiz.questions.length}');

    final questionText = _truncateOption(question.text, 300);

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

  /// Callback so'rovlarini boshqarish
  Future<void> handleCallback(Context ctx) async {
    final query = ctx.callbackQuery;
    if (query == null) return;

    final userId = query.from.id;
    final data = query.data;

    // Shuffle tanlash
    if (data?.startsWith('shuffle:') == true) {
      final shuffle = data == 'shuffle:yes';

      print('🔄 Foydalanuvchi $userId aralashtirish tanladi: $shuffle');

      sessionManager.setPendingShuffleChoice(userId, shuffle);

      await ctx.answerCallbackQuery();
      await ctx.editMessageText(
        '${shuffle ? "🔀" : "📋"} Savollar ${shuffle ? "aralashtiriladi" : "ketma-ketlikda beriladi"}.',
        parseMode: ParseMode.markdown,
      );

      // Vaqt tanlash tugmalarini ko'rsatish
      await Future.delayed(Duration(milliseconds: 300));
      await _showTimeSelection(ctx, userId);
      return;
    }

    // Vaqt tanlash
    if (data?.startsWith('time:') == true) {
      final timeStr = data!.substring(5);
      final time = int.tryParse(timeStr);

      if (time == null) {
        await ctx.answerCallbackQuery(text: '❌ Xatolik!');
        return;
      }

      print('⏱ Foydalanuvchi $userId vaqtni tanladi: $time soniya');

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

    // Qaytadan boshlash
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
      return;
    }
  }
}