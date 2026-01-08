import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  // 약관 동의 상태
  bool _agreeService = false;
  bool _agreePrivacy = false;
  bool _agreeLocation = false;
  bool _agreeMarketing = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 약관 동의 모달 표시 후 로그인 진행
  Future<void> _showTermsAndLogin(String provider) async {
    // 약관 동의 상태 초기화
    setState(() {
      _agreeService = false;
      _agreePrivacy = false;
      _agreeLocation = false;
      _agreeMarketing = false;
    });

    final agreed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildTermsModal(provider),
    );

    if (agreed == true) {
      // 약관 동의 완료 후 실제 로그인 진행
      if (provider == 'google') {
        await _performGoogleLogin();
      } else if (provider == 'kakao') {
        await _performKakaoLogin();
      }
    }
  }

  Widget _buildTermsModal(String provider) {
    return StatefulBuilder(
      builder: (context, setModalState) {
        final allChecked = _agreeService && _agreePrivacy && _agreeLocation && _agreeMarketing;
        final requiredChecked = _agreeService && _agreePrivacy && _agreeLocation;

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '서비스 이용 동의',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'HAIRGATOR 서비스 이용을 위해 아래 약관에 동의해주세요.',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 24),

              // 전체 동의
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CheckboxListTile(
                  value: allChecked,
                  onChanged: (value) {
                    setModalState(() {
                      _agreeService = value ?? false;
                      _agreePrivacy = value ?? false;
                      _agreeLocation = value ?? false;
                      _agreeMarketing = value ?? false;
                    });
                    setState(() {});
                  },
                  title: const Text(
                    '전체 동의',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  activeColor: const Color(0xFFE91E63),
                  checkColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 개별 약관
              _buildTermsItem(
                '서비스 이용약관 동의',
                true,
                _agreeService,
                (value) {
                  setModalState(() => _agreeService = value ?? false);
                  setState(() {});
                },
                () => _showTermsDetail('service'),
              ),
              _buildTermsItem(
                '개인정보처리방침 동의',
                true,
                _agreePrivacy,
                (value) {
                  setModalState(() => _agreePrivacy = value ?? false);
                  setState(() {});
                },
                () => _showTermsDetail('privacy'),
              ),
              _buildTermsItem(
                '위치기반서비스 이용약관 동의',
                true,
                _agreeLocation,
                (value) {
                  setModalState(() => _agreeLocation = value ?? false);
                  setState(() {});
                },
                () => _showTermsDetail('location'),
              ),
              _buildTermsItem(
                '마케팅 정보 수신 동의',
                false,
                _agreeMarketing,
                (value) {
                  setModalState(() => _agreeMarketing = value ?? false);
                  setState(() {});
                },
                null,
              ),

              const SizedBox(height: 24),

              // 동의하고 시작하기 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: requiredChecked
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE91E63),
                    disabledBackgroundColor: Colors.grey[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '동의하고 시작하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTermsItem(
    String title,
    bool required,
    bool value,
    ValueChanged<bool?> onChanged,
    VoidCallback? onViewTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFFE91E63),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(!value),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(color: Colors.grey[300], fontSize: 14),
                  children: [
                    TextSpan(text: title),
                    if (required)
                      const TextSpan(
                        text: ' (필수)',
                        style: TextStyle(color: Color(0xFFE91E63)),
                      )
                    else
                      TextSpan(
                        text: ' (선택)',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (onViewTap != null)
            TextButton(
              onPressed: onViewTap,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: Text(
                '보기',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  void _showTermsDetail(String type) {
    final titles = {
      'service': '서비스 이용약관',
      'privacy': '개인정보처리방침',
      'location': '위치기반서비스 이용약관',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    titles[type] ?? '약관',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.grey),
            Expanded(
              child: FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('terms')
                    .doc(type == 'service' ? 'terms' : type)
                    .get(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFFE91E63)),
                    );
                  }

                  String content = '약관 내용을 불러오는 중...';
                  if (snapshot.hasData && snapshot.data!.exists) {
                    content = snapshot.data!.get('content') ?? content;
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      content,
                      style: TextStyle(color: Colors.grey[300], fontSize: 14, height: 1.6),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performGoogleLogin() async {
    setState(() => _isLoading = true);

    final result = await _authService.signInWithGoogle();

    if (result != null && mounted) {
      // 약관 동의 정보 저장
      await _saveTermsAgreement(result.user?.uid, result.user?.email);
      _navigateToHome();
    } else {
      setState(() => _isLoading = false);
      _showError('Google 로그인에 실패했습니다.');
    }
  }

  Future<void> _performKakaoLogin() async {
    setState(() => _isLoading = true);

    final result = await _authService.signInWithKakao();

    if (result != null && mounted) {
      // 약관 동의 정보 저장
      await _saveTermsAgreement(result.user?.uid, result.user?.email);
      _navigateToHome();
    } else {
      setState(() => _isLoading = false);
      _showError('카카오 로그인에 실패했습니다.');
    }
  }

  Future<void> _saveTermsAgreement(String? uid, String? email) async {
    if (uid == null) return;

    try {
      // 이메일 기반 문서 ID
      String docId = uid;
      if (email != null && email.isNotEmpty) {
        docId = email.toLowerCase().replaceAll('@', '_').replaceAll('.', '_');
      }

      await FirebaseFirestore.instance.collection('users').doc(docId).set({
        'termsAgreement': {
          'service': _agreeService,
          'privacy': _agreePrivacy,
          'location': _agreeLocation,
          'marketing': _agreeMarketing,
          'agreedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      print('[LoginScreen] 약관 동의 저장 완료: $docId');
    } catch (e) {
      print('[LoginScreen] 약관 동의 저장 실패: $e');
    }
  }

  Future<void> _signInWithGoogle() async {
    await _showTermsAndLogin('google');
  }

  Future<void> _signInWithKakao() async {
    await _showTermsAndLogin('kakao');
  }

  Future<void> _signInWithEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('이메일과 비밀번호를 입력해주세요.');
      return;
    }

    // 회원가입 모드일 때만 약관 동의 필요
    if (!_isLoginMode) {
      // 약관 동의 상태 초기화
      setState(() {
        _agreeService = false;
        _agreePrivacy = false;
        _agreeLocation = false;
        _agreeMarketing = false;
      });

      final agreed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _buildTermsModal('email'),
      );

      if (agreed != true) return;
    }

    setState(() => _isLoading = true);

    final result = _isLoginMode
        ? await _authService.signInWithEmail(email, password)
        : await _authService.signUpWithEmail(email, password);

    if (result != null && mounted) {
      // 회원가입 시 약관 동의 저장
      if (!_isLoginMode) {
        await _saveTermsAgreement(result.user?.uid, email);
      }
      _navigateToHome();
    } else {
      setState(() => _isLoading = false);
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
