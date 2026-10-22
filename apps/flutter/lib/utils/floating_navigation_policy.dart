/// App-only preference. Never changes platform accessibility settings.
enum FloatingNavigationPolicy {
  automatic(0, '自动（兼顾无障碍）'),
  hideOnScroll(1, '滚动时隐藏'),
  alwaysVisible(2, '始终显示');

  const FloatingNavigationPolicy(this.storageValue, this.label);
  final int storageValue;
  final String label;

  static FloatingNavigationPolicy fromStorage(dynamic value) =>
      values.firstWhere((policy) => policy.storageValue == value,
          orElse: () => automatic);

  String? suppressionReason(bool accessibleNavigation) {
    if (this == alwaysVisible) return 'policy_always_visible';
    if (this == automatic && accessibleNavigation) {
      return 'accessible_navigation';
    }
    return null;
  }
}
