import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';
import 'package:purevideo/presentation/global/widgets/error_view.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';
import 'package:purevideo/presentation/player/bloc/player_bloc.dart';
import 'package:purevideo/presentation/player/bloc/player_event.dart';
import 'package:purevideo/presentation/player/bloc/player_state.dart';
import 'package:flutter_cast_framework/widgets.dart';

class PlayerScreen extends StatefulWidget {
  final MovieDetailsModel movie;
  final int? seasonIndex;
  final int? episodeIndex;

  const PlayerScreen({
    super.key,
    required this.movie,
    this.seasonIndex,
    this.episodeIndex,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late PlayerBloc _playerBloc;

  @override
  void initState() {
    _playerBloc = PlayerBloc();
    super.initState();
    // Android TV already locks us into landscape via the manifest, but we
    // keep this call so in-app state stays consistent on tablets / emulators.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void deactivate() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.deactivate();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _playerBloc.add(const DisposePlayer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _playerBloc
        ..add(InitializePlayer(
          movie: widget.movie,
          seasonIndex: widget.seasonIndex,
          episodeIndex: widget.episodeIndex,
        )),
      child: const PlayerView(),
    );
  }
}

class PlayerView extends StatelessWidget {
  const PlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlayerBloc, PlayerState>(
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.errorMessage!)),
          );
        }
      },
      builder: (context, state) {
        if (state.isLoading) {
          return _buildLoadingView(context, state);
        }
        if (state.errorMessage != null) {
          return _buildErrorView(context, state);
        }
        return _TvPlayerView(state: state);
      },
    );
  }

  Widget _buildLoadingView(BuildContext context, PlayerState state) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              state.displayState,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TvFocusable(
              autofocus: true,
              borderRadius: BorderRadius.circular(12),
              focusScale: 1.06,
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, color: colorScheme.onPrimary),
                    const SizedBox(width: 8),
                    Text('Anuluj',
                        style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, PlayerState state) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ErrorView(
        message: state.errorMessage!,
        onRetry: () {
          context.read<PlayerBloc>().add(const LoadVideoSources());
        },
      ),
    );
  }
}

/// The actual D-Pad driven playback view. Kept as a [StatefulWidget] so we
/// can own a few [FocusNode]s, key listeners, and the idle-hide timer for
/// the control overlay.
class _TvPlayerView extends StatefulWidget {
  final PlayerState state;
  const _TvPlayerView({required this.state});

  @override
  State<_TvPlayerView> createState() => _TvPlayerViewState();
}

class _TvPlayerViewState extends State<_TvPlayerView> {
  // Focus nodes used to move focus to the play/pause button whenever the
  // overlay is (re)opened, so that D-Pad OK immediately toggles playback.
  final FocusNode _playPauseFocus = FocusNode(debugLabel: 'player.playPause');
  final FocusNode _seekBarFocus = FocusNode(debugLabel: 'player.seekBar');

  // Node that swallows every key press while the overlay is hidden. This
  // lets us intercept D-Pad events so ANY key shows the overlay again and
  // left/right skip 10s even without the UI being visible.
  final FocusNode _rootFocus = FocusNode(debugLabel: 'player.root');

  @override
  void dispose() {
    _playPauseFocus.dispose();
    _seekBarFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final bloc = context.read<PlayerBloc>();
    final state = widget.state;
    final key = event.logicalKey;

    // LEFT / RIGHT always seek, regardless of overlay visibility. This is
    // the standard Android TV expectation for video playback.
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind) {
      bloc.add(const SeekWithDirection(isForward: false));
      bloc.add(const ShowControls());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward) {
      bloc.add(const SeekWithDirection(isForward: true));
      bloc.add(const ShowControls());
      return KeyEventResult.handled;
    }

    // Play/pause buttons on TV remotes.
    if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      bloc.add(const PlayPause());
      bloc.add(const ShowControls());
      return KeyEventResult.handled;
    }

    // While the overlay is hidden, swallow OK / UP / DOWN and use them to
    // bring the overlay back.
    if (!state.isOverlayVisible) {
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        bloc.add(const ShowControls());
        // After the state rebuilds the play button autofocuses.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _playPauseFocus.canRequestFocus) {
            _playPauseFocus.requestFocus();
          }
        });
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final bloc = context.read<PlayerBloc>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _onRootKey,
        child: Stack(
          children: [
            Video(
              controller: bloc.controller,
              controls: NoVideoControls,
              fit: state.isImersive ? BoxFit.cover : BoxFit.contain,
            ),
            _buildBufferingIndicator(state),
            _buildSeekFlash(state),
            // Overlay (controls) – fades in/out with state.isOverlayVisible.
            IgnorePointer(
              ignoring: !state.isOverlayVisible,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: state.isOverlayVisible ? 1 : 0,
                child: _buildOverlay(context, state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context, PlayerState state) {
    return SafeArea(
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Container(
          // Scrim so controls stay readable over bright video content.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withAlpha(150),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withAlpha(200),
              ],
              stops: const [0.0, 0.2, 0.7, 1.0],
            ),
          ),
          child: Column(
            children: [
              _buildTopBar(context, state),
              const Spacer(),
              _buildCenterControls(context, state),
              const SizedBox(height: 24),
              _buildBottomBar(context, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBufferingIndicator(PlayerState state) {
    if (!state.isBuffering) return const SizedBox.shrink();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          if (state.displayState.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              state.displayState,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildSeekFlash(PlayerState state) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: state.isSeeking ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: Align(
          alignment: state.seekDirection == SeekDirection.forward
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 80),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(160),
                shape: BoxShape.circle,
              ),
              child: Icon(
                state.seekDirection == SeekDirection.forward
                    ? Icons.fast_forward
                    : Icons.fast_rewind,
                color: Colors.white,
                size: 52,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, PlayerState state) {
    final playerScreen = context.findAncestorWidgetOfExactType<PlayerScreen>();
    final movie = playerScreen!.movie;

    String title = movie.title;
    if (movie.isSeries == true &&
        playerScreen.seasonIndex != null &&
        playerScreen.episodeIndex != null) {
      final seasonIndex = playerScreen.seasonIndex!;
      final episodeIndex = playerScreen.episodeIndex!;
      final episode = movie.seasons![seasonIndex].episodes[episodeIndex];
      title = '${movie.title} - ${episode.title}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
      child: Row(
        children: [
          TvFocusable(
            borderRadius: BorderRadius.circular(28),
            focusScale: 1.08,
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(120),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back,
                  color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (movie.isSeries) _buildNextEpisodeButton(context),
        ],
      ),
    );
  }

  Widget _buildNextEpisodeButton(BuildContext context) {
    final playerScreen = context.findAncestorWidgetOfExactType<PlayerScreen>();
    final movie = playerScreen!.movie;
    final seasonIndex = playerScreen.seasonIndex;
    final episodeIndex = playerScreen.episodeIndex;

    if (seasonIndex == null || episodeIndex == null) {
      return const SizedBox.shrink();
    }

    late Map<String, dynamic> queryParameters;
    final nextEpisodeIndex = episodeIndex + 1;
    if (nextEpisodeIndex < movie.seasons![seasonIndex].episodes.length) {
      queryParameters = {
        'season': seasonIndex.toString(),
        'episode': nextEpisodeIndex.toString(),
      };
    } else if (seasonIndex + 1 < movie.seasons!.length) {
      queryParameters = {
        'season': (seasonIndex + 1).toString(),
        'episode': '0',
      };
    } else {
      return const SizedBox.shrink();
    }

    return TvFocusable(
      borderRadius: BorderRadius.circular(12),
      focusScale: 1.06,
      onTap: () {
        context.pushReplacementNamed('player',
            extra: movie, queryParameters: queryParameters);
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(120),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Następny odcinek',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            SizedBox(width: 6),
            Icon(Icons.skip_next, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls(BuildContext context, PlayerState state) {
    final bloc = context.read<PlayerBloc>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CircleIconButton(
          icon: Icons.replay_10,
          onTap: () => bloc.add(const SeekWithDirection(isForward: false)),
        ),
        const SizedBox(width: 32),
        // Play / Pause – the primary control. Autofocuses whenever the
        // overlay is visible so that OK immediately toggles playback.
        TvFocusable(
          focusNode: _playPauseFocus,
          autofocus: state.isOverlayVisible,
          borderRadius: BorderRadius.circular(56),
          focusScale: 1.14,
          onTap: () => bloc.add(const PlayPause()),
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white70, width: 2),
            ),
            child: Icon(
              state.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 64,
            ),
          ),
        ),
        const SizedBox(width: 32),
        _CircleIconButton(
          icon: Icons.forward_10,
          onTap: () => bloc.add(const SeekWithDirection(isForward: true)),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, PlayerState state) {
    final bloc = context.read<PlayerBloc>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      child: Column(
        children: [
          _TvSeekBar(
            focusNode: _seekBarFocus,
            position: state.position,
            duration: state.duration,
            onSeek: (fraction) => bloc.add(SeekTo(position: fraction)),
            onSkipForward: () =>
                bloc.add(const SeekWithDirection(isForward: true)),
            onSkipBackward: () =>
                bloc.add(const SeekWithDirection(isForward: false)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(state.position),
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.videoSources != null &&
                      state.videoSources!.length > 1)
                    _QualityButton(state: state),
                  const SizedBox(width: 12),
                  _CircleIconButton(
                    icon: state.isImersive
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    size: 48,
                    onTap: () => bloc.add(const ToggleImmersiveMode()),
                  ),
                  const SizedBox(width: 12),
                  Focus(
                    // Cast button draws its own icon button under the hood,
                    // but we wrap in a Focus so D-Pad can still reach it
                    // reliably on TVs without a visible overlay.
                    child: CastButton(
                      castFramework: state.castFramework,
                      activeColor: Colors.white,
                      color: Colors.white,
                      disabledColor: Colors.white,
                    ),
                  ),
                ],
              ),
              Text(_formatDuration(state.duration),
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

/// A round icon button rendered as a focusable TV control.
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: BorderRadius.circular(size),
      focusScale: 1.14,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(22),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white54),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

class _QualityButton extends StatelessWidget {
  final PlayerState state;
  const _QualityButton({required this.state});

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: BorderRadius.circular(12),
      focusScale: 1.08,
      onTap: () async {
        final bloc = context.read<PlayerBloc>();
        final selected = await showModalBottomSheet<VideoSource>(
          context: context,
          backgroundColor: Colors.black.withAlpha(230),
          builder: (ctx) => SafeArea(
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text('Jakość / źródło',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                  for (var i = 0; i < state.videoSources!.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: TvFocusable(
                        autofocus: i == 0,
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(ctx)
                            .pop(state.videoSources![i]),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          color: Colors.white.withAlpha(18),
                          child: Text(
                            '${state.videoSources![i].host}: '
                            '${state.videoSources![i].quality} - '
                            '${state.videoSources![i].lang}',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: state.videoSources![i] ==
                                      state.selectedSource
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        if (selected != null) {
          bloc.add(ChangeVideoSource(source: selected));
        }
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(22),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white54),
        ),
        child: const Icon(Icons.settings, color: Colors.white, size: 24),
      ),
    );
  }
}

/// A custom seek bar tailored for D-Pad use:
///   * Focusable container – the usual TvFocusable visual appears when it
///     receives focus.
///   * While focused, LEFT / RIGHT triggers a 10-second skip through the
///     provided callbacks (mirroring the bloc's SeekWithDirection event).
///   * Drawn as a progress bar; no swipe gestures.
class _TvSeekBar extends StatelessWidget {
  final FocusNode focusNode;
  final Duration position;
  final Duration duration;
  final ValueChanged<double> onSeek;
  final VoidCallback onSkipForward;
  final VoidCallback onSkipBackward;

  const _TvSeekBar({
    required this.focusNode,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onSkipForward,
    required this.onSkipBackward,
  });

  @override
  Widget build(BuildContext context) {
    final double progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          onSkipBackward();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onSkipForward();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (context) {
        final hasFocus = Focus.of(context).hasFocus;
        final theme = Theme.of(context);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hasFocus ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withAlpha(120),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LayoutBuilder(builder: (context, constraints) {
              final filled = constraints.maxWidth * progress;
              return Stack(
                children: [
                  Container(
                    height: hasFocus ? 12 : 6,
                    color: Colors.white24,
                  ),
                  Container(
                    height: hasFocus ? 12 : 6,
                    width: filled,
                    color: theme.colorScheme.primary,
                  ),
                  if (hasFocus)
                    Positioned(
                      left: (filled - 10).clamp(0.0, constraints.maxWidth - 20),
                      top: -4,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withAlpha(120),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
        );
      }),
    );
  }
}
