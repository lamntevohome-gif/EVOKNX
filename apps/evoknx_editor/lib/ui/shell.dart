import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../state/bus_controller.dart';
import '../state/project_controller.dart';
import '../state/app_settings.dart';
import 'common.dart';
import 'connections_page.dart';
import 'editor_settings_dialog.dart';
import 'import_dialog.dart';
import 'new_project_dialog.dart';
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
            title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
        title: const Text('Lưu thay đổi trước khi đóng?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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

  Widget _topBar(BuildContext context) {
    final c = context.evo;
    final compact = MediaQuery.sizeOf(context).width < 1500;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: c.led,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: c.led.withValues(alpha: 0.25), spreadRadius: 3)],
            ),
          ),
          const SizedBox(width: 10),
          const Text('EVOKNX', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          const SizedBox(width: 8),
          Text(
            'Editor',
            style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 18),
          SyncedField(
            width: 220,
            value: p.projectName,
            bold: true,
            borderless: true,
            onChanged: (v) => p.mutate((d) => (d['project'] as Map)['name'] = v, coalesce: 'pname'),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: p.path ?? 'Dự án chưa được lưu thành file',
            child: Text(_status(), style: TextStyle(fontSize: 12.5, color: p.dirty ? c.warn : c.muted)),
          ),
          const SizedBox(width: 18),
          Seg<int>(items: const [(0, 'Cấu trúc'), (1, 'Kết nối'), (2, 'Kiểm tra')], value: ws, onChanged: (v) => setState(() => ws = v)),
          const Spacer(),
          IconButton(tooltip: 'Hoàn tác (Ctrl+Z)', onPressed: p.canUndo ? p.undo : null, icon: const Icon(Icons.undo, size: 19)),
          IconButton(tooltip: 'Làm lại (Ctrl+Y)', onPressed: p.canRedo ? p.redo : null, icon: const Icon(Icons.redo, size: 19)),
          const SizedBox(width: 8),
          EvoButton(label: compact ? '' : 'Mới', icon: Icons.note_add_outlined, tooltip: 'Dự án mới (Ctrl+N)', onPressed: _new),
          const SizedBox(width: 8),
          _openButton(compact),
          const SizedBox(width: 8),
          EvoButton(label: compact ? '' : 'Lưu', icon: Icons.save_outlined, tooltip: 'Lưu (Ctrl+S)', onPressed: () => _save()),
          const SizedBox(width: 8),
          EvoButton(
            label: compact ? '' : 'Lưu thành',
            icon: Icons.save_as_outlined,
            tooltip: 'Lưu thành file khác (Ctrl+Shift+S)',
            onPressed: () => _save(saveAs: true),
          ),
          const SizedBox(width: 8),
          EvoButton(
            label: compact ? '' : 'Nhập từ ETS',
            icon: Icons.upload_outlined,
            tooltip: 'Nhập địa chỉ nhóm từ ETS',
            onPressed: () => runEtsImport(context, p),
          ),
          const SizedBox(width: 8),
          EvoButton(
            label: compact ? '' : 'Xuất cấu hình',
            icon: Icons.download_outlined,
            primary: true,
            tooltip: 'Xuất file cấu hình cho App',
            onPressed: _export,
          ),
          const SizedBox(width: 6),
          IconButton(tooltip: 'Cài đặt Editor', onPressed: () => EditorSettingsDialog.show(context), icon: const Icon(Icons.settings_outlined, size: 20)),
        ],
      ),
    );
  }

  Widget _openButton(bool compact) {
    return PopupMenuButton<String>(
      tooltip: 'Mở dự án (Ctrl+O)',
      position: PopupMenuPosition.under,
      onSelected: (v) {
        if (v == '__folder') {
          final dir = p.projectDir;
          if (dir != null) Process.run('explorer', [dir]);
          return;
        }
        v == '__browse' ? _open() : _open(v);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: '__browse', child: Text('Mở file…')),
        if (p.projectDir != null) const PopupMenuItem(value: '__folder', child: Text('Mở folder dự án (xem lịch sử lưu)')),
        if (p.recent.isNotEmpty) const PopupMenuDivider(),
        for (final r in p.recent)
          PopupMenuItem(
            value: r,
            child: Text(r, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          ),
      ],
      child: IgnorePointer(
        child: EvoButton(label: compact ? '' : 'Mở', icon: Icons.folder_open_outlined, onPressed: _noop),
      ),
    );
  }
}

void _noop() {}
