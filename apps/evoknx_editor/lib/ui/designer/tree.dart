import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';
import 'icons.dart';
import 'model.dart';
import 'parts_ui.dart';

/// What is being dragged in the structure tree.
class _TreeDrag {
  const _TreeDrag(this.kind, this.id, [this.roomId]);
  final String kind; // floor | room | sub
  final String id;
  final String? roomId;
}

/// Left panel: Overview + floors › rooms › pages. Drag rows to reorder,
/// right-click for add / import / export / delete.
class StructureTree extends StatelessWidget {
  const StructureTree({super.key, required this.d});
  final Designer d;

  Future<void> _menu(BuildContext context, Offset at, List<(IconData, String, Future<void> Function()?)> items) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final v = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        for (var i = 0; i < items.length; i++)
          if (items[i].$3 == null && items[i].$2.isEmpty)
            const PopupMenuDivider(height: 9)
          else
            PopupMenuItem<int>(
              value: i,
              height: 30,
              enabled: items[i].$3 != null,
              child: Row(
                children: [
                  Icon(items[i].$1, size: 15, color: items[i].$2.startsWith('Xoá') ? context.evo.danger : context.evo.muted),
                  const SizedBox(width: 10),
                  Text(
                    items[i].$2,
                    style: TextStyle(fontSize: kUiText, color: items[i].$2.startsWith('Xoá') ? context.evo.danger : context.evo.ink),
                  ),
                ],
              ),
            ),
      ],
    );
    if (v != null) await items[v].$3?.call();
  }

  Future<bool> _confirm(BuildContext context, String title, String text, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SizedBox(width: 380, child: Text(text)),
          actions: [
            EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(c, false)),
            EvoButton(label: yes, danger: true, onPressed: () => Navigator.pop(c, true)),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final doc = d.doc;
    final curRoom = d.room;
    final curSub = d.sub;
    const sep = (Icons.remove, '', null);

    Widget row({
      required Widget leading,
      required String text,
      String? trailing,
      required bool on,
      required VoidCallback onTap,
      required void Function(Offset at) onMenu,
      double indent = 0,
      bool bold = false,
      _TreeDrag? drag,
      bool Function(_TreeDrag t)? accepts,
      void Function(_TreeDrag t)? onDrop,
    }) {
      Widget body(bool hover) => Material(
        color: on ? c.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: (e) => onMenu(e.globalPosition),
          child: Container(
            height: 28,
            padding: EdgeInsets.only(left: 12 + indent, right: 12),
            decoration: hover ? BoxDecoration(border: Border.all(color: c.accent, width: 1.5)) : null,
            child: Row(
              children: [
                SizedBox(width: 16, child: Center(child: leading)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: kUiText, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: c.ink),
                  ),
                ),
                if (trailing != null) Text(trailing, style: TextStyle(fontSize: 12, color: c.muted)),
              ],
            ),
          ),
        ),
      );
      final acc = accepts;
      Widget w = acc == null
          ? body(false)
          : DragTarget<_TreeDrag>(
              onWillAcceptWithDetails: (det) => det.data.id != drag?.id && acc(det.data),
              onAcceptWithDetails: (det) => onDrop?.call(det.data),
              builder: (context, cand, rej) => body(cand.isNotEmpty),
            );
      if (drag != null) {
        w = Draggable<_TreeDrag>(
          data: drag,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            color: c.panel,
            elevation: 4,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                text,
                style: TextStyle(fontSize: kUiText, color: c.ink),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: body(false)),
          child: w,
        );
      }
      return w;
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        row(
          leading: Icon(Icons.tune, size: 14, color: c.muted),
          text: 'Tổng quan',
          on: d.view == 'overview',
          onTap: d.overview,
          onMenu: (at) => _menu(context, at, [
            (Icons.add, 'Thêm tầng', () async => d.addFloor()),
            (Icons.file_download_outlined, 'Nhập tầng…', () => importPart(context, d)),
          ]),
        ),
        const SizedBox(height: 6),
        for (final f in floorsOf(doc)) ...[
          row(
            leading: iconWidget(f['icon'] as String? ?? 'stairs', 14, c.muted),
            text: (f['title'] ?? '').toString(),
            trailing: '${roomsOf(doc, f['id'] as String?).length}',
            on: d.view == 'floor' && d.floor?['id'] == f['id'],
            bold: true,
            onTap: () => d.selectFloor(f['id'] as String),
            drag: _TreeDrag('floor', f['id'] as String),
            accepts: (t) => t.kind == 'floor' || t.kind == 'room',
            onDrop: (t) => t.kind == 'floor' ? d.dropFloor(t.id, f['id'] as String) : d.dropRoom(t.id, floorId: f['id'] as String),
            onMenu: (at) => _menu(context, at, [
              (Icons.add, 'Thêm phòng', () async => d.addRoom(f['id'] as String)),
              (
                Icons.file_download_outlined,
                'Nhập phòng…',
                () async {
                  d.selectFloor(f['id'] as String);
                  await importPart(context, d);
                },
              ),
              (Icons.file_upload_outlined, 'Xuất tầng…', () => exportPart(context, d, 'floor', f['id'] as String)),
              sep,
              (
                Icons.delete_outline,
                'Xoá tầng',
                () async {
                  final m = d.deleteFloor(f['id'] as String);
                  if (m != null && context.mounted) toast(context, m);
                },
              ),
            ]),
          ),
          for (final r in roomsOf(doc, f['id'] as String?)) ...[
            row(
              indent: 16,
              leading: iconWidget(r['icon'] as String?, 14, c.muted),
              text: (r['title'] ?? '').toString(),
              trailing: '${subsOf(r).fold<int>(0, (n, s) => n + jsonList(s['widgets']).length)}',
              on: d.view == 'room' && d.roomFocus && curRoom?['id'] == r['id'],
              onTap: () => d.selectRoom(r['id'] as String),
              drag: _TreeDrag('room', r['id'] as String),
              accepts: (t) => t.kind == 'room',
              onDrop: (t) => d.dropRoom(t.id, targetRoomId: r['id'] as String),
              onMenu: (at) => _menu(context, at, [
                (
                  Icons.add,
                  'Thêm trang',
                  () async {
                    d.selectRoom(r['id'] as String);
                    d.addSub();
                  },
                ),
                (
                  Icons.file_download_outlined,
                  'Nhập trang…',
                  () async {
                    d.selectRoom(r['id'] as String);
                    await importPart(context, d);
                  },
                ),
                (Icons.file_upload_outlined, 'Xuất phòng…', () => exportPart(context, d, 'room', r['id'] as String)),
                sep,
                (
                  Icons.delete_outline,
                  'Xoá phòng',
                  () async {
                    final ok = await _confirm(
                      context,
                      'Xoá phòng “${r['title']}”?',
                      'Toàn bộ trang và thẻ trong phòng sẽ bị xoá. Có thể hoàn tác (Ctrl+Z).',
                      'Xoá phòng',
                    );
                    if (!ok) return;
                    d.selectRoom(r['id'] as String);
                    d.deleteRoom();
                  },
                ),
              ]),
            ),
            if (curRoom?['id'] == r['id'])
              for (final s in subsOf(r))
                row(
                  indent: 32,
                  leading: Icon(Icons.crop_portrait, size: 13, color: s['id'] == curSub?['id'] ? c.accent : c.muted),
                  text: (s['title'] ?? '').toString(),
                  trailing: '${jsonList(s['widgets']).length}',
                  on: d.view == 'room' && !d.roomFocus && s['id'] == curSub?['id'],
                  onTap: () => d.selectSub(r['id'] as String, s['id'] as String),
                  drag: _TreeDrag('sub', s['id'] as String, r['id'] as String),
                  accepts: (t) => t.kind == 'sub' && t.roomId == r['id'],
                  onDrop: (t) => d.dropSub(r['id'] as String, t.id, s['id'] as String),
                  onMenu: (at) => _menu(context, at, [
                    (
                      Icons.add,
                      'Thêm trang',
                      () async {
                        d.selectSub(r['id'] as String, s['id'] as String);
                        d.addSub();
                      },
                    ),
                    (
                      Icons.file_download_outlined,
                      'Nhập thẻ…',
                      () async {
                        d.selectSub(r['id'] as String, s['id'] as String);
                        await importPart(context, d);
                      },
                    ),
                    (Icons.file_upload_outlined, 'Xuất trang…', () => exportPart(context, d, 'page', s['id'] as String)),
                    sep,
                    (
                      Icons.delete_outline,
                      'Xoá trang',
                      () async {
                        d.selectSub(r['id'] as String, s['id'] as String);
                        final m = d.deleteSub();
                        if (m != null && context.mounted) toast(context, m);
                      },
                    ),
                  ]),
                ),
          ],
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}
