import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';

import 'package:evoknx_ui/evoknx_ui.dart';

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
              height: 34,
              enabled: items[i].$3 != null,
              child: Row(
                children: [
                  Icon(items[i].$1, size: 15, color: items[i].$2.startsWith('Delete') ? context.evo.danger : context.evo.muted),
                  const SizedBox(width: 10),
                  Text(
                    items[i].$2,
                    style: TextStyle(fontSize: kUiText, color: items[i].$2.startsWith('Delete') ? context.evo.danger : context.evo.ink),
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
            EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
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

    final allFloors = floorsOf(doc);
    final home = allFloors.where((f) => f['special'] == 'home').firstOrNull;
    final security = allFloors.where((f) => f['special'] == 'security').firstOrNull;
    final normal = normalFloorsOf(doc);
    final areaOpen = d.isTreeOpen('area', true);
    bool floorOpen(Json f) => d.isTreeOpen('f:${f['id']}', true);
    bool roomOpen(Json r) => d.isTreeOpen('r:${r['id']}', curRoom?['id'] == r['id']);

    // Visible rows in order, for Shift+click ranges.
    final order = <String>[];
    void addFloorRows(Json f) {
      order.add('f:${f['id']}');
      if (!floorOpen(f)) return;
      for (final r in roomsOf(doc, f['id'] as String?)) {
        order.add('r:${r['id']}');
        if (roomOpen(r)) {
          for (final s in subsOf(r)) {
            order.add('s:${r['id']}:${s['id']}');
          }
        }
      }
    }

    if (home != null) addFloorRows(home);
    if (areaOpen) normal.forEach(addFloorRows);
    if (security != null) addFloorRows(security);

    void tapRow(String key, VoidCallback normal) {
      final kb = HardwareKeyboard.instance;
      if (kb.isControlPressed || kb.isMetaPressed) {
        d.treeToggle(key);
      } else if (kb.isShiftPressed) {
        d.treeRange(order, key);
      } else {
        d.treeSel.clear();
        normal();
      }
    }

    Widget row({
      Widget? leading,
      required String text,
      required bool on,
      bool? open,
      VoidCallback? onToggle,
      required VoidCallback onTap,
      required void Function(Offset at) onMenu,
      String? selKey,
      double indent = 0,
      bool bold = false,
      _TreeDrag? drag,
      bool Function(_TreeDrag t)? accepts,
      void Function(_TreeDrag t)? onDrop,
    }) {
      // With several rows selected, those rows are highlighted instead.
      final isOn = selKey != null && d.treeSel.isNotEmpty ? d.treeSel.contains(selKey) : on;
      void menu(Offset at) {
        if (selKey != null && d.treeSel.length > 1 && d.treeSel.contains(selKey)) {
          _menu(context, at, [(Icons.delete_outline, 'Delete ${d.treeSel.length} selected items…', () => deleteTreeSelection(context, d))]);
        } else {
          onMenu(at);
        }
      }

      Widget body(bool hover) => Material(
        color: isOn ? c.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: selKey == null ? onTap : () => tapRow(selKey, onTap),
          onSecondaryTapDown: (e) => menu(e.globalPosition),
          child: Container(
            height: 36,
            padding: EdgeInsets.only(left: 12 + indent, right: 12),
            decoration: hover ? BoxDecoration(border: Border.all(color: c.accent, width: 1.5)) : null,
            child: Row(
              children: [
                // The triangle opens and closes the rows under this one.
                SizedBox(
                  width: 18,
                  child: open == null
                      ? null
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onToggle,
                          child: Center(child: Icon(open ? Icons.arrow_drop_down : Icons.arrow_right, size: 22, color: c.muted)),
                        ),
                ),
                if (leading != null) ...[SizedBox(width: 18, child: Center(child: leading)), const SizedBox(width: 6)],
                Expanded(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: kUiText + 1, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: c.ink),
                  ),
                ),
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

    // A floor, its rooms and (for the room being edited, or one that was opened) its pages. [base] is the indent of the
    // floor: a room is 16 further in, a page 32.
    // Home and Security have their own icons (a shield for Security) unless another one was chosen.
    Widget? floorIcon(Json f) {
      final k = f['icon'] as String?;
      final sp = f['special'];
      if (sp == 'security' && (k == null || k.isEmpty || k == 'shield-home')) return Icon(Icons.shield_outlined, size: 16, color: c.muted);
      if (sp == 'home' && (k == null || k.isEmpty || k == 'home')) return Icon(Icons.home_outlined, size: 16, color: c.muted);
      if (k == null || k.isEmpty || isNoIcon(k)) return Icon(Icons.layers_outlined, size: 16, color: c.muted);
      return iconWidget(k, 16, c.muted);
    }

    // A room without an icon has no space for one.
    Widget? roomIcon(Json r, Json f) {
      final k = r['icon'] as String?;
      if (f['special'] == 'security' && (k == null || k.isEmpty || k == 'shield-home')) return Icon(Icons.shield_outlined, size: 16, color: c.muted);
      if (f['special'] == 'home' && k == 'home') return Icon(Icons.home_outlined, size: 16, color: c.muted);
      if (k == null || k.isEmpty || isNoIcon(k)) return null;
      return iconWidget(k, 16, c.muted);
    }

    List<Widget> floorBlock(Json f, double base) {
      final fid = f['id'] as String;
      final open = floorOpen(f);
      final rooms = roomsOf(doc, fid);
      return [
        row(
          leading: floorIcon(f),
          text: (f['title'] ?? '').toString(),
          open: rooms.isEmpty ? null : open,
          onToggle: () => d.toggleTreeOpen('f:$fid', true),
          indent: base,
          on: d.view == 'floor' && d.floor?['id'] == fid,
          bold: true,
          selKey: 'f:$fid',
          onTap: () => d.selectFloor(fid),
          drag: _TreeDrag('floor', fid),
          accepts: (t) => t.kind == 'floor' || t.kind == 'room',
          onDrop: (t) => t.kind == 'floor' ? d.dropFloor(t.id, fid) : d.dropRoom(t.id, floorId: fid),
          onMenu: (at) => _menu(context, at, [
            (Icons.add, 'Add room', () async => d.addRoom(fid)),
            (
              Icons.file_download_outlined,
              'Import room',
              () async {
                d.selectFloor(fid);
                await importPart(context, d, only: 'room');
              },
            ),
            (Icons.file_upload_outlined, 'Export floor', () => exportPart(context, d, 'floor', fid)),
            sep,
            (
              Icons.delete_outline,
              'Delete floor',
              () async {
                final m = d.deleteFloor(fid);
                if (m != null && context.mounted) toast(context, m);
              },
            ),
          ]),
        ),
        if (open)
          for (final r in rooms) ...[
            row(
              indent: base + 16,
              leading: roomIcon(r, f),
              text: (r['title'] ?? '').toString(),
              open: subsOf(r).isEmpty ? null : roomOpen(r),
              onToggle: () => d.toggleTreeOpen('r:${r['id']}', curRoom?['id'] == r['id']),
              on: d.view == 'room' && d.roomFocus && curRoom?['id'] == r['id'],
              selKey: 'r:${r['id']}',
              onTap: () => d.selectRoom(r['id'] as String),
              drag: _TreeDrag('room', r['id'] as String),
              accepts: (t) => t.kind == 'room',
              onDrop: (t) => d.dropRoom(t.id, targetRoomId: r['id'] as String),
              onMenu: (at) => _menu(context, at, [
                (
                  Icons.add,
                  'Add page',
                  () async {
                    d.selectRoom(r['id'] as String);
                    d.addSub();
                  },
                ),
                (
                  Icons.file_download_outlined,
                  'Import page',
                  () async {
                    d.selectRoom(r['id'] as String);
                    await importPart(context, d, only: 'page');
                  },
                ),
                (Icons.file_upload_outlined, 'Export room', () => exportPart(context, d, 'room', r['id'] as String)),
                sep,
                (
                  Icons.delete_outline,
                  'Delete room',
                  () async {
                    final ok = await _confirm(
                      context,
                      'Delete the room “${r['title']}”?',
                      'All pages and cards in the room will be deleted. Can be undone (Ctrl+Z).',
                      'Delete room',
                    );
                    if (!ok) return;
                    d.selectRoom(r['id'] as String);
                    d.deleteRoom();
                  },
                ),
              ]),
            ),
            if (roomOpen(r))
              for (final s in subsOf(r))
                row(
                  indent: base + 32,
                  leading: Icon(Icons.crop_portrait, size: 15, color: s['id'] == curSub?['id'] ? c.accent : c.muted),
                  text: (s['title'] ?? '').toString(),
                  on: d.view == 'room' && !d.roomFocus && s['id'] == curSub?['id'],
                  selKey: 's:${r['id']}:${s['id']}',
                  onTap: () => d.selectSub(r['id'] as String, s['id'] as String),
                  drag: _TreeDrag('sub', s['id'] as String, r['id'] as String),
                  accepts: (t) => t.kind == 'sub' && t.roomId == r['id'],
                  onDrop: (t) => d.dropSub(r['id'] as String, t.id, s['id'] as String),
                  onMenu: (at) => _menu(context, at, [
                    (
                      Icons.add,
                      'Add page',
                      () async {
                        d.selectSub(r['id'] as String, s['id'] as String);
                        d.addSub();
                      },
                    ),
                    (
                      Icons.file_download_outlined,
                      'Import card',
                      () async {
                        d.selectSub(r['id'] as String, s['id'] as String);
                        await importPart(context, d, only: 'card');
                      },
                    ),
                    (Icons.file_upload_outlined, 'Export page', () => exportPart(context, d, 'page', s['id'] as String)),
                    sep,
                    (
                      Icons.delete_outline,
                      'Delete page',
                      () async {
                        d.selectSub(r['id'] as String, s['id'] as String);
                        final m = d.deleteSub();
                        if (m != null && context.mounted) toast(context, m);
                      },
                    ),
                  ]),
                ),
          ],
      ];
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        // The name of the project (click it to rename).
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
          child: Tooltip(
            message: tr('Click to rename the project'),
            child: SyncedField(
              value: d.p.projectName,
              bold: true,
              borderless: true,
              onChanged: (v) => d.p.mutate((doc) => (doc['project'] as Map)['name'] = v, coalesce: 'pname'),
            ),
          ),
        ),
        row(
          leading: Icon(Icons.tune, size: 16, color: c.muted),
          text: 'Overview',
          on: d.view == 'overview',
          onTap: d.overview,
          onMenu: (at) => _menu(context, at, [
            (Icons.add, 'Add floor', () async => d.addFloor()),
            (Icons.file_download_outlined, 'Import floor', () => importPart(context, d, only: 'floor')),
          ]),
        ),
        const SizedBox(height: 6),
        // Home – Area – Security, as the bar at the bottom of the App.
        if (home != null) ...floorBlock(home, 0),
        row(
          leading: Icon(Icons.layers_outlined, size: 16, color: c.muted),
          text: 'Area',
          open: areaOpen,
          onToggle: () => d.toggleTreeOpen('area', true),
          bold: true,
          on: false,
          onTap: () => d.toggleTreeOpen('area', true),
          onMenu: (at) => _menu(context, at, [
            (Icons.add, 'Add floor', () async => d.addFloor()),
            (Icons.file_download_outlined, 'Import floor', () => importPart(context, d, only: 'floor')),
          ]),
        ),
        if (areaOpen)
          for (final f in normal) ...floorBlock(f, 16),
        if (security != null) ...floorBlock(security, 0),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Confirms and deletes the selected floors, rooms and pages (Delete key or
/// the right-click menu). A floor takes its rooms with it, a room its pages.
Future<void> deleteTreeSelection(BuildContext context, Designer d) async {
  final keys = d.treeSel.isNotEmpty ? {...d.treeSel} : <String>{if (d.primaryTreeKey != null) d.primaryTreeKey!};
  if (keys.isEmpty) return;
  final plan = d.planTreeDelete(keys);
  final nSubs = plan.subs.values.fold<int>(0, (a, b) => a + b.length);
  if (plan.floors.isEmpty && plan.rooms.isEmpty && nSubs == 0) {
    toast(context, plan.notes.isEmpty ? 'Nothing to delete.' : plan.notes.join(' '));
    return;
  }
  final parts = [
    if (plan.floors.isNotEmpty) '${plan.floors.length} floors',
    if (plan.rooms.isNotEmpty) '${plan.rooms.length} rooms',
    if (nSubs > 0) '$nSubs ${nSubs == 1 ? 'page' : 'pages'}',
  ];
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Delete ${parts.join(', ')}?'),
      content: SizedBox(
        width: 400,
        child: Text(
          '${plan.cards > 0 ? 'Includes ${plan.cards} cards inside, which are deleted too. ' : ''}Can be undone with Ctrl+Z.${plan.notes.isEmpty ? '' : '\n\n${plan.notes.join('\n')}'}',
        ),
      ),
      actions: [
        EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
        EvoButton(label: 'Delete', danger: true, onPressed: () => Navigator.pop(c, true)),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  toast(context, d.deleteTreeItems(keys));
}
