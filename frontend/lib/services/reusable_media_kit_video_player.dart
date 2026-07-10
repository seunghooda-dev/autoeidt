import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class ReusableMediaInfo {
  const ReusableMediaInfo({required this.duration, required this.size});

  final Duration duration;
  final Size size;
}

abstract interface class ReusableVideoPlayerPlatform {
  Future<ReusableMediaInfo> replaceActiveSource(
    String resource, {
    Map<String, String> httpHeaders = const {},
    Duration timeout = const Duration(seconds: 12),
  });
}

class ReusableMediaKitVideoPlayer extends VideoPlayerPlatform
    implements ReusableVideoPlayerPlatform {
  final _players = HashMap<int, Player>();
  final _videoControllers = HashMap<int, VideoController>();
  final _eventControllers = HashMap<int, StreamController<VideoEvent>>();
  final _subscriptions = HashMap<int, List<StreamSubscription<dynamic>>>();
  final _initialized = <int>{};

  static void registerWith() {
    VideoPlayerPlatform.instance = ReusableMediaKitVideoPlayer();
  }

  @override
  Future<void> init() async {
    for (final textureId in _players.keys.toList()) {
      await dispose(textureId);
    }
  }

  @override
  Future<void> dispose(int playerId) async {
    final subscriptions = _subscriptions.remove(playerId) ?? const [];
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
    await _eventControllers.remove(playerId)?.close();
    _videoControllers.remove(playerId);
    _initialized.remove(playerId);
    await _players.remove(playerId)?.dispose();
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    final player = Player();
    final videoController = VideoController(player);
    final textureId = player.hashCode;
    final events = StreamController<VideoEvent>();

    _players[textureId] = player;
    _videoControllers[textureId] = videoController;
    _eventControllers[textureId] = events;
    _subscriptions[textureId] = _bindPlayerEvents(textureId, player, events);

    await player.open(
      Media(_resourceFor(dataSource), httpHeaders: dataSource.httpHeaders),
      play: false,
    );
    return textureId;
  }

  @override
  Future<ReusableMediaInfo> replaceActiveSource(
    String resource, {
    Map<String, String> httpHeaders = const {},
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_players.length != 1) {
      throw StateError('Exactly one active video player is required.');
    }
    final player = _players.values.single;
    await player.pause();
    await player.open(Media(resource, httpHeaders: httpHeaders), play: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final deadline = DateTime.now().add(timeout);
    while (true) {
      final duration = player.state.duration;
      final params = player.state.videoParams;
      final width = params.dw ?? 0;
      final height = params.dh ?? 0;
      if (duration > Duration.zero && width > 0 && height > 0) {
        await player.seek(Duration.zero);
        return ReusableMediaInfo(
          duration: duration,
          size: Size(width.toDouble(), height.toDouble()),
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'Reusable media source did not initialize.',
          timeout,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  List<StreamSubscription<dynamic>> _bindPlayerEvents(
    int textureId,
    Player player,
    StreamController<VideoEvent> events,
  ) {
    int? width;
    int? height;
    Duration? duration;

    void emitInitialized() {
      if (_initialized.contains(textureId) ||
          width == null ||
          height == null ||
          duration == null) {
        return;
      }
      _initialized.add(textureId);
      events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          size: Size(width!.toDouble(), height!.toDouble()),
          duration: duration,
        ),
      );
    }

    return [
      player.stream.duration.listen((value) {
        if (value > Duration.zero) {
          duration = value;
          emitInitialized();
        }
      }),
      player.stream.videoParams.listen((value) {
        width = value.dw;
        height = value.dh;
        if ((width ?? 0) > 0 && (height ?? 0) > 0) {
          emitInitialized();
        }
      }),
      player.stream.tracks.listen((value) {
        if (value.video.length == 2 && value.audio.length > 2) {
          width = 0;
          height = 0;
          emitInitialized();
        }
      }),
      player.stream.playing.listen((value) {
        if (!_initialized.contains(textureId)) {
          return;
        }
        events.add(
          VideoEvent(
            eventType: VideoEventType.isPlayingStateUpdate,
            isPlaying: value,
          ),
        );
      }),
      player.stream.completed.listen((value) {
        if (_initialized.contains(textureId) && value) {
          events.add(VideoEvent(eventType: VideoEventType.completed));
        }
      }),
      player.stream.buffering.listen((value) {
        if (!_initialized.contains(textureId)) {
          return;
        }
        events.add(
          VideoEvent(
            eventType: value
                ? VideoEventType.bufferingStart
                : VideoEventType.bufferingEnd,
          ),
        );
      }),
      player.stream.buffer.listen((value) {
        if (!_initialized.contains(textureId)) {
          return;
        }
        events.add(
          VideoEvent(
            eventType: VideoEventType.bufferingUpdate,
            buffered: [DurationRange(Duration.zero, value)],
          ),
        );
      }),
      player.stream.error.listen((value) {
        if (_initialized.contains(textureId)) {
          events.addError(PlatformException(code: 'media_kit', message: value));
        }
      }),
    ];
  }

  String _resourceFor(DataSource dataSource) {
    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        final asset = dataSource.package == null
            ? dataSource.asset
            : 'packages/${dataSource.package}/${dataSource.asset}';
        return 'asset:///$asset';
      case DataSourceType.network:
      case DataSourceType.file:
      case DataSourceType.contentUri:
        final uri = dataSource.uri;
        if (uri == null) {
          throw ArgumentError('uri must not be null');
        }
        return uri;
    }
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final controller = _eventControllers[playerId];
    if (controller == null) {
      throw StateError('Video player $playerId is not available.');
    }
    return controller.stream;
  }

  @override
  Future<void> play(int playerId) async => _players[playerId]?.play();

  @override
  Future<void> pause(int playerId) async => _players[playerId]?.pause();

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      _players[playerId]?.seek(position);

  @override
  Future<Duration> getPosition(int playerId) async =>
      _players[playerId]?.state.position ?? Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      _players[playerId]?.setPlaylistMode(
        looping ? PlaylistMode.single : PlaylistMode.none,
      );

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      _players[playerId]?.setVolume(volume * 100);

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      _players[playerId]?.setRate(speed);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setWebOptions(
    int playerId,
    VideoPlayerWebOptions options,
  ) async {}

  @override
  Widget buildView(int playerId) {
    final controller = _videoControllers[playerId];
    if (controller == null) {
      throw StateError('Video player $playerId is not available.');
    }
    return Video(
      key: ValueKey(controller),
      controller: controller,
      wakelock: false,
      controls: NoVideoControls,
      fill: const Color(0x00000000),
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: false,
    );
  }
}
