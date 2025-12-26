import 'dart:io';
import '../bot.dart';

Future<void> main(List<String> arguments) async {
  // Globe’da Environment Variables orqali tokenni oling
  final token = Platform.environment['BOT_TOKEN'];

  if (token == null || token.isEmpty) {
    print('❌ Error: BOT_TOKEN environment variable not set');
    print('💡 Add BOT_TOKEN in Globe Environment Variables');
    exit(1);
  }

  final bot = QuizBot(token);

  // Polling bot ishga tushadi
  print('🤖 Starting Quiz Bot...');

  try {
    await bot.start();
   // print('✅ Bot started: ${bot.username}');
  } catch (e) {
    print('❌ Fatal error: $e');
    exit(1);
  }

  // Graceful shutdown handler
  ProcessSignal.sigint.watch().listen((signal) async {
    print('\n⚠️ SIGINT received, stopping bot...');
    await bot.stop();
    exit(0);
  });

  // Globe Worker-da forever running loop
  // Polling bot shu yerda ishlayveradi
  await Future<void>.delayed(Duration(days: 365));
}
