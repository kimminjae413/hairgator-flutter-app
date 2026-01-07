import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/tab_config.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<TabConfig> _tabs = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isFullscreen = false; // 풀스크린 모드 (탭바 숨김)
  late WebViewController _webViewController;
  String? _idToken;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. 권한 요청 (카메라, 사진)
    await _requestPermissions();

    // 2. WebView 초기화
    await _initWebViewWithAuth();

    // 3. 탭 구독
    _watchTabs();
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
    // Firebase ID Token 가져오기
    try {
      final user = _auth.currentUser;
      if (user != null) {
        _idToken = await user.getIdToken();
        print('[WebView] Firebase ID Token 획득: ${_idToken?.substring(0, 20)}...');
      }
    } catch (e) {
      print('[WebView] Token 획득 실패: $e');
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
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
            // 페이지 로드 후 토큰으로 자동 로그인 시도
            _injectAuthToken();
            print('[WebView] 페이지 로드 완료: $url');
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

      // WebGL/DOM Storage 등 고급 기능 활성화
      // setGeolocationEnabled, setDomStorageEnabled 등은 기본값으로 활성화됨

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
  }

  String _getUrlWithToken(String baseUrl) {
    if (_idToken != null) {
      final separator = baseUrl.contains('?') ? '&' : '?';
      return '$baseUrl${separator}firebaseToken=$_idToken';
    }
    return baseUrl;
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

  /// 웹에서 보낸 메시지 처리
  void _handleJavaScriptMessage(String message) {
    print('[Flutter] JS 메시지 수신: $message');

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
