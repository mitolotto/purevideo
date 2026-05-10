import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/data/models/filmweb_model.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';
import 'package:purevideo/presentation/global/widgets/tv_text_field.dart';
import 'package:purevideo/presentation/search/bloc/search_block.dart';
import 'package:purevideo/presentation/search/bloc/search_event.dart';
import 'package:purevideo/presentation/search/bloc/search_state.dart';
import 'package:purevideo/presentation/global/widgets/error_view.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocProvider(
        create: (context) => SearchBloc(),
        child: const SearchScreenContent(),
      ),
    );
  }
}

class MovieListItem extends StatelessWidget {
  final FilmwebPreviewModel movie;
  final bool autofocus;

  const MovieListItem({
    super.key,
    required this.movie,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(12),
      focusScale: 1.1,
      onTap: () => context.pushNamed('movie_details',
          pathParameters: {'title': movie.title},
          queryParameters: {'filmweb': 'true'},
          extra: movie),
      child: FastCachedImage(
        url: movie.posterUrl,
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

class SearchScreenContent extends StatefulWidget {
  const SearchScreenContent({super.key});

  @override
  State<SearchScreenContent> createState() => _SearchScreenContentState();
}

class _SearchScreenContentState extends State<SearchScreenContent> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      context.read<SearchBloc>().add(const SearchCleared());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Szukaj',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TvTextField(
                  controller: _searchController,
                  autofocus: true,
                  hintText: 'Wpisz tytuł filmu...',
                  prefixIcon: Icon(
                    Icons.search,
                    color: theme.colorScheme.primary,
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: (query) =>
                      context.read<SearchBloc>().add(SearchRequested(query)),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        BlocBuilder<SearchBloc, SearchState>(
          builder: (context, state) {
            if (state is SearchInitial) {
              return const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Zacznij wpisywać aby wyszukać filmy'),
                  ),
                ),
              );
            } else if (state is SearchLoading) {
              return const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
              );
            } else if (state is SearchLoaded) {
              if (state.results.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Nie znaleziono żadnych filmów'),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    childAspectRatio: 2 / 3,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        MovieListItem(movie: state.results[index]),
                    childCount: state.results.length,
                  ),
                ),
              );
            } else if (state is SearchError) {
              return SliverToBoxAdapter(
                child: ErrorView(
                  message: state.message,
                  onRetry: () {
                    _onSearchChanged(_searchController.text);
                  },
                ),
              );
            }
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          },
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}
