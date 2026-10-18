import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Local HTTP audio streaming proxy that bridges media_kit (libmpv) with YouTube CDN.
///
/// Bundled libmpv on Android uses Mbed TLS, which lacks TLS 1.3 client support.
/// Because Google Video CDN enforces TLS 1.3 in most regions, direct HTTPS
/// connections from libmpv fail ("Failed to open https://...googlevideo.com/...").
///
/// This proxy runs locally on loopback (127.0.0.1). Dart's native HttpClient
/// (backed by Android's BoringSSL) handles the upstream TLS 1.3 connection to
/// YouTube CDN with full fidelity, forwarding Range headers and streaming audio
/// chunks to media_kit over plain local HTTP.
class StreamProxyService {
  static final StreamProxyService instance = StreamProxyService._internal();

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/125.0.0.0 Safari/537.36';

  HttpServer? _server;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 60)
    ..maxConnectionsPerHost = 10
    ..badCertificateCallback = ((cert, host, port) => true);

  final Map<String, Uri> _targetMap = {};
  Completer<void>? _startCompleter;

  /// Optional callback invoked when upstream returns 403 or 410 to auto-refresh the stream URL.
  Future<Uri?> Function(String trackId)? onStreamExpired;

  StreamProxyService._internal();

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  /// Ensures the local proxy HTTP server is started and listening on loopback.
  Future<void> ensureStarted() async {
    if (_server != null) return;
    if (_startCompleter != null) return _startCompleter!.future;

    _startCompleter = Completer<void>();
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      debugPrint('StreamProxyService: listening on http://127.0.0.1:$port');
      _server!.listen(_handleRequest, onError: (err) {
        debugPrint('StreamProxyService server error: $err');
      });
      _startCompleter!.complete();
    } catch (e, st) {
      debugPrint('StreamProxyService failed to start: $e\n$st');
      _startCompleter!.completeError(e, st);
      _startCompleter = null;
      rethrow;
    }
  }

  /// Registers an upstream audio stream URL and returns a local proxy URI.
  Uri getProxyUri(String trackId, Uri upstreamUrl, {String? ext}) {
    _targetMap[trackId] = upstreamUrl;
    final fileExt = (ext != null && ext.isNotEmpty) ? '.$ext' : '';
    return Uri.parse('http://127.0.0.1:$port/stream/$trackId$fileExt');
  }

  /// Performs an upstream request while manually handling redirects so that Range,
  /// User-Agent, and Referer headers are never stripped by Dart's HttpClient.
  Future<HttpClientResponse> _openUpstream({
    required String method,
    required Uri initialUri,
    required Map<String, List<String>> incomingHeaders,
    int maxRedirects = 5,
  }) async {
    Uri currentUri = initialUri;
    int redirects = 0;

    while (true) {
      final req = await _client.openUrl(method, currentUri);
      req.followRedirects = false;

      // Forward client Range request headers so seeking and buffering work seamlessly.
      incomingHeaders.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'range' || lower == 'if-range') {
          for (final v in values) {
            req.headers.add(name, v);
          }
        }
      });

      // Browser/YouTube headers required to avoid 403 CDN rejections
      req.headers.set(HttpHeaders.userAgentHeader, _defaultUserAgent);
      req.headers.set(HttpHeaders.refererHeader, 'https://www.youtube.com/');
      req.headers.set('Origin', 'https://www.youtube.com');

      final res = await req.close();
      if (res.isRedirect && redirects < maxRedirects) {
        final location = res.headers.value(HttpHeaders.locationHeader);
        if (location != null && location.isNotEmpty) {
          currentUri = currentUri.resolve(location);
          redirects++;
          await res.drain();
          continue;
        }
      }
      return res;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final pathSegments = request.uri.pathSegments;
    if (pathSegments.length < 2 || pathSegments[0] != 'stream') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final rawToken = pathSegments[1];
    final trackId = rawToken.contains('.')
        ? rawToken.substring(0, rawToken.lastIndexOf('.'))
        : rawToken;

    var upstreamUrl = _targetMap[trackId];
    if (upstreamUrl == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final incomingHeaders = <String, List<String>>{};
    request.headers.forEach((name, values) {
      incomingHeaders[name] = List<String>.from(values);
    });

    final isHead = request.method == 'HEAD';
    final upstreamMethod = isHead ? 'HEAD' : request.method;

    try {
      var upstreamRes = await _openUpstream(
        method: upstreamMethod,
        initialUri: upstreamUrl,
        incomingHeaders: incomingHeaders,
      );

      // If upstream rejects with 403/410, attempt auto-refresh via callback
      if ((upstreamRes.statusCode == 403 || upstreamRes.statusCode == 410) &&
          onStreamExpired != null) {
        debugPrint(
            'StreamProxyService: upstream returned ${upstreamRes.statusCode} for $trackId; requesting fresh stream...');
        await upstreamRes.drain();
        final freshUri = await onStreamExpired!(trackId);
        if (freshUri != null) {
          _targetMap[trackId] = freshUri;
          upstreamUrl = freshUri;
          upstreamRes = await _openUpstream(
            method: upstreamMethod,
            initialUri: freshUri,
            incomingHeaders: incomingHeaders,
          );
        }
      }

      if (upstreamRes.statusCode >= 400) {
        debugPrint(
            'StreamProxyService: upstream final status ${upstreamRes.statusCode} for $trackId');
      }

      request.response.statusCode = upstreamRes.statusCode;
      request.response.bufferOutput = false;

      // Forward crucial playback headers
      upstreamRes.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'content-type' ||
            lower == 'content-length' ||
            lower == 'content-range' ||
            lower == 'accept-ranges') {
          for (final v in values) {
            request.response.headers.add(name, v);
          }
        }
      });

      // HEAD requests must NOT write response body in Dart (throws StateError)
      if (!isHead) {
        await request.response.addStream(upstreamRes);
      }
      await request.response.close();
    } catch (e) {
      // Client disconnects (e.g. seek or next track skip) are normal.
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Shuts down the proxy server and frees resources.
  Future<void> dispose() async {
    _targetMap.clear();
    await _server?.close(force: true);
    _server = null;
    _startCompleter = null;
    _client.close(force: true);
  }
}
