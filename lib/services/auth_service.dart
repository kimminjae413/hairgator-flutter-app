import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:http/http.dart' as http;

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 현재 로그인된 사용자
  User? get currentUser => _auth.currentUser;

  // 로그인 상태 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Google 로그인
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      // Firestore에 사용자 정보 저장/업데이트
      await _saveUserToFirestore(userCredential.user, provider: 'google');

      return userCredential;
    } catch (e) {
      print('Google 로그인 에러: $e');
      return null;
    }
  }

  // 카카오 로그인
  // 마지막 카카오 로그인 에러 (디버깅용)
  String? lastKakaoError;

  Future<UserCredential?> signInWithKakao() async {
    lastKakaoError = null;
    try {
      print('[KAKAO] ========== v59 카카오 로그인 시작 ==========');

      kakao.OAuthToken? token;

      // 1. 카카오톡 앱 로그인 먼저 시도
      try {
        final isKakaoTalkInstalled = await kakao.isKakaoTalkInstalled();
        print('[KAKAO] 카카오톡 설치 여부: $isKakaoTalkInstalled');

        if (isKakaoTalkInstalled) {
          print('[KAKAO] 카카오톡 앱 로그인 시도 중...');
          token = await kakao.UserApi.instance.loginWithKakaoTalk();
          print('[KAKAO] ✅ 카카오톡 앱 로그인 성공! accessToken: ${token.accessToken.substring(0, 10)}...');
        } else {
          print('[KAKAO] ⚠️ 카카오톡 미설치 - 웹 로그인 필요');
        }
      } catch (e, stackTrace) {
        print('[KAKAO] ❌ 카카오톡 앱 로그인 실패');
        print('[KAKAO] 에러 타입: ${e.runtimeType}');
        print('[KAKAO] 에러 메시지: $e');
        print('[KAKAO] 스택: $stackTrace');
        token = null;
      }

      // 2. 앱 로그인 실패 시 웹 로그인으로 폴백
      if (token == null) {
        print('[KAKAO] 웹 로그인으로 폴백...');
        try {
          token = await kakao.UserApi.instance.loginWithKakaoAccount()
              .timeout(const Duration(seconds: 120), onTimeout: () {
            throw Exception('카카오 웹 로그인 타임아웃 (120초)');
          });
          print('[KAKAO] 웹 로그인 성공! accessToken: ${token.accessToken.substring(0, 10)}...');
        } catch (e) {
          print('[KAKAO] 웹 로그인도 실패: $e');
          lastKakaoError = '카카오 웹 로그인 실패: $e';
          return null;
        }
      }

      // 카카오 사용자 정보 가져오기
      print('[KAKAO] 5. 사용자 정보 가져오기...');
      final kakaoUser = await kakao.UserApi.instance.me();
      print('[KAKAO] 6. 사용자 정보: id=${kakaoUser.id}, email=${kakaoUser.kakaoAccount?.email}');

      // 서버에서 Firebase Custom Token 받아오기
      print('[KAKAO] 7. Firebase Custom Token 요청...');
      final customToken = await _getFirebaseCustomToken(
        kakaoAccessToken: token.accessToken,
        kakaoId: kakaoUser.id.toString(),
        email: kakaoUser.kakaoAccount?.email,
        nickname: kakaoUser.kakaoAccount?.profile?.nickname,
        profileImage: kakaoUser.kakaoAccount?.profile?.profileImageUrl,
      );

      if (customToken == null) {
        lastKakaoError = 'Firebase Custom Token 생성 실패 (서버 응답 없음)';
        print('[KAKAO] ERROR: $lastKakaoError');
        return null;
      }
      print('[KAKAO] 8. Custom Token 받음: ${customToken.substring(0, 20)}...');

      // Firebase Custom Token으로 로그인
      print('[KAKAO] 9. Firebase 로그인 시도...');
      final userCredential = await _auth.signInWithCustomToken(customToken);
      print('[KAKAO] 10. Firebase 로그인 성공: ${userCredential.user?.uid}');

      // Firestore에 사용자 정보 저장/업데이트
      print('[KAKAO] 11. Firestore 저장...');
      final kakaoEmail = kakaoUser.kakaoAccount?.email;
      print('[KAKAO] 카카오 이메일: $kakaoEmail');
      await _saveUserToFirestore(
        userCredential.user,
        provider: 'kakao',
        kakaoId: kakaoUser.id,
        displayName: kakaoUser.kakaoAccount?.profile?.nickname,
        photoURL: kakaoUser.kakaoAccount?.profile?.profileImageUrl,
        overrideEmail: kakaoEmail, // 카카오 이메일로 기존 사용자 매칭
      );
      print('[KAKAO] 12. 완료!');

      return userCredential;
    } catch (e, stackTrace) {
      lastKakaoError = '카카오 로그인 에러: $e';
      print('[KAKAO] ERROR: $lastKakaoError');
      print('[KAKAO] StackTrace: $stackTrace');
      return null;
    }
  }

  // 서버에서 Firebase Custom Token 받아오기
  Future<String?> _getFirebaseCustomToken({
    required String kakaoAccessToken,
    required String kakaoId,
    String? email,
    String? nickname,
    String? profileImage,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://app.hairgator.kr/.netlify/functions/kakao-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'kakaoAccessToken': kakaoAccessToken,
          'kakaoId': kakaoId,
          'email': email,
          'nickname': nickname,
          'profileImage': profileImage,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['customToken'];
      } else {
        print('Custom Token API 에러: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('Custom Token 요청 에러: $e');
      return null;
    }
  }

  // 이메일/비밀번호 로그인
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _saveUserToFirestore(userCredential.user, provider: 'email');
      return userCredential;
    } catch (e) {
      print('이메일 로그인 에러: $e');
      return null;
    }
  }

  // 이메일/비밀번호 회원가입
  Future<UserCredential?> signUpWithEmail(String email, String password) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _saveUserToFirestore(userCredential.user, provider: 'email', isNewUser: true);
      return userCredential;
    } catch (e) {
      print('회원가입 에러: $e');
      return null;
    }
  }

  // Firestore에 사용자 정보 저장
  Future<void> _saveUserToFirestore(
    User? user, {
    String provider = 'unknown',
    bool isNewUser = false,
    int? kakaoId,
    String? displayName,
    String? photoURL,
    String? overrideEmail, // 카카오 등 소셜 로그인 시 이메일 직접 전달
  }) async {
    if (user == null) return;

    // 이메일 우선순위: overrideEmail > user.email
    final email = overrideEmail ?? user.email ?? '';

    // 1. 카카오 로그인인 경우 - kakao-token 서버에서 이미 처리했으므로 스킵
    // (서버에서 kakaoId로 기존 사용자 매칭 로직 수행)
    if (provider == 'kakao') {
      print('[Firestore] 카카오 로그인 - 서버에서 이미 사용자 문서 처리됨');
      return;
    }

    // 2. 일반 로그인 (Google, Email)
    final docId = email.isNotEmpty
        ? email.replaceAll('@', '_').replaceAll('.', '_')
        : user.uid;

    print('[Firestore] 사용자 저장 - email: $email, docId: $docId');

    final userDoc = _firestore.collection('users').doc(docId);
    final docSnapshot = await userDoc.get();

    if (!docSnapshot.exists) {
      // 신규 사용자
      await userDoc.set({
        'uid': user.uid,
        'email': email,
        'displayName': displayName ?? user.displayName ?? '',
        'photoURL': photoURL ?? user.photoURL ?? '',
        'provider': provider,
        'tokenBalance': 200, // 신규 가입 시 200 토큰
        'plan': 'free',
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    } else {
      // 기존 사용자 - 마지막 로그인 시간만 업데이트
      await userDoc.update({
        'lastLoginAt': FieldValue.serverTimestamp(),
        if (displayName != null) 'displayName': displayName,
        if (photoURL != null) 'photoURL': photoURL,
      });
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      // 카카오 로그아웃
      if (await kakao.AuthApi.instance.hasToken()) {
        await kakao.UserApi.instance.logout();
      }
    } catch (e) {
      print('카카오 로그아웃 에러: $e');
    }
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // 사용자 ID 가져오기 (Firestore 문서 ID)
  String? getUserDocId() {
    final email = currentUser?.email;
    if (email == null || email.isEmpty) {
      // 카카오 로그인의 경우 uid 사용
      return currentUser?.uid;
    }
    return email.replaceAll('@', '_').replaceAll('.', '_');
  }
}
