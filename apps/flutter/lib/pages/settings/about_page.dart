import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../constants/constants.dart';
import '../../utils/navigation_diagnostics.dart';
import 'navigation_diagnostics_page.dart';
import '../../components/app_logo.dart';
import '../../components/update_check_tile.dart';
import '../../utils/utils.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final version = Get.parameters['version'] ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
        leading: const BackButton(),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: AppLogo(size: 96)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.all_inclusive),
            title: const Text(Constants.APP_NAME),
            subtitle: const Text('一个轻量的非官方酷安客户端'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('版本'),
            subtitle: Text(version),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.build_outlined),
            title: const Text('构建与悬浮导航诊断'),
            subtitle: Text(NavigationBuildIdentity.label),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const NavigationDiagnosticsPage())),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('项目地址'),
            subtitle: const Text(Constants.URL_SOURCE_CODE),
            onTap: () => Utils.launchURL(Constants.URL_SOURCE_CODE),
          ),
          const UpdateCheckTile(),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('项目许可证 · AGPL-3.0'),
            subtitle: const Text('查看本仓库保留的完整 GNU AGPL-3.0 文本'),
            onTap: () => Utils.launchURL(
                '${Constants.URL_SOURCE_CODE}/blob/main/LICENSE'),
          ),
          ListTile(
            leading: const Icon(Icons.source_outlined),
            title: const Text('Flutter 及依赖许可证'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: Constants.APP_NAME,
              applicationVersion: version,
              applicationLegalese: 'GNU AGPL-3.0 · 保留原作者与第三方版权声明',
              applicationIcon: const AppLogo(),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('问题反馈'),
            subtitle: const Text('在本项目仓库提交问题或功能建议'),
            onTap: () => Utils.launchURL('${Constants.URL_SOURCE_CODE}/issues'),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('来源与致谢'),
            subtitle: const Text('保留原维护者署名与第三方授权声明'),
            onTap: () => Utils.launchURL(
                '${Constants.URL_SOURCE_CODE}/blob/main/docs/THIRD_PARTY_NOTICES.md'),
          ),
        ],
      ),
    );
  }
}
