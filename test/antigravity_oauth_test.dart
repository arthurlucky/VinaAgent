import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketstrike/features/providers/data/antigravity_helper.dart';
import 'package:pocketstrike/features/providers/data/antigravity_oauth.dart';

void main() {
  group('Antigravity OAuth authorization URL', () {
    test('contains PKCE, offline access and the loopback redirect', () {
      const challenge = 'abc123challenge';
      const state = 'state-xyz';

      final uri = Uri.parse(
        AntigravityOAuthService.buildAuthorizationUrl(
          codeChallenge: challenge,
          state: state,
        ),
      );

      expect(uri.host, 'accounts.google.com');
      expect(uri.path, '/o/oauth2/v2/auth');
      expect(uri.queryParameters['client_id'], AntigravityOAuthConfig.clientId);
      expect(uri.queryParameters['response_type'], 'code');
      expect(
        uri.queryParameters['redirect_uri'],
        AntigravityOAuthConfig.redirectUri,
      );
      expect(uri.queryParameters['code_challenge'], challenge);
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(uri.queryParameters['state'], state);
      expect(uri.queryParameters['access_type'], 'offline');
      expect(uri.queryParameters['prompt'], 'consent');
      expect(
        uri.queryParameters['scope'],
        contains('https://www.googleapis.com/auth/cloud-platform'),
      );
    });

    test('loopback redirect points at localhost:51121', () {
      expect(
        AntigravityOAuthConfig.redirectUri,
        'http://localhost:51121/oauth-callback',
      );
    });
  });

  group('PKCE helpers', () {
    test('verifier is URL-safe and long enough', () {
      final verifier = AntigravityOAuthService.newCodeVerifier();
      expect(verifier.length, 86);
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(verifier), isTrue);
      expect(verifier.contains('='), isFalse);
    });

    test('challenge matches the RFC 7636 test vector', () {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      expect(
        AntigravityOAuthService.codeChallengeFor(verifier),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('challenge is deterministic and differs from the verifier', () {
      final verifier = AntigravityOAuthService.newCodeVerifier();
      final first = AntigravityOAuthService.codeChallengeFor(verifier);
      final second = AntigravityOAuthService.codeChallengeFor(verifier);
      expect(first, second);
      expect(first, isNot(verifier));
      expect(first.length, 43);
    });
  });

  group('Authorization code extraction', () {
    test('accepts a bare code', () {
      expect(
        AntigravityOAuthService.extractAuthorizationCode(' 4/0AX4XfWh  '),
        '4/0AX4XfWh',
      );
    });

    test('decodes a URL-encoded code', () {
      expect(
        AntigravityOAuthService.extractAuthorizationCode('4%2F0AX4XfWh'),
        '4/0AX4XfWh',
      );
    });

    test('accepts a code= fragment', () {
      expect(
        AntigravityOAuthService.extractAuthorizationCode(
          'code=4/0AX4XfWh&state=abc',
        ),
        '4/0AX4XfWh',
      );
    });

    test('accepts the full localhost callback URL', () {
      expect(
        AntigravityOAuthService.extractAuthorizationCode(
          'http://localhost:51121/oauth-callback?state=abc&code=4%2F0AX4XfWh',
        ),
        '4/0AX4XfWh',
      );
    });

    test('returns empty for blank input', () {
      expect(AntigravityOAuthService.extractAuthorizationCode('   '), '');
    });
  });

  group('AntigravityOAuthResult credentials', () {
    test('serializes a JSON blob that parses back', () {
      final result = AntigravityOAuthResult(
        accessToken: 'ya29.access',
        refreshToken: '1//refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        email: 'user@example.com',
        projectId: 'cloudaicompanion-123',
      );

      final json = result.toCredentialsJson();
      final map = jsonDecode(json) as Map<String, dynamic>;

      expect(map['access_token'], 'ya29.access');
      expect(map['refresh_token'], '1//refresh');
      expect(map['client_id'], AntigravityOAuthConfig.clientId);
      expect(map['client_secret'], AntigravityOAuthConfig.clientSecret);
      expect(map['email'], 'user@example.com');
      expect(map['project_id'], 'cloudaicompanion-123');
      expect(map['token_type'], 'Bearer');

      final parsed = AntigravityCredentials.parse(json);
      expect(parsed.accessToken, 'ya29.access');
      expect(parsed.refreshToken, '1//refresh');
      expect(parsed.email, 'user@example.com');
      expect(parsed.projectId, 'cloudaicompanion-123');
      expect(parsed.canRefresh, isTrue);
      expect(parsed.isExpired, isFalse);
    });

    test('falls back to the built-in OAuth client when none is stored', () {
      final creds = AntigravityCredentials.parse('ya29.raw');
      expect(creds.effectiveClientId, AntigravityOAuthConfig.clientId);
      expect(creds.effectiveClientSecret, AntigravityOAuthConfig.clientSecret);
      expect(creds.canRefresh, isFalse);
    });

    test('refresh-only credentials can renew themselves', () {
      final creds = AntigravityCredentials.parse(
        jsonEncode({'refresh_token': '1//refresh'}),
      );
      expect(creds.accessToken, isNotEmpty);
      expect(creds.canRefresh, isTrue);
      expect(creds.effectiveClientId, AntigravityOAuthConfig.clientId);
    });
  });

  group('AntigravityHelper.extractProjectId', () {
    test('reads a plain string project id', () {
      expect(
        AntigravityHelper.extractProjectId({
          'cloudaicompanionProject': 'project-1',
        }),
        'project-1',
      );
    });

    test('reads a nested object project id', () {
      expect(
        AntigravityHelper.extractProjectId({
          'cloudaicompanionProject': {'id': 'project-2'},
        }),
        'project-2',
      );
    });

    test('returns null when absent', () {
      expect(AntigravityHelper.extractProjectId({}), isNull);
    });
  });
}
