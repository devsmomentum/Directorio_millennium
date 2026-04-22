import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class ScreenAdBanners extends StatefulWidget {
  final Widget child;
  final String topPlaceholderLabel;
  final String bottomPlaceholderLabel;
  final bool showTop;
  final bool showBottom;

  const ScreenAdBanners({
    super.key,
    required this.child,
    this.topPlaceholderLabel = 'Publicidad superior',
    this.bottomPlaceholderLabel = 'Publicidad inferior',
    this.showTop = true,
    this.showBottom = true,
  });

  @override
  State<ScreenAdBanners> createState() => _ScreenAdBannersState();
}

class _ScreenAdBannersState extends State<ScreenAdBanners> {
  List<Map<String, dynamic>> _topBanners = [];
  List<Map<String, dynamic>> _bottomBanners = [];

  @override
  void initState() {
    super.initState();
    _loadBanners();
  }

  Future<void> _loadBanners() async {
    await _ensureBannerCacheLoaded();

    if (!mounted) return;
    setState(() {
      _topBanners = List<Map<String, dynamic>>.from(_BannerCache.topBanners);
      _bottomBanners = List<Map<String, dynamic>>.from(
        _BannerCache.bottomBanners,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bannerHeight = MediaQuery.of(context).size.height * 0.1;
    final children = <Widget>[];

    if (widget.showTop) {
      children.add(
        SizedBox(
          height: bannerHeight,
          child: _AdBannerWidget(
            banners: _topBanners,
            placeholderLabel: widget.topPlaceholderLabel,
          ),
        ),
      );
    }

    children.add(Expanded(child: widget.child));

    if (widget.showBottom) {
      children.add(
        SizedBox(
          height: bannerHeight,
          child: _AdBannerWidget(
            banners: _bottomBanners,
            placeholderLabel: widget.bottomPlaceholderLabel,
          ),
        ),
      );
    }

    return Column(children: children);
  }
}

class BottomNavigationAdBanner extends StatefulWidget {
  final String placeholderLabel;
  final double heightFactor;

  const BottomNavigationAdBanner({
    super.key,
    this.placeholderLabel = 'Publicidad inferior',
    this.heightFactor = 0.1,
  });

  @override
  State<BottomNavigationAdBanner> createState() =>
      _BottomNavigationAdBannerState();
}

class _BottomNavigationAdBannerState extends State<BottomNavigationAdBanner> {
  List<Map<String, dynamic>> _bottomBanners = [];

  @override
  void initState() {
    super.initState();
    _loadBanners();
  }

  Future<void> _loadBanners() async {
    await _ensureBannerCacheLoaded();

    if (!mounted) return;
    setState(() {
      _bottomBanners = List<Map<String, dynamic>>.from(
        _BannerCache.bottomBanners,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bannerHeight =
        MediaQuery.of(context).size.height * widget.heightFactor;
    return SizedBox(
      height: bannerHeight,
      child: _AdBannerWidget(
        banners: _bottomBanners,
        placeholderLabel: widget.placeholderLabel,
      ),
    );
  }
}

class _BannerCache {
  static bool loaded = false;
  static Future<void>? pendingLoad;
  static List<Map<String, dynamic>> topBanners = [];
  static List<Map<String, dynamic>> bottomBanners = [];
}

Future<void> _ensureBannerCacheLoaded() async {
  if (_BannerCache.loaded) return;

  if (_BannerCache.pendingLoad != null) {
    await _BannerCache.pendingLoad;
    return;
  }

  final loadFuture = _fetchAndCacheBanners();
  _BannerCache.pendingLoad = loadFuture;
  await loadFuture;
  _BannerCache.pendingLoad = null;
}

Future<void> _fetchAndCacheBanners() async {
  try {
    final response = await Supabase.instance.client
        .from('banners')
        .select(
          'id, media_url, media_type, ui_position, is_active, slot_position',
        )
        .eq('is_active', true)
        .order('slot_position', ascending: true);

    final all = List<Map<String, dynamic>>.from(response);
    _BannerCache.topBanners = all
        .where((banner) => banner['ui_position'] == 'top')
        .toList();
    _BannerCache.bottomBanners = all
        .where((banner) => banner['ui_position'] == 'bottom')
        .toList();
    _BannerCache.loaded = true;
  } catch (e) {
    debugPrint('Error loading screen banners: $e');
  }
}

class _AdBannerWidget extends StatefulWidget {
  final List<Map<String, dynamic>> banners;
  final String placeholderLabel;

  const _AdBannerWidget({
    required this.banners,
    required this.placeholderLabel,
  });

  @override
  State<_AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<_AdBannerWidget> {
  Timer? _rotationTimer;
  int _currentBannerIndex = 0;
  VideoPlayerController? _videoController;

  Map<String, dynamic>? get _currentBanner {
    if (widget.banners.isEmpty) return null;
    if (_currentBannerIndex >= widget.banners.length) {
      _currentBannerIndex = 0;
    }
    return widget.banners[_currentBannerIndex];
  }

  @override
  void initState() {
    super.initState();
    _configureLoop();
  }

  @override
  void didUpdateWidget(covariant _AdBannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldSignature = oldWidget.banners
        .map((banner) => banner['id']?.toString() ?? '')
        .join('|');
    final newSignature = widget.banners
        .map((banner) => banner['id']?.toString() ?? '')
        .join('|');

    if (oldSignature != newSignature) {
      _currentBannerIndex = 0;
      _configureLoop();
    }
  }

  void _configureLoop() {
    _rotationTimer?.cancel();
    unawaited(_prepareCurrentMedia());

    if (widget.banners.length <= 1) return;

    _rotationTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || widget.banners.isEmpty) return;

      setState(() {
        _currentBannerIndex = (_currentBannerIndex + 1) % widget.banners.length;
      });

      unawaited(_prepareCurrentMedia());
    });
  }

  Future<void> _prepareCurrentMedia() async {
    _videoController?.dispose();
    _videoController = null;

    final banner = _currentBanner;
    if (banner == null) {
      if (mounted) setState(() {});
      return;
    }

    final mediaType = (banner['media_type'] ?? 'image')
        .toString()
        .toLowerCase();
    final mediaUrl = banner['media_url']?.toString() ?? '';

    if (mediaType != 'video' || mediaUrl.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    final uri = Uri.tryParse(mediaUrl);
    if (uri == null) {
      if (mounted) setState(() {});
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0.0);
      await controller.play();

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _videoController = controller;
      });
    } catch (e) {
      debugPrint('Error loading banner video: $e');
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF181818), Color(0xFF2A2A2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: -30,
            top: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.pinkAccent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -40,
            bottom: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.network(
                  'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/logo.png',
                  height: 34,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.storefront, color: Colors.white70),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.placeholderLabel,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentBanner() {
    final banner = _currentBanner;
    if (banner == null) return _buildPlaceholder();

    final mediaType = (banner['media_type'] ?? 'image')
        .toString()
        .toLowerCase();
    final mediaUrl = banner['media_url']?.toString() ?? '';

    if (mediaType == 'video') {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),
        );
      }

      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.pinkAccent),
        ),
      );
    }

    if (mediaType == 'image' && mediaUrl.isNotEmpty) {
      return Image.network(
        mediaUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: Container(
          key: ValueKey<String>(
            _currentBanner?['id']?.toString() ?? 'placeholder',
          ),
          width: double.infinity,
          color: Colors.black,
          child: _buildCurrentBanner(),
        ),
      ),
    );
  }
}
