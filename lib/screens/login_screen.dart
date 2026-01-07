import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLoginMode = true;
  String _kakaoDebugInfo = 'v45: 확인 중...';
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _checkKakaoTalkInstalled();
  }

  Future<void> _checkKakaoTalkInstalled() async {
    try {
      final isInstalled = await kakao.isKakaoTalkInstalled();
      setState(() {
        _kakaoDebugInfo = 'v43: 카카오톡 ${isInstalled ? "설치됨 ✅" : "미설치 ❌"}';
      });
      print('[DEBUG] isKakaoTalkInstalled: $isInstalled');
    } catch (e) {
      setState(() {
        _kakaoDebugInfo = 'v43: 확인 오류 - $e';
      });
      print('[DEBUG] isKakaoTalkInstalled error: $e');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    final result = await _authService.signInWithGoogle();

    setState(() => _isLoading = false);

    if (result != null && mounted) {
      _navigateToHome();
    } else {
      _showError('Google 로그인에 실패했습니다.');
    }
  }

  Future<void> _signInWithKakao() async {
    setState(() {
      _isLoading = true;
      _lastError = null;
    });

    final result = await _authService.signInWithKakao();

    setState(() => _isLoading = false);

    if (result != null && mounted) {
      _navigateToHome();
    } else {
      // 상세 에러 메시지 표시 (디버깅용)
      final errorMsg = _authService.lastKakaoError ?? '카카오 로그인에 실패했습니다.';
      setState(() {
        _lastError = errorMsg;
      });
      _showError(errorMsg);
    }
  }

  Future<void> _signInWithEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('이메일과 비밀번호를 입력해주세요.');
      return;
    }

    setState(() => _isLoading = true);

    final result = _isLoginMode
        ? await _authService.signInWithEmail(email, password)
        : await _authService.signUpWithEmail(email, password);

    setState(() => _isLoading = false);

    if (result != null && mounted) {
      _navigateToHome();
    } else {
      _showError(_isLoginMode ? '로그인에 실패했습니다.' : '회원가입에 실패했습니다.');
    }
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.grey[900]!,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 48 : 24,
                vertical: 24,
              ),
              child: Container(
                constraints: BoxConstraints(maxWidth: isTablet ? 380 : 400),
                padding: isTablet ? const EdgeInsets.all(32) : EdgeInsets.zero,
                decoration: isTablet
                    ? BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      )
                    : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: isTablet ? 20 : 40),

                    // 로고
                    Center(
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/logo.png',
                            width: isTablet ? 100 : 120,
                            height: isTablet ? 100 : 120,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'HAIRGATOR',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '헤어 디자이너를 위한 AI 스타일 가이드',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 디버그 정보 (카카오톡 설치 상태)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _kakaoDebugInfo,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          // 에러 메시지 표시
                          if (_lastError != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red),
                              ),
                              child: Text(
                                _lastError!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    SizedBox(height: isTablet ? 32 : 48),

                  // 카카오 로그인 버튼
                  _buildKakaoButton(),

                  const SizedBox(height: 12),

                  // Google 로그인 버튼
                  _buildGoogleButton(),

                  const SizedBox(height: 24),

                  // 구분선
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey[700])),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '또는',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey[700])),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 이메일 입력
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '이메일',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.email, color: Colors.grey[400]),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[700]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFE91E63)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[900],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 비밀번호 입력
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '비밀번호',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.lock, color: Colors.grey[400]),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[700]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFE91E63)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[900],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 로그인/회원가입 버튼
                  _buildEmailButton(),

                  const SizedBox(height: 16),

                  // 모드 전환 버튼
                  TextButton(
                    onPressed: () {
                      setState(() => _isLoginMode = !_isLoginMode);
                    },
                    child: Text(
                      _isLoginMode
                          ? '계정이 없으신가요? 회원가입'
                          : '이미 계정이 있으신가요? 로그인',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ),

                    SizedBox(height: isTablet ? 20 : 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKakaoButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _signInWithKakao,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFEE500), // 카카오 노란색
        foregroundColor: const Color(0xFF191919),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 카카오 아이콘 (심볼)
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFF191919),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'K',
                style: TextStyle(
                  color: Color(0xFFFEE500),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '카카오로 계속하기',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _signInWithGoogle,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.network(
                  'https://www.google.com/favicon.ico',
                  width: 24,
                  height: 24,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.g_mobiledata, size: 24);
                  },
                ),
                const SizedBox(width: 12),
                const Text(
                  'Google로 계속하기',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmailButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _signInWithEmail,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE91E63),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              _isLoginMode ? '로그인' : '회원가입',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
