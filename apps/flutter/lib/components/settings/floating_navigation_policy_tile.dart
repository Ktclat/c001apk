import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../utils/floating_navigation_policy.dart';
import '../../utils/storage_util.dart';

class FloatingNavigationPolicyTile extends StatelessWidget {
  const FloatingNavigationPolicyTile({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: GStorage.settings
            .listenable(keys: [SettingsBoxKey.floatingNavigationPolicy]),
        builder: (context, _, __) => ListTile(
          leading: const Icon(Icons.swipe_vertical_outlined),
          title: const Text('悬浮导航隐藏方式'),
          subtitle: Text(GStorage.floatingNavigationPolicy.label),
          onTap: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              scrollable: true,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              title: const Text('悬浮导航隐藏方式'),
              content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(MediaQuery.accessibleNavigationOf(context)
                      ? '系统当前报告无障碍导航需求。自动模式会保持导航可见；这不代表已确认启用某一种无障碍服务。'
                      : '自动模式会尊重系统报告的无障碍导航需求。'),
                  for (final policy in FloatingNavigationPolicy.values)
                    RadioListTile<FloatingNavigationPolicy>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(policy.label),
                      subtitle: Text(switch (policy) {
                        FloatingNavigationPolicy.automatic =>
                          '默认选项。有无障碍导航需求时不随滚动隐藏。',
                        FloatingNavigationPolicy.hideOnScroll =>
                          '由你选择：即使系统报告无障碍需求也收起。手指上推浏览后文时隐藏，下拉回看、回到顶部或切换页面时出现。',
                        FloatingNavigationPolicy.alwaysVisible => '不因滚动隐藏。',
                      }),
                      value: policy,
                      groupValue: GStorage.floatingNavigationPolicy,
                      onChanged: (value) async {
                        if (value == null) return;
                        await GStorage.setFloatingNavigationPolicy(value);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                    ),
                  const Text(
                      '仅作用于已开启的悬浮 Tab 导航；键盘弹出时仍会隐藏。不会修改系统无障碍设置，也无需关闭无障碍服务。'),
                ]),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消'))
              ],
            ),
          ),
        ),
      );
}
