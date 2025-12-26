import 'dart:io';
import '../bot.dart';

void main() async {
  final token = Platform.environment['BOT_TOKEN'];

  if (token == null || token.isEmpty) {
    print('❌ Error: BOT_TOKEN environment variable not set');
    exit(1);
  }

  final bot = QuizBot(token);

  // Graceful shutdown
  ProcessSignal.sigint.watch().listen((signal) async {
    print('\n⚠️  Received SIGINT, shutting down...');
    await bot.stop();
    exit(0);
  });

  // Botni ishga tushirish
  await bot.start();

  // Forever delay, worker sifatida ishlashi uchun
  await Future<void>.delayed(Duration(days: 365));
}
