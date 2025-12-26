import 'dart:io';
import '../bot.dart';

Future<void> main() async {
  final token = Platform.environment['BOT_TOKEN'] ?? '';
  if (token.isEmpty) {
    print('❌ BOT_TOKEN not set');
    exit(1);
  }

  final bot = QuizBot(token);
  await bot.start();

  // Minimal HTTP server, Globe port binding uchun
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('🌐 HTTP server running on port $port');

  await server.forEach((HttpRequest req) {
    req.response
      ..write('Bot is running!')
      ..close();
  });
}
