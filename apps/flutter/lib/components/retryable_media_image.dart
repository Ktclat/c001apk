import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

typedef MediaImageProviderBuilder = ImageProvider Function(
    String url, int index, int attempt);

/// Ordinary media uses a separate memory namespace, not a different disk key.
/// The package's delayed URL-key eviction must not evict a newer gallery load.
/// Equal sources still share successful images across pages and route visits.
@immutable
class _MediaCachedImageProvider
    extends ImageProvider<_MediaCachedImageProvider> {
  _MediaCachedImageProvider(this.source);

  final CachedNetworkImageProvider source;
  final _resolution = _MediaResolution();

  @override
  Future<_MediaCachedImageProvider> obtainKey(
          ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  void resolveStreamForKey(ImageConfiguration configuration, ImageStream stream,
      _MediaCachedImageProvider key, ImageErrorListener handleError) {
    super.resolveStreamForKey(configuration, stream, key, handleError);
    final completer = stream.completer;
    if (completer != null) {
      _resolution.completer = WeakReference(completer);
    }
  }

  // The visible widget also observes errors after a stale cached first frame.
  // A weak reference identifies its resolution without retaining any bitmap.
  void evictFailedResolution() => _evictIfOwned(_resolution.completer?.target);

  void _evictIfOwned(ImageStreamCompleter? completer) {
    if (completer == null) return;
    final cache = PaintingBinding.instance.imageCache;
    // No await between lookup and removal: a detached old request cannot
    // remove a newer completer cached under the same stable media key.
    if (cache.statusForKey(this).tracked &&
        identical(cache.putIfAbsent(this, () => completer), completer)) {
      cache.evict(this);
    }
  }

  @override
  ImageStreamCompleter loadImage(
      _MediaCachedImageProvider key, ImageDecoderCallback decode) {
    final completer = source.loadImage(source, decode);
    // This listener neither retains a live image nor extends its lifecycle.
    // Flutter removes it after the first frame/error. Unlike the package's
    // URL-only cleanup, only this completer may remove its failed cache entry.
    completer.addEphemeralErrorListener((error, stack) {
      key._evictIfOwned(completer);
      // Cleanup is not an error sink. The widget's errorBuilder still handles
      // current failures; unobserved errors retain normal framework reporting.
      throw error;
    });
    return completer;
  }

  @override
  bool operator ==(Object other) =>
      other is _MediaCachedImageProvider && source == other.source;

  @override
  int get hashCode => Object.hash(_MediaCachedImageProvider, source);
}

class _MediaResolution {
  WeakReference<ImageStreamCompleter>? completer;
}

/// Lightweight state only: no retained decoded image, stream or PhotoView.
/// A viewer keeps these entries so visiting an observed failure does not retry.
class MediaImageAttempt extends ChangeNotifier {
  MediaImageAttempt(this.url, this.index, {this.providerBuilder});

  final String url;
  final int index;
  final MediaImageProviderBuilder? providerBuilder;
  int generation = 0;
  bool retrying = false;
  bool cacheRemovalFailed = false;
  Object? error;
  Object? activeMount;
  bool _disposed = false;
  ImageProvider? _provider;

  ImageProvider get provider {
    if (_provider != null) return _provider!;
    final source = providerBuilder?.call(url, index, generation) ??
        CachedNetworkImageProvider(url);
    return _provider = source is CachedNetworkImageProvider
        ? _MediaCachedImageProvider(source)
        : source;
  }

  Future<void> retry() async {
    if (_disposed || retrying || error == null) return;
    final previous = provider;
    final source =
        previous is _MediaCachedImageProvider ? previous.source : previous;
    final previousGeneration = generation;
    retrying = true;
    cacheRemovalFailed = false;
    notifyListeners();
    try {
      // Decode failures can leave corrupt disk bytes. Remove just this failed
      // cache key, never all images, and do not change URL or request headers.
      if (source is CachedNetworkImageProvider) {
        await (source.cacheManager ??
                CachedNetworkImageProvider.defaultCacheManager)
            .removeFile(source.cacheKey ?? source.url);
      }
      if (_disposed || generation != previousGeneration) return;
      // Wrapped failures were already removed with their completer identity.
      // A different ordinal may now be loading the same key, so never evict it.
      if (previous is! _MediaCachedImageProvider) await previous.evict();
    } catch (_) {
      if (!_disposed && generation == previousGeneration) {
        retrying = false;
        cacheRemovalFailed = true;
        notifyListeners();
      }
      return;
    }
    if (_disposed || generation != previousGeneration) return;
    generation++;
    _provider = null;
    error = null;
    retrying = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Local to ordinary media thumbnails and the full-screen image viewer.
/// Shared avatars, app icons and article thumbnails keep their original helper.
class RetryableMediaImage extends StatefulWidget {
  const RetryableMediaImage({
    super.key,
    required this.url,
    required this.index,
    this.attempt,
    this.heroTag,
    this.providerBuilder,
    this.isGallery = false,
    this.width,
    this.height,
    this.fit,
  });

  final String url;
  final int index;
  final MediaImageAttempt? attempt;
  final Object? heroTag;
  final bool isGallery;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final MediaImageProviderBuilder? providerBuilder;

  @override
  State<RetryableMediaImage> createState() => _RetryableMediaImageState();
}

class _RetryableMediaImageState extends State<RetryableMediaImage> {
  final _mountIdentity = Object();
  late final MediaImageAttempt _attempt = widget.attempt ??
      MediaImageAttempt(widget.url, widget.index,
          providerBuilder: widget.providerBuilder);

  @override
  void initState() {
    super.initState();
    _attempt.activeMount = _mountIdentity;
  }

  @override
  void dispose() {
    if (identical(_attempt.activeMount, _mountIdentity)) {
      _attempt.activeMount = null;
    }
    if (widget.attempt == null) _attempt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _attempt,
        builder: (context, _) {
          if (_attempt.retrying) return _loading(context, null);
          if (_attempt.error != null) return _error(context);
          final generation = _attempt.generation;
          Widget onError(
              BuildContext context, Object error, StackTrace? stack) {
            if (mounted &&
                identical(_attempt.activeMount, _mountIdentity) &&
                generation == _attempt.generation &&
                _attempt.error == null) {
              final provider = _attempt.provider;
              if (provider is _MediaCachedImageProvider) {
                provider.evictFailedResolution();
              }
              _attempt.error = error;
              // Image's errorBuilder runs during build. Replace the resolver
              // after this frame, so later TickerMode/dependency changes cannot
              // silently resolve a failed thumbnail again. Replayed errors do
              // not clean a newer resolution or schedule another notification.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted &&
                    identical(_attempt.activeMount, _mountIdentity) &&
                    generation == _attempt.generation &&
                    identical(_attempt.error, error) &&
                    !_attempt.retrying) {
                  setState(() {});
                }
              });
            }
            return _error(context);
          }

          if (!widget.isGallery) {
            return SizedBox(
              width: widget.width,
              height: widget.height,
              child: Image(
                key: ValueKey(generation),
                image: _attempt.provider,
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
                excludeFromSemantics: true,
                frameBuilder: (context, child, frame, synchronous) =>
                    frame == null ? _loading(context, null) : child,
                loadingBuilder: (context, child, event) =>
                    event == null ? child : _loading(context, event),
                errorBuilder: onError,
              ),
            );
          }
          return PhotoView(
            key: ValueKey(generation),
            imageProvider: _attempt.provider,
            backgroundDecoration:
                const BoxDecoration(color: Colors.transparent),
            initialScale: PhotoViewComputedScale.contained,
            heroAttributes: widget.heroTag == null
                ? null
                : PhotoViewHeroAttributes(tag: widget.heroTag!),
            semanticLabel: '图片 ${widget.index + 1}',
            loadingBuilder: _loading,
            errorBuilder: onError,
          );
        },
      );

  Widget _error(BuildContext context) {
    if (!widget.isGallery) {
      return Semantics(
        label: '图片加载失败，点击查看原图',
        child: ColoredBox(
          color: Theme.of(context).colorScheme.errorContainer,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      );
    }
    final message = _attempt.cacheRemovalFailed ? '重试准备失败，请再试一次' : '图片加载失败';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _attempt.retry,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.refresh),
              label: const Text('重试本图'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loading(BuildContext context, ImageChunkEvent? event) {
    final total = event?.expectedTotalBytes;
    final progress = event == null || total == null || total <= 0
        ? null
        : (event.cumulativeBytesLoaded / total).clamp(0.0, 1.0);
    return Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          value: progress,
          semanticsLabel: '正在加载图片',
        ),
      ),
    );
  }
}
