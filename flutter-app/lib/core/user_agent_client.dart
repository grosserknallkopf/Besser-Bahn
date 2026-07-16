import 'package:http/http.dart' as http;

/// Wraps a [http.Client] so **every** request it sends carries an identifying
/// `User-Agent`.
///
/// This exists as a client wrapper rather than a header added per call site on
/// purpose: Träwelling rejects unidentified clients with HTTP 403 ("No
/// identifiable User-Agent provided"), and a per-call-site header is only ever
/// as good as the next person remembering it. Wrapping the client makes the
/// header structural — a route added later cannot forget it (#34).
///
/// Note that Dart does not leave the header empty when unset: `dart:io` fills
/// in `Dart/<version> (dart:io)`, which Träwelling blocks just like a missing
/// one. So the header must be actively set, not merely "not omitted".
class UserAgentClient extends http.BaseClient {
  UserAgentClient(this._inner, this._userAgent);

  final http.Client _inner;
  final String _userAgent;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // `BaseRequest.headers` compares keys case-insensitively, so this respects
    // an explicit per-request override in any casing.
    request.headers.putIfAbsent('user-agent', () => _userAgent);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
