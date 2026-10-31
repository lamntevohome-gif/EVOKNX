import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../state/bus_controller.dart';
import '../state/project_controller.dart';
import 'common.dart';
import 'connections_page.dart';
import 'import_dialog.dart';
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

  ProjectController get p => widget.project;

  Future<void> _save({bool saveAs = false}) async {
    final m = await p.save(saveAs: saveAs);
    if (m != null && mounted) toast(context, m);
  }

  Future<void> _open([String? path]) async {
    final m = await p.open(path);
    if (m != null && mounted) toast(context, m);
  }

  Future<void> _new() async {
    final name = await showDialog<String>(context: context, builder: (_) => const _NewProjectDialog());
    if (name != null) p.newDocument(name);
  }

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

  Widget _topBar(BuildContext context) {
    final c = context.evo;
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
            message: p.path ?? 'Chưa lưu thành file',
            child: Text(p.dirty ? 'Chưa lưu' : 'Đã lưu', style: TextStyle(fontSize: 12.5, color: p.dirty ? c.warn : c.muted)),
          ),
          const SizedBox(width: 18),
          Seg<int>(items: const [(0, 'Cấu trúc'), (1, 'Kết nối'), (2, 'Kiểm tra')], value: ws, onChanged: (v) => setState(() => ws = v)),
          const Spacer(),
          IconButton(tooltip: 'Hoàn tác (Ctrl+Z)', onPressed: p.canUndo ? p.undo : null, icon: const Icon(Icons.undo, size: 19)),
          IconButton(tooltip: 'Làm lại (Ctrl+Y)', onPressed: p.canRedo ? p.redo : null, icon: const Icon(Icons.redo, size: 19)),
          const SizedBox(width: 8),
          EvoButton(label: 'Mới', icon: Icons.note_add_outlined, tooltip: 'Dự án mới (Ctrl+N)', onPressed: _new),
          const SizedBox(width: 8),
          _openButton(),
          const SizedBox(width: 8),
          EvoButton(label: 'Lưu', icon: Icons.save_outlined, tooltip: 'Lưu (Ctrl+S)', onPressed: () => _save()),
          const SizedBox(width: 8),
          EvoButton(label: 'Nhập từ ETS', icon: Icons.upload_outlined, onPressed: () => runEtsImport(context, p)),
          const SizedBox(width: 8),
          EvoButton(label: 'Xuất cấu hình', icon: Icons.download_outlined, primary: true, tooltip: 'Xuất file cấu hình cho App', onPressed: _export),
        ],
      ),
    );
  }

  Widget _openButton() {
    return PopupMenuButton<String>(
      tooltip: 'Mở dự án (Ctrl+O)',
      position: PopupMenuPosition.under,
      onSelected: (v) => v == '__browse' ? _open() : _open(v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '__browse', child: Text('Mở file…')),
        if (p.recent.isNotEmpty) const PopupMenuDivider(),
        for (final r in p.recent)
          PopupMenuItem(
            value: r,
            child: Text(r, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          ),
      ],
      child: const IgnorePointer(
        child: EvoButton(label: 'Mở', icon: Icons.folder_open_outlined, onPressed: _noop),
      ),
    );
  }
}

void _noop() {}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();
  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tạo dự án mới', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dự án hiện tại sẽ được thay thế. Bạn vẫn có thể hoàn tác (Ctrl+Z).', style: TextStyle(color: context.evo.muted)),
            const SizedBox(height: 14),
            FieldLabel(
              'Tên dự án',
              TextField(
                controller: _c,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Ví dụ: Biệt thự anh Nam'),
                onSubmitted: (v) => Navigator.pop(context, v),
              ),
            ),
          ],
        ),
      ),
      actions: [
        EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(context)),
        EvoButton(label: 'Tạo dự án', primary: true, onPressed: () => Navigator.pop(context, _c.text)),
      ],
    );
  }
}
