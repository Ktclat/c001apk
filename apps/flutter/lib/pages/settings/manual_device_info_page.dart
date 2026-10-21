import 'package:flutter/material.dart';

import '../../utils/device_profile.dart';
import '../../utils/storage_util.dart';

/// Edit an existing local device profile without requiring the official app.
class ManualDeviceInfoPage extends StatefulWidget {
  const ManualDeviceInfoPage({super.key});

  @override
  State<ManualDeviceInfoPage> createState() => _ManualDeviceInfoPageState();
}

class _ManualDeviceInfoPageState extends State<ManualDeviceInfoPage> {
  final _id = TextEditingController();
  late final _manufacturer = TextEditingController(text: GStorage.manufacturer);
  late final _brand = TextEditingController(text: GStorage.brand);
  late final _model = TextEditingController(text: GStorage.model);
  late final _build = TextEditingController(text: GStorage.buildNumber);
  late final _sdk = TextEditingController(text: GStorage.sdkInt);
  late final _android = TextEditingController(text: GStorage.androidVersion);
  bool _saving = false;
  bool _saved = false;
  bool _showId = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _manufacturer.dispose();
    _brand.dispose();
    _model.dispose();
    _build.dispose();
    _sdk.dispose();
    _android.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      await GStorage.saveManualDeviceInfo(
        profile: DeviceProfile(
          _manufacturer.text, _brand.text, _model.text,
          _build.text, _sdk.text, _android.text,
        ),
        manualShuzlmId: _id.text,
      );
      if (!mounted) return;
      // Do not leave the entered identifier visible in the widget tree.
      _id.clear();
      setState(() => _saved = true);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，原有标识与参数未被自动清空');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController controller, String key,
      {TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: Key(key),
          controller: controller,
          keyboardType: keyboard,
          enabled: !_saving,
          maxLines: 1,
          autocorrect: false,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: label,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('手动填写设备信息')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('自定义请求设备信息',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('手动填写不需要安装官方酷安。修改后会更新本地请求参数，'
                    '但不能保证解决服务端验证或访问限制。请只填写自己有权使用的信息。'),
                const SizedBox(height: 18),
                TextField(
                  key: const Key('manual-shuzlm-id'),
                  controller: _id,
                  enabled: !_saving,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: !_showId,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: '数盟 ID（可选）',
                    hintText: '留空则保留当前设备标识',
                    helperText: '仅接受单个 ShuzlmID，不要填入 OAID、AndroidID 或 UUID',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      tooltip: _showId ? '隐藏标识' : '显示标识',
                      onPressed: () => setState(() => _showId = !_showId),
                      icon: Icon(_showId
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  GStorage.szlmId.isEmpty
                      ? '尚未保存官方或手动输入的数盟 ID；留空会沿用安装时的设备编码。'
                      : '本机已有数盟 ID；留空将继续使用原值。',
                ),
                const SizedBox(height: 20),
                Text('设备与系统参数',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('以下内容预填了本机当前保存的参数，可按需调整。'
                    '保存时会保留已有的安装标识、账号与本地收藏。'),
                const SizedBox(height: 12),
                _field('制造商', _manufacturer, 'manual-manufacturer'),
                _field('品牌', _brand, 'manual-brand'),
                _field('型号', _model, 'manual-model'),
                _field('系统构建号', _build, 'manual-build'),
                _field('SDK 版本', _sdk, 'manual-sdk',
                    keyboard: TextInputType.number),
                _field('Android 版本', _android, 'manual-android',
                    keyboard: TextInputType.number),
                if (_error != null)
                  Text(_error!, style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
                if (_saved)
                  const Text('已保存。返回页面刷新后生效；输入的数盟 ID 已从表单清除。'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '正在保存…' : '保存并应用'),
                ),
                const SizedBox(height: 12),
                Text('设备标识仅保存在本机并用于请求。'
                    '不要公开真实数盟 ID、完整设备编码或带有账号信息的日志。',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
}
