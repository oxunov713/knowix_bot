import 'dart:async';
import 'dart:io';

import '../bot.dart';

void main() async {
  // Environment variables
  // final botToken = Platform.environment['BOT_TOKEN'];
  // final supabaseUrl = Platform.environment['SUPABASE_URL'];
  // final supabaseKey = Platform.environment['SUPABASE_ANON_KEY'];
  final token = "8338523756:AAFt5yv6KW8uyR6bPDNuU9CPR-7w3KjJvYU";
  final supabaseUrl ="https://kcqjxkswvzxuobrqukxa.supabase.co";
  final supabaseKey =



      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtjcWp4a3N3dnp4dW9icnF1a3hhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NDA4NDQsImV4cCI6MjA4NDMxNjg0NH0.yAQvEY-aStHRhxaltaLxbmW9NA7E-U0tAyLZKbOWG7g";// Validate BOT_TOKEN (required)
  // ✅ Validate environment variables
  if (token.isEmpty) {
    print('❌ BOT_TOKEN not set in environment variables');
    exit(1);
  }

  if (supabaseUrl.isEmpty) {
    print('⚠️  SUPABASE_URL not set - running without database');
  }

  if (supabaseKey.isEmpty) {
    print('⚠️  SUPABASE_KEY not set - running without database');
  }

  QuizBot? bot;

  try {
    // ✅ Initialize bot
    bot = QuizBot(
      token,
      supabaseUrl,
      supabaseKey,
    );

    // ✅ Start bot with retry
    await bot.start();

    // ✅ Setup graceful shutdown
    _setupGracefulShutdown(bot);

    // ✅ Setup health monitoring
    _setupHealthMonitoring(bot);

    // ✅ Setup session cleanup
    _setupSessionCleanup(bot);

    // ✅ Keep the process alive
    // Use _keepAlive() for heartbeat logs every hour
    // Use _keepAliveQuiet() for no periodic logs
    await _keepAliveQuiet(); // Changed to quiet mode

  } catch (e, stack) {
    print('❌ Fatal error: $e');
    print('Stack trace: $stack');

    if (bot != null) {
      await bot.stop();
    }

    exit(1);
  }
}

/// ✅ Setup graceful shutdown on SIGTERM/SIGINT
void _setupGracefulShutdown(QuizBot bot) {
  ProcessSignal.sigint.watch().listen((signal) async {
    print('\n🛑 Received SIGINT (Ctrl+C) - shutting down gracefully...');
    await bot.stop();
    bot.dispose();
    exit(0);
  });

  ProcessSignal.sigterm.watch().listen((signal) async {
    print('\n🛑 Received SIGTERM - shutting down gracefully...');
    await bot.stop();
    bot.dispose();
    exit(0);
  });

  print('✅ Graceful shutdown handlers registered');
}

/// ✅ Setup health monitoring
void _setupHealthMonitoring(QuizBot bot) {
  Timer.periodic(Duration(minutes: 5), (timer) async {
    try {
      final isHealthy = await bot.healthCheck();

      if (!isHealthy) {
        print('⚠️  Health check failed - attempting reconnect...');
        await bot.forceReconnect();
      } else {
        print('💚 Health check passed');
      }

      // Print stats
      final stats = await bot.getStats();
      print('📊 Stats: ${stats['active_sessions']} sessions, '
          '${stats['total_messages']} messages, '
          'reconnects: ${stats['reconnect_attempts']}');
    } catch (e) {
      print('⚠️  Health monitoring error: $e');
    }
  });

  print('✅ Health monitoring started (every 5 minutes)');
}

/// ✅ Setup session cleanup
void _setupSessionCleanup(QuizBot bot) {
  Timer.periodic(Duration(hours: 1), (timer) {
    try {
      // This is handled by QuizSessionManager internally
      print('🧹 Running session cleanup...');
    } catch (e) {
      print('⚠️  Cleanup error: $e');
    }
  });

  print('✅ Session cleanup scheduled (every hour)');
}

/// ✅ Keep process alive
Future<void> _keepAlive() async {
  // Create a completer that never completes
  final completer = Completer<void>();

  // Setup periodic heartbeat
  Timer.periodic(Duration(hours: 1), (timer) {
    print('💓 Heartbeat - Bot still running (${DateTime.now()})');
  });

  return completer.future;
}

/// ✅ Alternative: Simple keep alive without periodic logging
Future<void> _keepAliveQuiet() async {
  // Just wait forever
  await Future.delayed(Duration(days: 365 * 100));
}