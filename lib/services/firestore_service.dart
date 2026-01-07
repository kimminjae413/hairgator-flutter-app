import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tab_config.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Firestore app_config/tabs 문서에서 탭 설정 로드
  Future<List<TabConfig>> loadTabConfigs() async {
    try {
      print('[FirestoreService] 탭 설정 로드 시작...');
      final doc = await _firestore.collection('app_config').doc('tabs').get();

      if (!doc.exists) {
        print('[FirestoreService] app_config/tabs 문서 없음, 기본값 사용');
        return _getDefaultTabs();
      }

      final data = doc.data()!;
      print('[FirestoreService] 탭 데이터 로드됨: ${data.keys.toList()}');

      final List<TabConfig> tabs = [];

      // tab1, tab2, tab3, tab4 필드 읽기
      for (int i = 1; i <= 4; i++) {
        final tabData = data['tab$i'] as Map<String, dynamic>?;
        if (tabData != null) {
          print('[FirestoreService] tab$i: label=${tabData['label']}, enabled=${tabData['enabled']}, url=${tabData['url']}');
          final tab = TabConfig.fromFirestore(tabData);
          if (tab.enabled) {
            tabs.add(tab);
            print('[FirestoreService] tab$i 추가됨: ${tab.menuName}');
          } else {
            print('[FirestoreService] tab$i 비활성화됨, 스킵');
          }
        }
      }

      // order 기준 정렬
      tabs.sort((a, b) => a.order.compareTo(b.order));
      print('[FirestoreService] 최종 탭 수: ${tabs.length}');
      return tabs;
    } catch (e) {
      print('[FirestoreService] 탭 로드 오류: $e');
      return _getDefaultTabs();
    }
  }

  /// 기본 탭 설정 (Firestore 연결 실패 시)
  List<TabConfig> _getDefaultTabs() {
    return [
      TabConfig(
        order: 1,
        enabled: true,
        menuName: 'Style Menu',
        meta: 'styleMenuTab',
        url: 'https://app.hairgator.kr',
      ),
      TabConfig(
        order: 3,
        enabled: true,
        menuName: '상품',
        meta: 'pkg_iamportPayment_productMulti',
        url: 'https://app.hairgator.kr/#products',
      ),
      TabConfig(
        order: 4,
        enabled: true,
        menuName: 'My',
        meta: 'myPage',
        url: 'https://app.hairgator.kr/#mypage',
      ),
    ];
  }
}
