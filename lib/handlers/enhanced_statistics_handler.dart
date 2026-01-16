import 'package:televerse/televerse.dart';
import 'package:televerse/telegram.dart';
import '../services/supabase_service.dart';

/// Yaxshilangan statistika handler
class EnhancedStatisticsHandler {
  final SupabaseService supabaseService;

  EnhancedStatisticsHandler(this.supabaseService);

  /// Umumiy statistika
  Future<void> handleStatistics(Context ctx) async {
    final userId = ctx.message?.from?.id ?? ctx.callbackQuery?.from.id;
    if (userId == null) return;

    final loadingMsg = ctx.callbackQuery != null
        ? null
        : await ctx.reply('⏳ Statistika yuklanmoqda...');

    try {
      await supabaseService.updateUserActivity(userId);

      final stats = await supabaseService.getUserStats(userId);
      final detailedStats = await supabaseService.getDetailedUserStats(userId);

      if (stats.isEmpty || stats['total_quizzes'] == 0) {
        if (ctx.callbackQuery != null) {
          await ctx.editMessageText(
            '📊 *Statistika yo\'q!*\n\n'
                'Birinchi quizni yarating.',
            parseMode: ParseMode.markdown,
          );
        } else if (loadingMsg != null) {
          await ctx.api.editMessageText(
            ChatID(userId),
            loadingMsg.messageId,
            '📊 *Statistika yo\'q!*\n\n'
                'Birinchi quizni yarating.',
            parseMode: ParseMode.markdown,
          );
        }
        return;
      }

      final message = _buildStatisticsMessage(stats, detailedStats);

      if (ctx.callbackQuery != null) {
        await ctx.editMessageText(
          message,
          parseMode: ParseMode.markdown,
          replyMarkup: _getStatsKeyboard(),
        );
      } else if (loadingMsg != null) {
        await ctx.api.editMessageText(
          ChatID(userId),
          loadingMsg.messageId,
          message,
          parseMode: ParseMode.markdown,
          replyMarkup: _getStatsKeyboard(),
        );
      }
    } catch (e) {
      print('❌ Error getting stats: $e');
      final errorMsg = '❌ Statistikani yuklashda xatolik yuz berdi.';

      if (ctx.callbackQuery != null) {
        await ctx.editMessageText(errorMsg);
      } else if (loadingMsg != null) {
        await ctx.api.editMessageText(
          ChatID(userId),
          loadingMsg.messageId,
          errorMsg,
        );
      }
    }
  }

  /// Statistika keyboard
  InlineKeyboard _getStatsKeyboard() {
    return InlineKeyboard(
      inlineKeyboard: [
        [
          InlineKeyboardButton(
            text: '📈 Batafsil',
            callbackData: 'stats_detailed',
          ),
          InlineKeyboardButton(
            text: '🏆 Top',
            callbackData: 'stats_top',
          ),
        ],
        [
          InlineKeyboardButton(
            text: '📚 Fanlar',
            callbackData: 'stats_subjects',
          ),
        ],
      ],
    );
  }

  /// Statistika xabarini yaratish
  String _buildStatisticsMessage(
      Map<String, dynamic> stats,
      Map<String, dynamic> detailed,
      ) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('📊 *SIZNING STATISTIKANGIZ*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln();

    // Asosiy ko'rsatkichlar
    final totalQuizzes = stats['total_quizzes'] ?? 0;
    final completedTests = stats['completed_tests'] ?? 0;
    final avgPercentage = stats['average_percentage'] ?? 0.0;

    buffer.writeln('📚 *Jami quizlar:* $totalQuizzes');
    buffer.writeln('✅ *Yakunlangan testlar:* $completedTests');

    if (completedTests > 0) {
      buffer.writeln('📈 *O\'rtacha natija:* ${avgPercentage.toStringAsFixed(1)}%');
      buffer.writeln();

      // Progress bar
      buffer.writeln(_buildProgressBar(avgPercentage));
      buffer.writeln();

      // Baho
      final grade = _calculateGrade(avgPercentage);
      buffer.writeln('🎯 *O\'rtacha baho:* $grade');
      buffer.writeln();
    } else {
      buffer.writeln();
      buffer.writeln('⚠️ Hali test topshirmadingiz!');
      buffer.writeln();
    }

    // Qo'shimcha statistika
    if (detailed.isNotEmpty) {
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln();

      // Eng yaxshi natija
      if (detailed['best_score'] != null) {
        buffer.writeln('🏆 *Eng yaxshi natija:* ${detailed['best_score'].toStringAsFixed(1)}%');
      }

      // Eng past natija
      if (detailed['worst_score'] != null) {
        buffer.writeln('📉 *Eng past natija:* ${detailed['worst_score'].toStringAsFixed(1)}%');
      }

      // Jami savollar
      if (detailed['total_questions_answered'] != null) {
        buffer.writeln('❓ *Javob berilgan savollar:* ${detailed['total_questions_answered']}');
      }

      // To'g'ri javoblar
      if (detailed['total_correct_answers'] != null) {
        buffer.writeln('✓ *To\'g\'ri javoblar:* ${detailed['total_correct_answers']}');
      }

      // Sarflangan vaqt
      if (detailed['total_time_spent'] != null) {
        final minutes = (detailed['total_time_spent'] as int) ~/ 60;
        buffer.writeln('⏱ *Jami sarflangan vaqt:* ${minutes}d');
      }

      buffer.writeln();
    }

    // Footer
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln();
    buffer.writeln('💡 Ko\'proq ma\'lumot uchun tugmalardan foydalaning');

    return buffer.toString();
  }

  /// Progress bar yaratish
  String _buildProgressBar(double percentage) {
    final filled = (percentage / 10).round();
    final empty = 10 - filled;

    final bar = '█' * filled + '░' * empty;
    return '[$bar] ${percentage.toStringAsFixed(1)}%';
  }

  /// Baho hisoblash
  String _calculateGrade(double percentage) {
    if (percentage >= 90) return '5 (A\'lo)';
    if (percentage >= 75) return '4 (Yaxshi)';
    if (percentage >= 60) return '3 (Qoniqarli)';
    return '2 (Qoniqarsiz)';
  }

  /// Batafsil statistika
  Future<void> handleDetailedStats(Context ctx) async {
    final query = ctx.callbackQuery;
    if (query == null) return;

    final userId = query.from.id;

    await ctx.answerCallbackQuery(text: 'Yuklanmoqda...');

    try {
      final detailed = await supabaseService.getDetailedUserStats(userId);
      final recentResults = await supabaseService.getRecentResults(userId, limit: 5);

      final buffer = StringBuffer();
      buffer.writeln('📈 *BATAFSIL STATISTIKA*');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln();

      if (detailed.isNotEmpty) {
        // Umumiy ma'lumotlar
        if (detailed['total_questions_answered'] != null) {
          final total = detailed['total_questions_answered'] as int;
          final correct = detailed['total_correct_answers'] as int;
          final accuracy = (correct / total * 100);

          buffer.writeln('📊 *Umumiy:*');
          buffer.writeln('❓ Savollar: *$total*');
          buffer.writeln('✓ To\'g\'ri: *$correct*');
          buffer.writeln('✗ Xato: *${total - correct}*');
          buffer.writeln('🎯 Aniqlik: *${accuracy.toStringAsFixed(1)}%*');
          buffer.writeln();
        }

        // Vaqt
        if (detailed['total_time_spent'] != null) {
          final totalSeconds = detailed['total_time_spent'] as int;
          final hours = totalSeconds ~/ 3600;
          final minutes = (totalSeconds % 3600) ~/ 60;

          buffer.writeln('⏱ *Vaqt:*');
          buffer.writeln('Jami: *${hours}s ${minutes}d*');

          if (detailed['avg_time_per_quiz'] != null) {
            final avgMinutes = (detailed['avg_time_per_quiz'] as int) ~/ 60;
            buffer.writeln('O\'rtacha: *${avgMinutes}d/quiz*');
          }
          buffer.writeln();
        }

        // Oxirgi natijalar
        if (recentResults.isNotEmpty) {
          buffer.writeln('📝 *Oxirgi 5 natija:*');
          buffer.writeln();

          for (int i = 0; i < recentResults.length && i < 5; i++) {
            final result = recentResults[i];
            final percentage = result['percentage'] as double;
            final emoji = _getEmojiForScore(percentage);
            final date = _formatDate(result['completed_at']);

            buffer.writeln('$emoji ${percentage.toStringAsFixed(1)}% — $date');
          }
          buffer.writeln();
        }
      } else {
        buffer.writeln('⚠️ Ma\'lumot yo\'q!');
        buffer.writeln();
      }

      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');

      await ctx.editMessageText(
        buffer.toString(),
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(
          inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: '⬅️ Orqaga',
                callbackData: 'stats_main',
              ),
            ],
          ],
        ),
      );
    } catch (e) {
      print('❌ Error: $e');
      await ctx.editMessageText('❌ Xatolik yuz berdi!');
    }
  }

  /// Top natijalar
  Future<void> handleTopResults(Context ctx) async {
    final query = ctx.callbackQuery;
    if (query == null) return;

    final userId = query.from.id;

    await ctx.answerCallbackQuery(text: 'Yuklanmoqda...');

    try {
      final detailed = await supabaseService.getDetailedUserStats(userId);
      final recentResults = await supabaseService.getRecentResults(userId, limit: 5);

      final buffer = StringBuffer();
      buffer.writeln('📈 *BATAFSIL STATISTIKA*');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln();

      if (detailed.isNotEmpty) {
        // Umumiy ma'lumotlar
        buffer.writeln('📊 *Umumiy ko\'rsatkichlar:*');
        buffer.writeln();

        if (detailed['total_questions_answered'] != null) {
          final total = detailed['total_questions_answered'] as int;
          final correct = detailed['total_correct_answers'] as int;
          final accuracy = (correct / total * 100);

          buffer.writeln('❓ Jami savollar: *$total*');
          buffer.writeln('✓ To\'g\'ri: *$correct*');
          buffer.writeln('✗ Xato: *${total - correct}*');
          buffer.writeln('🎯 Aniqlik: *${accuracy.toStringAsFixed(1)}%*');
          buffer.writeln();
        }

        // Vaqt statistikasi
        if (detailed['total_time_spent'] != null) {
          final totalSeconds = detailed['total_time_spent'] as int;
          final hours = totalSeconds ~/ 3600;
          final minutes = (totalSeconds % 3600) ~/ 60;

          buffer.writeln('⏱ *Vaqt statistikasi:*');
          buffer.writeln();
          buffer.writeln('Jami: *${hours}s ${minutes}d*');

          if (detailed['avg_time_per_quiz'] != null) {
            final avgMinutes = (detailed['avg_time_per_quiz'] as int) ~/ 60;
            buffer.writeln('O\'rtacha (quiz): *${avgMinutes}d*');
          }
          buffer.writeln();
        }

        // Oxirgi 5 ta natija
        if (recentResults.isNotEmpty) {
          buffer.writeln('📝 *Oxirgi natijalar:*');
          buffer.writeln();

          for (int i = 0; i < recentResults.length && i < 5; i++) {
            final result = recentResults[i];
            final percentage = result['percentage'] as double;
            final emoji = _getEmojiForScore(percentage);
            final date = _formatDate(result['completed_at']);

            buffer.writeln('$emoji ${percentage.toStringAsFixed(1)}% — $date');
          }
          buffer.writeln();
        }
      }

      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');

      await ctx.editMessageText(
        buffer.toString(),
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(
          inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: '⬅️ Orqaga',
                callbackData: 'stats_main',
              ),
            ],
          ],
        ),
      );
    } catch (e) {
      print('❌ Error: $e');
      await ctx.editMessageText('❌ Xatolik yuz berdi!');
    }
  }


  /// Fanlar bo'yicha statistika
  Future<void> handleStatsBySubject(Context ctx) async {
    final query = ctx.callbackQuery;
    if (query == null) return;

    final userId = query.from.id;

    await ctx.answerCallbackQuery(text: 'Yuklanmoqda...');

    try {
      final subjectStats = await supabaseService.getStatsBySubject(userId);

      final buffer = StringBuffer();
      buffer.writeln('📚 *FANLAR BO\'YICHA STATISTIKA*');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln();

      if (subjectStats.isEmpty) {
        buffer.writeln('⚠️ Hali natijalar yo\'q!');
      } else {
        for (final subject in subjectStats) {
          final name = subject['subject_name'] ?? 'Noma\'lum';
          final avgScore = subject['avg_percentage'] as double;
          final testCount = subject['test_count'] as int;

          final emoji = _getEmojiForScore(avgScore);

          buffer.writeln('$emoji *$name*');
          buffer.writeln('   📊 O\'rtacha: ${avgScore.toStringAsFixed(1)}%');
          buffer.writeln('   📝 Testlar: $testCount ta');
          buffer.writeln('   ${_buildMiniProgressBar(avgScore)}');
          buffer.writeln();
        }
      }

      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');

      await ctx.editMessageText(
        buffer.toString(),
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard(
          inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: '⬅️ Orqaga',
                callbackData: 'stats_main',
              ),
            ],
          ],
        ),
      );
    } catch (e) {
      print('❌ Error: $e');
      await ctx.editMessageText('❌ Xatolik yuz berdi!');
    }
  }

  /// Mini progress bar
  String _buildMiniProgressBar(double percentage) {
    final filled = (percentage / 20).round();
    final empty = 5 - filled;
    return '▓' * filled + '░' * empty;
  }

  /// Emoji olish
  String _getEmojiForScore(double percentage) {
    if (percentage >= 90) return '🏆';
    if (percentage >= 75) return '🌟';
    if (percentage >= 60) return '👍';
    if (percentage >= 50) return '📚';
    return '💪';
  }

  /// Sana formatlash
  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) return 'Bugun';
      if (diff.inDays == 1) return 'Kecha';
      if (diff.inDays < 7) return '${diff.inDays} kun oldin';

      return '${date.day}.${date.month}.${date.year}';
    } catch (e) {
      return '';
    }
  }
}