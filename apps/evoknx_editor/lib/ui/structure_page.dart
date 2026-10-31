import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// Cấu trúc workspace. Phase 1: floors / rooms / pages management.
/// The visual designer (phone canvas, components, properties) is phase 2.
class StructurePage extends StatefulWidget {
  const StructurePage({super.key, required this.project});
  final ProjectController project;
  @override
  State<StructurePage> createState() => _StructurePageState();
}

class _StructurePageState extends State<StructurePage> {
  String? selFloor;
  String? selRoom;

  ProjectController get p => widget.project;

  List<Json> _rooms(Json d, String floorId) => jsonList(d['pages']).where((r) => r['floorId'] == floorId).toList();

  void _edit(void Function(Json d) fn, {String? key}) => p.mutate(fn, coalesce: key);

  Json? _find(List<Json> l, String? id) {
    for (final x in l) {
      if (x['id'] == id) return x;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final floors = jsonList(p.doc['floors']);
    final room = _find(jsonList(p.doc['pages']), selRoom);
    final floor = _find(floors, selFloor);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 300,
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(right: BorderSide(color: c.line)),
          ),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Row(
                children: [
                  Expanded(
                    child: EvoButton(
                      label: 'Tổng quan',
                      icon: Icons.settings_outlined,
                      small: true,
                      onPressed: () => setState(() => selRoom = selFloor = null),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: EvoButton(
                      label: 'Thêm tầng',
                      icon: Icons.add,
                      small: true,
                      onPressed: () => _edit((d) {
                        final f = makeFloor('Tầng ${floors.length + 1}');
                        (d['floors'] as List).add(f);
                        selFloor = f['id'] as String;
                        selRoom = null;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final f in floors) ...[
                _treeRow(
                  context,
                  icon: Icons.stairs_outlined,
                  text: f['title'] as String? ?? '',
                  bold: true,
                  selected: f['id'] == selFloor && selRoom == null,
                  onTap: () => setState(() {
                    selFloor = f['id'] as String;
                    selRoom = null;
                  }),
                  trailing: '${_rooms(p.doc, f['id'] as String).length} phòng',
                ),
                for (final r in _rooms(p.doc, f['id'] as String))
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _treeRow(
                      context,
                      icon: Icons.meeting_room_outlined,
                      text: r['title'] as String? ?? '',
                      selected: r['id'] == selRoom,
                      onTap: () => setState(() {
                        selRoom = r['id'] as String;
                        selFloor = f['id'] as String;
                      }),
                      trailing: '${jsonList(r['subpages']).length} trang',
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _treeRow(
                    context,
                    icon: Icons.add,
                    text: 'Thêm phòng',
                    accent: true,
                    onTap: () => _edit((d) {
                      final r = makeRoom('Phòng ${jsonList(d['pages']).length + 1}', floorId: f['id'] as String);
                      (d['pages'] as List).add(r);
                      selRoom = r['id'] as String;
                      selFloor = f['id'] as String;
                    }),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: c.panel,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone_iphone, size: 40, color: c.accent),
                  const SizedBox(height: 12),
                  const Text('Màn hình thiết kế giao diện', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'Điện thoại mô phỏng, thanh thành phần, kéo thả và bảng thuộc tính đang được chuyển sang Flutter ở giai đoạn 2. '
                    'Hiện tại bạn đã quản lý được tầng, phòng, trang, kết nối, địa chỉ nhóm và kiểm tra bus KNX thật. '
                    'File dự án từ bản web mở được ở đây và giữ nguyên toàn bộ thiết kế.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(left: BorderSide(color: c.line)),
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (room != null) ..._roomProps(context, room, floors) else if (floor != null) ..._floorProps(context, floor, floors) else ..._overview(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _treeRow(
    BuildContext context, {
    required IconData icon,
    required String text,
    bool bold = false,
    bool selected = false,
    bool accent = false,
    String? trailing,
    required VoidCallback onTap,
  }) {
    final c = context.evo;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: selected ? c.accentSoft : null, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(icon, size: 18, color: accent || selected ? c.accentInk : c.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                  color: accent || selected ? c.accentInk : c.ink,
                  fontSize: accent ? 13.5 : 14,
                ),
              ),
            ),
            if (trailing != null) Text(trailing, style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
      ),
    );
  }

  List<Widget> _overview(BuildContext context) {
    final c = context.evo;
    final pages = jsonList(p.doc['pages']);
    final widgets = allWidgets(p.doc).length;
    Widget stat(String n, String t) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            Text(t, style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
      ),
    );
    return [
      const SectionTitle('Tổng quan dự án'),
      Row(children: [stat('${jsonList(p.doc['floors']).length}', 'tầng'), const SizedBox(width: 8), stat('${pages.length}', 'phòng')]),
      const SizedBox(height: 8),
      Row(children: [stat('$widgets', 'thành phần'), const SizedBox(width: 8), stat('${p.groupAddresses.length}', 'địa chỉ nhóm')]),
    ];
  }

  List<Widget> _floorProps(BuildContext context, Json f, List<Json> floors) {
    final id = f['id'] as String;
    final nRooms = _rooms(p.doc, id).length;
    return [
      SectionTitle(
        'Tầng',
        trailing: floors.length > 1
            ? EvoButton(
                label: 'Xoá tầng',
                icon: Icons.delete_outline,
                small: true,
                danger: true,
                onPressed: () {
                  if (nRooms > 0) {
                    toast(context, '${f['title']} còn $nRooms phòng. Hãy chuyển hoặc xoá các phòng trước.');
                    return;
                  }
                  _edit((d) => (d['floors'] as List).removeWhere((x) => x is Map && x['id'] == id));
                  setState(() => selFloor = null);
                },
              )
            : null,
      ),
      FieldLabel(
        'Tên tầng',
        SyncedField(
          value: f['title'] as String? ?? '',
          onChanged: (v) => _edit((d) => _find(jsonList(d['floors']), id)?['title'] = v, key: 'fl:$id'),
        ),
      ),
      const SizedBox(height: 12),
      CheckboxListTile(
        value: f['showIcon'] != false,
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Ẩn/hiện biểu tượng'),
        onChanged: (v) => _edit((d) => _find(jsonList(d['floors']), id)?['showIcon'] = v ?? true),
      ),
    ];
  }

  List<Widget> _roomProps(BuildContext context, Json r, List<Json> floors) {
    final id = r['id'] as String;
    final subs = jsonList(r['subpages']);
    Json? room(Json d) => _find(jsonList(d['pages']), id);
    return [
      SectionTitle(
        'Phòng',
        trailing: EvoButton(
          label: 'Xoá phòng',
          icon: Icons.delete_outline,
          small: true,
          danger: true,
          onPressed: () {
            _edit((d) => (d['pages'] as List).removeWhere((x) => x is Map && x['id'] == id));
            setState(() => selRoom = null);
            toast(context, 'Đã xoá phòng. Có thể hoàn tác (Ctrl+Z).');
          },
        ),
      ),
      FieldLabel(
        'Tên phòng',
        SyncedField(
          value: r['title'] as String? ?? '',
          onChanged: (v) => _edit((d) => room(d)?['title'] = v, key: 'rm:$id'),
        ),
      ),
      const SizedBox(height: 12),
      FieldLabel(
        'Thuộc tầng',
        EvoDropdown<String>(
          width: double.infinity,
          value: r['floorId'] as String? ?? '',
          items: [for (final f in floors) (f['id'] as String, f['title'] as String? ?? '')],
          onChanged: (v) => _edit((d) => room(d)?['floorId'] = v),
        ),
      ),
      const SizedBox(height: 18),
      SectionTitle(
        'Trang trong phòng',
        trailing: EvoButton(
          label: 'Thêm trang',
          icon: Icons.add,
          small: true,
          onPressed: () => _edit((d) => (room(d)?['subpages'] as List?)?.add(makeSub('Trang ${subs.length + 1}'))),
        ),
      ),
      for (var i = 0; i < subs.length; i++)
        Padding(
          key: ValueKey(subs[i]['id']),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: SyncedField(
                  value: subs[i]['title'] as String? ?? '',
                  onChanged: (v) => _edit((d) => _find(jsonList(room(d)?['subpages']), subs[i]['id'] as String)?['title'] = v, key: 'sub:${subs[i]['id']}'),
                ),
              ),
              const SizedBox(width: 6),
              Text('${jsonList(subs[i]['widgets']).length}', style: TextStyle(color: context.evo.muted, fontSize: 12.5)),
              if (subs.length > 1)
                IconButton(
                  tooltip: 'Xoá trang',
                  icon: Icon(Icons.close, size: 17, color: context.evo.muted),
                  onPressed: () => _edit((d) => (room(d)?['subpages'] as List?)?.removeWhere((x) => x is Map && x['id'] == subs[i]['id'])),
                ),
            ],
          ),
        ),
    ];
  }
}
