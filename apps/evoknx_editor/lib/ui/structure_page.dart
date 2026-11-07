import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/bus_controller.dart';
import '../state/card_library.dart';
import '../state/project_controller.dart';
import 'common.dart';
import 'designer/canvas.dart';
import 'designer/designer.dart';

import 'package:evoknx_ui/evoknx_ui.dart';

import 'designer/props.dart';
import 'designer/parts_ui.dart';
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

  /// Left panel tab: 0 = Cấu trúc (layers), 1 = Thành phần (assets).
  int leftTab = 0;

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
    // No card selected: Delete removes the floor / room / page(s) selected in
    // the structure tree (asks first).
    if (k == LogicalKeyboardKey.delete && !d.test && (d.treeSel.isNotEmpty || d.primaryTreeKey != null)) {
      deleteTreeSelection(context, d);
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
    // Selected card: arrows move it, Shift+arrows resize it (one cell).
    final arrows = {
      LogicalKeyboardKey.arrowLeft: (-1, 0),
      LogicalKeyboardKey.arrowRight: (1, 0),
      LogicalKeyboardKey.arrowUp: (0, -1),
      LogicalKeyboardKey.arrowDown: (0, 1),
    };
    if (!ctrl && d.widgetId != null && !d.test && arrows.containsKey(k)) {
      final (ax, ay) = arrows[k]!;
      final m = HardwareKeyboard.instance.isShiftPressed ? d.nudgeSelected(dw: ax, dh: ay) : d.nudgeSelected(dx: ax, dy: ay);
      if (m != null) toast(context, m);
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
                width: 276,
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border(right: BorderSide(color: c.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _leftHeader(context),
                    Expanded(child: leftTab == 0 ? StructureTree(d: d) : _assets(context)),
                  ],
                ),
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
                width: 336,
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

  /// Tabs of the left panel, like Layers / Assets in design tools.
  Widget _leftHeader(BuildContext context) {
    final c = context.evo;
    Widget tab(int i, String label) => InkWell(
      onTap: () => setState(() => leftTab = i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          label,
          style: TextStyle(fontSize: kUiText, fontWeight: leftTab == i ? FontWeight.w600 : FontWeight.w400, color: leftTab == i ? c.ink : c.muted),
        ),
      ),
    );
    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: 6, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          tab(0, 'Cấu trúc'),
          tab(1, 'Thành phần'),
          const Spacer(),
          if (leftTab == 0) IconButton(tooltip: tr('Thêm tầng'), icon: const Icon(Icons.add), onPressed: d.addFloor),
        ],
      ),
    );
  }

  /// "Thành phần": card types on top, the card library below. Items can be
  /// dragged onto the screen or clicked to add to the selected cell.
  Widget _assets(BuildContext context) {
    final c = context.evo;
    Widget item(Widget icon, String label, {VoidCallback? onTap, Widget? trailing, bool accent = false, void Function(Offset)? onMenu}) => PressEffect(
      scale: 0.98,
      radius: 4,
      child: InkWell(
        onTap: onTap,
        onSecondaryTapDown: onMenu == null ? null : (e) => onMenu(e.globalPosition),
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(left: 12, right: 6),
          child: Row(
            children: [
              SizedBox(width: 16, child: Center(child: icon)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: kUiText, color: accent ? c.accentInk : c.ink),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
    Widget feedback(Widget icon, String label) => Material(
      color: c.panel,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
        side: BorderSide(color: kEditorSelection),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: kUiText, color: c.ink),
            ),
          ],
        ),
      ),
    );
    Widget header(String title, {Widget? trailing}) => Container(
      height: 38,
      padding: const EdgeInsets.only(left: 12, right: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
    final grip = Icon(Icons.drag_indicator, size: 14, color: c.lineStrong);

    final types = ListView(
      padding: const EdgeInsets.only(bottom: 6),
      children: [
        header('LOẠI THẺ'),
        if (d.clip != null)
          item(
            Icon(Icons.content_paste, size: 15, color: c.accent),
            'Dán “${d.clip!['label'] ?? ''}”',
            accent: true,
            onTap: () {
              final m = d.paste();
              if (m != null) toast(context, m);
            },
          ),
        for (final t in kWidgetTypes.values)
          Draggable<DragItem>(
            data: DragItem.palette(t.type),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback(iconWidget(t.icon, 17, c.muted), t.name),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: item(
                iconWidget(t.icon, 17, c.muted),
                t.name,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(tooltip: tr('Thêm vào ô đang chọn (hoặc chỗ trống đầu tiên)'), icon: const Icon(Icons.add), onPressed: () => _add(t.type)),
                    grip,
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    final library = ListenableBuilder(
      listenable: cardLibrary,
      builder: (context, _) {
        final list = cardLibrary.entries;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(
              'THƯ VIỆN THẺ',
              trailing: IconButton(tooltip: tr('Thêm thẻ vào thư viện từ file'), icon: const Icon(Icons.add), onPressed: () => importCardsToLibrary(context)),
            ),
            Expanded(
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Text('Chưa có thẻ. Xuất một thẻ đã cấu hình, hoặc bấm + để thêm từ file.', style: TextStyle(fontSize: 13, color: c.muted)),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: list.length,
                      onReorder: (a, b) => cardLibrary.reorder(a, b > a ? b - 1 : b),
                      proxyDecorator: (child, i, anim) => Material(color: c.panel, elevation: 4, child: child),
                      itemBuilder: (context, i) {
                        final e = list[i];
                        final id = e['id'] as String;
                        final card = CardLibrary.cardOf(e);
                        final icon = iconWidget((card?['icon'] ?? kWidgetTypes[e['type']]?.icon)?.toString(), 15, c.muted);
                        final name = (e['name'] ?? '').toString();
                        // The grip (right) reorders; the rest of the row drags
                        // the card onto the screen.
                        return Row(
                          key: ValueKey(id),
                          children: [
                            Expanded(
                              child: Draggable<DragItem>(
                                data: DragItem.lib(id),
                                dragAnchorStrategy: pointerDragAnchorStrategy,
                                feedback: feedback(icon, name),
                                child: item(
                                  icon,
                                  name,
                                  onMenu: (at) async {
                                    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                                    final v = await showMenu<String>(
                                      context: context,
                                      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
                                      items: [
                                        PopupMenuItem(
                                          value: 'del',
                                          height: 36,
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline, size: 15, color: c.danger),
                                              const SizedBox(width: 10),
                                              Text(
                                                'Xoá khỏi thư viện',
                                                style: TextStyle(fontSize: kUiText, color: c.danger),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                    if (v == 'del') await cardLibrary.remove(id);
                                  },
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: tr('Thêm vào ô đang chọn (hoặc chỗ trống đầu tiên)'),
                              icon: const Icon(Icons.add),
                              onPressed: () {
                                final m = d.addLibCard(id);
                                if (m != null) toast(context, m);
                              },
                            ),
                            Tooltip(
                              message: tr('Kéo để sắp xếp'),
                              child: ReorderableDragStartListener(
                                index: i,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.resizeUpDown,
                                  child: Padding(padding: const EdgeInsets.fromLTRB(4, 4, 8, 4), child: grip),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: types),
        Divider(color: c.line),
        Expanded(flex: 2, child: library),
      ],
    );
    // Cards cannot be added while testing: the list is greyed out.
    if (!d.test) return body;
    return Stack(
      children: [
        Opacity(opacity: 0.45, child: IgnorePointer(child: body)),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Material(
            color: c.paper,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                'Đang Chạy thử. Chuyển sang Thiết kế để thêm thẻ.',
                style: TextStyle(fontSize: kUiText - 1, color: c.muted),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Toolbar above the screen: design/test mode, device, live switch.
  Widget _palette(BuildContext context) {
    final c = context.evo;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Seg<bool>(items: const [(false, 'Thiết kế'), (true, 'Chạy thử')], value: d.test, onChanged: d.setTest),
          if (_devices().length > 1) ...[
            const SizedBox(width: 8),
            Seg<String>(items: [for (final dv in _devices()) (dv, _devName(dv))], value: (d.doc['activeDev'] ?? 'mobile').toString(), onChanged: d.setDevice),
          ],
          if (d.test) ...[
            const SizedBox(width: 8),
            Seg<bool>(items: const [(false, 'Giả lập'), (true, 'Test trực tiếp')], value: d.live, onChanged: d.setLive),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                d.live
                    ? [
                        if (widget.bus.connected) 'Đang điều khiển bus KNX thật' else 'Chưa kết nối bus (mở khu Kiểm tra để kết nối)',
                        if (d.usesHa)
                          switch (d.haState) {
                            HaConnection.connected => 'Home Assistant: đã kết nối',
                            HaConnection.connecting => 'Home Assistant: đang kết nối…',
                            HaConnection.failed => 'Home Assistant: lỗi, đang thử lại',
                            _ => 'Home Assistant: chưa bật trong tab HA',
                          },
                      ].join(' · ')
                    : 'Lệnh chỉ ghi vào nhật ký, chưa gửi xuống bus hay Home Assistant',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: d.live && !widget.bus.connected && !d.usesHa ? c.danger : c.muted),
              ),
            ),
          ],
          const Spacer(),
          if (!d.test && d.clip != null)
            EvoButton(
              label: 'Dán',
              icon: Icons.content_paste,
              small: true,
              tooltip: tr('Dán “${d.clip!['label'] ?? ''}” (Ctrl+V)'),
              onPressed: () {
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      children: [
        Row(
          children: [
            Icon(Icons.play_circle_outline, size: 16, color: c.muted),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Nhật ký lệnh', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            if (d.log.isNotEmpty) TextButton(onPressed: () => setState(d.log.clear), child: const Text('Xoá')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          d.live && widget.bus.connected
              ? 'Đang điều khiển bus KNX thật. Mọi thay đổi trên bus cũng hiện ngay trên màn hình mô phỏng.'
              : 'Lệnh được ghi lại dưới đây, chưa gửi xuống bus.',
          style: TextStyle(fontSize: 13, color: c.muted),
        ),
        const SizedBox(height: 12),
        const SectionTitle('Lệnh gửi'),
        if (d.log.isEmpty)
          Text(
            'Chưa có lệnh nào. Bấm vào các thành phần trên màn hình.',
            style: TextStyle(color: c.muted, fontSize: kUiText),
          ),
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
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: kUiText, color: e.missing ? c.danger : c.ink),
                  ),
                ),
                Expanded(
                  child: Text(
                    e.text,
                    style: TextStyle(fontSize: kUiText, color: e.missing ? c.danger : c.ink),
                  ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    issues.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                    size: 15,
                    color: errs > 0 ? c.danger : (warns > 0 ? c.warn : const Color(0xFF14AE5C)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    issues.isEmpty ? 'Không có vấn đề, sẵn sàng xuất cấu hình' : [if (errs > 0) '$errs lỗi', if (warns > 0) '$warns lưu ý'].join(', '),
                    style: TextStyle(fontSize: kUiText, fontWeight: FontWeight.w500, color: errs > 0 ? c.danger : (warns > 0 ? c.warn : c.muted)),
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
                            Icon(i.error ? Icons.error_outline : Icons.info_outline, size: 14, color: i.error ? c.danger : c.warn),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(i.text, style: const TextStyle(fontSize: kUiText)),
                            ),
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
