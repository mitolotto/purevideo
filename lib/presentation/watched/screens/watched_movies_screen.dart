import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';
import 'package:go_router/go_router.dart';

class WatchedMoviesScreen extends StatefulWidget {
  const WatchedMoviesScreen({super.key});

  @override
  State<WatchedMoviesScreen> createState() => _WatchedMoviesScreenState();
}

class MovieListItem extends StatelessWidget {
  final MovieModel movie;
  final bool autofocus;

  const MovieListItem({super.key, required this.movie, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(12),
      focusScale: 1.12,
      onTap: () => context.pushNamed('movie_details',
          pathParameters: {
            'title': movie.title,
          },
          extra: movie),
      child: FastCachedImage(
        url: movie.imageUrl,
        headers: movie.imageHeaders,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.movie,
            color: Theme.of(context).colorScheme.primary,
            size: 40,
          ),
        ),
      ),
    );
  }
}

class _WatchedMoviesScreenState extends State<WatchedMoviesScreen> {
  final WatchedService _watchedService = getIt<WatchedService>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder(
        stream: _watchedService.watchedStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(
              child: Text('Brak obejrzanych filmów'),
            );
          }

          final watchedMovies = snapshot.data!;

          if (watchedMovies.isEmpty) {
            return const Center(
              child: Text('Brak obejrzanych filmów'),
            );
          }

          // Convert WatchedMovieModel to MovieModel for display
          final movies = watchedMovies
              .map((watched) => MovieModel(
                    services: watched.movie.services
                        .map((e) => ServiceMovieModel(
                            service: e.service,
                            url: e.url,
                            title: e.title,
                            imageUrl: e.imageUrl))
                        .toList(),
                  ))
              .toList();

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    childAspectRatio: 2 / 3,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return MovieListItem(
                        movie: movies[index],
                        autofocus: index == 0,
                      );
                    },
                    childCount: movies.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
