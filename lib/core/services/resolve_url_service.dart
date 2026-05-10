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
/// Historical architecture (removed):
///   Earlier builds shipped an embedded CPython (serious_python) that
///   ran a Flask server on http://localhost:8080 wrapping the
///   libresolveurl Kodi addon. That approach never worked on
///   Android TV (Amlogic libc does not load CPython's _ssl/_hashlib
///   extensions, and our CI never ran the two-step
///   `dart run serious_python:main package` build, so
///   libpythonbundle.so was missing from the APK).
///
/// Current architecture:
///   * serious_python is gone.
///   * Resolution is delegated to a backend at RESOLVER_BASE_URL,
///     typically a hosted copy of `app/temp/main.py` (FastAPI) or the
///     Flask version bundled in `app/app.zip`. Build with:
///
///       flutter build apk --release \
///         --dart-define=RESOLVER_BASE_URL=https://your.host
///
///   * If RESOLVER_BASE_URL is empty (default) or the backend is
///     unreachable, we do NOT fail: we wrap the raw hoster URLs as
///     VideoSource objects with a Referer header and let media_kit
///     try them directly. This works for hosters that don't obfuscate
///     the stream URL (Doodstream, plain Streamtape CDN, some
///     Mixdrop mirrors) and, crucially, replaces "Nie znaleziono
///     źródeł odtwarzania" with an actual attempt at playback.
class ResolveUrlService {
  final Dio _dio;

  /// Base URL of the resolver backend. Empty by default so freshly
  /// installed APKs immediately use the raw-URL fallback instead of
  /// hanging on a non-existent localhost server.
  String serverUrl = const String.fromEnvironment(
    'RESOLVER_BASE_URL',
    defaultValue: '',
  );

  /// Cached result of the last `/health` probe. `null` means we
  /// haven't checked yet; `true` means we got a 200 at least once;
  /// `false` means the last check failed and we'll skip the resolver
  /// until the user restarts the app (cheap restart fixes it).
  bool? _serverAvailable;

  ResolveUrlService(this._dio);

  Future<bool> _probeHealth() async {
    // No backend configured at build time -> never probe, just use
    // the raw-URL fallback. This also makes debug builds on a laptop
    // work out of the box without any --dart-define.
    if (serverUrl.isEmpty) return false;
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
