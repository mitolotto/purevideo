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
  ///   2. Otherwise wait for `#signin-form`, pre-fill the login and
  ///      password inputs — but DO NOT click submit. Filman renders
  ///      an in-form checkbox captcha ("nie jestem robotem") that
  ///      the user has to tick with the TV remote; submitting before
  ///      the captcha response is present makes the server reject
  ///      the POST with "Nieprawidłowy token bezpieczeństwa".
  ///      So we hand the form back to the user and wait for *their*
  ///      click on the submit button.
  ///   3. Hook into the form's submit event. The first submit flips
  ///      `state.submitted` and from that point on we (a) let the
  ///      request actually go to the server and (b) start watching
  ///      for `.alert-danger` on the post-redirect page — that's
  ///      filman's error channel for CSRF/credentials/captcha
  ///      rejections. Watching for .alert-danger *before* the user
  ///      clicks submit was the original race (fixed in PR #19);
  ///      auto-clicking submit ourselves was the second race that
  ///      silently skipped the captcha.
  ///   4. Generous 180s timeout — long enough for the user to solve
  ///      a picture captcha with a TV remote, short enough that the
  ///      dialog doesn't hang forever if the page is broken.
  ///
  /// The script is idempotent. `onLoadStop` fires a second time
  /// after the login POST redirect, which re-injects this script;
  /// `__pvFilmanState` (session-scoped) makes the second pass pick
  /// up the error/success path instead of re-filling the form.
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
            return raw ? JSON.parse(raw) : { submitted: false, reported: false, preSnap: null };
          } catch (e) {
            return { submitted: false, reported: false, preSnap: null };
          }
        }
        function setState(s) {
          try { sessionStorage.setItem('__pvFilmanState', JSON.stringify(s)); } catch (e) {}
        }
        var state = getState();
        var timeoutId = null;

        // Snapshot the login form so that when the server rejects us
        // with "Nieprawidłowy token bezpieczeństwa" we can see in the
        // log what the form actually contained (hidden CSRF inputs,
        // Turnstile widget, reCAPTCHA, etc.). This is purely diagnostic.
        //
        // Selectors use attribute values with quotes: unquoted values
        // like [src*=foo.bar] are invalid per CSS (the dot makes it
        // parse as a class selector) and throw SyntaxError at runtime,
        // killing the snapshot itself — which is how the first
        // diagnostic build produced no data at all.
        function snapshotForm() {
          try {
            var form = document.querySelector('#signin-form');
            var hidden = [];
            if (form) {
              var inputs = form.querySelectorAll('input[type=hidden]');
              for (var i = 0; i < inputs.length; i++) {
                var n = inputs[i].name || '(noname)';
                var v = inputs[i].value || '';
                hidden.push(n + '=' + (v ? '[' + v.length + ']' : 'empty'));
              }
            }
            var turnstile = document.querySelector('.cf-turnstile') ||
                            document.querySelector('iframe[src*="challenges.cloudflare.com"]');
            var recaptcha = document.querySelector('.g-recaptcha') ||
                            document.querySelector('iframe[src*="recaptcha"]');
            var hcaptcha  = document.querySelector('.h-captcha') ||
                            document.querySelector('iframe[src*="hcaptcha"]');
            var rcResp = document.getElementById('g-recaptcha-response');
            var tsResp = document.querySelector('input[name="cf-turnstile-response"]');
            return {
              url: window.location.href,
              pathname: window.location.pathname,
              hasForm: !!form,
              action: form ? form.getAttribute('action') : null,
              method: form ? form.getAttribute('method') : null,
              hiddenInputs: hidden,
              hasTurnstile: !!turnstile,
              hasRecaptcha: !!recaptcha,
              hasHcaptcha: !!hcaptcha,
              recaptchaRespLen: rcResp ? (rcResp.value || '').length : -1,
              turnstileRespLen: tsResp ? (tsResp.value || '').length : -1,
              cookieNames: (document.cookie || '').split(';').map(function(c){return c.trim().split('=')[0];}).filter(Boolean),
              title: document.title
            };
          } catch (e) {
            return { snapshotError: String(e) };
          }
        }

        function report(payload) {
          if (state.reported) return;
          state.reported = true;
          setState(state);
          if (timeoutId) { clearTimeout(timeoutId); timeoutId = null; }
          // Attach the pre-submit snapshot to every non-success report so
          // the cause of server-side rejection (e.g. missing Turnstile
          // token, stale CSRF) is visible in the log next to the error.
          if (payload && payload.success !== true) {
            payload.debug = { preSubmit: state.preSnap, postSubmit: snapshotForm() };
          }
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

        // Generous timeout: the user may need a while with the TV
        // remote to tick the in-form "nie jestem robotem" captcha
        // (image challenge etc.), and we don't want to yank the
        // dialog out from under them mid-solve.
        timeoutId = setTimeout(function() {
          report({ success: false, error: 'Przekroczono czas oczekiwania na odpowiedź filman.cc.' });
        }, 180000);

        // If we arrived back on /logowanie AFTER the user submitted,
        // look for the error banner. Only then — before that, any
        // .alert-danger on the page is a stale flash from an earlier
        // session and must be ignored.
        if (state.submitted) {
          waitForElement('.alert-danger',
            function(el) { report({ success: false, error: el.textContent.trim() }); },
            function() { return state.reported; });
          return;
        }

        // First pass on /logowanie: pre-fill login/password so the
        // user doesn't have to type with a TV remote, then HAND OVER
        // to the user. The form has a captcha checkbox below the
        // password field ("nie jestem robotem") that the user must
        // click manually; auto-clicking the submit button before the
        // captcha is solved makes the server respond with
        // "Nieprawidłowy token bezpieczeństwa".
        //
        // We listen for the real submit event so that *whenever* the
        // user clicks the button we snapshot the form state and flip
        // `state.submitted` — letting the form POST through
        // untouched. On the next onLoadStop (either on '/' for
        // success, or back on '/logowanie' for failure) the re-
        // injected script will take the appropriate branch above.
        //
        // Extra sanity check: Cloudflare's "Just a moment..." challenge
        // pages can carry their own form-like markup. Require both the
        // form AND a submit button named "submit" before we consider
        // ourselves on the real login page.
        waitForElement('#signin-form button[name=submit]',
          function(btn) {
            if (state.submitted) return;
            var form = document.querySelector('#signin-form');
            if (!form || !form.login || !form.password) return;  // still not the real form
            try {
              // Only overwrite if empty, so the user can correct a typo
              // without the script clobbering their edit on a later tick.
              if (!form.login.value) form.login.value = '$login';
              if (!form.password.value) form.password.value = '$password';
              $captchaLine
            } catch (e) {
              report({ success: false, error: 'Nie udało się wypełnić formularza: ' + e });
              return;
            }
            // Hook the real submit event (not the button click —
            // some themes intercept click handlers for validation,
            // but the browser always fires submit on the form when
            // the POST is actually about to go out).
            form.addEventListener('submit', function() {
              if (state.submitted) return;
              state.preSnap = snapshotForm();
              state.submitted = true;
              setState(state);
              // Let the submit proceed. We intentionally do NOT
              // call preventDefault; the navigation that follows
              // will re-inject this script and the next pass will
              // take either the success or the .alert-danger path.
            }, true);
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
              captcha: fields['g-recaptcha-response']),
          // Required: filman's _csrf input is session-bound to
          // PHPSESSID. Without persistent cookies the cookie set
          // on GET /logowanie is gone by the time we POST, and
          // every login fails with "Nieprawidłowy token
          // bezpieczeństwa". Diagnostic snapshot from PR #20
          // confirmed cookieNames=['BKD_COOKIES'] at preSubmit
          // and PHPSESSID only appearing post-failure.
          persistCookies: true);

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
          final errorText = json['error'] ?? 'Nieznany błąd logowania $webviewLogin';
          // When the server rejects us (wrong token, wrong credentials,
          // Turnstile missing, etc.) the JS snapshot in json['debug']
          // tells us what the form actually looked like. Surface it so
          // the runtime log is enough to diagnose next failure without
          // another rebuild cycle.
          final debug = json['debug'];
          final authModel = AuthModel(
            service: SupportedService.filman,
            success: false,
            error: [
              errorText,
              if (debug != null) 'debug: ${jsonEncode(debug)}',
            ],
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
