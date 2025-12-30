import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/tab_config.dart';
import '../services/firestore_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<TabConfig> _tabs = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  late WebViewController _webViewController;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _loadTabs();
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse('https://app.hairgator.kr'));
  }

  Future<void> _loadTabs() async {
    final tabs = await _firestoreService.loadTabConfigs();
    setState(() {
      _tabs = tabs;
      _isLoading = false;
    });
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);

    final tab = _tabs[index];
    String url = tab.url ?? 'https://app.hairgator.kr';

    // URL에 userId 파라미터가 있으면 실제 userId로 대체
    // TODO: 로그인 후 실제 userId 사용
    url = url.replaceAll('\${userInfo._id.oid}', 'guest');

    _webViewController.loadRequest(Uri.parse(url));
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
      bottomNavigationBar: _tabs.isEmpty
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
