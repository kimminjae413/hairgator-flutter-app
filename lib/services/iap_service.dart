// lib/services/iap_service.dart
// iOS 인앱결제 서비스

import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class IAPService {
  static final IAPService _instance = IAPService._internal();
  factory IAPService() => _instance;
  IAPService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;

  // 구매 상태 스트림
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // 상품 ID (App Store Connect에서 생성한 것과 일치해야 함)
  static const Set<String> _productIds = {
    'hairgator_basic',      // 베이직 22,000원 -> 10,000 토큰
    'hairgator_pro',        // 프로 38,000원 -> 18,000 토큰
    'hairgator_business',   // 비즈니스 50,000원 -> 25,000 토큰
    'hairgator_tokens_5000', // 추가 토큰 5,000원 -> 5,000 토큰
  };

  // 상품 정보
  List<ProductDetails> products = [];

  // 구매 완료 콜백
  Function(String productId, int tokens, String? receipt)? onPurchaseSuccess;
  Function(String error)? onPurchaseError;

  // 현재 사용자 ID (서버 영수증 검증에 사용)
  String? currentUserId;

  // 이미 처리된 구매 ID (중복 콜백 방지)
  final Set<String> _processedPurchaseIds = {};

  // 상품별 토큰 수
  static const Map<String, int> productTokens = {
    'hairgator_basic': 10000,
    'hairgator_pro': 18000,
    'hairgator_business': 25000,
    'hairgator_tokens_5000': 5000,
  };

  // 상품별 이름
  static const Map<String, String> productNames = {
    'hairgator_basic': '베이직',
    'hairgator_pro': '프로',
    'hairgator_business': '비즈니스',
    'hairgator_tokens_5000': '추가 토큰 5,000',
  };

  /// 초기화
  Future<bool> initialize() async {
    // iOS가 아니면 초기화하지 않음
    if (!Platform.isIOS) {
      print('[IAP] iOS가 아니므로 인앱결제 비활성화');
      return false;
    }

    final available = await _iap.isAvailable();
    if (!available) {
      print('[IAP] 인앱결제를 사용할 수 없습니다');
      return false;
    }

    print('[IAP] 인앱결제 초기화 시작');

    // 기존 구독이 있으면 먼저 취소 (중복 리스너 방지)
    await _subscription?.cancel();
    _subscription = null;

    // 구매 스트림 리스너 등록
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) => print('[IAP] 구매 스트림 에러: $error'),
    );

    // 상품 정보 로드
    await loadProducts();

    print('[IAP] 인앱결제 초기화 완료');
    return true;
  }

  /// 상품 정보 로드
  Future<void> loadProducts() async {
    try {
      final response = await _iap.queryProductDetails(_productIds);

      if (response.notFoundIDs.isNotEmpty) {
        print('[IAP] 찾을 수 없는 상품: ${response.notFoundIDs}');
      }

      products = response.productDetails;
      print('[IAP] 로드된 상품: ${products.map((p) => p.id).toList()}');

      for (final product in products) {
        print('[IAP] - ${product.id}: ${product.title} (${product.price})');
      }
    } catch (e) {
      print('[IAP] 상품 로드 오류: $e');
    }
  }

  /// 구매 요청
  Future<bool> purchase(String productId) async {
    print('[IAP] ⭐⭐⭐ purchase() 호출됨: $productId');

    if (!Platform.isIOS) {
      print('[IAP] iOS가 아니므로 구매 불가');
      onPurchaseError?.call('iOS에서만 인앱결제가 가능합니다.');
      return false;
    }

    // ⭐ 디버그: _iap 상태 확인
    print('[IAP] InAppPurchase instance: $_iap');
    final isAvailable = await _iap.isAvailable();
    print('[IAP] isAvailable: $isAvailable');

    if (!isAvailable) {
      print('[IAP] ❌ 인앱결제를 사용할 수 없음!');
      onPurchaseError?.call('인앱결제를 사용할 수 없습니다.');
      return false;
    }

    try {
      // 상품 찾기
      print('[IAP] 상품 목록에서 검색: ${products.map((p) => p.id).toList()}');
      final product = products.firstWhere(
        (p) => p.id == productId,
        orElse: () => throw Exception('상품을 찾을 수 없습니다: $productId'),
      );

      print('[IAP] 상품 찾음: ${product.id} (${product.price})');
      print('[IAP] 상품 상세: title=${product.title}, description=${product.description}');

      // 구매 파라미터 생성 (비갱신 구독)
      final purchaseParam = PurchaseParam(productDetails: product);
      print('[IAP] PurchaseParam 생성 완료');

      // 구매 시작 (비갱신 구독은 buyNonConsumable 사용)
      print('[IAP] ⭐ buyNonConsumable 호출 직전...');
      final success = await _iap.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      print('[IAP] ⭐ buyNonConsumable 결과: $success');

      if (success) {
        print('[IAP] ✅ buyNonConsumable true! purchaseStream 대기 중...');
        onDebugMessage?.call('🎯 buyNonConsumable=true, 스트림 대기...', const Color(0xFF00BCD4));
      } else {
        print('[IAP] ❌ buyNonConsumable이 false 반환!');
        onDebugMessage?.call('❌ buyNonConsumable=false!', const Color(0xFFF44336));
        onPurchaseError?.call('구매 요청이 실패했습니다.');
      }

      return success;
    } catch (e, stackTrace) {
      print('[IAP] ❌ 구매 요청 오류: $e');
      print('[IAP] 스택 트레이스: $stackTrace');
      onPurchaseError?.call(e.toString());
      return false;
    }
  }

  // ⭐ 디버그: 스낵바 표시용 콜백 (home_screen에서 설정)
  Function(String message, Color color)? onDebugMessage;

  /// 구매 업데이트 처리
  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    print('[IAP] ⭐⭐⭐ _onPurchaseUpdate 호출됨! purchases: ${purchases.length}개');
    onDebugMessage?.call('📥 purchaseStream 수신: ${purchases.length}개', const Color(0xFF9C27B0));

    for (final purchase in purchases) {
      print('[IAP] 구매 상태: ${purchase.productID} - ${purchase.status}');
      onDebugMessage?.call('📦 ${purchase.productID}: ${purchase.status}', const Color(0xFF673AB7));

      switch (purchase.status) {
        case PurchaseStatus.pending:
          print('[IAP] 구매 대기 중...');
          onDebugMessage?.call('⏳ 결제 대기 중... (pending)', const Color(0xFFFF9800));
          break;

        case PurchaseStatus.purchased:
          _handleSuccessfulPurchase(purchase);
          break;

        case PurchaseStatus.restored:
          // Consumable products should not be restored
          print('[IAP] Ignoring restore: ${purchase.productID}');
          _completePurchase(purchase);
          break;

        case PurchaseStatus.error:
          print('[IAP] 구매 오류: ${purchase.error?.message}');
          onPurchaseError?.call(purchase.error?.message ?? '구매 중 오류가 발생했습니다.');
          _completePurchase(purchase);
          break;

        case PurchaseStatus.canceled:
          print('[IAP] 구매 취소됨');
          onPurchaseError?.call('구매가 취소되었습니다.');
          _completePurchase(purchase);
          break;
      }
    }
  }

  /// 구매 성공 처리
  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchase) async {
    // 중복 처리 방지
    final purchaseId = purchase.purchaseID ?? purchase.productID + DateTime.now().toString();
    if (_processedPurchaseIds.contains(purchaseId)) {
      print('[IAP] 이미 처리된 구매, 스킵: $purchaseId');
      await _completePurchase(purchase);
      return;
    }
    _processedPurchaseIds.add(purchaseId);
    
    print('[IAP] 구매 성공: ${purchase.productID}');

    // 영수증 가져오기
    String? receipt;
    if (purchase.verificationData.serverVerificationData.isNotEmpty) {
      receipt = purchase.verificationData.serverVerificationData;
      print('[IAP] 영수증 데이터 있음 (${receipt.length} bytes)');
    }

    // 토큰 수 계산
    final tokens = productTokens[purchase.productID] ?? 0;

    // 서버에 영수증 검증 요청 (선택적)
    final verified = await _verifyReceiptOnServer(
      purchase.productID,
      receipt ?? '',
    );

    if (verified) {
      // 구매 성공 콜백 호출
      onPurchaseSuccess?.call(purchase.productID, tokens, receipt);
    } else {
      onPurchaseError?.call('영수증 검증에 실패했습니다.');
    }

    // 구매 완료 처리
    await _completePurchase(purchase);
  }

  /// 구매 완료 처리 (Apple에 알림)
  Future<void> _completePurchase(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
      print('[IAP] 구매 완료 처리됨: ${purchase.productID}');
    }
  }

  /// 서버에서 영수증 검증 및 토큰 충전
  Future<bool> _verifyReceiptOnServer(String productId, String receipt) async {
    try {
      print('[IAP] 서버 영수증 검증 요청...');
      print('[IAP] userId: $currentUserId');

      final response = await http.post(
        Uri.parse('https://app.hairgator.kr/.netlify/functions/iap-verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'productId': productId,
          'receipt': receipt,
          'platform': 'ios',
          'userId': currentUserId, // 사용자 ID 전달
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('[IAP] 서버 검증 성공: $data');
        return data['success'] == true;
      } else {
        print('[IAP] 서버 검증 실패: ${response.statusCode}');
        // 서버 검증 실패 시 거부
        return false;
      }
    } catch (e) {
      print('[IAP] 서버 검증 오류: $e');
      // 네트워크 오류 시 거부
      return false;
    }
  }

  /// 이전 구매 복원 (구독 앱용, 소모성 상품에는 불필요)
  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  /// 리소스 해제
  void dispose() {
    _subscription?.cancel();
  }

  /// 특정 상품 정보 가져오기
  ProductDetails? getProduct(String productId) {
    try {
      return products.firstWhere((p) => p.id == productId);
    } catch (e) {
      return null;
    }
  }

  /// iOS인지 확인
  static bool get isAvailable => Platform.isIOS;
}
