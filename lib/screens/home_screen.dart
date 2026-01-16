import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../models/tab_config.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../services/iap_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final IAPService _iapService = IAPService(); // iOS 인앱결제
  List<TabConfig> _tabs = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isFullscreen = false; // 풀스크린 모드 (탭바 숨김)
  late WebViewController _webViewController;
  String? _idToken;
  bool _webViewReady = false; // WebView 초기화 완료 플래그

  // ⭐ iOS 스피너 숨김 타이머
  Timer? _spinnerHideTimer;

  // 디버그 콘솔 로그
  bool _showDebugConsole = false;
  final List<String> _consoleLogs = [];
  final int _maxLogs = 100; // 최대 로그 개수

  // login.html 리다이렉트 감지 (무한 루프 방지)
  int _loginRedirectCount = 0;
  static const int _maxLoginRedirects = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spinnerHideTimer?.cancel();
    _iapService.dispose(); // IAP 리소스 해제
    super.dispose();
  }

  /// ⭐ 앱 라이프사이클 감지 - iOS bfcache 스피너 문제 해결
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _webViewReady && Platform.isIOS) {
      print('[HomeScreen] 앱 resumed (iOS) → 스피너 강제 숨김');
      _injectSpinnerHider();
    }
  }

  Future<void> _initializeApp() async {
    // 1. 권한 요청 (카메라, 사진)
    await _requestPermissions();

    // 2. iOS 인앱결제 초기화
    await _initializeIAP();

    // 3. WebView 초기화
    await _initWebViewWithAuth();

    // 4. 탭 구독
    _watchTabs();
  }

  /// iOS 인앱결제 초기화
  Future<void> _initializeIAP() async {
    if (!Platform.isIOS) {
      print('[IAP] iOS가 아니므로 인앱결제 스킵');
      return;
    }

    // 현재 사용자 ID 설정 (서버 영수증 검증에 사용)
    final user = _auth.currentUser;
    if (user != null) {
      // 이메일 기반 userId 생성 (Firestore 문서 ID와 동일하게)
      String? email = user.email;
      
      // 카카오 로그인 등 이메일이 없는 경우 token claims에서 가져오기
      if (email == null || email.isEmpty) {
        try {
          final tokenResult = await user.getIdTokenResult();
          email = tokenResult.claims?['email'] as String?;
          print('[IAP] token claims에서 이메일 가져옴: $email');
        } catch (e) {
          print('[IAP] token claims 조회 실패: $e');
        }
      }
      
      if (email != null && email.isNotEmpty) {
        _iapService.currentUserId = email.replaceAll('@', '_').replaceAll('.', '_');
      } else {
        _iapService.currentUserId = user.uid;
      }
      print('[IAP] 사용자 ID 설정: ${_iapService.currentUserId}');
    }

    final initialized = await _iapService.initialize();
    if (initialized) {
      print('[IAP] 인앱결제 초기화 성공');

      // 구매 성공 콜백
      _iapService.onPurchaseSuccess = (productId, tokens, receipt) {
        print('[IAP] 구매 성공! productId: $productId, tokens: $tokens');
        _onIAPSuccess(productId, tokens, receipt);
      };

      // 구매 실패 콜백
      _iapService.onPurchaseError = (error) {
        print('[IAP] 구매 실패: $error');
        _onIAPError(error);
      };
    } else {
      print('[IAP] 인앱결제 초기화 실패');
    }
  }

  /// IAP 구매 성공 처리 - WebView에 결과 전달
  void _onIAPSuccess(String productId, int tokens, String? receipt) {
    if (!mounted) return;

    // WebView에 구매 성공 알림
    _webViewController.runJavaScript('''
      console.log('[Flutter IAP] 구매 성공: $productId, $tokens 토큰');
      if (window.onIAPSuccess) {
        window.onIAPSuccess('$productId', $tokens);
      } else {
        // 토큰 충전 후 페이지 새로고침
        alert('$tokens 토큰이 충전되었습니다!');
        location.reload();
      }
    ''');

    // 스낵바 알림
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$tokens 토큰이 충전되었습니다!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// IAP 구매 실패 처리 - WebView에 결과 전달
  void _onIAPError(String error) {
    if (!mounted) return;

    // WebView에 구매 실패 알림
    _webViewController.runJavaScript('''
      console.log('[Flutter IAP] 구매 실패: $error');
      if (window.onIAPError) {
        window.onIAPError('$error');
      }
    ''');

    // 스낵바 알림 (취소는 알림 안 함)
    if (!error.contains('취소')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('결제 실패: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// WebView에서 IAP 구매 요청 처리
  Future<void> _handleIAPRequest(String message) async {
    print('[IAP] WebView에서 구매 요청: $message');
    _addConsoleLog('[IAP 요청] $message');

    if (!Platform.isIOS) {
      print('[IAP] iOS가 아니므로 IAP 불가');
      _onIAPError('iOS에서만 인앱결제가 가능합니다.');
      return;
    }

    try {
      // 메시지 형식: productId (예: "hairgator_basic")
      // 또는 JSON 형식: {"action": "purchase", "productId": "hairgator_basic"}
      String productId = message;

      if (message.startsWith('{')) {
        // JSON 형식
        final data = jsonDecode(message);
        if (data['action'] == 'purchase') {
          productId = data['productId'];
        } else if (data['action'] == 'getProducts') {
          // 상품 목록 요청
          _sendProductsToWeb();
          return;
        }
      }

      // ⭐ 상품 로드 상태 확인
      print('[IAP] 로드된 상품 수: ${_iapService.products.length}');
      if (_iapService.products.isEmpty) {
        print('[IAP] ⚠️ 상품이 로드되지 않음 → 다시 로드 시도');
        await _iapService.loadProducts();
        print('[IAP] 재로드 후 상품 수: ${_iapService.products.length}');

        if (_iapService.products.isEmpty) {
          _onIAPError('상품 정보를 불러올 수 없습니다. 잠시 후 다시 시도해주세요.');
          return;
        }
      }

      // 구매 시작 (await 추가!)
      final success = await _iapService.purchase(productId);
      print('[IAP] 구매 요청 완료: success=$success');
    } catch (e) {
      print('[IAP] 요청 처리 오류: $e');
      _onIAPError(e.toString());
    }
  }

  /// WebView에 상품 목록 전달
  void _sendProductsToWeb() {
    final products = _iapService.products.map((p) => {
      'id': p.id,
      'title': p.title,
      'description': p.description,
      'price': p.price,
      'tokens': IAPService.productTokens[p.id] ?? 0,
    }).toList();

    final productsJson = jsonEncode(products);
    _webViewController.runJavaScript('''
      console.log('[Flutter IAP] 상품 목록 수신');
      if (window.onIAPProducts) {
        window.onIAPProducts($productsJson);
      }
    ''');
  }

  /// Firebase User에서 Firestore 문서 ID 생성
  /// 이메일 기반: user@example.com → user_example_com
  String _getFirestoreUserId(User user) {
    if (user.email != null && user.email!.isNotEmpty) {
      // 이메일 기반 ID (@ → _, . → _)
      return user.email!.replaceAll('@', '_').replaceAll('.', '_');
    }
    // 이메일 없으면 UID 사용
    return user.uid;
  }

  /// 카메라/사진 권한 요청
  Future<void> _requestPermissions() async {
    print('[Permission] 권한 요청 시작...');

    // Android 13+ (API 33+) 에서는 READ_MEDIA_IMAGES 사용
    // 그 이하 버전에서는 storage 권한 사용
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.photos, // iOS & Android 13+
      Permission.storage, // Android 12 이하
    ].request();

    statuses.forEach((permission, status) {
      print('[Permission] $permission: $status');
    });
  }

  /// Firestore 탭 설정 실시간 구독
  void _watchTabs() {
    _firestoreService.watchTabConfigs().listen((tabs) {
      print('[HomeScreen] 탭 실시간 업데이트: ${tabs.map((t) => t.menuName).toList()}');
      setState(() {
        _tabs = tabs;
        _isLoading = false;
      });
    }, onError: (e) {
      print('[HomeScreen] 탭 구독 오류: $e');
      setState(() => _isLoading = false);
    });
  }

  Future<void> _initWebViewWithAuth() async {
    // Firebase ID Token 가져오기 (강제 갱신)
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // true = 강제로 새 토큰 발급 (만료된 토큰 방지)
        _idToken = await user.getIdToken(true);
        print('[WebView] Firebase ID Token 획득 (강제 갱신): ${_idToken?.substring(0, 20)}...');
      } else {
        print('[WebView] 로그인된 사용자 없음 → 로그인 화면으로 이동');
        // 로그인 화면으로 돌아가기
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
        return;
      }
    } catch (e) {
      print('[WebView] Token 획득 실패: $e → 로그인 화면으로 이동');
      // 토큰 획득 실패 시 로그인 화면으로
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
      return;
    }

    // 플랫폼별 WebView 생성 파라미터
    late final PlatformWebViewControllerCreationParams params;

    if (Platform.isIOS) {
      // iOS: WKWebView 설정
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      // Android: 기본 설정
      params = const PlatformWebViewControllerCreationParams();
    }

    _webViewController = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _handleJavaScriptMessage(message.message);
        },
      )
      ..addJavaScriptChannel(
        'DownloadChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _downloadAndSaveImage(message.message);
        },
      )
      ..addJavaScriptChannel(
        'ConsoleLogChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _addConsoleLog(message.message);
        },
      );

    // ⭐ iOS에서만 IAPChannel 등록 (Android에서는 외부결제 사용)
    if (Platform.isIOS) {
      _webViewController.addJavaScriptChannel(
        'IAPChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          // async 콜백으로 에러 처리
          try {
            print('[IAPChannel] 메시지 수신: ${message.message}');
            await _handleIAPRequest(message.message);
          } catch (e) {
            print('[IAPChannel] 처리 오류: $e');
            _onIAPError(e.toString());
          }
        },
      );
    }

    _webViewController.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
            // 콘솔 로그 캡처 주입
            _injectConsoleCapture();
            // 페이지 로드 후 토큰으로 자동 로그인 시도
            _injectAuthToken();
            // ⭐ iOS bfcache 스피너 문제 해결 - 강제 숨김
            _injectSpinnerHider();
            print('[WebView] 페이지 로드 완료: $url');

            // ⚠️ login.html로 리다이렉트된 경우 → 다시 index.html로 로드 (무한 루프 방지)
            if (url.contains('login.html') || url.endsWith('/login')) {
              _loginRedirectCount++;
              print('[WebView] ⚠️ login.html 감지! (${_loginRedirectCount}/$_maxLoginRedirects)');
              _addConsoleLog('[⚠️ REDIRECT] login.html 감지 #$_loginRedirectCount');

              if (_loginRedirectCount <= _maxLoginRedirects) {
                // 토큰과 함께 index.html 다시 로드
                _webViewController.loadRequest(
                  Uri.parse(_getUrlWithToken('https://app.hairgator.kr'))
                );
              } else {
                // 계속 login.html로 가면 → 네이티브 로그인 화면으로
                print('[WebView] 🔴 login.html 반복 → 네이티브 로그인으로 이동');
                _addConsoleLog('[🔴 ERROR] login 반복 → 네이티브 로그인');
                _handleLogout();
              }
            } else {
              // 정상 페이지면 카운터 리셋
              _loginRedirectCount = 0;
            }
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView error: ${error.description}');
          },
        ),
      );

    // Android 전용 설정
    if (_webViewController.platform is AndroidWebViewController) {
      final androidController =
          _webViewController.platform as AndroidWebViewController;

      // 미디어 자동 재생 허용
      androidController.setMediaPlaybackRequiresUserGesture(false);

      // 카메라/마이크 권한 요청 처리 (getUserMedia)
      androidController.setOnPlatformPermissionRequest((request) {
        print('[WebView] 웹 권한 요청: ${request.types}');
        request.grant(); // 모든 권한 허용
      });

      // 파일 선택기 처리 (input type="file" - 갤러리 접근)
      androidController.setOnShowFileSelector((params) async {
        print('[WebView] 파일 선택기 요청: ${params.acceptTypes}');
        return await _handleFileSelection(params);
      });

      print('[WebView] Android WebView 설정 완료');
    }

    // iOS 전용 설정
    if (_webViewController.platform is WebKitWebViewController) {
      final iosController =
          _webViewController.platform as WebKitWebViewController;

      // iOS에서 미디어 캡처 허용
      iosController.setAllowsBackForwardNavigationGestures(true);

      print('[WebView] iOS WebView 설정 완료');
    }

    _webViewController
        .loadRequest(Uri.parse(_getUrlWithToken('https://app.hairgator.kr')));

    // WebView 준비 완료 플래그 설정
    _webViewReady = true;

    // ⭐ iOS 전용: 주기적 스피너 숨김 타이머 (bfcache 문제 해결)
    if (Platform.isIOS) {
      print('[WebView] iOS 감지 → 주기적 스피너 숨김 타이머 시작');
      _spinnerHideTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (_webViewReady && !_isLoading) {
          _injectSpinnerHiderSilent();
        }
      });
    }
  }

  String _getUrlWithToken(String baseUrl) {
    final separator = baseUrl.contains('?') ? '&' : '?';
    // Flutter 앱임을 표시 + Firebase 토큰 전달 + 캐시 방지 타임스탬프
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    String url = '$baseUrl${separator}isFlutterApp=true&_t=$timestamp';
    if (_idToken != null) {
      url += '&firebaseToken=$_idToken';
    }
    print('[WebView] 로드 URL: $url');
    return url;
  }

  Future<void> _injectAuthToken() async {
    if (_idToken == null) return;

    // JavaScript로 토큰 전달하여 자동 로그인
    try {
      await _webViewController.runJavaScript('''
        if (window.handleFirebaseToken) {
          window.handleFirebaseToken('$_idToken');
        } else {
          console.log('[Flutter] Firebase token ready: ${_idToken?.substring(0, 20)}...');
          window.flutterFirebaseToken = '$_idToken';
        }
      ''');
    } catch (e) {
      print('[WebView] JS injection error: $e');
    }
  }

  /// 콘솔 로그 캡처 JavaScript 주입
  Future<void> _injectConsoleCapture() async {
    try {
      await _webViewController.runJavaScript('''
        (function() {
          if (window.__consoleCapture) return; // 이미 주입됨
          window.__consoleCapture = true;

          const originalLog = console.log;
          const originalError = console.error;
          const originalWarn = console.warn;
          const originalInfo = console.info;

          function sendToFlutter(type, args) {
            try {
              const message = Array.from(args).map(arg => {
                if (typeof arg === 'object') {
                  try { return JSON.stringify(arg); }
                  catch (e) { return String(arg); }
                }
                return String(arg);
              }).join(' ');

              const timestamp = new Date().toLocaleTimeString('ko-KR', {hour12: false});
              const logEntry = '[' + timestamp + '] [' + type + '] ' + message;

              if (window.ConsoleLogChannel) {
                window.ConsoleLogChannel.postMessage(logEntry);
              }
            } catch (e) {}
          }

          console.log = function() {
            sendToFlutter('LOG', arguments);
            originalLog.apply(console, arguments);
          };

          console.error = function() {
            sendToFlutter('ERROR', arguments);
            originalError.apply(console, arguments);
          };

          console.warn = function() {
            sendToFlutter('WARN', arguments);
            originalWarn.apply(console, arguments);
          };

          console.info = function() {
            sendToFlutter('INFO', arguments);
            originalInfo.apply(console, arguments);
          };

          // 전역 에러 캡처
          window.onerror = function(msg, url, line, col, error) {
            sendToFlutter('UNCAUGHT', ['Error: ' + msg + ' at ' + url + ':' + line + ':' + col]);
            return false;
          };

          // Promise rejection 캡처
          window.onunhandledrejection = function(event) {
            sendToFlutter('REJECTION', ['Unhandled Promise: ' + event.reason]);
          };

          console.log('[Flutter Console Capture] ✅ 콘솔 캡처 활성화됨');
        })();
      ''');
      print('[WebView] 콘솔 캡처 주입 완료');
    } catch (e) {
      print('[WebView] 콘솔 캡처 주입 실패: $e');
    }
  }

  /// ⭐ iOS 주기적 스피너 숨김 (조용한 버전 - 로그 없음)
  Future<void> _injectSpinnerHiderSilent() async {
    try {
      await _webViewController.runJavaScript('''
        (function() {
          var byId = document.getElementById('loadingOverlay');
          if (byId && (byId.classList.contains('visible') || byId.style.display !== 'none')) {
            byId.style.cssText = 'display: none !important; visibility: hidden !important; opacity: 0 !important;';
            byId.classList.remove('visible');
          }
          document.querySelectorAll('.loading-overlay.visible').forEach(function(el) {
            el.style.cssText = 'display: none !important; visibility: hidden !important; opacity: 0 !important;';
            el.classList.remove('visible');
          });
        })();
      ''');
    } catch (e) {
      // 에러 무시 (조용한 버전)
    }
  }

  /// ⭐ iOS bfcache 스피너 강제 숨김 JavaScript 주입
  Future<void> _injectSpinnerHider() async {
    try {
      await _webViewController.runJavaScript('''
        (function() {
          // 스피너 강제 숨김 함수
          function forceHideSpinner() {
            var found = false;

            // ID로 찾기
            var byId = document.getElementById('loadingOverlay');
            if (byId) {
              byId.style.cssText = 'display: none !important; visibility: hidden !important; opacity: 0 !important; pointer-events: none !important;';
              byId.classList.remove('visible');
              byId.classList.add('force-hide');
              found = true;
            }

            // 클래스로 찾기
            var overlays = document.querySelectorAll('.loading-overlay');
            overlays.forEach(function(el) {
              el.style.cssText = 'display: none !important; visibility: hidden !important; opacity: 0 !important; pointer-events: none !important;';
              el.classList.remove('visible');
              el.classList.add('force-hide');
              found = true;
            });

            // 스피너 클래스로 찾기
            var spinners = document.querySelectorAll('.loading-spinner');
            spinners.forEach(function(el) {
              el.style.cssText = 'display: none !important; visibility: hidden !important;';
              found = true;
            });

            // visible 클래스가 있는 모든 로딩 요소
            var visibleLoading = document.querySelectorAll('.loading-overlay.visible, [class*="loading"][class*="visible"]');
            visibleLoading.forEach(function(el) {
              el.classList.remove('visible');
              el.style.display = 'none';
              found = true;
            });

            return found;
          }

          // 즉시 실행 (여러 번)
          forceHideSpinner();
          setTimeout(forceHideSpinner, 50);
          setTimeout(forceHideSpinner, 100);
          setTimeout(forceHideSpinner, 200);
          setTimeout(forceHideSpinner, 500);
          setTimeout(forceHideSpinner, 1000);

          console.log('[Flutter Spinner Hider] ✅ 스피너 강제 숨김 실행됨');
        })();
      ''');
      print('[WebView] 스피너 숨김 주입 완료');
    } catch (e) {
      print('[WebView] 스피너 숨김 주입 실패: $e');
    }
  }

  /// 콘솔 로그 추가
  void _addConsoleLog(String log) {
    print('[WebConsole] $log');
    setState(() {
      _consoleLogs.insert(0, log);
      if (_consoleLogs.length > _maxLogs) {
        _consoleLogs.removeLast();
      }
    });
  }

  /// 웹에서 보낸 메시지 처리
  void _handleJavaScriptMessage(String message) {
    print('[Flutter] JS 메시지 수신: $message');
    _addConsoleLog('[Flutter MSG] $message');

    if (message == 'logout') {
      _handleLogout();
    } else if (message == 'toggleFullscreen') {
      setState(() {
        _isFullscreen = !_isFullscreen;
      });
      print('[Flutter] 풀스크린 모드: $_isFullscreen');
    } else if (message == 'showTabs') {
      setState(() {
        _isFullscreen = false;
      });
    } else if (message == 'hideTabs') {
      setState(() {
        _isFullscreen = true;
      });
    } else if (message == 'requestCameraPermission') {
      // 웹에서 카메라 권한 요청 시
      _requestPermissions();
    } else if (message == 'auth_state_null') {
      // 웹에서 auth state가 null이 됨 → 로그 기록
      _addConsoleLog('[⚠️ AUTH] 웹에서 auth state null 감지됨!');
      print('[Flutter] ⚠️ 웹에서 auth state null 감지!');
    }
  }

  /// 파일 선택 처리 (갤러리/카메라에서 이미지 선택)
  Future<List<String>> _handleFileSelection(FileSelectorParams params) async {
    final ImagePicker picker = ImagePicker();

    try {
      // 이미지 타입인지 확인
      final acceptTypes = params.acceptTypes;
      final isImage = acceptTypes.isEmpty ||
          acceptTypes.any((type) =>
              type.contains('image') || type == '*/*' || type == '*');

      if (isImage) {
        // 선택 방식 다이얼로그 표시
        final source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('갤러리에서 선택'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('카메라로 촬영'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ],
            ),
          ),
        );

        if (source == null) {
          return []; // 사용자가 취소
        }

        final XFile? image = await picker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );

        if (image != null) {
          final filePath = 'file://${image.path}';
          print('[WebView] 이미지 선택됨: $filePath');
          return [filePath];
        }
      }

      return [];
    } catch (e) {
      print('[WebView] 파일 선택 에러: $e');
      return [];
    }
  }

  /// 이미지 다운로드 및 갤러리 저장
  Future<void> _downloadAndSaveImage(String imageUrl) async {
    print('[Flutter] 이미지 다운로드 요청: ${imageUrl.substring(0, imageUrl.length > 100 ? 100 : imageUrl.length)}...');

    try {
      // 로딩 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('이미지 저장 중...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      Uint8List imageBytes;

      // base64 데이터 URL인 경우
      if (imageUrl.startsWith('data:image')) {
        print('[Flutter] Base64 이미지 감지');
        // data:image/jpeg;base64,/9j/4AAQ... 형식에서 base64 부분 추출
        final base64Data = imageUrl.split(',').last;
        imageBytes = base64Decode(base64Data);
      } else {
        // HTTP URL인 경우 다운로드
        print('[Flutter] HTTP URL 다운로드');
        final dio = Dio();
        final response = await dio.get(
          imageUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        imageBytes = Uint8List.fromList(response.data);
      }

      // 임시 파일로 저장
      final tempDir = await getTemporaryDirectory();
      final fileName = 'hairgator_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      // 갤러리에 저장 (gal 패키지)
      await Gal.putImage(filePath, album: 'Hairgator');

      print('[Flutter] 이미지 저장 성공: $filePath');

      // 임시 파일 삭제
      await file.delete();

      // 결과 알림
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('이미지가 갤러리에 저장되었습니다!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // 웹에 결과 전달
        _webViewController.runJavaScript('''
          if (window.onImageSaved) {
            window.onImageSaved(true);
          }
        ''');
      }
    } catch (e) {
      print('[Flutter] 이미지 저장 에러: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 로그아웃 처리 - 네이티브 로그인 화면으로 이동
  Future<void> _handleLogout() async {
    print('[Flutter] 웹에서 로그아웃 요청 수신');

    try {
      final authService = AuthService();
      await authService.signOut();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false, // 모든 이전 화면 제거
        );
      }
    } catch (e) {
      print('[Flutter] 로그아웃 에러: $e');
    }
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
      // 다른 탭으로 이동하면 풀스크린 해제
      _isFullscreen = false;
    });

    final tab = _tabs[index];
    final hashRoute = _getHashRoute(tab);

    print('[HomeScreen] 탭 $index (${tab.menuName}) → #$hashRoute');

    // SPA 라우터 방식: JavaScript로 해시만 변경 (페이지 새로고침 없음)
    // 사이드바도 닫기
    _webViewController.runJavaScript('''
      // 사이드바 닫기
      if (window.closeSidebar) {
        window.closeSidebar();
      }
      var sidebar = document.getElementById('sidebar');
      if (sidebar) {
        sidebar.classList.remove('open');
      }
      var overlay = document.getElementById('sidebar-overlay');
      if (overlay) {
        overlay.style.display = 'none';
      }

      window.location.hash = '$hashRoute';
      console.log('[Flutter] 탭 네비게이션: #$hashRoute');
    ''');
  }

  /// 탭의 해시 라우트 결정 (meta 기반)
  String _getHashRoute(TabConfig tab) {
    // URL에 해시가 있으면 추출
    if (tab.url != null && tab.url!.contains('#')) {
      return tab.url!.split('#').last;
    }

    // meta 기반으로 해시 결정
    switch (tab.meta) {
      case 'styleMenuTab':
        return ''; // 메인 화면 (홈)
      case 'pkg_iamportPayment_productMulti':
        return 'products';
      case 'myPage':
        return 'mypage';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // WebView with improved touch handling
            WebViewWidget(
              controller: _webViewController,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<VerticalDragGestureRecognizer>(
                  () => VerticalDragGestureRecognizer(),
                ),
                Factory<HorizontalDragGestureRecognizer>(
                  () => HorizontalDragGestureRecognizer(),
                ),
              },
            ),

            // 로딩 인디케이터
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFE91E63),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: (_tabs.isEmpty || _isFullscreen)
          ? null
          : BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.black,
              selectedItemColor: const Color(0xFFE91E63),
              unselectedItemColor: Colors.grey,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              items: _tabs.map((tab) {
                return BottomNavigationBarItem(
                  icon: _buildTabIcon(tab, false),
                  activeIcon: _buildTabIcon(tab, true),
                  label: tab.menuName,
                );
              }).toList(),
            ),
    );
  }

  Widget _buildTabIcon(TabConfig tab, bool isSelected) {
    final iconUrl = isSelected ? tab.iconLightSelected : tab.iconLight;

    if (iconUrl != null && iconUrl.isNotEmpty) {
      return Image.network(
        iconUrl,
        width: 24,
        height: 24,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            _getDefaultIcon(tab.meta),
            size: 24,
          );
        },
      );
    }

    return Icon(
      _getDefaultIcon(tab.meta),
      size: 24,
    );
  }

  IconData _getDefaultIcon(String meta) {
    switch (meta) {
      case 'styleMenuTab':
        return Icons.style;
      case 'pkg_iamportPayment_productMulti':
        return Icons.shopping_bag;
      case 'myPage':
        return Icons.person;
      default:
        return Icons.circle;
    }
  }
}
