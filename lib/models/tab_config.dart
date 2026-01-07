/// Firestore app_config/tabs 문서에서 로드하는 탭 설정 모델
class TabConfig {
  final int order;
  final bool enabled;
  final String menuName;
  final String meta;
  final String? url;
  final String? iconLight;
  final String? iconLightSelected;

  TabConfig({
    required this.order,
    required this.enabled,
    required this.menuName,
    required this.meta,
    this.url,
    this.iconLight,
    this.iconLightSelected,
  });

  factory TabConfig.fromFirestore(Map<String, dynamic> data) {
    final iconSet = data['iconSet'] as Map<String, dynamic>?;

    // Admin에서 'label'로 저장, Flutter에서 'menuName'으로 사용
    // Admin에서 'url'을 root에 저장 (module.url 아님)
    return TabConfig(
      order: data['order'] ?? 0,
      enabled: data['enabled'] ?? false,
      menuName: data['label'] ?? data['menuName'] ?? '',
      meta: data['meta'] ?? '',
      url: data['url'],
      iconLight: iconSet?['light'],
      iconLightSelected: iconSet?['light_selected'],
    );
  }
}
