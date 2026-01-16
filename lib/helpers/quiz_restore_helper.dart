
import '../models/question.dart';
import '../models/quiz.dart';

/// Quiz'ni database'dan restore qilish helper
class QuizRestoreHelper {

  /// Supabase data'dan Quiz obyekt yaratish
  static Quiz fromSupabaseData(Map<String, dynamic> quizData) {
    try {
      // 1. Savollarni convert qilish
      final questionsList = List<Map<String, dynamic>>.from(
          quizData['questions'] as List
      );

      print('📝 Converting ${questionsList.length} questions from database...');

      // 2. Question obyektlarini yaratish
      final questions = questionsList.map((q) {
        return Question(
          text: q['question_text'] as String,
          options: List<String>.from(q['options'] as List),
          correctOptionIndex: q['correct_index'] as int,
        );
      }).toList();

      print('✅ ${questions.length} questions converted successfully');

      // 3. Quiz obyekt yaratish
      final quiz = Quiz(
        subjectName: quizData['subject_name'] as String,
        questions: questions,
        timePerQuestion: quizData['time_per_question'] as int,
        shuffled: quizData['is_shuffled'] as bool,
      );

      print('✅ Quiz restored: ${quiz.subjectName} (${quiz.questions.length} questions)');

      return quiz;

    } catch (e, stackTrace) {
      print('❌ Error converting quiz from database: $e');
      print('Stack trace: $stackTrace');
      print('Quiz data: $quizData');
      rethrow;
    }
  }

  /// Quiz'ni validate qilish
  static bool validateQuizData(Map<String, dynamic> quizData) {
    try {
      // Required fields tekshirish
      if (quizData['subject_name'] == null) {
        print('❌ Missing subject_name');
        return false;
      }

      if (quizData['questions'] == null) {
        print('❌ Missing questions');
        return false;
      }

      final questions = quizData['questions'] as List;
      if (questions.isEmpty) {
        print('❌ Empty questions list');
        return false;
      }

      // Birinchi savolni tekshirish
      final firstQuestion = questions.first as Map<String, dynamic>;
      if (firstQuestion['question_text'] == null ||
          firstQuestion['options'] == null ||
          firstQuestion['correct_index'] == null) {
        print('❌ Invalid question structure');
        return false;
      }

      print('✅ Quiz data validation passed');
      return true;

    } catch (e) {
      print('❌ Validation error: $e');
      return false;
    }
  }

  /// Quiz'ni JSON'ga convert qilish (Supabase'ga saqlash uchun)
  static Map<String, dynamic> toSupabaseData(Quiz quiz) {
    return {
      'subject_name': quiz.subjectName,
      'total_questions': quiz.questions.length,
      'is_shuffled': quiz.shuffled,
      'time_per_question': quiz.timePerQuestion,
      'has_stored_questions': true,
      'questions': quiz.questions.map((q) => {
        'text': q.text,
        'options': q.options,
        'correctIndex': q.correctOptionIndex,
      }).toList(),
    };
  }

  /// Debug: Quiz ma'lumotlarini print qilish
  static void debugPrintQuizData(Map<String, dynamic> quizData) {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 QUIZ DATA DEBUG');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('Subject: ${quizData['subject_name']}');
    print('Total Questions: ${quizData['total_questions']}');
    print('Is Shuffled: ${quizData['is_shuffled']}');
    print('Time Per Question: ${quizData['time_per_question']}');
    print('Has Stored Questions: ${quizData['has_stored_questions']}');

    if (quizData['questions'] != null) {
      final questions = quizData['questions'] as List;
      print('Questions in data: ${questions.length}');

      if (questions.isNotEmpty) {
        print('\nFirst question:');
        final first = questions.first as Map<String, dynamic>;
        print('  Text: ${first['question_text']}');
        print('  Options: ${first['options']}');
        print('  Correct Index: ${first['correct_index']}');
      }
    } else {
      print('❌ No questions in data!');
    }
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }
}