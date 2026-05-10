import 'dart:async';
import 'dart:ui';
import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:purevideo/core/services/media_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/di/adapters_container.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/app.dart';
import 'package:serious_python/serious_python.dart';

import 'firebase_options.dart';

Future<void> main() async {
  // All app startup work happens inside runZonedGuarded so that any
  // uncaught async exception (for example in a plugin like PiP, media
  // browser, or Firebase) is routed to our own handler instead of
  // killing the process. On a TV box, crashing the main isolate means
  // the user just sees a black screen and has no way to recover.
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // --- Firebase (optional on Android TV) -----------------------
    // Firebase itself sometimes fails to initialise on TV boxes that
    // ship only a partial Google Play Services. Wrap it in try/catch
    // so the rest of the app boots anyway.
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseAnalytics.instance;

      FlutterError.onError = (errorDetails) {
        // Log and report, but DO NOT flag as fatal. Flutter framework
        // errors should never tear down the whole app on TV.
        FlutterError.presentError(errorDetails);
        FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        // Engine-level errors (from platform channels / plugins). Also
        // report as non-fatal.
        debugPrint('PlatformDispatcher error: $error\n$stack');
        try {
          FirebaseCrashlytics.instance
              .recordError(error, stack, fatal: false);
        } catch (_) {}
        return true;
      };
    } catch (e, st) {
      debugPrint('Firebase initialisation failed, continuing without it: $e');
      debugPrint('$st');
      // Still install a FlutterError handler so at least errors are
      // printed.
      FlutterError.onError = (details) => FlutterError.presentError(details);
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Unhandled platform error: $error\n$stack');
        return true;
      };
    }

    await FastCachedImageConfig.init(
      clearCacheAfter: const Duration(days: 1),
    );

    MediaKit.ensureInitialized();

    Hive.init((await getApplicationDocumentsDirectory()).path);

    setupHiveAdapters();
    setupInjection();
    await getIt<SettingsService>().init();
    await getIt<WatchedService>().init();
    await getIt<MediaService>().init();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    // Android TV: force landscape only. The app targets 16:9 screens
    // and D-Pad input, so portrait is explicitly disabled.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // serious_python's extraction and startup can take a while and
    // occasionally fails on TV boxes where the embedded interpreter
    // does not have a compatible libc. Run it fire-and-forget and
    // isolate failures so they never kill the Flutter UI.
    unawaited(
      SeriousPython.run('app/app.zip').then((log) {
        debugPrint('Python log: $log');
      }).catchError((Object error, StackTrace st) {
        debugPrint('Error executing Python code: $error');
        debugPrint('$st');
      }),
    );

    runApp(PureVideoApp());
  }, (Object error, StackTrace stack) {
    // Last-resort catch: anything that escapes main(). We log and try
    // to forward to Crashlytics but do not re-throw, so the process
    // keeps running whenever possible.
    debugPrint('Uncaught zone error: $error\n$stack');
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
    } catch (_) {}
  });
}
