import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'antigravity_helper.dart';

/// Raised for any user-actionable failure in the Antigravity login flow.
class AntigravityOAuthException implements Exception {
  AntigravityOAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A prepared login attempt: the URL to open plus the PKCE secrets needed to
/// exchange the resulting authorization code.
class AntigravityOAuthSession {
  const AntigravityOAuthSession({
    required this.authUrl,
    required this.state,
    required this.codeVerifier,
    required this.codeChallenge,
    required this.redirectUri,
  });

  final String authUrl;
  final String state;
  final String codeVerifier;
  final String codeChallenge;
  final String redirectUri;
}

/// Tokens + profile obtained after a successful Google sign-in.
class AntigravityOAuthResult {
  const AntigravityOAuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.email,
    this.projectId,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String? email;
  final String? projectId;

  AntigravityCredentials toCredentials() => AntigravityCredentials(
        accessToken: accessToken,
        refreshToken: refreshToken,
        clientId: AntigravityOAuthConfig.clientId,
        clientSecret: AntigravityOAuthConfig.clientSecret,
        expiresAt: expiresAt,
        projectId: projectId,
        email: email,
      );

  /// JSON blob stored in the provider's secure key slot.
  String toCredentialsJson() => toCredentials().toJsonString();
}

/// Google OAuth (PKCE) login for Antigravity.
///
/// Mirrors the flow used by the Antigravity CLI and open-source bridges:
///  1. open the consent page in the browser with a loopback redirect,
///  2. run a tiny HTTP server on `localhost:51121` that captures the code,
///  3. exchange code + PKCE verifier for access/refresh tokens.
///
/// The code is also rendered on the callback page so it can be copied and
/// pasted manually if the browser cannot reach the in-app listener.
class AntigravityOAuthService {
  AntigravityOAuthService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 25),
              receiveTimeout: const Duration(seconds: 45),
            ));

  final Dio _dio;
  final List<HttpServer> _servers = [];
  final StreamController<String> _codeController =
      StreamController<String>.broadcast();

  String? _lastCode;

  /// Codes captured by the localhost callback, in arrival order.
  Stream<String> get onCode => _codeController.stream;

  /// The most recent code captured on localhost, if any.
  String? get capturedCode => _lastCode;

  /// Whether the loopback listener is currently running.
  bool get isListening => _servers.isNotEmpty;

  /// Starts the loopback listener and returns the consent URL to open.
  Future<AntigravityOAuthSession> start() async {
    if (_servers.isNotEmpty) {
      throw AntigravityOAuthException('A login attempt is already running.');
    }

    final verifier = newCodeVerifier();
    final challenge = codeChallengeFor(verifier);
    final state = _randomUrlSafe(24);

    await _bind();

    return AntigravityOAuthSession(
      authUrl: buildAuthorizationUrl(
        codeChallenge: challenge,
        state: state,
      ),
      state: state,
      codeVerifier: verifier,
      codeChallenge: challenge,
      redirectUri: AntigravityOAuthConfig.redirectUri,
    );
  }

  /// Builds the Google consent URL. Exposed for tests.
  static String buildAuthorizationUrl({
    required String codeChallenge,
    required String state,
  }) {
    final uri = Uri.parse(AntigravityOAuthConfig.authorizeEndpoint);
    return uri.replace(queryParameters: {
      'client_id': AntigravityOAuthConfig.clientId,
      'response_type': 'code',
      'redirect_uri': AntigravityOAuthConfig.redirectUri,
      'scope': AntigravityOAuthConfig.scopes.join(' '),
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent',
      'include_granted_scopes': 'true',
    }).toString();
  }

  /// Accepts either a bare authorization code, a `code=...` fragment, or the
  /// full `http://localhost:51121/oauth-callback?code=...` URL.
  static String extractAuthorizationCode(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';

    if (text.contains('://')) {
      final uri = Uri.tryParse(text);
      final fromQuery = uri?.queryParameters['code'];
      if (fromQuery != null && fromQuery.trim().isNotEmpty) {
        return fromQuery.trim();
      }
    }

    final marker = text.indexOf('code=');
    if (marker >= 0) {
      text = text.substring(marker + 5);
      final amp = text.indexOf('&');
      if (amp >= 0) text = text.substring(0, amp);
    }

    try {
      text = Uri.decodeComponent(text);
    } catch (_) {
      // Already decoded (or contains a stray '%'); keep as-is.
    }
    return text.trim();
  }

  /// Exchanges an authorization code for tokens, then resolves the profile
  /// email and Cloud AI Companion project id.
  Future<AntigravityOAuthResult> exchangeCode({
    required String codeInput,
    required String codeVerifier,
  }) async {
    final code = extractAuthorizationCode(codeInput);
    if (code.isEmpty) {
      throw AntigravityOAuthException('The authorization code is empty.');
    }

    final Response<Map<String, dynamic>> tokenResponse;
    try {
      tokenResponse = await _dio.post<Map<String, dynamic>>(
        AntigravityOAuthConfig.tokenEndpoint,
        data: {
          'client_id': AntigravityOAuthConfig.clientId,
          'client_secret': AntigravityOAuthConfig.clientSecret,
          'code': code,
          'grant_type': 'authorization_code',
          'redirect_uri': AntigravityOAuthConfig.redirectUri,
          'code_verifier': codeVerifier,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      throw AntigravityOAuthException(_describeTokenError(e));
    }

    final payload = tokenResponse.data;
    final accessToken = payload?['access_token']?.toString();
    final refreshToken = payload?['refresh_token']?.toString();
    final expiresIn = (payload?['expires_in'] as num?)?.toInt() ?? 3600;

    if (accessToken == null || accessToken.isEmpty) {
      throw AntigravityOAuthException(
        'Google did not return an access token. Try signing in again.',
      );
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      throw AntigravityOAuthException(
        'Google did not return a refresh token. Remove Vina Agent from '
        'https://myaccount.google.com/permissions and sign in again.',
      );
    }

    final email = await _fetchEmail(accessToken);
    final projectId = await _fetchProjectId(accessToken);

    return AntigravityOAuthResult(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      email: email,
      projectId: projectId,
    );
  }

  Future<String?> _fetchEmail(String accessToken) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${AntigravityOAuthConfig.userInfoEndpoint}?alt=json',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final email = response.data?['email']?.toString();
      return (email != null && email.isNotEmpty) ? email : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchProjectId(String accessToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${AntigravityHelper.defaultEndpoint}/v1internal:loadCodeAssist',
        data: jsonEncode({
          'metadata': {
            'ideType': 'ANTIGRAVITY',
            'platform': 'PLATFORM_UNSPECIFIED',
            'pluginType': 'GEMINI',
          },
        }),
        options: Options(headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'User-Agent': AntigravityHelper.userAgent,
          'X-Goog-Api-Client': AntigravityHelper.googApiClient,
        }),
      );
      final data = response.data;
      if (data == null) return null;
      return AntigravityHelper.extractProjectId(data);
    } catch (_) {
      return null;
    }
  }

  String _describeTokenError(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final code = data['error']?.toString();
      final description = data['error_description']?.toString();
      if (code != null || description != null) {
        return 'Google rejected the login'
            '${code != null ? ' ($code)' : ''}'
            '${description != null ? ': $description' : ''}.';
      }
    }
    return 'Could not reach Google to exchange the code: ${error.message ?? error.type.name}';
  }

  Future<void> _bind() async {
    Object? lastError;

    // IPv4 loopback is the primary listener; the IPv6 loopback is added so
    // `localhost` works regardless of which family the browser resolves.
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        AntigravityOAuthConfig.port,
      );
      _attach(server);
    } catch (e) {
      lastError = e;
    }

    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv6,
        AntigravityOAuthConfig.port,
        v6Only: true,
      );
      _attach(server);
    } catch (e) {
      lastError ??= e;
    }

    if (_servers.isEmpty) {
      throw AntigravityOAuthException(
        'Could not start the localhost login listener on port '
        '${AntigravityOAuthConfig.port}. Another app may be using it. '
        'Details: $lastError',
      );
    }
  }

  void _attach(HttpServer server) {
    _servers.add(server);
    server.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.uri.path == AntigravityOAuthConfig.callbackPath) {
        final error = request.uri.queryParameters['error'];
        final code = request.uri.queryParameters['code'];

        if (code != null && code.trim().isNotEmpty) {
          _lastCode = code.trim();
          if (!_codeController.isClosed) _codeController.add(_lastCode!);
          response.headers.contentType = ContentType.html;
          response.write(_successPage(_lastCode!));
        } else {
          response.headers.contentType = ContentType.html;
          response.write(_errorPage(error ?? 'No authorization code returned.'));
        }
      } else {
        response.headers.contentType = ContentType.html;
        response.write(_waitingPage());
      }
    } catch (_) {
      response.statusCode = HttpStatus.internalServerError;
      response.write('Internal error');
    } finally {
      await response.close();
    }
  }

  /// Stops the listener and releases the stream.
  Future<void> dispose() async {
    for (final server in _servers) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
    _servers.clear();
    if (!_codeController.isClosed) {
      await _codeController.close();
    }
  }

  /// Generates a PKCE code verifier (86 URL-safe characters).
  static String newCodeVerifier() => _randomUrlSafe(64);

  /// Computes the S256 PKCE challenge for [verifier].
  static String codeChallengeFor(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static String _randomUrlSafe(int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _shell({required String title, required String body}) => '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>
  :root { color-scheme: dark; }
  body {
    margin: 0; min-height: 100vh; display: flex; align-items: center;
    justify-content: center; background: #0b0b12; color: #ececf5;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  }
  .card {
    width: min(92vw, 560px); padding: 28px; border-radius: 18px;
    background: #16161f; border: 1px solid #2a2a3a;
  }
  h1 { font-size: 19px; margin: 0 0 10px; }
  p { color: #a8a8bd; font-size: 14px; line-height: 1.55; margin: 0 0 14px; }
  code {
    display: block; padding: 14px; border-radius: 12px; background: #0b0b12;
    border: 1px solid #2a2a3a; font-size: 13px; word-break: break-all;
    color: #b9a7ff; user-select: all;
  }
  button {
    margin-top: 12px; padding: 10px 16px; border-radius: 10px; border: 0;
    background: #7c5cff; color: white; font-size: 14px; font-weight: 600;
  }
  .ok { color: #6ee7b7; }
  .bad { color: #fca5a5; }
</style>
</head>
<body>
  <div class="card">
    $body
  </div>
</body>
</html>
''';

  String _successPage(String code) {
    final safe = const HtmlEscape().convert(code);
    return _shell(
      title: 'Vina Agent — Login complete',
      body: '''
<h1 class="ok">Login complete</h1>
<p>Vina Agent captured this authorization code automatically. You can close
this tab and return to the app.</p>
<p>If the app is still waiting, copy the code below and paste it into the
login dialog:</p>
<code id="code">$safe</code>
<button onclick="navigator.clipboard.writeText(document.getElementById('code').textContent)">Copy code</button>
''',
    );
  }

  String _errorPage(String error) {
    final safe = const HtmlEscape().convert(error);
    return _shell(
      title: 'Vina Agent — Login failed',
      body: '''
<h1 class="bad">Login failed</h1>
<p>Google returned an error instead of an authorization code.</p>
<code>$safe</code>
<p>Return to Vina Agent and try signing in again.</p>
''',
    );
  }

  String _waitingPage() => _shell(
        title: 'Vina Agent — Waiting for Google',
        body: '''
<h1>Waiting for Google sign-in</h1>
<p>This page only handles the OAuth callback. Start the login from Vina Agent
and complete the consent screen in your browser.</p>
''',
      );
}

