import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:purevideo/core/services/media_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/player/bloc/player_event.dart';
import 'package:purevideo/presentation/player/bloc/player_state.dart';
import 'package:pip/pip.dart';

/// Bloc that drives the video player screen.
///
/// Google Cast has been deliberately removed from this bloc. The
/// flutter_cast_framework plugin requires the Dynamite
/// "cast.framework.dynamite" module at runtime. That module is not
/// present on Android TV boxes (Homatics Box R 4K Plus crashed at
/// startup with DynamiteModule$LoadingException, followed by an
/// UninitializedPropertyAccessException in FlutterCastFrameworkPlugin's
/// onResume where mSessionManager had never been initialized). Casting
/// from a TV box to another device is also conceptually odd — the box
/// is itself the receiver. The bloc now only drives local playback via
/// media_kit plus PiP.
class PlayerBloc extends Bloc<PlayerEvent, PlayerState> {
  final WatchedService watchedService = getIt();

  late final Player _player;
  late final VideoController _controller;
  late StreamSubscription<Duration> _positionSubscription;
  late StreamSubscription<Duration?> _durationSubscription;
  late StreamSubscription<bool> _playingSubscription;
  late StreamSubscription<bool> _bufferingSubscription;

  Timer? _hideControlsTimer;
  Timer? _seekingTimer;
  Timer? _debounceHideControlsTimer;

  final VideoSourceRepository _videoSourceRepository =
      getIt<VideoSourceRepository>();
  final Map<SupportedService, MovieRepository> _movieRepositories =
      getIt<Map<SupportedService, MovieRepository>>();
  final MediaService _mediaService = getIt<MediaService>();

  // Nullable instead of `late final`: on Android TV boxes the audio
  // session plugin (just_audio's AudioSession) can fail to initialise
  // because several TV firmwares ship a stripped-down AudioManager
  // without the session types it expects. When that happens, reading
  // `_audioSession` later from _onDisposePlayer / _onPlayPause would
  // throw LateInitializationError and kill the whole bloc (which
  // manifests as "playback stopped -> app looks frozen"). Keeping it
  // nullable lets every access guard with `_audioSession?.setActive(..)`
  // and a no-op fallback.
  AudioSession? _audioSession;

  MovieDetailsModel? _movie;
  int? _seasonIndex;
  int? _episodeIndex;

  PlayerBloc() : super(PlayerState(pipFramework: Pip())) {
    on<InitializePlayer>(_onInitializePlayer);
    on<LoadVideoSources>(_onLoadVideoSources);
    on<InitializeVideoPlayer>(_onInitializeVideoPlayer);
    on<PlayPause>(_onPlayPause);
    on<SeekTo>(_onSeekTo);
    on<SeekWithDirection>(_onSeekWithDirection);
    on<ChangeVideoSource>(_onChangeVideoSource);
    on<ToggleControlsVisibility>(_onToggleControlsVisibility);
    on<ShowControls>(_onShowControls);
    on<HideControls>(_onHideControls);
    on<HideSeekingIndicator>(_onHideSeekingIndicator);
    on<UpdatePosition>(_onUpdatePosition);
    on<UpdateDuration>(_onUpdateDuration);
    on<UpdatePlayingState>(_onUpdatePlayingState);
    on<UpdateBufferingState>(_onUpdateBufferingState);
    on<PlayerError>(_onPlayerError);
    on<DisposePlayer>(_onDisposePlayer);
    on<ToggleImmersiveMode>(_onToggleImmersiveMode);
  }

  @override
  Future<void> close() {
    _disposeMediaKit();
    _hideControlsTimer?.cancel();
    _seekingTimer?.cancel();
    _debounceHideControlsTimer?.cancel();
    return super.close();
  }

  void _initMediaKit() {
    _player = Player();
    _controller = VideoController(_player);

    _positionSubscription = _player.stream.position.listen((position) {
      add(UpdatePosition(position: position));
    });

    _durationSubscription = _player.stream.duration.listen((duration) {
      add(UpdateDuration(duration: duration));
    });

    _playingSubscription = _player.stream.playing.listen((playing) {
      add(UpdatePlayingState(isPlaying: playing));
    });

    _bufferingSubscription = _player.stream.buffering.listen((buffering) {
      add(UpdateBufferingState(isBuffering: buffering));
    });
  }

  void _disposeMediaKit() {
    try {
      _positionSubscription.cancel();
    } catch (e) {
      debugPrint('Error cancelling position subscription: $e');
    }

    try {
      _durationSubscription.cancel();
    } catch (e) {
      debugPrint('Error cancelling duration subscription: $e');
    }

    try {
      _playingSubscription.cancel();
    } catch (e) {
      debugPrint('Error cancelling playing subscription: $e');
    }

    try {
      _bufferingSubscription.cancel();
    } catch (e) {
      debugPrint('Error cancelling buffering subscription: $e');
    }

    try {
      _player.dispose();
    } catch (e) {
      debugPrint('Error disposing media player: $e');
    }
  }

  Future<void> _onInitializePlayer(
    InitializePlayer event,
    Emitter<PlayerState> emit,
  ) async {
    _movie = event.movie;
    _seasonIndex = event.seasonIndex;
    _episodeIndex = event.episodeIndex;

    _initMediaKit();

    const options = PipOptions(
      autoEnterEnabled: true,
      aspectRatioX: 16,
      aspectRatioY: 9,
      sourceRectHintLeft: 0,
      sourceRectHintTop: 0,
      sourceRectHintRight: 1080,
      sourceRectHintBottom: 720,
      sourceContentView: 0,
      contentView: 0,
      preferredContentWidth: 480,
      preferredContentHeight: 270,
      controlStyle: 2,
    );

    // PiP is not supported on many Android TV boxes; fail gracefully
    // rather than crashing the player on startup.
    try {
      await state.pipFramework.setup(options);
      await state.pipFramework
          .registerStateChangedObserver(PipStateChangedObserver(
        onPipStateChanged: (pipState, error) {
          switch (pipState) {
            case PipState.pipStateStarted:
              emit(state.copyWith(isOverlayVisible: false));
              _hideControlsTimer?.cancel();
              debugPrint('PiP started');
              break;
            case PipState.pipStateFailed:
              debugPrint('PiP failed: $error');
              break;
            default:
              break;
          }
        },
      ));
    } catch (e) {
      debugPrint('PiP not available on this device: $e');
    }

    emit(state.copyWith(
      isLoading: true,
      errorMessage: null,
    ));

    add(const LoadVideoSources());
  }

  Future<void> _onLoadVideoSources(
    LoadVideoSources event,
    Emitter<PlayerState> emit,
  ) async {
    if (_movie == null) return;

    emit(state.copyWith(
      isLoading: true,
      errorMessage: null,
    ));

    try {
      MovieDetailsModel movieDetails;

      if (_seasonIndex != null && _episodeIndex != null) {
        final episodes = <EpisodeModel>[];
        for (final service in _movie!.services) {
          final movieRepository = _movieRepositories[service.service];
          if (movieRepository == null) {
            continue;
          }

          if (_seasonIndex! >= service.seasons!.length) continue;
          final season = service.seasons?[_seasonIndex!];
          if (season == null) continue;
          if (_episodeIndex! >= season.episodes.length) continue;
          final episode = season.episodes[_episodeIndex!];
          final episodeWithHosts =
              await movieRepository.getEpisodeHosts(episode);
          episodes.add(episodeWithHosts);
        }

        // this is dummy af but this system works better for movies than series
        final tempModel = MovieDetailsModel(
          services: [
            ServiceMovieDetailsModel(
                service: SupportedService.values.first,
                url: '',
                title: '',
                description: '',
                imageUrl: '',
                isSeries: true,
                videoUrls: episodes.expand((e) => e.videoUrls!).toList()),
          ],
          filmwebInfo: _movie!.filmwebInfo,
        );

        movieDetails = await _videoSourceRepository.scrapeVideoUrls(tempModel);
      } else {
        movieDetails = _movie!;
      }

      if (movieDetails.directUrls != null &&
          movieDetails.directUrls!.isNotEmpty) {
        final selectedSource = movieDetails.directUrls!.first;

        emit(state.copyWith(
          videoSources: movieDetails.directUrls,
          selectedSource: selectedSource,
          isLoading: false,
        ));

        add(InitializeVideoPlayer(source: selectedSource));
      } else {
        emit(state.copyWith(
          isLoading: false,
          errorMessage: 'Nie znaleziono źródeł odtwarzania',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Wystąpił błąd: $e',
      ));
    }
  }

  Future<void> _onInitializeVideoPlayer(
    InitializeVideoPlayer event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(
      displayState: 'Przygotowywanie odtwarzacza...',
      isBuffering: true,
    ));

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _audioSession = session;
    } catch (e) {
      debugPrint('Error initializing audio session: $e');
      // Leave _audioSession as null so every later access is a no-op
      // instead of throwing LateInitializationError.
      _audioSession = null;
    }

    try {
      final Map<String, String> headers = event.source.headers ?? {};

      int? watchedPosition;

      if (_seasonIndex != null && _episodeIndex != null) {
        final episode =
            _movie!.seasons![_seasonIndex!].episodes[_episodeIndex!];
        final watchedEpisode = watchedService.getByEpisode(_movie!, episode);
        watchedPosition = watchedEpisode?.watchedTime;
      } else {
        final watchedMovie = watchedService.getByMovie(_movie!);
        watchedPosition = watchedMovie?.watchedTime;
      }

      debugPrint('[PlayerBloc] Opening media: ${event.source.url}');
      await _player.open(
        Media(event.source.url,
            httpHeaders: headers,
            start: Duration(seconds: watchedPosition ?? 0)),
        play: true,
      );

      emit(state.copyWith(
        selectedSource: event.source,
        displayState: '',
      ));
    } catch (e) {
      emit(state.copyWith(
        isBuffering: false,
        errorMessage: 'Błąd inicjalizacji odtwarzacza: $e',
      ));
    }
  }

  Future<void> _onPlayPause(
    PlayPause event,
    Emitter<PlayerState> emit,
  ) async {
    try {
      _audioSession?.setActive(!state.isPlaying);
    } catch (_) {
      // audio session may not have been initialised yet
    }
    _player.playOrPause();

    if (state.isOverlayVisible) {
      _resetHideControlsTimer();
    }
  }

  Future<void> _onSeekTo(
    SeekTo event,
    Emitter<PlayerState> emit,
  ) async {
    final position = Duration(
      milliseconds: (event.position * state.duration.inMilliseconds).round(),
    );
    _player.seek(position);
  }

  Future<void> _onSeekWithDirection(
    SeekWithDirection event,
    Emitter<PlayerState> emit,
  ) async {
    final direction =
        event.isForward ? SeekDirection.forward : SeekDirection.backward;

    emit(state.copyWith(
      seekDirection: direction,
      isSeeking: true,
      isOverlayVisible: false,
    ));

    _seekingTimer?.cancel();
    _seekingTimer = Timer(const Duration(milliseconds: 400), () {
      add(const HideSeekingIndicator());
    });

    int newPositionSeconds = state.position.inSeconds;

    if (direction == SeekDirection.backward) {
      newPositionSeconds = max(0, newPositionSeconds - 10);
    } else {
      newPositionSeconds =
          min(newPositionSeconds + 10, state.duration.inSeconds);
    }

    _player.seek(Duration(seconds: newPositionSeconds));
  }

  Future<void> _onChangeVideoSource(
    ChangeVideoSource event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(selectedSource: event.source));
    add(InitializeVideoPlayer(source: event.source));
  }

  Future<void> _onToggleControlsVisibility(
    ToggleControlsVisibility event,
    Emitter<PlayerState> emit,
  ) async {
    if (state.isOverlayVisible) {
      emit(state.copyWith(isOverlayVisible: false));
      _hideControlsTimer?.cancel();
    } else {
      emit(state.copyWith(isOverlayVisible: true));
      _resetHideControlsTimer();
    }
  }

  Future<void> _onShowControls(
    ShowControls event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(isOverlayVisible: true));
    _resetHideControlsTimer();
  }

  Future<void> _onHideControls(
    HideControls event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(isOverlayVisible: false));
  }

  Future<void> _onHideSeekingIndicator(
    HideSeekingIndicator event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(isSeeking: false));
  }

  Future<void> _onUpdatePosition(
    UpdatePosition event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(position: event.position));
    _updateNotification();
  }

  Future<void> _onUpdateDuration(
    UpdateDuration event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(duration: event.duration));
    if (event.duration.inSeconds == 0) {
      return;
    }
    _mediaService.audioHandler.add(MediaItem(
      id: _movie!.title,
      title: _movie!.title,
      artUri: Uri.parse(_movie!.imageUrl),
      duration: state.duration,
    ));
    _updateNotification();
  }

  Future<void> _onUpdatePlayingState(
    UpdatePlayingState event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(isPlaying: event.isPlaying));
    _updateNotification();
  }

  Future<void> _onUpdateBufferingState(
    UpdateBufferingState event,
    Emitter<PlayerState> emit,
  ) async {
    if (event.isBuffering) {
      debugPrint('[PlayerBloc] Buffering started');
      emit(state.copyWith(isBuffering: true));
    } else {
      debugPrint('[PlayerBloc] Buffering complete - playback ready');
      emit(state.copyWith(
        isBuffering: false,
        isPlaying: true,
      ));
    }
    _updateNotification();
  }

  Future<void> _onPlayerError(
    PlayerError event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(
      isBuffering: false,
      errorMessage: event.message,
    ));
  }

  Future<void> _onDisposePlayer(
    DisposePlayer event,
    Emitter<PlayerState> emit,
  ) async {
    if (isClosed) return;

    try {
      // `?.` guards against LateInitializationError when the user
      // disposes the player before playback has ever started (e.g.
      // backs out of the details screen while sources are still
      // resolving).
      _audioSession?.setActive(false);
    } catch (e) {
      debugPrint('Error setting audio session inactive: $e');
    }

    try {
      _mediaService.audioHandler.playbackState.add(PlaybackState(
        playing: false,
      ));
    } catch (e) {
      debugPrint('Error updating playback state: $e');
    }

    if (_movie != null) {
      try {
        if (_movie!.isSeries) {
          watchedService.watchEpisode(
              _movie!,
              _movie!.seasons![_seasonIndex!],
              _movie!.seasons![_seasonIndex!].episodes[_episodeIndex!],
              state.position.inSeconds);
        } else {
          watchedService.watchMovie(_movie!, state.position.inSeconds);
        }
      } catch (e) {
        debugPrint('Error saving watched progress: $e');
      }
    }

    try {
      state.pipFramework.dispose();
    } catch (e) {
      debugPrint('Error disposing PiP framework: $e');
    }

    _disposeMediaKit();
    _hideControlsTimer?.cancel();
    _seekingTimer?.cancel();
    _debounceHideControlsTimer?.cancel();
  }

  void _resetHideControlsTimer() {
    // Debounce: only reset timer if controls are visible and at least 500ms have passed since last reset
    _debounceHideControlsTimer?.cancel();
    _debounceHideControlsTimer = Timer(const Duration(milliseconds: 500), () {
      _hideControlsTimer?.cancel();
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (!isClosed && state.isPlaying) {
          add(const HideControls());
        }
      });
    });
  }

  Future<void> _onToggleImmersiveMode(
    ToggleImmersiveMode event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(isImersive: !state.isImersive));
  }

  VideoController get controller => _controller;

  void _updateNotification() {
    _mediaService.audioHandler.playbackState.add(PlaybackState(
      playing: state.isPlaying,
      updatePosition: state.position,
      processingState: state.isBuffering
          ? AudioProcessingState.buffering
          : AudioProcessingState.ready,
      bufferedPosition: state.duration,
    ));
  }
}
