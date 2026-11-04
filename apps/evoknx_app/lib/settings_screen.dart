import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import 'app_store.dart';
import 'knx_link.dart';
import 'receive_dialog.dart';

/// Settings: theme, KNX connection, another configuration, about.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store, required this.knx});
  final AppStore store;
  final KnxLink knx;

  static const _themes = [('light', 'Sáng'), ('dark', 'Tối'), ('graphite', 'Xám than'), ('sand', 'Kem')];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, knx]),
      builder: (context, _) {
        final pal = AppPalette.of(store.mode);
        Widget card(String title, List<Widget> rows) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 6),
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: pal.muted),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: pal.tile,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: pal.tileEdge),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[rows[i], if (i < rows.length - 1) Divider(height: 1, indent: 16, color: pal.line)],
                  ],
                ),
              ),
            ],
          ),
        );
        Widget row(Widget leading, String text, {String? sub, Widget? trailing, VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text, style: TextStyle(fontSize: 16, color: pal.ink)),
                      if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: TextStyle(fontSize: 13, color: pal.muted))],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        );
        final conns = store.connections;
        final cur = store.connection;
        return Theme(
          data: ThemeData(
            brightness: pal.screen.computeLuminance() < 0.35 ? Brightness.dark : Brightness.light,
            fontFamily: kEvoFont,
            useMaterial3: true,
            colorSchemeSeed: pal.accent,
          ),
          child: Scaffold(
            backgroundColor: pal.screen,
            appBar: AppBar(
              backgroundColor: pal.screen,
              foregroundColor: pal.ink,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: Text(
                'Cài đặt',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.ink),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                card('Giao diện', [
                  for (final (k, n) in _themes)
                    row(
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppPalette.of(k).screen,
                          shape: BoxShape.circle,
                          border: Border.all(color: pal.lineStrong),
                        ),
                      ),
                      n,
                      sub: k == (jsonMap(store.config?['theme'])['mode'] ?? 'light') ? 'Mặc định của dự án' : null,
                      trailing: k == store.mode ? Icon(Icons.check, color: pal.accent) : null,
                      onTap: () => store.setTheme(k),
                    ),
                  row(
                    Icon(Icons.screen_lock_portrait_outlined, color: pal.muted),
                    'Giữ màn hình luôn sáng',
                    sub: 'Dành cho tablet gắn tường',
                    trailing: Switch(value: store.keepScreenOn, onChanged: store.setKeepScreenOn, activeColor: pal.accent),
                  ),
                ]),
                card('Kết nối KNX', [
                  for (final c in conns)
                    row(
                      Icon(Icons.router_outlined, color: pal.muted),
                      (c['name'] ?? 'Kết nối').toString(),
                      sub: '${c['host'] ?? ''}:${c['port'] ?? 3671}${c['natMode'] == true ? ' · NAT' : ''}',
                      trailing: c == cur ? Icon(Icons.check, color: pal.accent) : null,
                      onTap: conns.length > 1
                          ? () async {
                              await store.setConnection(c['id'] as String);
                              await knx.connect();
                            }
                          : null,
                    ),
                  row(
                    Icon(knx.connected ? Icons.link : Icons.link_off, color: knx.connected ? pal.accent : pal.muted),
                    knx.statusText,
                    trailing: TextButton(onPressed: knx.connect, child: Text(knx.connected ? 'Kết nối lại' : 'Thử lại')),
                  ),
                ]),
                card('Cấu hình', [
                  row(
                    Icon(Icons.home_work_outlined, color: pal.muted),
                    store.projectName,
                    sub: 'Phiên bản cấu hình ${jsonMap(store.config?['project'])['revision'] ?? 0}',
                  ),
                  row(
                    Icon(Icons.wifi_tethering, color: pal.muted),
                    'Nhận từ máy tính (Wi-Fi)',
                    sub: 'Editor → menu EVOKNX → Gửi sang App qua Wi-Fi',
                    onTap: () async {
                      final ok = await showReceiveDialog(context, store, pal);
                      if (ok && context.mounted) Navigator.of(context).popUntil((x) => x.isFirst);
                    },
                  ),
                  row(
                    Icon(Icons.folder_open_outlined, color: pal.muted),
                    'Mở file cấu hình khác',
                    sub: 'Chọn file .json xuất từ EVOKNX Editor',
                    onTap: () async {
                      final r = await store.importConfig();
                      if (context.mounted && r != null && r.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r)));
                      } else if (context.mounted && r == null) {
                        Navigator.of(context).popUntil((x) => x.isFirst);
                      }
                    },
                  ),
                ]),
                card('Giới thiệu', [
                  row(Icon(Icons.info_outline, color: pal.muted), 'EVOKNX', sub: 'Phiên bản 0.1.0 · © ${DateTime.now().year} Evohome'),
                  row(Icon(Icons.palette_outlined, color: pal.muted), 'Biểu tượng', sub: 'Material Design Icons · Pictogrammers (Apache 2.0)'),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}
