import 'package:flutter_test/flutter_test.dart';
import 'package:finaudio/services/lyrics_service.dart';

void main() {
  group('LyricsRomanizer Tests', () {
    test('detects foreign scripts accurately', () {
      expect(LyricsRomanizer.hasForeign('Hello World'), isFalse);
      expect(LyricsRomanizer.hasForeign('Just two lovers'), isFalse);
      expect(LyricsRomanizer.hasForeign('안녕하세요'), isTrue);
      expect(LyricsRomanizer.hasForeign('ありがとう'), isTrue);
      expect(LyricsRomanizer.hasForeign('アイシテル'), isTrue);
      expect(LyricsRomanizer.hasForeign('Привет мир'), isTrue);
    });

    test('romanizes Korean Hangul to Revised Romanization', () {
      final romanized = LyricsRomanizer.romanize('안녕하세요 사랑해요');
      expect(romanized.toLowerCase(), contains('annyeonghaseyo'));
      expect(romanized.toLowerCase(), contains('saranghaeyo'));
    });

    test('romanizes Japanese Hiragana and Katakana to Hepburn Romaji', () {
      final romanized = LyricsRomanizer.romanize('ありがとう さようなら');
      expect(romanized.toLowerCase(), contains('arigatou'));
      expect(romanized.toLowerCase(), contains('sayounara'));

      final katakana = LyricsRomanizer.romanize('アイシテル');
      expect(katakana.toLowerCase(), contains('aishiteru'));
    });

    test('romanizes Cyrillic script to Latin', () {
      final romanized = LyricsRomanizer.romanize('Привет мир');
      expect(romanized.toLowerCase(), contains('privet'));
    });

    test('romanizes Hindi Devanagari to Latin', () {
      expect(LyricsRomanizer.hasForeign('तुम ही हो'), isTrue);
      final romanized = LyricsRomanizer.romanize('तुम ही हो');
      expect(romanized.toLowerCase(), contains('tum'));
      expect(romanized.toLowerCase(), contains('hee'));
      expect(romanized.toLowerCase(), contains('ho'));
    });

    test('romanizes Chinese characters to Pinyin', () {
      expect(LyricsRomanizer.hasForeign('我爱你'), isTrue);
      final romanized = LyricsRomanizer.romanize('我爱你');
      expect(romanized.toLowerCase(), contains('wo'));
      expect(romanized.toLowerCase(), contains('ai'));
      expect(romanized.toLowerCase(), contains('ni'));
    });

    test('romanizes Japanese Kanji compounds to Romaji', () {
      expect(LyricsRomanizer.hasForeign('不埒なリズム刻んでよ'), isTrue);
      final romanized = LyricsRomanizer.romanize('不埒なリズム刻んでよ');
      expect(romanized.toLowerCase(), contains('furachi'));
      expect(romanized.toLowerCase(), contains('kizan'));

      final romanized2 = LyricsRomanizer.romanize('ゆらり文字も踊り出す');
      expect(romanized2.toLowerCase(), contains('moji'));
      expect(romanized2.toLowerCase(), contains('odori'));

      final romanized3 = LyricsRomanizer.romanize('駅から');
      expect(romanized3.toLowerCase(), contains('eki'));
    });

    test('LyricLine supports romanizedText and translationText', () {
      const line = LyricLine(
        timestamp: Duration(seconds: 14),
        text: 'ゆらり文字も踊り出す',
        romanizedText: 'Yurari moji mo odori dasu',
        translationText: 'From the station where loose letters start to dance',
      );
      expect(line.romanizedText, 'Yurari moji mo odori dasu');
      expect(line.translationText, contains('letters start to dance'));
    });
  });
}

