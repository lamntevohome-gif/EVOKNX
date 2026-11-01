import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/bus_controller.dart';
import '../state/project_controller.dart';
import 'common.dart';
import 'designer/canvas.dart';
import 'designer/designer.dart';
import 'designer/icons.dart';
import 'designer/model.dart';
import 'designer/props.dart';
import 'designer/tree.dart';

/// "Cấu trúc" workspace: structure tree, phone canvas and properties.
class StructurePage extends StatefulWidget {
  const StructurePage({super.key, required this.project, required this.bus});
  final ProjectController project;
  final BusController bus;

  @override
  State<StructurePage> createState() => _StructurePageState();
}

class _StructurePageState extends State<StructurePage> {
  late final Designer d = Designer(widget.project, widget.bus)
    ..onMessage = (m) {
      if (mounted) toast(context, m);
    };
  final FocusNode _focus = FocusNode(debugLabel: 'designer');
  bool issuesOpen = false;

  @override
  void dispose() {
    d.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && (ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || _typing) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final k = e.logicalKey;
    if ((k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) && d.widgetId != null) {
      d.deleteWidget();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyC && d.widgetId != null) {
      final m = d.copy();
      if (m != null) toast(context, m);
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyV && d.clip != null) {
      final m = d.paste();
      if (m != null) toast(context, m);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape && (d.widgetId != null || d.cell != null)) {
      d.selectWidget(null);
      return KeyEventResult.handled;
    }
    if (!ctrl && (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) && d.widgetId == null) {
      d.stepSub(k == LogicalKeyboardKey.arrowLeft ? -1 : 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _add(String type) {
    final m = d.addWidget(type);
    if (m != null) toast(context, m);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.project, d, widget.bus]),
        builder: (context, _) {
          syncCustomIcons(d.doc);
          final issues = computeIssues(d.doc);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 280,
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border(right: BorderSide(color: c.line)),
                ),
                child: StructureTree(d: d),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _palette(context),
                    Expanded(
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (_) => _focus.requestFocus(),
                        child: Container(
                          color: c.paper,
                          child: DesignCanvas(d: d, issues: issues),
                        ),
                      ),
                    ),
                    _issuesBar(context, issues),
                  ],
                ),
              ),
              Container(
                width: 330,
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border(left: BorderSide(color: c.line)),
                ),
                child: d.test ? _testPanel(context) : PropsPanel(d: d),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _palette(BuildContext context) {
    final c = context.evo;
    Widget chip(IconData icon, String label, {VoidCallback? onTap, bool accent = false}) => Material(
      color: c.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: accent ? c.accent : c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: accent ? c.accentInk : c.accent),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, color: accent ? c.accentInk : c.ink)),
            ],
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Seg<bool>(items: const [(false, 'Thiết kế'), (true, 'Chạy thử')], value: d.test, onChanged: d.setTest),
          if (_devices().length > 1) ...[
            const SizedBox(width: 6),
            Seg<String>(items: [for (final dv in _devices()) (dv, _devName(dv))], value: (d.doc['activeDev'] ?? 'mobile').toString(), onChanged: d.setDevice),
          ],
          const SizedBox(width: 10),
          if (d.test) ...[
            Seg<bool>(items: const [(false, 'Giả lập'), (true, 'Live (KNX)')], value: d.live, onChanged: d.setLive),
            const SizedBox(width: 8),
            Text(
              d.live
                  ? (widget.bus.connected
                        ? 'Live: lệnh gửi lên bus KNX thật, trạng thái lấy từ bus.'
                        : 'Live cần kết nối bus: mở màn hình Kiểm tra và bấm Kết nối.')
                  : 'Giả lập: bấm vào thành phần để xem App phản ứng và lệnh sẽ gửi.',
              style: TextStyle(fontSize: 12.5, color: d.live && !widget.bus.connected ? c.danger : c.muted),
            ),
          ],
          if (!d.test) Text('Thành phần', style: TextStyle(fontSize: 12.5, color: c.muted)),
          if (!d.test) const SizedBox(width: 4),
          if (!d.test)
            for (final t in kWidgetTypes.values)
              Tooltip(
                message: 'Kéo vào màn hình, hoặc bấm để thêm',
                child: Draggable<DragItem>(
                  data: DragItem.palette(t.type),
                  feedback: Material(type: MaterialType.transparency, child: chip(iconOf(t.icon), t.name)),
                  child: chip(iconOf(t.icon), t.name, onTap: () => _add(t.type)),
                ),
              ),
          if (d.clip != null && !d.test)
            chip(
              Icons.content_paste,
              'Dán “${d.clip!['label'] ?? ''}”',
              accent: true,
              onTap: () {
                final m = d.paste();
                if (m != null) toast(context, m);
              },
            ),
        ],
      ),
    );
  }

  List<String> _devices() {
    final m = jsonMap(d.doc['devices']);
    return ['mobile', 'tabletP', 'tabletL'].where((k) => k == 'mobile' ? m['mobile'] != false : m[k] == true).toList();
  }

  String _devName(String k) => switch (k) {
    'tabletP' => 'Tablet dọc',
    'tabletL' => 'Tablet ngang',
    _ => 'Mobile',
  };

  Widget _testPanel(BuildContext context) {
    final c = context.evo;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.play_circle_outline, size: 20, color: c.accent),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Chạy thử', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            if (d.log.isNotEmpty) TextButton(onPressed: () => setState(d.log.clear), child: const Text('Xoá')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          d.live && widget.bus.connected
              ? 'Đang điều khiển bus KNX thật. Mọi thay đổi trên bus cũng hiện ngay trên màn hình mô phỏng.'
              : 'Lệnh được ghi lại dưới đây, chưa gửi xuống bus.',
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
        const SizedBox(height: 12),
        const SectionTitle('Lệnh gửi'),
        if (d.log.isEmpty) Text('Chưa có lệnh nào. Bấm vào các thành phần trên màn hình.', style: TextStyle(color: c.muted, fontSize: 13)),
        for (final e in d.log)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 70,
                  child: Text(
                    e.address,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: e.missing ? c.danger : c.ink),
                  ),
                ),
                Expanded(
                  child: Text(e.text, style: TextStyle(fontSize: 13, color: e.missing ? c.danger : c.ink)),
                ),
                if (e.live) Icon(Icons.bolt, size: 15, color: c.accent),
              ],
            ),
          ),
      ],
    );
  }

  Widget _issuesBar(BuildContext context, List<Issue> issues) {
    final c = context.evo;
    final errs = issues.where((i) => i.error).length;
    final warns = issues.length - errs;
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: issues.isEmpty ? null : () => setState(() => issuesOpen = !issuesOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    issues.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                    size: 18,
                    color: errs > 0 ? c.danger : (warns > 0 ? c.warn : c.accent),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    issues.isEmpty ? 'Không có vấn đề, sẵn sàng xuất cấu hình' : [if (errs > 0) '$errs lỗi', if (warns > 0) '$warns lưu ý'].join(', '),
                    style: TextStyle(fontWeight: FontWeight.w600, color: errs > 0 ? c.danger : (warns > 0 ? c.warn : c.accentInk)),
                  ),
                  const Spacer(),
                  if (issues.isNotEmpty) Icon(issuesOpen ? Icons.expand_more : Icons.expand_less, size: 18, color: c.muted),
                ],
              ),
            ),
          ),
          if (issuesOpen && issues.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: [
                  for (final i in issues)
                    InkWell(
                      onTap: i.roomId == null
                          ? null
                          : () {
                              d.selectSub(i.roomId!, i.subId!);
                              if (i.widgetId != null) d.selectWidget(i.widgetId);
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            Icon(i.error ? Icons.error_outline : Icons.info_outline, size: 16, color: i.error ? c.danger : c.warn),
                            const SizedBox(width: 8),
                            Expanded(child: Text(i.text, style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
