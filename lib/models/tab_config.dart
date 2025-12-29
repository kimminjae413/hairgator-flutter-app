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
    final module = data['module'] as Map<String, dynamic>?;
    final iconSet = data['iconSet'] as Map<String, dynamic>?;

    return TabConfig(
      order: data['order'] ?? 0,
      enabled: data['enabled'] ?? false,
      menuName: data['menuName'] ?? '',
      meta: data['meta'] ?? '',
      url: module?['url'],
      iconLight: iconSet?['light'],
      iconLightSelected: iconSet?['light_selected'],
    );
  }
}
