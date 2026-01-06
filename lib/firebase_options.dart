import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not supported');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  // iOS 설정 (GoogleService-Info.plist에서 추출)
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC0SSTVJpBllZa-lTYWrh2iqSUNwzKD_BA',
    appId: '1:800038006875:ios:c9d40ec75104c3e3e0cf7e',
    messagingSenderId: '800038006875',
    projectId: 'hairgatormenu-4a43e',
    storageBucket: 'hairgatormenu-4a43e.firebasestorage.app',
    iosBundleId: 'com.hairgator',
  );

  // Android 설정 (google-services.json에서 추출)
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBLGRJ_SDYGMveVjkCciuApiuI5sw98PJ8',
    appId: '1:800038006875:android:54bfacf26a453507e0cf7e',
    messagingSenderId: '800038006875',
    projectId: 'hairgatormenu-4a43e',
    storageBucket: 'hairgatormenu-4a43e.firebasestorage.app',
  );
}
