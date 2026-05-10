import 'package:equatable/equatable.dart';
import 'package:flutter/rendering.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:hive/hive.dart';
import 'package:purevideo/core/services/resolve_url_service.dart';
import 'package:purevideo/data/models/movie_model.dart';

@HiveType(typeId: 3)
class VideoSource extends Equatable {
  @HiveField(0)
  final String url;
  @HiveField(1)
  final String lang;
  @HiveField(2)
  final String quality;
  @HiveField(3)
  final String host;
  @HiveField(4)
  final Map<String, String>? headers;

  const VideoSource({
    required this.url,
    required this.lang,
    required this.quality,
    required this.host,
    this.headers,
  });

  @override
  String toString() {
    return 'VideoSource(url: $url, lang: $lang, quality: $quality, host: $host, headers: $headers)';
  }

  // Intentionally ignore `headers` in equality: two VideoSources that
  // point at the same stream URL with the same language/quality/host
  // are the same source regardless of request-header ordering. This
  // makes `state.videoSources.contains(state.selectedSource)` work
  // across copyWith-driven rebuilds, which the quality-picker
  // autofocus relies on to focus the currently selected row.
  @override
  List<Object?> get props => [url, lang, quality, host];
}

class VideoSourceRepository {
  late final ResolveUrlService _resolveService;

  VideoSourceRepository() {
    _initialize();
  }

  void _initialize() {
    _resolveService = getIt<ResolveUrlService>();
  }

  Future<MovieDetailsModel> scrapeVideoUrls(MovieDetailsModel movie) async {
    if (movie.videoUrls == null) return movie;

    final results = await _resolveService.resolve(movie.videoUrls ?? []);

    debugPrint('Resolved video sources: $results');

    return movie.copyWith(directUrls: results);
  }
}
