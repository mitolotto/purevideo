import 'dart:async';
import 'dart:io' as io;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:purevideo/core/utils/global_context.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewService {
  String _getJsCodeForElement(String elementSelector) {
    return '''
      (function() {
        function waitForElement(selector, callback) {
          const element = document.querySelector(selector);
          if (element) {
            callback(element);
          } else {
            setTimeout(() => waitForElement(selector, callback), 100);
          }
        }
        waitForElement('$elementSelector', function(element) {
          window.flutter_inappwebview.callHandler('messageHandler', element.outerHTML);
        });
        // setTimeout(() => {
        //   window.flutter_inappwebview.callHandler('messageHandler', null, 'timeout');
        // }, 15000);
      })();
    ''';
  }

  Future<dom.Element?> waitForDomElement(
      String url, String elementSelector) async {
    final completer = Completer<dom.Element?>();

    executeJavaScript(url, _getJsCodeForElement(elementSelector))
        .then((result) {
      if (result != null) {
        final document = dom.Document.html(result);
        final element = document.querySelector(elementSelector);
        completer.complete(element);
      } else {
        completer.complete(null);
      }
    }).catchError((error) {
      debugPrint('Error waiting for DOM element: $error');
      completer.complete(null);
    });

    return completer.future;
  }

  /// Opens a WebView dialog, navigates to [url], and injects [jsCode].
  ///
  /// [persistCookies] defaults to `false` for backwards compatibility:
  /// we normally run the dialog in incognito with cookies/cache wiped
  /// so one scraping attempt doesn't reuse stale state from another.
  ///
  /// Set it to `true` for flows that need a session cookie to survive
  /// between the initial GET and a follow-up POST in the SAME WebView.
  /// Filman.cc's login form is the canonical case: the hidden `_csrf`
  /// input is tied to the `PHPSESSID` cookie set by the first GET, and
  /// the server rejects the POST with "Nieprawidłowy token
  /// bezpieczeństwa" if the cookie doesn't make it through. On some
  /// Android TV firmwares (e.g. Homatics Box R 4K Plus) the
  /// combination of `incognito: true` + `CookieManager.deleteAllCookies()`
  /// in `onWebViewCreated` + a Cloudflare interstitial between GET and
  /// the real page eats the `Set-Cookie: PHPSESSID` header before it
  /// reaches the cookie jar, which is exactly what the diagnostic
  /// snapshot from PR #20 showed: `cookieNames` at pre-submit was
  /// `["BKD_COOKIES"]` only, `PHPSESSID` appeared only AFTER the
  /// failing POST.
  Future<String?> executeJavaScript(
    String url,
    String jsCode, {
    bool persistCookies = false,
  }) async {
    final completer = Completer<String?>();

    showDialog(
      context: getIt<GlobalContext>().context,
      builder: (context) => _buildWebViewDialog(
        context,
        url,
        jsCode,
        completer,
        persistCookies: persistCookies,
      ),
    );

    return completer.future;
  }

  Future<List<io.Cookie>?> getCfCookies(String url,
      {List<io.Cookie>? initialCookies}) async {
    final completer = Completer<List<io.Cookie>?>();

    showDialog(
        context: getIt<GlobalContext>().context,
        builder: (context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: EdgeInsets.zero,
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(url)),
                initialSettings: InAppWebViewSettings(
                  userAgent:
                      'Mozilla/5.0 (Linux; Android 16; Pixel 8 Build/BP31.250610.004; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/138.0.7204.180 Mobile Safari/537.36',
                  transparentBackground: true,
                  supportZoom: false,
                  disableContextMenu: true,
                  disableHorizontalScroll: true,
                  disableVerticalScroll: true,
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  clearCache: true,
                  cacheEnabled: false,
                  incognito: true,
                  useShouldInterceptRequest: true,
                ),
                onWebViewCreated: (controller) async {
                  await CookieManager.instance().deleteAllCookies();
                  if (initialCookies != null && initialCookies.isNotEmpty) {
                    for (io.Cookie cookie in initialCookies) {
                      await CookieManager.instance().setCookie(
                        name: cookie.name,
                        url: WebUri(url),
                        value: cookie.value,
                        domain: cookie.domain,
                      );
                    }
                  }
                  await WebStorageManager.instance().deleteAllData();
                },
                shouldInterceptRequest: (controller, request) async {
                  if (!request.url.rawValue.contains(url)) {
                    return null;
                  }
                  final cookies = await CookieManager.instance()
                      .getCookies(url: request.url);
                  final cfClearance = cookies.firstWhereOrNull(
                    (cookie) => cookie.name == 'cf_clearance',
                  );
                  if (cfClearance != null && !completer.isCompleted) {
                    completer.complete(cookies.map((cookie) {
                      return io.Cookie(
                        cookie.name,
                        cookie.value,
                      );
                    }).toList());
                    if (context.mounted) Navigator.of(context).pop();
                  }
                  return null;
                },
                onLoadStop: (controller, url) async {
                  try {
                    final cookies =
                        await CookieManager.instance().getCookies(url: url!);
                    final cfClearance = cookies.firstWhereOrNull(
                      (cookie) => cookie.name == 'cf_clearance',
                    );
                    if (cfClearance != null && !completer.isCompleted) {
                      completer.complete(cookies.map((cookie) {
                        return io.Cookie(
                          cookie.name,
                          cookie.value,
                        );
                      }).toList());
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  } catch (e) {
                    if (context.mounted) Navigator.of(context).pop();
                    // if (context.mounted) {
                    //   _showErrorDialog(context, controller, completer);
                    // }
                  }
                },
              ),
            ),
          );
        });

    return completer.future;
  }

  Widget _buildWebViewDialog(
    BuildContext context,
    String url,
    String jsCode,
    Completer<String?> completer, {
    bool persistCookies = false,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.zero,
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialSettings: InAppWebViewSettings(
            userAgent:
                'Mozilla/5.0 (Linux; Android 16; Pixel 8 Build/BP31.250610.004; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/138.0.7204.180 Mobile Safari/537.36',
            transparentBackground: true,
            supportZoom: false,
            disableContextMenu: true,
            disableHorizontalScroll: true,
            disableVerticalScroll: true,
            javaScriptEnabled: true,
            domStorageEnabled: true,
            // When we need cookies to survive between GET and POST in
            // the same dialog (see executeJavaScript docs), the cache /
            // incognito settings have to loosen up too — otherwise the
            // cookie jar is wiped out from under us on Android TV.
            clearCache: !persistCookies,
            cacheEnabled: persistCookies,
            incognito: !persistCookies,
          ),
          onWebViewCreated: (controller) async {
            if (!persistCookies) {
              await CookieManager.instance().deleteAllCookies();
              await WebStorageManager.instance().deleteAllData();
            }

            controller.addJavaScriptHandler(
              handlerName: 'messageHandler',
              callback: (message) {
                if (message.isNotEmpty && message[0] != null) {
                  completer.complete(message[0].toString());
                  Navigator.of(context).pop();
                } else {
                  _showErrorDialog(context, controller, completer);
                }
              },
            );
          },
          onLoadStop: (controller, url) async {
            try {
              await controller.evaluateJavascript(source: jsCode);
            } catch (e) {
              debugPrint('Błąd wykonywania JavaScript: $e');
              if (context.mounted) {
                _showErrorDialog(context, controller, completer);
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _showErrorDialog(BuildContext context,
      InAppWebViewController controller, Completer<String?> completer) {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Błąd'),
          content: const Text(
            'Wystąpił błąd podczas wykonywania operacji w WebView.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                completer.complete(null);
                Navigator.of(context).pop();
              },
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                controller.reload();
              },
              child: const Text('Ponów'),
            ),
          ],
        );
      },
    );
  }
}
