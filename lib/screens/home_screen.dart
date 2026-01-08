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

  // 디버그 콘솔 로그
  bool _showDebugConsole = false;
  final List<String> _consoleLogs = [];
  final int _maxLogs = 100; // 최대 로그 개수

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
      )
      ..setNavigationDelegate(
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
  }

  String _getUrlWithToken(String baseUrl) {
    final separator = baseUrl.contains('?') ? '&' : '?';
    // Flutter 앱임을 표시 + Firebase 토큰 전달
    String url = '$baseUrl${separator}isFlutterApp=true';
    if (_idToken != null) {
      url += '&firebaseToken=$_idToken';
    }
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

            // 디버그 콘솔 토글 버튼 (좌측 상단)
            Positioned(
              top: 10,
              left: 10,
              child: GestureDetector(
                onTap: () => setState(() => _showDebugConsole = !_showDebugConsole),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _showDebugConsole ? Colors.red : Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.bug_report, color: Colors.white, size: 20),
                ),
              ),
            ),

            // 디버그 콘솔 오버레이
            if (_showDebugConsole)
              Positioned(
                top: 50,
                left: 10,
                right: 10,
                bottom: 100,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green, width: 1),
                  ),
                  child: Column(
                    children: [
                      // 헤더
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(11),
                            topRight: Radius.circular(11),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.terminal, color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'WebView Console (${_consoleLogs.length})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            // 로그 지우기 버튼
                            GestureDetector(
                              onTap: () => setState(() => _consoleLogs.clear()),
                              child: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 12),
                            // 닫기 버튼
                            GestureDetector(
                              onTap: () => setState(() => _showDebugConsole = false),
                              child: const Icon(Icons.close, color: Colors.white, size: 18),
                            ),
                          ],
                        ),
                      ),
                      // 로그 목록
                      Expanded(
                        child: _consoleLogs.isEmpty
                            ? const Center(
                                child: Text(
                                  '콘솔 로그가 여기에 표시됩니다',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: _consoleLogs.length,
                                itemBuilder: (context, index) {
                                  final log = _consoleLogs[index];
                                  Color textColor = Colors.white;
                                  if (log.contains('[ERROR]') || log.contains('[UNCAUGHT]')) {
                                    textColor = Colors.red;
                                  } else if (log.contains('[WARN]')) {
                                    textColor = Colors.orange;
                                  } else if (log.contains('[INFO]')) {
                                    textColor = Colors.lightBlue;
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Text(
                                      log,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
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
