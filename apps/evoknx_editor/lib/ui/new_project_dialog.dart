import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';
import 'ets_password_dialog.dart';

import 'package:evoknx_ui/evoknx_ui.dart';

/// "Mới": choose Quick create (floors, rooms, icons, ETS) or Manual.
Future<void> showNewProjectDialog(BuildContext context, ProjectController p) async {
  final doc = await showDialog<Json>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _NewProjectDialog(p: p),
  );
  if (doc != null) {
    p.replaceDocument(doc);
    if (context.mounted) {
      final floors = jsonList(doc['floors']).length, rooms = jsonList(doc['pages']).length, gas = jsonList(doc['groupAddresses']).length;
      toast(
        context,
        'Đã tạo “${jsonMap(doc['project'])['name']}”: $floors tầng, $rooms phòng${gas > 0 ? ', $gas địa chỉ nhóm' : ''}. Có thể hoàn tác (Ctrl+Z).',
      );
    }
  }
}

const _roomDefaults = [
  ('sofa', 'Phòng khách'),
  ('kitchen', 'Bếp'),
  ('bed', 'Phòng ngủ'),
  ('bath', 'Phòng tắm'),
  ('desk', 'Phòng làm việc'),
  ('kids', 'Phòng trẻ em'),
  ('dining', 'Phòng ăn'),
  ('cinema', 'Phòng giải trí'),
];

class _Room {
  _Room(this.name, this.icon);
  String name, icon;
}

class _Floor {
  _Floor(this.title, this.icon, this.rooms);
  String title, icon;
  final List<_Room> rooms;
}

_Room _newRoom(int k) => _Room('Phòng ${k + 1}', _roomDefaults[k % _roomDefaults.length].$1);
_Floor _newFloor(int i) => _Floor(i == 0 ? 'Tầng 1' : 'Tầng ${i + 1}', 'stairs', [for (var k = 0; k < 3; k++) _newRoom(k)]);

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog({required this.p});
  final ProjectController p;
  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  String step = 'choose'; // choose | quick | manual
  String name = '';
  final List<_Floor> floors = [_newFloor(0)];
  EtsResult? ets;
  String? etsFile;
  String? etsError;
  bool busy = false;
  int _gen = 0; // forces text fields to refresh after count changes

  void _setFloorCount(int n) => setState(() {
    n = n.clamp(1, 10);
    while (floors.length < n) {
      floors.add(_newFloor(floors.length));
    }
    floors.removeRange(n, floors.length);
    _gen++;
  });

  void _setRoomCount(_Floor f, int n) => setState(() {
    n = n.clamp(0, 30);
    while (f.rooms.length < n) {
      f.rooms.add(_newRoom(f.rooms.length));
    }
    f.rooms.removeRange(n, f.rooms.length);
    _gen++;
  });

  Future<void> _pickEts() async {
    setState(() => busy = true);
    final r = await widget.p.pickEts(askPassword: (name, wrong) => askEtsPassword(context, name, wrong: wrong));
    if (!mounted) return;
    setState(() {
      busy = false;
      if (r.fileName == null) return;
      etsFile = r.fileName;
      etsError = r.error;
      ets = r.error == null ? r.result : null;
      if (ets != null && ets!.items.isEmpty) {
        etsError = 'Không tìm thấy địa chỉ nhóm trong file.';
        ets = null;
      }
    });
  }

  Json _build() {
    final title = name.trim().isNotEmpty ? name.trim() : ((ets?.projectName ?? '').isNotEmpty ? ets!.projectName : 'Dự án mới');
    final d = newProject(title);
    if (step == 'manual') return d;
    final fl = <Json>[];
    final pages = <Json>[];
    for (var i = 0; i < floors.length; i++) {
      final f = floors[i];
      final jf = makeFloor(f.title.trim().isEmpty ? 'Tầng ${i + 1}' : f.title.trim(), icon: f.icon);
      fl.add(jf);
      for (var k = 0; k < f.rooms.length; k++) {
        final r = f.rooms[k];
        pages.add(makeRoom(r.name.trim().isEmpty ? 'Phòng ${k + 1}' : r.name.trim(), icon: r.icon, floorId: jf['id'] as String));
      }
    }
    d['floors'] = fl;
    d['pages'] = pages;
    if (ets != null) applyEts(d, ets!);
    if (name.trim().isNotEmpty) jsonMap(d['project'])['name'] = name.trim();
    return d;
  }

  Future<String?> _icon(String current, List<(String, String)> items) => showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Chọn biểu tượng', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 460,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (k, n) in items)
              Tooltip(
                message: n,
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => Navigator.pop(c, k),
                  child: Container(
                    width: 96,
                    height: 76,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: k == current ? c.evo.accentSoft : null,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: k == current ? c.evo.accent : c.evo.line),
                    ),
                    child: Column(
                      children: [
                        iconWidget(k, 26, c.evo.ink),
                        const Spacer(),
                        Text(
                          n,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: c.evo.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [EvoButton(label: 'Đóng', onPressed: () => Navigator.pop(c))],
    ),
  );

  Widget _iconBtn(String icon, List<(String, String)> items, ValueChanged<String> onPick) => Tooltip(
    message: 'Đổi biểu tượng',
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final v = await _icon(icon, items);
        if (v != null) setState(() => onPick(v));
      },
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: context.evo.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: iconWidget(icon, 19, context.evo.accent),
      ),
    ),
  );

  Widget _counter(int value, int min, int max, ValueChanged<int> onChanged, {String unit = ''}) {
    final c = context.evo;
    Widget b(IconData i, int d) => InkWell(
      onTap: (d < 0 ? value <= min : value >= max) ? null : () => onChanged(value + d),
      child: SizedBox(width: 28, height: 32, child: Icon(i, size: 16, color: (d < 0 ? value <= min : value >= max) ? c.lineStrong : c.ink)),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          b(Icons.remove, -1),
          SizedBox(
            width: unit.isEmpty ? 30 : 64,
            child: Text(
              '$value$unit',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: kUiText),
            ),
          ),
          b(Icons.add, 1),
        ],
      ),
    );
  }

  Widget _choice(IconData icon, String title, String desc, String to) {
    final c = context.evo;
    return Expanded(
      child: Material(
        color: c.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          hoverColor: c.accentSoft,
          onTap: () => setState(() => step = to),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 26, color: c.accent),
                const SizedBox(height: 10),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(fontSize: kUiText, color: c.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final nameField = FieldLabel(
      'Tên dự án',
      TextFormField(
        initialValue: name,
        autofocus: true,
        onChanged: (v) => name = v,
        decoration: const InputDecoration(hintText: 'Ví dụ: Biệt thự anh Nam'),
      ),
    );
    final Widget content;
    final List<Widget> actions;
    if (step == 'choose') {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dự án hiện tại sẽ được thay thế. Bạn vẫn có thể hoàn tác (Ctrl+Z), hoặc lưu trước nếu cần giữ lại.', style: TextStyle(color: c.muted)),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _choice(Icons.bolt_outlined, 'Tạo nhanh', 'Đặt tên, số tầng, số phòng, biểu tượng và nhập địa chỉ nhóm từ file ETS.', 'quick'),
                const SizedBox(width: 12),
                _choice(Icons.edit_note_outlined, 'Tạo thủ công', 'Bắt đầu với dự án trống, tự thêm tầng, phòng và địa chỉ nhóm.', 'manual'),
              ],
            ),
          ),
        ],
      );
      actions = [EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(context))];
    } else if (step == 'manual') {
      content = Column(mainAxisSize: MainAxisSize.min, children: [nameField]);
      actions = [
        EvoButton(label: 'Quay lại', onPressed: () => setState(() => step = 'choose')),
        EvoButton(label: 'Tạo dự án', primary: true, onPressed: () => Navigator.pop(context, _build())),
      ];
    } else {
      content = SizedBox(
        height: 520,
        child: ListView(
          children: [
            nameField,
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text('Số tầng', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                _counter(floors.length, 1, 10, _setFloorCount),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < floors.length; i++)
              Container(
                key: ValueKey('fl-$i-$_gen'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _iconBtn(floors[i].icon, kFloorIcons, (v) => floors[i].icon = v),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: floors[i].title,
                            onChanged: (v) => floors[i].title = v,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            decoration: const InputDecoration(hintText: 'Tên tầng'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _counter(floors[i].rooms.length, 0, 30, (n) => _setRoomCount(floors[i], n), unit: ' phòng'),
                      ],
                    ),
                    for (var k = 0; k < floors[i].rooms.length; k++)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 20),
                        child: Row(
                          children: [
                            _iconBtn(floors[i].rooms[k].icon, kRoomIcons, (v) => floors[i].rooms[k].icon = v),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: floors[i].rooms[k].name,
                                onChanged: (v) => floors[i].rooms[k].name = v,
                                decoration: const InputDecoration(hintText: 'Tên phòng'),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            const Text('File ETS (không bắt buộc)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                EvoButton(label: etsFile == null ? 'Chọn file ETS…' : 'Chọn file khác…', icon: Icons.upload_file_outlined, onPressed: busy ? null : _pickEts),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    busy
                        ? 'Đang đọc file…'
                        : etsError != null
                        ? etsError!
                        : ets != null
                        ? '$etsFile: ${ets!.items.length} địa chỉ nhóm${ets!.projectName.isNotEmpty ? ' (project “${ets!.projectName}”)' : ''}'
                        : '.knxproj, hoặc danh sách địa chỉ nhóm CSV/XML',
                    style: TextStyle(fontSize: 14.5, color: etsError != null ? c.danger : (ets != null ? c.accentInk : c.muted)),
                  ),
                ),
                if (ets != null || etsError != null)
                  IconButton(
                    tooltip: 'Bỏ file',
                    onPressed: () => setState(() {
                      ets = null;
                      etsError = null;
                      etsFile = null;
                    }),
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
          ],
        ),
      );
      actions = [
        EvoButton(label: 'Quay lại', onPressed: () => setState(() => step = 'choose')),
        EvoButton(label: 'Tạo dự án', primary: true, onPressed: busy ? null : () => Navigator.pop(context, _build())),
      ];
    }
    return AlertDialog(
      title: Text(switch (step) {
        'quick' => 'Tạo dự án nhanh',
        'manual' => 'Tạo dự án thủ công',
        _ => 'Tạo dự án mới',
      }, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: SizedBox(width: 600, child: content),
      actions: actions,
    );
  }
}
