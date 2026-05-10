import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';
import 'package:purevideo/di/injection_container.dart';

/// Resolves raw hoster links (e.g. streamtape.com embed pages) into
/// direct playable URLs.
///
/// Historical architecture:
///   The resolver runs inside an embedded CPython interpreter shipped
///   as `app/app.zip` and started by `serious_python` from `main.dart`.
///   It's a Flask server on `http://localhost:8080` that wraps the
///   `libresolveurl` Kodi addon (see `app/temp/main.py` for a copy).
///
/// Problem on Android TV:
///   1. `serious_python` requires its Python packages to be pre-built
///      at CI time via `SERIOUS_PYTHON_SITE_PACKAGES`. Our workflow
///      only `pip install`s `resolver/requirements.txt` — which does
///      not exist in the repo — so the APK ships an `app.zip` whose
///      `import flask` fails immediately at startup.
///   2. Even when the packages are present, several TV firmwares
///      (Amlogic-based: Homatics, Mecool, …) ship a libc build that
///      refuses to load CPython's `_ssl` / `_hashlib` extensions,
///      which also crashes the interpreter before `app.run()` is
///      called.
///   3. The user sees `Connection refused` to localhost because the
///      server was never actually up.
///
/// Fix:
///   * Make the base URL configurable at runtime. Set
///     `RESOLVER_BASE_URL` at compile time to point at a hosted copy
///     of `main.py` (Fly.io/Render/VPS) — zero changes needed in
///     source. If the env var is empty the code still tries
///     localhost:8080, so mobile/debug builds where the embedded
///     Python does start up keep working.
///   * Short timeouts so a dead server never blocks the UI for 30s.
///   * Probe `/health` once per instance; if it's unreachable we skip
///     the POST entirely and emit an "unresolved" VideoSource list so
///     the player can fall back to the raw embed URL via media_kit.
///     That is enough for hosters that don't obfuscate the direct
///     link (a surprisingly large set — Doodstream, Streamtape's
///     plain CDN, Mixdrop mirrors, etc.).
class ResolveUrlService {
  final Dio _dio;

  /// Base URL of the resolver backend. Keeps the legacy default so
  /// devices that DO have a working embedded Python still work.
  /// Override in builds via:
  ///   flutter build apk --release \
  ///     --dart-define=RESOLVER_BASE_URL=https://resolver.example.com
  String serverUrl = const String.fromEnvironment(
    'RESOLVER_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  /// Cached result of the last `/health` probe. `null` means we
  /// haven't checked yet; `true` means we got a 200 at least once;
  /// `false` means the last check failed and we'll skip the resolver
  /// until the user restarts the app (cheap restart fixes it).
  bool? _serverAvailable;

  ResolveUrlService(this._dio);

  Future<bool> _probeHealth() async {
    if (_serverAvailable != null) return _serverAvailable!;
    try {
      final response = await _dio.get(
        '$serverUrl/health',
        options: Options(
          // 1.5s is plenty for localhost; if a remote backend is
          // configured via RESOLVER_BASE_URL the user can bump this.
          receiveTimeout: const Duration(milliseconds: 1500),
          sendTimeout: const Duration(milliseconds: 1500),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      _serverAvailable = response.statusCode == 200;
      if (!_serverAvailable!) {
        debugPrint(
            'Resolver health check returned ${response.statusCode}, '
            'falling back to raw URLs.');
      }
      return _serverAvailable!;
    } catch (e) {
      debugPrint('Resolver at $serverUrl unreachable ($e). '
          'Playback will use raw hoster URLs as fallback.');
      _serverAvailable = false;
      return false;
    }
  }

  /// Convert a raw `HostLink` into a `VideoSource` without going
  /// through the resolver. Used when the resolver is down; the player
  /// gets the original embed URL and lets media_kit try its luck.
  VideoSource _fallbackSource(HostLink link) {
    return VideoSource(
      url: link.url,
      lang: link.lang ?? '',
      quality: link.quality ?? 'SD',
      host: _hostName(link.url),
      headers: {'Referer': link.url},
    );
  }

  String _hostName(String url) {
    try {
      final host = Uri.parse(url).host;
      final stripped = host.startsWith('www.') ? host.substring(4) : host;
      final first = stripped.split('.').first;
      return first.toUpperCase();
    } catch (_) {
      return 'UNKNOWN';
    }
  }

  Future<List<VideoSource>> resolve(List<HostLink> urls) async {
    debugPrint('Resolving URLs: $urls');

    urls = await Future.wait(urls
        .map((link) async => link.url.contains('play.ekino.link')
            ? link.copyWith(
                url: (await getIt<WebViewService>()
                        .waitForDomElement(link.url, 'iframe'))
                    ?.attributes['src'])
            : link)
        .toList());

    // Short-circuit if the resolver backend is unreachable: hand raw
    // embed URLs back so the player at least has something to try,
    // instead of showing "nie znaleziono zrodel odtwarzania".
    if (!await _probeHealth()) {
      return urls.map(_fallbackSource).toList();
    }

    try {
      final response = await _dio.post(
        '$serverUrl/resolve',
        data: jsonEncode(urls
            .map((link) => {
                  'url': link.url,
                  'language': link.lang,
                  'quality': link.quality,
                })
            .toList()),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          // Bound the total wait — the resolver can spend ~30s per
          // link internally but we don't want the player to hang more
          // than ~20s total, otherwise the user just sees a spinner.
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 5),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      debugPrint(
          'Response from resolver: ${response.statusCode} - ${response.data}');

      final data = response.data;
      if (data is! List) {
        debugPrint('Unexpected resolver response shape, using fallback');
        return urls.map(_fallbackSource).toList();
      }

      return data.map((item) {
        return VideoSource(
          url: item['url'] ?? '',
          lang: item['language'] ?? '',
          quality: item['quality'] ?? '',
          host: item['host'] ?? '',
          headers: item['headers'] != null
              ? Map<String, String>.from(item['headers'])
              : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error resolving URLs: $e — falling back to raw URLs');
      // Mark server as unavailable for the rest of this session so we
      // don't pay the timeout on every subsequent click.
      _serverAvailable = false;
      return urls.map(_fallbackSource).toList();
    }
  }
}
