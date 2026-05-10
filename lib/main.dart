import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:purevideo/core/services/media_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/di/adapters_container.dart';
import 'package:purevideo/presentation/global/widgets/app.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'dart:ui';
import 'package:serious_python/serious_python.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseAnalytics.instance;

  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

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
  // Android TV: force landscape only. The app targets 16:9 screens and
  // D-Pad input, so portrait is explicitly disabled.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  SeriousPython.run('app/app.zip').then((log) {
    debugPrint('Python log: $log');
  }).catchError((error) {
    debugPrint('Error executing Python code: $error');
  });

  runApp(PureVideoApp());
}
