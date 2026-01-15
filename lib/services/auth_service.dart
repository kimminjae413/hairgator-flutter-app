import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 현재 로그인된 사용자
  User? get currentUser => _auth.currentUser;

  // 로그인 상태 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 마지막 Google 로그인 에러 (디버깅용)
  String? lastGoogleError;

  // Google 로그인
  Future<UserCredential?> signInWithGoogle() async {
    lastGoogleError = null;
    try {
      print('[GOOGLE] ========== Google 로그인 시작 ==========');

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        lastGoogleError = '사용자가 로그인을 취소했습니다.';
        print('[GOOGLE] ERROR: $lastGoogleError');
        return null;
      }
      print('[GOOGLE] 1. Google 계정 선택 완료: ${googleUser.email}');

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      print('[GOOGLE] 2. Google Auth 토큰 획득 완료');

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      print('[GOOGLE] 3. Firebase Credential 생성 완료');

      final userCredential = await _auth.signInWithCredential(credential);
      print('[GOOGLE] 4. Firebase 로그인 성공: ${userCredential.user?.uid}');

      // Firestore에 사용자 정보 저장/업데이트
      await _saveUserToFirestore(userCredential.user, provider: 'google');
      print('[GOOGLE] 5. Firestore 저장 완료');

      return userCredential;
    } on FirebaseAuthException catch (e) {
      lastGoogleError = '[${e.code}] ${e.message}';
      print('[GOOGLE] ========== Firebase Auth 에러 ==========');
      print('[GOOGLE] code: ${e.code}');
      print('[GOOGLE] message: ${e.message}');
      return null;
    } catch (e, stackTrace) {
      lastGoogleError = '$e';
      print('[GOOGLE] ========== 일반 에러 ==========');
      print('[GOOGLE] 에러 타입: ${e.runtimeType}');
      print('[GOOGLE] 에러 내용: $e');
      print('[GOOGLE] StackTrace: $stackTrace');
      return null;
    }
  }

  // Apple 로그인 (iOS 필수)
  String? lastAppleError;

  // SHA256 해시 생성 (Apple 로그인용 nonce)
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // 랜덤 nonce 생성
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  Future<UserCredential?> signInWithApple() async {
    lastAppleError = null;

    // iOS에서만 동작
    if (!Platform.isIOS) {
      lastAppleError = 'Apple 로그인은 iOS에서만 지원됩니다.';
      print('[APPLE] ERROR: $lastAppleError');
      return null;
    }

    String? jwtPayload;

    try {
      print('[APPLE] ========== Apple 로그인 시작 ==========');

      // 1. nonce 생성
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);
      print('[APPLE] 1. nonce 생성 완료');
      print('[APPLE] rawNonce: $rawNonce');
      print('[APPLE] hashedNonce: $nonce');

      // 2. Apple 인증 요청
      print('[APPLE] 2. Apple 인증 요청 중...');
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      print('[APPLE] 3. Apple 인증 성공!');
      print('[APPLE] userIdentifier: ${appleCredential.userIdentifier}');
      print('[APPLE] email: ${appleCredential.email}');
      print('[APPLE] authorizationCode: ${appleCredential.authorizationCode.substring(0, 20)}...');

      // 3. Apple ID Token 확인
      final identityToken = appleCredential.identityToken;
      if (identityToken == null) {
        lastAppleError = 'Apple identityToken이 null입니다.';
        print('[APPLE] ERROR: $lastAppleError');
        return null;
      }
      print('[APPLE] 4. identityToken 받음 (길이: ${identityToken.length})');

      // JWT 토큰 디코딩하여 내용 확인
      try {
        final parts = identityToken.split('.');
        if (parts.length == 3) {
          final payload = parts[1];
          final normalized = base64Url.normalize(payload);
          final decoded = utf8.decode(base64Url.decode(normalized));
          jwtPayload = decoded;
          print('[APPLE] JWT Payload: $decoded');
        }
      } catch (e) {
        print('[APPLE] JWT 디코딩 실패: $e');
      }

      // 4. Firebase OAuthCredential 생성 (accessToken에 authorizationCode 필수!)
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );
      print('[APPLE] 5. Firebase OAuthCredential 생성 완료');

      // 5. Firebase 로그인
      print('[APPLE] 6. Firebase 로그인 시도...');
      final userCredential = await _auth.signInWithCredential(oauthCredential);
      print('[APPLE] 7. Firebase 로그인 성공: ${userCredential.user?.uid}');

      // 6. 사용자 이름 업데이트 (Apple은 첫 로그인 시에만 이름 제공)
      final displayName = appleCredential.givenName != null && appleCredential.familyName != null
          ? '${appleCredential.familyName}${appleCredential.givenName}'
          : null;

      if (displayName != null && userCredential.user?.displayName == null) {
        await userCredential.user?.updateDisplayName(displayName);
        print('[APPLE] 8. displayName 업데이트: $displayName');
      }

      // 7. Firestore에 사용자 정보 저장
      print('[APPLE] 9. Firestore 저장...');
      await _saveUserToFirestore(
        userCredential.user,
        provider: 'apple',
        displayName: displayName,
        overrideEmail: appleCredential.email,
      );
      print('[APPLE] 10. 완료!');

      return userCredential;
    } on FirebaseAuthException catch (e) {
      // Firebase Auth 관련 에러 상세 정보
      lastAppleError = '[${e.code}] ${e.message}\n\nJWT: $jwtPayload';
      print('[APPLE] ========== Firebase Auth 에러 ==========');
      print('[APPLE] code: ${e.code}');
      print('[APPLE] message: ${e.message}');
      print('[APPLE] credential: ${e.credential}');
      print('[APPLE] email: ${e.email}');
      print('[APPLE] phoneNumber: ${e.phoneNumber}');
      print('[APPLE] tenantId: ${e.tenantId}');
      return null;
    } catch (e, stackTrace) {
      lastAppleError = '$e\n\nJWT: $jwtPayload';
      print('[APPLE] ========== 일반 에러 ==========');
      print('[APPLE] 에러 타입: ${e.runtimeType}');
      print('[APPLE] 에러 내용: $e');
      print('[APPLE] StackTrace: $stackTrace');
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
