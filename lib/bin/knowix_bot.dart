import 'dart:io';
import 'dart:async';
import '../bot.dart';

Future<void> main() async {
  print('=' * 50);
  print('🚀 QUIZ BOT STARTING');
  print('=' * 50);

  final token = Platform.environment['BOT_TOKEN'] ?? '';
  if (token.isEmpty) {
    print('❌ BOT_TOKEN not set');
    exit(1);
  }

  print('✅ BOT_TOKEN: ${token.substring(0, 10)}...${token.substring(token.length - 5)}');

  // HTTP serverni ishga tushirish
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  try {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('🌐 HTTP server bound to port $port');

    // Non-blocking HTTP handler
    server.listen((HttpRequest req) {
      final timestamp = DateTime.now().toIso8601String();
      print('📥 [HTTP] ${req.method} ${req.uri.path} - $timestamp');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"status":"ok","service":"quiz_bot","time":"$timestamp"}')
        ..close();
    });

    print('✅ HTTP server is listening');
  } catch (e) {
    print('❌ HTTP server error: $e');
    exit(1);
  }

  // Small delay to ensure HTTP is ready
  await Future.delayed(Duration(milliseconds: 500));

  // Botni ishga tushirish
  print('=' * 50);
  print('🤖 INITIALIZING BOT');
  print('=' * 50);

  try {
    final bot = QuizBot(token);
    print('✅ QuizBot instance created');

    // Start bot without await (background task)
    print('🔄 Starting bot in background...');
    bot.start().then((_) {
      print('✅ Bot.start() completed');
    }).catchError((e) {
      print('❌ Bot.start() error: $e');
    });

    // Give bot time to start
    await Future.delayed(Duration(seconds: 2));

    print('=' * 50);
    print('✅ SYSTEM FULLY OPERATIONAL');
    print('📡 Bot is polling for updates...');
    print('🌐 HTTP health check available on port $port');
    print('=' * 50);

    // Keep process alive
    await Future.delayed(Duration(days: 365 * 100));

  } catch (e, stackTrace) {
    print('=' * 50);
    print('❌ CRITICAL ERROR');
    print('=' * 50);
    print('Error: $e');
    print('Stack trace:');
    print(stackTrace);
    exit(1);
  }
}