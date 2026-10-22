import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/navigation_diagnostics.dart';

class NavigationDiagnosticsPage extends StatefulWidget {
  const NavigationDiagnosticsPage({super.key});
  @override
  State<NavigationDiagnosticsPage> createState() =>
      _NavigationDiagnosticsPageState();
}

class _NavigationDiagnosticsPageState extends State<NavigationDiagnosticsPage> {
  final recorder = NavigationDiagnostics.instance;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('悬浮导航诊断')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          SelectableText(NavigationBuildIdentity.label),
          const SizedBox(height: 12),
          if (NavigationBuildIdentity.diagnostic)
            const Text(
                '这是独立诊断版，不读取原应用的设置或账号。请先在「设置 → 外观与字体」开启悬浮 Tab 导航；无需登录，不要关闭需要的无障碍功能。'),
          const Text('仅在本机内存记录最近 60 个滚动信号，不含账号、内容或设备标识，不会自动上传。不写入磁盘，进程结束后清除。'),
          const SizedBox(height: 8),
          const Text(
              '1. 开始记录。\n2. 返回首页「动态」，手指向上推列表，浏览更后面的内容。\n3. 返回此页，停止并查看，再按需复制报告。\n记录中的滚动信号不等于已证明真实触摸；程序跳转与惯性更新会分别保留原始特征。'),
          Wrap(spacing: 8, children: [
            FilledButton(
                onPressed: () => setState(recorder.start),
                child: const Text('开始新记录')),
            OutlinedButton(
                onPressed: () => setState(() => recorder.recording = false),
                child: const Text('停止并查看')),
            TextButton(
                onPressed: () => setState(recorder.clear),
                child: const Text('清空记录')),
            TextButton(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: recorder.report()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制诊断报告，不会自动发送')));
                  }
                },
                child: const Text('复制报告')),
          ]),
          Text(recorder.recording ? '正在记录（仅内存）' : '未在记录'),
          const SizedBox(height: 12),
          SelectableText(recorder.report(),
              style: const TextStyle(fontSize: 12)),
        ]),
      );
}
