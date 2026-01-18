import 'dart:io';

import '../bot.dart';

void main() async {
  // Environment variables
  // final botToken = Platform.environment['BOT_TOKEN'];
  // final supabaseUrl = Platform.environment['SUPABASE_URL'];
  // final supabaseKey = Platform.environment['SUPABASE_ANON_KEY'];
  final botToken = "8338523756:AAFt5yv6KW8uyR6bPDNuU9CPR-7w3KjJvYU";
  final supabaseUrl ="https://kcqjxkswvzxuobrqukxa.supabase.co";
  final supabaseKey =



      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtjcWp4a3N3dnp4dW9icnF1a3hhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NDA4NDQsImV4cCI6MjA4NDMxNjg0NH0.yAQvEY-aStHRhxaltaLxbmW9NA7E-U0tAyLZKbOWG7g";// Validate BOT_TOKEN (required)
  if (botToken == null || botToken.isEmpty) {
    print('❌ Error: BOT_TOKEN environment variable not set');
    print('💡 Usage: export BOT_TOKEN=your_token && dart run bin/main.dart');
    exit(1);
  }



  // Initialize bot
  final bot = QuizBot(
    botToken,
    supabaseUrl,
    supabaseKey,
  );

  // Graceful shutdown
  ProcessSignal.sigint.watch().listen((signal) async {
    print('\n⚠️  Received SIGINT, shutting down...');
    await bot.stop();
    exit(0);
  });



  // Start bot
  try {
    await bot.start();
    print('✅ Bot successfully started and running...');

    // Keep alive
    await Future<void>.delayed(Duration(days: 365));
  } catch (e, stack) {
    print('❌ Fatal error: $e');
    print(stack);
    exit(1);
  }
}