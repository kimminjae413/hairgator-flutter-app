import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  // 1. Flutter 바인딩 초기화 (필수)
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 카카오 SDK 초기화 - 반드시 runApp() 전에!
  // 이게 없으면 isKakaoTalkInstalled()가 항상 false 반환
  kakao.KakaoSdk.init(nativeAppKey: '0f63cd86d49dd376689358cac993a842');

  // 3. 앱 실행 (Firebase는 앱 내에서 async 초기화)
  runApp(const HairgatorApp());
}

class HairgatorApp extends StatefulWidget {
  const HairgatorApp({super.key});

  @override
  State<HairgatorApp> createState() => _HairgatorAppState();
}

class _HairgatorAppState extends State<HairgatorApp> {
  String _status = 'v40: Starting...';
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // 카카오 SDK는 main()에서 이미 초기화됨 (runApp 전에 필수!)
      setState(() => _status = 'v41: Firebase init...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      setState(() {
        _status = 'v41: Ready!';
        _initialized = true;
      });
    } catch (e) {
      setState(() {
        _status = 'v41: ERROR';
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HAIRGATOR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFE91E63),
          secondary: const Color(0xFF4A90E2),
          surface: const Color(0xFF1A1A1A),
        ),
        scaffoldBackgroundColor: Colors.black,
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.black,
          selectedItemColor: Color(0xFFE91E63),
          unselectedItemColor: Colors.grey,
        ),
      ),
      home: _initialized
        ? const AuthWrapper()
        : _buildLoadingScreen(),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFE91E63)),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    _status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 로그인 상태에 따라 화면 분기
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFE91E63)),
            ),
          );
        }
        if (snapshot.hasData) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
