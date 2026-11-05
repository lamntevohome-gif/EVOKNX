import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../state/bus_controller.dart';
import '../state/project_controller.dart';
import 'common.dart';
import 'connections_page.dart';
import 'editor_settings_dialog.dart';
import 'import_dialog.dart';
import 'new_project_dialog.dart';
import 'send_to_app_dialog.dart';
import 'structure_page.dart';
import 'test_page.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, required this.project, required this.bus});
  final ProjectController project;
  final BusController bus;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int ws = 0;
  late final AppLifecycleListener _life = AppLifecycleListener(onExitRequested: _onExitRequested);
  bool _asking = false;

  ProjectController get p => widget.project;

  @override
  void initState() {
    super.initState();
    _life; // registers the close handler
    p.confirm = (title, message, yes) async =>
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            content: SizedBox(width: 460, child: Text(message)),
            actions: [
              EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(c, false)),
              EvoButton(label: yes, primary: true, onPressed: () => Navigator.pop(c, true)),
            ],
          ),
        ) ==
        true;
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  /// Called when the window is being closed: offers to save changes.
  Future<AppExitResponse> _onExitRequested() async {
    if (!p.dirty || _asking || !mounted) return AppExitResponse.exit;
    _asking = true;
    final name = p.fileName;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Lưu thay đổi trước khi đóng?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 440,
          child: Text(
            name != null
                ? 'Dự án “${p.projectName}” có thay đổi chưa lưu vào file $name.'
                : 'Dự án “${p.projectName}” chưa được lưu thành file. Bấm Lưu để chọn tên và thư mục.',
          ),
        ),
        actions: [
          EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(c)),
          EvoButton(label: 'Không lưu', danger: true, onPressed: () => Navigator.pop(c, 'discard')),
          EvoButton(label: name != null ? 'Lưu' : 'Lưu thành…', primary: true, onPressed: () => Navigator.pop(c, 'save')),
        ],
      ),
    );
    _asking = false;
    if (choice == 'discard') return AppExitResponse.exit;
    if (choice == 'save') {
      final ok = await p.saveForClose();
      return ok ? AppExitResponse.exit : AppExitResponse.cancel;
    }
    return AppExitResponse.cancel;
  }

  Future<void> _save({bool saveAs = false}) async {
    final m = await p.save(saveAs: saveAs);
    if (m != null && mounted) toast(context, m);
  }

  Future<void> _open([String? path]) async {
    final m = await p.open(path);
    if (m != null && mounted) toast(context, m);
  }

  Future<void> _new() => showNewProjectDialog(context, p);

  Future<void> _export() async {
    final m = await p.exportConfig();
    if (m != null && mounted) toast(context, m);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () => _save(saveAs: true),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () => _open(),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _new,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): p.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): p.redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): p.redo,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([p, widget.bus]),
            builder: (context, _) => Column(
              children: [
                _topBar(context),
                Expanded(
                  child: IndexedStack(
                    index: ws,
                    children: [
                      StructurePage(project: p, bus: widget.bus),
                      ConnectionsPage(project: p),
                      TestPage(project: p, bus: widget.bus),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _status() {
    if (p.viewingSnapshot != null) return 'Đang xem bản ${p.viewingSnapshot} · Lưu để khôi phục';
    if (p.path == null) return p.dirty ? 'Chưa lưu thành file' : 'Chưa lưu thành file';
    if (p.dirty) return 'Chưa lưu';
    final t = p.savedAt;
    if (t == null) return 'Đã lưu';
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return p.lastSaveWasAuto ? 'Tự lưu lúc $hm' : 'Đã lưu lúc $hm';
  }

  /// Top bar: app menu and workspaces on the left, project name and save
  /// state in the middle, undo/redo and the one primary action on the right.
  Widget _topBar(BuildContext context) =>
      // Always dark, like the toolbar of design tools.
      Theme(
        data: _barTheme(),
        child: Builder(builder: _darkTopBar),
      );

  Widget _darkTopBar(BuildContext context) {
    final c = context.evo;
    Widget tab(int i, String label) {
      final on = ws == i;
      return InkWell(
        onTap: () => setState(() => ws = i),
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? c.accent : null, borderRadius: BorderRadius.circular(5)),
          child: Text(
            label,
            style: TextStyle(fontSize: kUiText, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? Colors.white : c.muted),
          ),
        ),
      );
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: _kBar,
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Row(
        children: [
          _appMenu(context),
          Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 8), color: c.line),
          tab(0, 'Cấu trúc'),
          tab(1, 'Kết nối'),
          tab(2, 'Kiểm tra'),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Tooltip(
                      message: 'Bấm để đổi tên dự án',
                      child: SyncedField(
                        value: p.projectName,
                        bold: true,
                        borderless: true,
                        onChanged: (v) => p.mutate((d) => (d['project'] as Map)['name'] = v, coalesce: 'pname'),
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: p.path ?? 'Dự án chưa được lưu thành file',
                  child: Text(
                    _status(),
                    style: TextStyle(fontSize: kUiText, color: p.dirty ? c.warn : c.muted),
                  ),
                ),
              ],
            ),
          ),
          IconButton(tooltip: 'Hoàn tác (Ctrl+Z)', onPressed: p.canUndo ? p.undo : null, icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Làm lại (Ctrl+Y)', onPressed: p.canRedo ? p.redo : null, icon: const Icon(Icons.redo)),
        ],
      ),
    );
  }

  /// The application menu (logo button), like the main menu of design tools.
  Widget _appMenu(BuildContext context) {
    final c = context.evo;
    const ctrl = true;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.note_add_outlined),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyN, control: ctrl),
          onPressed: _new,
          child: const Text('Dự án mới…'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.folder_open_outlined),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyO, control: ctrl),
          onPressed: () => _open(),
          child: const Text('Mở…'),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.history),
          menuChildren: [
            if (p.recent.isEmpty) const MenuItemButton(child: Text('Chưa có dự án gần đây')),
            for (final r in p.recent)
              MenuItemButton(
                onPressed: () => _open(r),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(r, overflow: TextOverflow.ellipsis),
                ),
              ),
          ],
          child: const Text('Mở gần đây'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.drive_folder_upload_outlined),
          onPressed: p.projectDir == null ? null : () => Process.run('explorer', [p.projectDir!]),
          child: const Text('Mở folder dự án (lịch sử lưu)'),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.save_outlined),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: ctrl),
          onPressed: () => _save(),
          child: const Text('Lưu'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.save_as_outlined),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: ctrl, shift: true),
          onPressed: () => _save(saveAs: true),
          child: const Text('Lưu thành…'),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.upload_outlined),
          onPressed: () => runEtsImport(context, p),
          child: const Text('Nhập địa chỉ nhóm từ ETS…'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.wifi_tethering),
          onPressed: () => showSendToAppDialog(context, p),
          child: const Text('Gửi sang App qua Wi-Fi…'),
        ),
        MenuItemButton(leadingIcon: const Icon(Icons.download_outlined), onPressed: _export, child: const Text('Xuất cấu hình ra file…')),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined),
          onPressed: () => EditorSettingsDialog.show(context),
          child: const Text('Cài đặt Editor…'),
        ),
      ],
      builder: (context, ctl, _) => InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: () => ctl.isOpen ? ctl.close() : ctl.open(),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: ctl.isOpen ? _kBarHover : null, borderRadius: BorderRadius.circular(5)),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(5)),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: c.led, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'EVOKNX',
                style: TextStyle(fontSize: kUiText, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: Colors.white),
              ),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down, size: 16, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top bar colours: a mid charcoal (lighter than Figma's near-black) so the
/// logo and labels stay clearly visible.
const Color _kBar = Color(0xFF3A3A3A);
const Color _kBarHover = Color(0xFF4A4A4A);

ThemeData _barTheme() {
  final t = buildTheme(Brightness.dark);
  return t.copyWith(
    hoverColor: _kBarHover,
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        iconSize: 18,
        minimumSize: const Size(32, 32),
        fixedSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        foregroundColor: Colors.white,
        hoverColor: _kBarHover,
      ),
    ),
  );
}
