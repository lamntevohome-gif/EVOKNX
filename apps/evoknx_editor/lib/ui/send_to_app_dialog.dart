import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;
import 'package:flutter/services.dart';
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// "Gửi sang App qua Wi-Fi": while open, the Editor serves the configuration
/// to Apps on the same network that enter the code shown here.
Future<void> showSendToAppDialog(BuildContext context, ProjectController p) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SendDialog(p: p),
);

class _SendDialog extends StatefulWidget {
  const _SendDialog({required this.p});
  final ProjectController p;
  @override
  State<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<_SendDialog> {
  late final LanShareServer share = LanShareServer(widget.p.appConfig);
  String? error;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    share.onChanged = () {
      if (mounted) setState(() {});
    };
    share.start().then((e) {
      if (mounted) {
        setState(() {
          error = e;
          ready = true;
        });
      }
    });
  }

  @override
  void dispose() {
    share.onChanged = null;
    share.stop();
    super.dispose();
  }

  String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final code = share.code.length == 6 ? '${share.code.substring(0, 3)} ${share.code.substring(3)}' : share.code;
    Widget box(String label, Widget value) => Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: kUiText - 1, color: c.muted),
          ),
          const SizedBox(height: 4),
          value,
        ],
      ),
    );
    return AlertDialog(
      title: const Text('Gửi sang App qua Wi-Fi'),
      content: SizedBox(
        width: 460,
        child: !ready
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : error != null
            ? Text(error!, style: TextStyle(color: c.danger))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Trên điện thoại (cùng Wi-Fi với máy tính này): mở App EvoKNX → Cài đặt → Mở cấu hình khác → Nhận từ máy tính, rồi nhập địa chỉ và mã dưới đây.',
                    style: TextStyle(height: 1.45, color: c.muted),
                  ),
                  const SizedBox(height: 14),
                  box(
                    'Mã (hết hạn sau 15 phút)',
                    Row(
                      children: [
                        Expanded(
                          child: Text(code, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 3)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  box(
                    'Địa chỉ máy tính',
                    share.addresses.isEmpty
                        ? Text('Không tìm thấy địa chỉ mạng. Kiểm tra máy tính đã kết nối Wi-Fi hoặc mạng LAN.', style: TextStyle(color: c.danger))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final a in share.addresses)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: '${a.ip}:${share.port}',
                                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                                            ),
                                            TextSpan(
                                              text: '   ${a.interfaceName}',
                                              style: TextStyle(fontSize: kUiText - 1, color: c.muted),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: tr('Chép địa chỉ'),
                                      icon: const Icon(Icons.copy_outlined),
                                      onPressed: () => Clipboard.setData(ClipboardData(text: '${a.ip}:${share.port}')),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        share.locked || share.expired ? Icons.lock_outline : (share.sent > 0 ? Icons.check_circle_outline : Icons.hourglass_empty),
                        size: 18,
                        color: share.locked || share.expired ? c.danger : (share.sent > 0 ? const Color(0xFF14AE5C) : c.muted),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          share.locked
                              ? 'Đã khoá vì nhập sai mã nhiều lần. Đóng và mở lại để lấy mã mới.'
                              : share.expired
                              ? 'Mã đã hết hạn. Đóng và mở lại để lấy mã mới.'
                              : share.sent > 0
                              ? 'Đã gửi ${share.sent} lần (lần cuối lúc ${_hm(share.lastSentAt!)}). Có thể gửi tiếp cho máy khác.'
                              : 'Đang chờ App nhận…',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Lần đầu dùng, Windows có thể hỏi về tường lửa: chọn Cho phép trên mạng riêng tư. Cấu hình có chứa mật khẩu camera, chỉ gửi trong mạng nhà và chỉ cho máy nhập đúng mã.',
                    style: TextStyle(fontSize: kUiText - 1, height: 1.4, color: c.muted),
                  ),
                ],
              ),
      ),
      actions: [EvoButton(label: 'Đóng', primary: true, onPressed: () => Navigator.pop(context))],
    );
  }
}
