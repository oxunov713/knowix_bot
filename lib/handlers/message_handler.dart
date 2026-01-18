import 'dart:io';
import 'dart:math';
import 'package:televerse/telegram.dart' show InlineKeyboardButton, InputPollOption, Message;
import 'package:televerse/televerse.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../services/quiz_service.dart';
import '../services/quiz_session_manager.dart';
import '../services/supabase_service.dart';

/// Enhanced message handler with improved error handling and share functionality
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
    try {
      final userId = ctx.message?.from?.id;
      final username = ctx.message?.from?.username ?? 'unknown';
      final firstName = ctx.message?.from?.firstName;
      final lastName = ctx.message?.from?.lastName;

      if (userId != null) {
        sessionManager.clearUserData(userId);

        try {
          await supabaseService.upsertUser(
            telegramId: userId,
            username: username,
            firstName: firstName,
            lastName: lastName,
          );
        } catch (e) {
          print('⚠️ Supabase user upsert error: $e');
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
            '   /quizlarim - Mening quizlarim\n'
            '   /statistika - Mening statistikam\n'
            '   /share - Quizni ulashish\n'
            '   /help - Yordam\n'
            '   /stop - Testni to\'xtatish',
        parseMode: ParseMode.markdown,
      );
    } catch (e) {
      print('❌ handleStart error: $e');
      await _sendErrorMessage(ctx, 'Xatolik yuz berdi. Qaytadan urinib ko\'ring.');
    }
  }

  Future<void> handleDocument(Context ctx) async {
    final document = ctx.message?.document;
    if (document == null) return;

    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    final fileName = document.fileName ?? 'noma\'lum';
    Message? loadingMsg;

    try {
      await supabaseService.updateUserActivity(userId);

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

      loadingMsg = await ctx.reply('⏳ Fayl qayta ishlanmoqda...');

      final file = await _downloadFile(ctx.api, document.fileId, fileName);

      try {
        final quiz = await quizService.processFile(file);

        if (quiz.questions.isEmpty) {
          throw Exception('Faylda savollar topilmadi!');
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
      } finally {
        try {
          await file.delete();
        } catch (e) {
          print('⚠️ Failed to delete temp file: $e');
        }
      }
    } catch (e) {
      print('❌ handleDocument error: $e');

      if (loadingMsg != null) {
        try {
          await ctx.api.editMessageText(
            ChatID(userId),
            loadingMsg.messageId,
            '❌ *Xatolik yuz berdi!*\n\n'
                '${e.toString()}\n\n'
                '💡 *Format tekshiring:*\n'
                '   • Savollar: +++++\n'
                '   • Variantlar: =====\n'
                '   • To\'g\'ri javob: #\n\n'
                'Qaytadan urinib ko\'ring: /start',
            parseMode: ParseMode.markdown,
          );
        } catch (editError) {
          print('❌ Failed to edit message: $editError');
          await _sendErrorMessage(ctx, 'Fayl qayta ishlashda xatolik: ${e.toString()}');
        }
      } else {
        await _sendErrorMessage(ctx, 'Fayl qayta ishlashda xatolik: ${e.toString()}');
      }
    }
  }

  Future<void> handleText(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    final text = ctx.message?.text;
    if (text == null || text.isEmpty || text.startsWith('/')) return;

    try {
      final session = sessionManager.getSession(userId);

      if (session != null && session.quiz.subjectName == null) {
        final cleanedText = text.trim();
        if (cleanedText.isEmpty || cleanedText.length > 100) {
          await ctx.reply(
            '⚠️ Fan nomi 1-100 belgi orasida bo\'lishi kerak.',
            parseMode: ParseMode.markdown,
          );
          return;
        }

        final updatedQuiz = session.quiz.copyWith(subjectName: cleanedText);
        sessionManager.createSession(userId, updatedQuiz);

        await ctx.reply(
          '📚 *Fan:* $cleanedText\n\n'
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
    } catch (e) {
      print('❌ handleText error: $e');
      await _sendErrorMessage(ctx, 'Xatolik yuz berdi. Qaytadan urinib ko\'ring.');
    }
  }

  Future<void> handleCallback(Context ctx) async {
    final query = ctx.callbackQuery;
    if (query == null) return;

    final userId = query.from.id;
    final data = query.data;

    try {
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

      // FIXED: Share quiz with proper error handling
      if (data?.startsWith('share_quiz:') == true) {
        final quizIdStr = data!.substring(11);
        final quizId = int.tryParse(quizIdStr);

        if (quizId == null) {
          await ctx.answerCallbackQuery(text: '❌ Noto\'g\'ri quiz ID');
          return;
        }

        try {
          // FIXED: Handle null return from generateShareCode
          final shareCode = await supabaseService.generateShareCode(quizId);

          if (shareCode == null || shareCode.isEmpty) {
            await ctx.answerCallbackQuery(
              text: '❌ Share code yaratilmadi',
            );
            await ctx.reply(
              '❌ *Xatolik!*\n\n'
                  'Share code yaratilmadi. Qaytadan urinib ko\'ring.',
              parseMode: ParseMode.markdown,
            );
            return;
          }

          await ctx.answerCallbackQuery(
            text: '📤 Ulashish havolasi yaratildi!',
          );

          final botUsername = (await ctx.api.getMe()).username;

          if (botUsername == null || botUsername.isEmpty) {
            throw Exception('Bot username topilmadi');
          }

          final shareUrl = 'https://t.me/$botUsername?start=quiz_$shareCode';

          await ctx.reply(
            '📤 *Quiz ulashish*\n\n'
                '🔗 Havola: `$shareUrl`\n\n'
                '📋 Kod: `$shareCode`\n\n'
                '💡 Do\'stlaringiz ushbu havola orqali aynan shu quizni yechishlari mumkin!',
            parseMode: ParseMode.markdown,
            replyMarkup: InlineKeyboard(
              inlineKeyboard: [
                [
                  InlineKeyboardButton(
                    text: '📤 Telegram orqali ulashish',
                    url: 'https://t.me/share/url?url=$shareUrl&text=Bu quizni yeching! 🎯',
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
          await ctx.reply(
            '❌ *Ulashish xatoligi!*\n\n'
                '${e.toString()}\n\n'
                'Qaytadan urinib ko\'ring: /share',
            parseMode: ParseMode.markdown,
          );
        }
        return;
      }
    } catch (e) {
      print('❌ handleCallback error: $e');
      try {
        await ctx.answerCallbackQuery(text: '❌ Xatolik yuz berdi');
      } catch (e) {
        print('❌ Failed to answer callback: $e');
      }
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
      await _sendErrorMessage(ctx, 'Xatolik yuz berdi. /start ni bosing.');
    }
  }

  Future<void> _startQuiz(Context ctx, int userId, int timePerQuestion) async {
    try {
      final session = sessionManager.getSession(userId);
      if (session == null) {
        await _sendErrorMessage(ctx, 'Sessiya topilmadi. /start ni bosing.');
        return;
      }

      var quiz = session.quiz.copyWith(timePerQuestion: timePerQuestion);

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
          break;
      }

      // FIXED: Generate shareCode before creating session
      final shareCode = _generateShareCode();
      quiz = quiz.copyWith(shareCode: shareCode);

      // Update session with new quiz
      sessionManager.createSession(userId, quiz);

      try {
        final fileName = sessionManager.getFileName(userId);

        final questions = quiz.questions.map((q) {
          return {
            'text': q.text,
            'options': q.options,
            'correctIndex': q.correctOptionIndex,
          };
        }).toList();

        // FIXED: Ensure subjectName is not null
        final subjectName = quiz.subjectName ?? 'Unknown Subject';

        final quizData = await supabaseService.saveQuiz(
          telegramId: userId,
          subjectName: subjectName,
          totalQuestions: quiz.questions.length,
          isShuffled: quiz.shuffled,
          answersShuffled: quiz.answersShuffled,
          timePerQuestion: timePerQuestion,
          fileName: fileName ?? 'unknown',
          questions: questions,
          shareCode: shareCode,
        );

        sessionManager.setQuizId(userId, quizData['id']);
        print('✅ Quiz saved with ID: ${quizData['id']}, share code: $shareCode');
      } catch (e) {
        print('⚠️ Error saving quiz to Supabase: $e');
        // Don't fail the quiz start if Supabase save fails
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
    } catch (e) {
      print('❌ _startQuiz error: $e');
      await _sendErrorMessage(ctx, 'Test boshlashda xatolik: ${e.toString()}');
    }
  }

  Future<void> _sendQuestion(Context ctx, int userId) async {
    try {
      final session = sessionManager.getSession(userId);
      if (session == null || session.isCompleted) return;

      final question = session.currentQuestion;
      final quiz = session.quiz;

      final List<InputPollOption> pollOptions = [];
      for (final opt in question.options) {
        pollOptions.add(InputPollOption(text: _truncate(opt, 100)));
      }

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
      print('❌ _sendQuestion error: $e');
      await ctx.api.sendMessage(
        ChatID(userId),
        '❌ Savol yuborishda xatolik!\n\n'
            'Test to\'xtatildi. Qaytadan boshlang: /start',
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
        final subjectName = quiz['subject_name'] ?? 'Noma\'lum';
        final totalQuestions = quiz['total_questions'] ?? 0;
        final hasStored = quiz['has_stored_questions'] == true;

        final emoji = hasStored ? '✅' : '📄';

        buttons.add([
          InlineKeyboardButton(
            text: '$emoji $subjectName ($totalQuestions)',
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
            '📄 = Faqat tarix\n\n'
            'Quiz tanlang yoki ulashing:',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(inlineKeyboard: buttons),
      );
    } catch (e) {
      print('❌ handleMyQuizzes error: $e');
      await _sendErrorMessage(ctx, 'Quizlar yuklanmadi. Qaytadan urinib ko\'ring.');
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
      print('❌ handleStatistics error: $e');
      await _sendErrorMessage(ctx, 'Statistika yuklanmadi.');
    }
  }

  Future<void> handleStop(Context ctx) async {
    final userId = ctx.message?.from?.id;
    if (userId == null) return;

    try {
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
    } catch (e) {
      print('❌ handleStop error: $e');
      await _sendErrorMessage(ctx, 'Xatolik yuz berdi.');
    }
  }

  Future<void> handleHelp(Context ctx) async {
    try {
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
    } catch (e) {
      print('❌ handleHelp error: $e');
    }
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  Future<File> _downloadFile(RawAPI api, String fileId, String fileName) async {
    try {
      final file = await api.getFile(fileId);
      final filePath = file.filePath;

      if (filePath == null) {
        throw Exception('Fayl yo\'li topilmadi');
      }

      final url = 'https://api.telegram.org/file/bot${api.token}/$filePath';

      final response = await http.get(Uri.parse(url)).timeout(
        Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Fayl yuklab olish juda uzoq davom etdi');
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Faylni yuklab bo\'lmadi (${response.statusCode})');
      }

      final tempDir = Directory.systemTemp;
      final tempFile = File(path.join(tempDir.path, fileName));
      await tempFile.writeAsBytes(response.bodyBytes);

      return tempFile;
    } catch (e) {
      print('❌ _downloadFile error: $e');
      throw Exception('Faylni yuklab olishda xatolik: ${e.toString()}');
    }
  }

  Future<void> _sendErrorMessage(Context ctx, String message) async {
    try {
      await ctx.reply(
        '❌ *Xatolik!*\n\n$message',
        parseMode: ParseMode.markdown,
      );
    } catch (e) {
      print('❌ Failed to send error message: $e');
    }
  }
}