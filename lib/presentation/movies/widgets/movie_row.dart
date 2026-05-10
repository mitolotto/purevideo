import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';

class MovieRow extends StatelessWidget {
  final String title;
  final List<MovieModel> movies;

  const MovieRow({super.key, required this.title, required this.movies});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ),
        SizedBox(
          // Larger than on mobile so D-Pad focus scaling never clips the
          // posters against the next row.
          height: 280,
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: ListView.separated(
              // Extra leading / trailing padding so the first tile isn't
              // cropped when it scales on focus.
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              scrollDirection: Axis.horizontal,
              itemCount: movies.length,
              separatorBuilder: (context, index) => const SizedBox(width: 20),
              itemBuilder: (context, index) {
                final movie = movies[index];
                return AspectRatio(
                  aspectRatio: 2 / 3,
                  child: TvFocusable(
                    borderRadius: BorderRadius.circular(12),
                    focusScale: 1.12,
                    onTap: () => context.pushNamed(
                      'movie_details',
                      pathParameters: {
                        'title': movie.title,
                      },
                      extra: movie,
                    ),
                    child: FastCachedImage(
                      url: movie.imageUrl,
                      headers: movie.imageHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[300],
                        child: const Icon(
                          Icons.broken_image,
                          size: 50,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
