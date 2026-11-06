import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import 'account_panel.dart';
import 'app_store.dart';
import 'knx_link.dart';
import 'receive_dialog.dart';

/// Settings: theme, KNX connection, another configuration, about.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store, required this.knx});
  final AppStore store;
  final KnxLink knx;

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
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: pal.sMuted),
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
        Widget tab(List<Widget> cards) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: cards);
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
            brightness: pal.sInk.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
            fontFamily: kEvoFont,
            useMaterial3: true,
            colorSchemeSeed: pal.accent,
          ),
          child: DefaultTabController(
            length: 5,
            child: Scaffold(
              backgroundColor: pal.screen,
              appBar: AppBar(
                backgroundColor: pal.screen,
                foregroundColor: pal.sInk,
                elevation: 0,
                scrolledUnderElevation: 0,
                title: Text(
                  'Cài đặt',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.sInk),
                ),
                bottom: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: pal.accent,
                  labelColor: pal.sInk,
                  unselectedLabelColor: pal.sMuted,
                  dividerColor: pal.line,
                  labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  tabs: const [
                    Tab(text: 'Tài khoản'),
                    Tab(text: 'Hồ sơ'),
                    Tab(text: 'Giao diện'),
                    Tab(text: 'Kết nối KNX'),
                    Tab(text: 'Giới thiệu'),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  tab([AccountPanel(account: store.account, pal: pal)]),
                  tab([
                    card('Hồ sơ', [
                      for (final pf in store.profiles)
                        row(
                          Icon(pf.id == store.activeId ? Icons.home : Icons.home_outlined, color: pf.id == store.activeId ? pal.accent : pal.muted),
                          pf.name,
                          sub: pf.id == store.activeId
                              ? 'Đang dùng · phiên bản cấu hình ${jsonMap(store.config?['project'])['revision'] ?? 0}'
                              : 'Bấm để chuyển sang nhà này',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (pf.id != store.activeId)
                                TextButton(
                                  onPressed: () async {
                                    await store.switchProfile(pf.id);
                                    if (context.mounted) Navigator.of(context).popUntil((x) => x.isFirst);
                                  },
                                  child: Text(
                                    'Chuyển',
                                    style: TextStyle(color: pal.accent, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              PopupMenuButton<String>(
                                tooltip: 'Tuỳ chọn',
                                icon: Icon(Icons.more_vert, color: pal.muted),
                                color: pal.panel,
                                onSelected: (v) async {
                                  if (v != 'del') return;
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: Text('Xoá hồ sơ “${pf.name}”?'),
                                      content: const Text('Cấu hình của nhà này sẽ bị xoá khỏi điện thoại. Bạn vẫn có thể thêm lại từ EVOKNX Editor.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
                                        TextButton(
                                          onPressed: () => Navigator.pop(c, true),
                                          child: Text('Xoá', style: TextStyle(color: pal.danger)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true) return;
                                  final wasActive = pf.id == store.activeId;
                                  await store.deleteProfile(pf.id);
                                  if (wasActive && context.mounted) Navigator.of(context).popUntil((x) => x.isFirst);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'del',
                                    child: Text('Xoá hồ sơ', style: TextStyle(color: pal.danger)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: pf.id == store.activeId
                              ? null
                              : () async {
                                  await store.switchProfile(pf.id);
                                  if (context.mounted) Navigator.of(context).popUntil((x) => x.isFirst);
                                },
                        ),
                      row(
                        Icon(Icons.wifi_tethering, color: pal.muted),
                        'Thêm hồ sơ từ máy tính (Wi-Fi)',
                        sub: 'Editor → menu EVOKNX → Gửi sang App qua Wi-Fi',
                        onTap: () async {
                          final before = store.profiles.length;
                          final ok = await showReceiveDialog(context, store, pal);
                          if (!ok || !context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                store.profiles.length > before ? 'Đã thêm hồ sơ “${store.projectName}”.' : 'Đã cập nhật hồ sơ “${store.projectName}”.',
                              ),
                            ),
                          );
                          Navigator.of(context).popUntil((x) => x.isFirst);
                        },
                      ),
                      row(
                        Icon(Icons.folder_open_outlined, color: pal.muted),
                        'Thêm hồ sơ từ file cấu hình',
                        sub: 'File .json xuất từ EVOKNX Editor. Cùng tên dự án thì cập nhật hồ sơ đó.',
                        onTap: () async {
                          final before = store.profiles.length;
                          final r = await store.importConfig();
                          if (!context.mounted) return;
                          if (r != null && r.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r)));
                          } else if (r == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  store.profiles.length > before ? 'Đã thêm hồ sơ “${store.projectName}”.' : 'Đã cập nhật hồ sơ “${store.projectName}”.',
                                ),
                              ),
                            );
                            Navigator.of(context).popUntil((x) => x.isFirst);
                          }
                        },
                      ),
                    ]),
                  ]),
                  tab([
                    card('Giao diện', [
                      // Three groups (Sáng, Trung tính, Tối): tap one to show its three themes.
                      for (final (group, items) in kAppThemeGroups)
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            key: PageStorageKey('theme-group-$group'),
                            initiallyExpanded: items.any((t) => t.$1 == store.mode),
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                            childrenPadding: EdgeInsets.zero,
                            iconColor: pal.muted,
                            collapsedIconColor: pal.muted,
                            shape: const Border(),
                            collapsedShape: const Border(),
                            title: Text(
                              group,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.ink),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  for (final (k, _) in items) ...[ThemeSwatch(AppPalette.of(k), size: 22), const SizedBox(width: 6)],
                                ],
                              ),
                            ),
                            children: [
                              for (final (k, n) in items)
                                row(
                                  ThemeSwatch(AppPalette.of(k)),
                                  n,
                                  sub: k == themeKey(jsonMap(store.config?['theme'])['mode']) ? 'Mặc định của dự án' : null,
                                  trailing: k == store.mode ? Icon(Icons.check, color: pal.accent) : null,
                                  onTap: () => store.setTheme(k),
                                ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.format_size, color: pal.muted),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text('Cỡ chữ', style: TextStyle(fontSize: 16, color: pal.ink)),
                                ),
                                Text(
                                  '${(store.textScale * 100).round()}%',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.accent),
                                ),
                              ],
                            ),
                            Slider(
                              value: store.textScale,
                              min: 0.8,
                              max: 1.5,
                              divisions: 14,
                              activeColor: pal.accent,
                              onChanged: (v) => store.setTextScale(v, save: false),
                              onChangeEnd: (v) => store.setTextScale(v),
                            ),
                            Text(
                              '100% là đúng cỡ chữ đã thiết kế trong Editor. Không phụ thuộc cỡ chữ của điện thoại.',
                              style: TextStyle(fontSize: 13, color: pal.muted),
                            ),
                          ],
                        ),
                      ),
                      if (defaultTargetPlatform == TargetPlatform.android)
                        row(
                          Icon(Icons.aspect_ratio, color: pal.muted),
                          'Tự cân cỡ chữ theo màn hình',
                          sub:
                              'Màn hình ${MediaQuery.sizeOf(context).width.round()} × ${MediaQuery.sizeOf(context).height.round()} dp · '
                              'hệ số ${store.uiScaleFor(MediaQuery.sizeOf(context)).toStringAsFixed(2)}',
                          trailing: Switch(value: store.autoScale, onChanged: store.setAutoScale, activeColor: pal.accent),
                        ),
                      row(
                        Icon(Icons.screen_lock_portrait_outlined, color: pal.muted),
                        'Giữ màn hình luôn sáng',
                        sub: 'Dành cho tablet gắn tường',
                        trailing: Switch(value: store.keepScreenOn, onChanged: store.setKeepScreenOn, activeColor: pal.accent),
                      ),
                    ]),
                  ]),
                  tab([
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
                  ]),
                  tab([
                    card('Giới thiệu', [
                      row(Icon(Icons.info_outline, color: pal.muted), 'EVOKNX', sub: 'Phiên bản 0.1.0 · © ${DateTime.now().year} Evohome'),
                      row(Icon(Icons.palette_outlined, color: pal.muted), 'Biểu tượng', sub: 'Material Design Icons · Pictogrammers (Apache 2.0)'),
                      row(Icon(Icons.text_fields, color: pal.muted), 'Phông chữ', sub: 'Inter · Rasmus Andersson (SIL Open Font License)'),
                    ]),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
