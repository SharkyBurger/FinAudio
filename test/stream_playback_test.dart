// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:finaudio/services/youtube_service.dart';

void main() {
  test('Test YoutubeService audio resolution and media_kit direct playback', () async {
    MediaKit.ensureInitialized(
      libmpv: r'C:\Users\Ethan John\Documents\backupfinaudio\finaudio\build\windows\x64\runner\Debug\libmpv-2.dll',
    );
    final player = Player(
      configuration: const PlayerConfiguration(
        logLevel: MPVLogLevel.error,
      ),
    );

    final errors = <String>[];
    player.stream.error.listen((error) {
      print('TEST MediaKit error: $error');
      errors.add(error);
    });

    Duration currentPos = Duration.zero;
    player.stream.position.listen((pos) {
      currentPos = pos;
    });

    final ytService = YoutubeService();
    const testId = 'BoJ0pfhMmfU';
    
    print('Resolving audio stream for $testId via YoutubeService...');
    final resolved = await ytService.resolveAudioStream(testId);
    print('Resolved video: ${resolved.title}');
    print('Audio stream URL: ${resolved.audioStreamUrl}');
    print('Container: ${resolved.container}');

    expect(resolved.audioStreamUrl.toString(), isNotEmpty);
    expect(resolved.audioStreamUrl.scheme, equals('https'));

    print('Opening resolved audio stream in media_kit...');
    await player.open(
      Media(
        resolved.audioStreamUrl.toString(),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
          'Referer': 'https://www.youtube.com/',
        },
      ),
      play: true,
    );

    // Wait up to 6 seconds for playback to begin
    for (int i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (currentPos > Duration.zero) break;
    }

    print('Player state: playing=${player.state.playing}, pos=$currentPos, duration=${player.state.duration}');
    print('Errors encountered: $errors');

    expect(errors, isEmpty);
    expect(currentPos > Duration.zero || player.state.duration > Duration.zero, isTrue);

    await player.dispose();
    ytService.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
