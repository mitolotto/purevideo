import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/account_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/filman/filman_dio_factory.dart';
import 'package:purevideo/core/services/secure_storage_service.dart';
import 'package:purevideo/di/injection_container.dart';

class FilmanAuthRepository implements AuthRepository {
  late Dio _dio;
  AccountModel? _account;
  final _authController = StreamController<AuthModel>.broadcast();
  late StreamSubscription<AuthModel> _authSubscription;

  FilmanAuthRepository([AccountModel? account]) {
    _loadSavedAccount();
    _authSubscription = _authController.stream.listen(_onAuthChanged);
  }

  Future<void> _loadSavedAccount() async {
    try {
      final accountJson = await SecureStorageService.getServiceData(
        SupportedService.filman,
        'account',
      );

      if (accountJson != null) {
        _account = AccountModel.fromMap(jsonDecode(accountJson));
        _dio = FilmanDioFactory.getDio(_account);

        try {
          await _dio.get('/');
          _authController.add(
            AuthModel(
              service: SupportedService.filman,
              success: true,
              account: _account,
            ),
          );
        } catch (e) {
          await SecureStorageService.deleteServiceData(
            SupportedService.filman,
            'account',
          );
          _account = null;
          _dio = FilmanDioFactory.getDio(null);
        }
      } else {
        _dio = FilmanDioFactory.getDio(null);
      }
    } catch (e) {
      debugPrint('Błąd podczas ładowania konta Filman.cc: $e');
      _dio = FilmanDioFactory.getDio(null);
    }
  }

  void _onAuthChanged(AuthModel auth) {
    if (auth.service == SupportedService.filman) {
      _dio = FilmanDioFactory.getDio(auth.account);
    }
  }

  @override
  Stream<AuthModel> get authStream => _authController.stream;

  /// JavaScript injected into the Filman login WebView.
  ///
  /// Logic, in order:
  ///   1. If we already left `/logowanie` (login succeeded — filman
  ///      redirects authenticated users to `/`), hand the session
  ///      cookies back to Dart and we're done.
  ///   2. Otherwise wait for the `#signin-form` element, fill it,
  ///      submit it EXACTLY ONCE (using a `window.__pvFilmanState`
  ///      guard that survives re-injection on navigation).
  ///   3. After submit has been clicked, and only then, start
  ///      watching for a `.alert-danger` banner — that's how filman
  ///      reports CSRF/credentials/captcha problems. Watching for
  ///      it BEFORE submit was the bug that kept firing
  ///      "Nieprawidłowy token bezpieczeństwa" on devices where a
  ///      stale flash message from an earlier attempt was already
  ///      in the DOM on first page load.
  ///   4. Hard 20s timeout so we never hang the dialog forever if
  ///      filman silently redirects somewhere unexpected or the
  ///      network drops between submit and next navigation.
  ///
  /// The script is idempotent. `onLoadStop` fires a second time
  /// after the login POST redirect, which re-injects this script;
  /// `__pvFilmanState` makes the second pass a no-op (or picks up
  /// the error/success path as appropriate) instead of re-filling
  /// and re-submitting the form, which would either resubmit stale
  /// credentials or race a fresh CSRF token.
  String _getFilmanLoginScript(String login, String password,
      {String? captcha}) {
    final captchaLine = captcha != null
        ? "var rc = document.getElementById('g-recaptcha-response'); if (rc) { rc.value = '$captcha'; }"
        : "";
    return '''
      (function() {
        // Shared state across (re-)injections of this script.
        // Backed by sessionStorage so it survives the full page
        // navigation after submit (filman redirects to '/' on
        // success and back to '/logowanie' on failure — both are
        // separate document loads that re-inject this script from
        // scratch, so plain `window.__pvFilmanState` would reset).
        function getState() {
          try {
            var raw = sessionStorage.getItem('__pvFilmanState');
            return raw ? JSON.parse(raw) : { submitted: false, reported: false };
          } catch (e) {
            return { submitted: false, reported: false };
          }
        }
        function setState(s) {
          try { sessionStorage.setItem('__pvFilmanState', JSON.stringify(s)); } catch (e) {}
        }
        var state = getState();
        var timeoutId = null;

        function report(payload) {
          if (state.reported) return;
          state.reported = true;
          setState(state);
          if (timeoutId) { clearTimeout(timeoutId); timeoutId = null; }
          window.flutter_inappwebview.callHandler('messageHandler', JSON.stringify(payload));
        }

        function waitForElement(selector, callback, stopFlag) {
          var check = function() {
            if (stopFlag && stopFlag()) return;       // cancel when no longer needed
            if (state.reported) return;               // something already resolved
            var el = document.querySelector(selector);
            if (el) { callback(el); return; }
            setTimeout(check, 100);
          };
          check();
        }

        // Case 1: already redirected away from /logowanie -> login succeeded.
        // Note: filman redirects to '/' on success, not to a subpath of /logowanie.
        if (!window.location.pathname.startsWith('/logowanie')) {
          report({ success: true, cookies: document.cookie });
          return;
        }

        // Global timeout so the dialog cannot hang forever.
        timeoutId = setTimeout(function() {
          report({ success: false, error: 'Przekroczono czas oczekiwania na odpowiedź filman.cc.' });
        }, 20000);

        // If we arrived back on /logowanie AFTER clicking submit,
        // look for the error banner. Only then — before that, any
        // .alert-danger on the page is a stale flash from an
        // earlier session and must be ignored.
        if (state.submitted) {
          waitForElement('.alert-danger',
            function(el) { report({ success: false, error: el.textContent.trim() }); },
            function() { return state.reported; });
          return;
        }

        // First pass on /logowanie: fill the form and click submit.
        // Extra sanity check: Cloudflare's "Just a moment..." challenge
        // pages can carry their own form-like markup. Require both the
        // form AND a submit button named "submit" before we consider
        // ourselves on the real login page.
        waitForElement('#signin-form button[name=submit]',
          function(btn) {
            if (state.submitted) return;
            var form = document.querySelector('#signin-form');
            if (!form || !form.login || !form.password) return;  // still not the real form
            state.submitted = true;
            setState(state);
            try {
              form.login.value = '$login';
              form.password.value = '$password';
              $captchaLine
              btn.click();
            } catch (e) {
              report({ success: false, error: 'Nie udało się wypełnić formularza: ' + e });
            }
          },
          function() { return state.reported || state.submitted; });
      })();
    ''';
  }

  @override
  Future<AuthModel> signIn(
    Map<String, String> fields,
  ) async {
    try {
      final webviewLogin = await getIt<WebViewService>().executeJavaScript(
          '${SupportedService.filman.baseUrl}/logowanie',
          _getFilmanLoginScript(fields['login']!, fields['password']!,
              captcha: fields['g-recaptcha-response']));

      try {
        final json = jsonDecode(webviewLogin!);
        if (json['success'] == true && json['cookies'] != null) {
          final cookieList = (json['cookies'] as String).split(';');

          final cookies = cookieList
              .map((header) => Cookie.fromSetCookieValue(header))
              .toList();

          _account = AccountModel(
            fields: fields,
            cookies: cookies,
            service: SupportedService.filman,
          );

          final authModel = AuthModel(
            service: SupportedService.filman,
            success: true,
            account: _account,
          );
          _authController.add(authModel);
          return authModel;
        } else {
          final authModel = AuthModel(
            service: SupportedService.filman,
            success: false,
            error: [json['error'] ?? 'Nieznany błąd logowania $webviewLogin'],
          );
          _authController.add(authModel);
          return authModel;
        }
      } catch (e) {
        debugPrint('Błąd parsowania odpowiedzi logowania: $e');

        final authModel = AuthModel(
          service: SupportedService.filman,
          success: false,
          error: ['Błąd parsowania odpowiedzi logowania: $e'],
        );
        _authController.add(authModel);
        return authModel;
      }
    } catch (e) {
      final authModel = AuthModel(
        service: SupportedService.filman,
        success: false,
        error: ['Błąd logowania: $e'],
      );
      _authController.add(authModel);
      return authModel;
    }
  }

  @override
  AccountModel? getAccount() {
    return _account;
  }

  @override
  Future<void> setAccount(AccountModel account) async {
    _account = account;
    _dio = FilmanDioFactory.getDio(_account);

    await SecureStorageService.saveServiceData(
      SupportedService.filman,
      'account',
      jsonEncode(account.toMap()),
    );

    _authController.add(
      AuthModel(
        service: SupportedService.filman,
        success: true,
        account: _account,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _account = null;
    _dio = FilmanDioFactory.getDio(null);
    _authController.add(
      AuthModel(
        service: SupportedService.filman,
        success: false,
        account: null,
      ),
    );
    await SecureStorageService.deleteServiceData(
      SupportedService.filman,
      'account',
    );
  }

  void dispose() {
    _authSubscription.cancel();
    _authController.close();
  }
}
