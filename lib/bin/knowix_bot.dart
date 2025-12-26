import 'dart:io';
import '../bot.dart';

Future<void> main() async {
  final token = Platform.environment['BOT_TOKEN'] ?? '';
  if (token.isEmpty) {
    print('❌ BOT_TOKEN not set');
    exit(1);
  }

  // HTTP serverni BIRINCHI ishga tushirish (Globe uchun)
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('🌐 HTTP server running on port $port');

  // HTTP serverga javob berish (background task)
  server.listen((HttpRequest req) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write('{"status":"running","bot":"Quiz Bot"}')
      ..close();
  });

  // Botni ishga tushirish (keyin)
  final bot = QuizBot(token);
  await bot.start();

  print('✅ System fully started');
}