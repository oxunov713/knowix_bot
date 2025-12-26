import 'dart:io';
import '../bot.dart';
import 'package:dotenv/dotenv.dart';

void main(List<String> arguments) async {
  var env = DotEnv()..load();

  final token = Platform.environment['BOT_TOKEN'];
  if (token == null || token.isEmpty) {
    print('❌ Error: BOT_TOKEN environment variable not set');
    print('💡 Usage: BOT_TOKEN=your_token_here dart run');
    exit(1);
  }

  final bot = QuizBot(token);

  // Handle graceful shutdown
  ProcessSignal.sigint.watch().listen((signal) async {
    print('\n⚠️  Received SIGINT, shutting down...');
    await bot.stop();
    exit(0);
  });

  try {
    await bot.start();
  } catch (e) {
    print('❌ Fatal error: $e');
    exit(1);
  }
}
