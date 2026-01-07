import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/tab_config.dart';
import '../services/firestore_service.dart';

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
    _initWebViewWithAuth();
    _watchTabs(); // 실시간 구독
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

    _webViewController = WebViewController()
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

            // 로그인 페이지가 로드되면 Flutter 로그아웃 처리
            if (url.contains('login.html') || url.contains('/login')) {
              print('[WebView] 웹앱 로그인 페이지 감지 → Flutter 로그아웃');
              _auth.signOut();
            }
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(_getUrlWithToken('https://app.hairgator.kr')));
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

    if (message == 'toggleFullscreen') {
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
    _webViewController.runJavaScript('''
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
        return '';  // 메인 화면 (홈)
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
            // WebView
            WebViewWidget(controller: _webViewController),

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
