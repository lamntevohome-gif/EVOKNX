import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
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
  const StructurePage({super.key, required this.project});
  final ProjectController project;

  @override
  State<StructurePage> createState() => _StructurePageState();
}

class _StructurePageState extends State<StructurePage> {
  late final Designer d = Designer(widget.project);
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
        listenable: Listenable.merge([widget.project, d]),
        builder: (context, _) {
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
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _focus.requestFocus(),
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
                child: PropsPanel(d: d),
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
          Text('Thành phần', style: TextStyle(fontSize: 12.5, color: c.muted)),
          const SizedBox(width: 4),
          for (final t in kWidgetTypes.values)
            Tooltip(
              message: 'Kéo vào màn hình, hoặc bấm để thêm',
              child: Draggable<DragItem>(
                data: DragItem.palette(t.type),
                feedback: Material(type: MaterialType.transparency, child: chip(iconOf(t.icon), t.name)),
                child: chip(iconOf(t.icon), t.name, onTap: () => _add(t.type)),
              ),
            ),
          if (d.clip != null)
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
