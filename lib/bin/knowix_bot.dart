import 'dart:io';
import 'dart:async';
import '../bot.dart';

void main() async {
  // Global error catching
  runZonedGuarded(() async {
    print('🚀 Quiz Bot Service Starting');

    final token = Platform.environment['BOT_TOKEN'] ?? '';
    if (token.isEmpty) {
      print('❌ BOT_TOKEN missing');
      exit(1);
    }

    print('Token: ${token.substring(0, 10)}...');

    // HTTP Server
    final port = int.parse(Platform.environment['PORT'] ?? '8080');
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('✅ HTTP :$port');

    server.listen((req) {
      req.response
        ..statusCode = 200
        ..write('{"status":"ok","bot":"active"}')
        ..close();
    });

    // Bot startup with error handling
    print('🤖 Creating bot...');
    final bot = QuizBot(token);

    // Run bot in separate zone
    runZonedGuarded(() async {
      print('🔄 Starting bot polling...');
      await bot.start();
    }, (error, stack) {
      print('❌ Bot zone error: $error');
      print(stack);
    });

    // Status check every 30 seconds
    Timer.periodic(Duration(seconds: 30), (timer) {
      print('💚 Heartbeat - System OK');
    });

    print('✅ All systems operational');

    // Keep alive
    await Future.delayed(Duration(days: 365 * 100));

  }, (error, stack) {
    print('❌ Fatal error: $error');
    print(stack);
    exit(1);
  });
}