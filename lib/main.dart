import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

// 디버그 상태 저장
String debugStatus = 'Starting...';

void main() async {
  debugStatus = '1. WidgetsBinding...';
  WidgetsFlutterBinding.ensureInitialized();

  // 카카오 SDK 초기화 (iPad 등에서 실패해도 앱은 실행)
  debugStatus = '2. Kakao SDK...';
  try {
    kakao.KakaoSdk.init(nativeAppKey: '0f63cd86d49dd376689358cac993a842');
    debugStatus = '2. Kakao SDK OK';
  } catch (e) {
    debugStatus = '2. Kakao SDK FAIL: $e';
    debugPrint('Kakao SDK init failed: $e');
  }

  debugStatus = '3. Firebase init...';
  try {
    await Firebase.initializeApp();
    debugStatus = '3. Firebase OK';
  } catch (e) {
    debugStatus = '3. Firebase FAIL: $e';
    debugPrint('Firebase init failed: $e');
  }

  debugStatus = '4. Running app...';
  runApp(const HairgatorApp());
}

class HairgatorApp extends StatelessWidget {
  const HairgatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HAIRGATOR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFE91E63), // 핑크
          secondary: const Color(0xFF4A90E2), // 블루
          surface: const Color(0xFF1A1A1A),
        ),
        scaffoldBackgroundColor: Colors.black,
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.black,
          selectedItemColor: Color(0xFFE91E63),
          unselectedItemColor: Colors.grey,
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

// 로그인 상태에 따라 화면 분기
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  String _authStatus = 'Checking auth...';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 로딩 중
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    color: Color(0xFFE91E63),
                  ),
                  const SizedBox(height: 20),
                  // 디버그 정보 표시
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'DEBUG v31:\n$debugStatus\nAuth: waiting...',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 로그인 됨 -> 홈 화면
        if (snapshot.hasData) {
          return const HomeScreen();
        }

        // 로그인 안 됨 -> 로그인 화면
        return const LoginScreen();
      },
    );
  }
}
