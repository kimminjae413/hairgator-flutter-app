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
      print('[KAKAO] 1. 카카오 로그인 시작');

      // 카카오톡 설치 여부에 따라 로그인 방식 선택
      kakao.OAuthToken token;
      final isInstalled = await kakao.isKakaoTalkInstalled();
      print('[KAKAO] 2. 카카오톡 설치됨: $isInstalled');

      if (isInstalled) {
        // 카카오톡으로 로그인 (앱투앱)
        try {
          print('[KAKAO] 3. 카카오톡 앱으로 로그인 시도...');
          token = await kakao.UserApi.instance.loginWithKakaoTalk();
          print('[KAKAO] 4. 카카오톡 로그인 성공: ${token.accessToken.substring(0, 20)}...');
        } catch (talkError) {
          // 카카오톡 로그인 실패 시 웹 로그인으로 폴백
          print('[KAKAO] 카카오톡 로그인 실패, 웹으로 폴백: $talkError');
          token = await kakao.UserApi.instance.loginWithKakaoAccount();
          print('[KAKAO] 4. 카카오 계정 로그인 성공: ${token.accessToken.substring(0, 20)}...');
        }
      } else {
        // 카카오 계정으로 로그인 (웹뷰)
        print('[KAKAO] 3. 카카오톡 미설치, 카카오 계정으로 로그인 시도...');
        token = await kakao.UserApi.instance.loginWithKakaoAccount();
        print('[KAKAO] 4. 카카오 계정 로그인 성공: ${token.accessToken.substring(0, 20)}...');
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
      await _saveUserToFirestore(
        userCredential.user,
        provider: 'kakao',
        kakaoId: kakaoUser.id,
        displayName: kakaoUser.kakaoAccount?.profile?.nickname,
        photoURL: kakaoUser.kakaoAccount?.profile?.profileImageUrl,
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
  }) async {
    if (user == null) return;

    final email = user.email ?? '';
    final docId = email.isNotEmpty
        ? email.replaceAll('@', '_').replaceAll('.', '_')
        : 'kakao_${kakaoId ?? user.uid}';

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
        'kakaoId': kakaoId,
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
