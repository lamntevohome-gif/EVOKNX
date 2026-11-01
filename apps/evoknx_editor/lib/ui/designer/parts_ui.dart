import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../../state/project_files.dart';
import '../common.dart';
import 'designer.dart';

const _partType = XTypeGroup(label: 'Tầng / phòng / trang EVOKNX', extensions: ['evoknxpart']);
const _kindName = {'floor': 'tầng', 'room': 'phòng', 'page': 'trang'};

/// "Xuất tầng/phòng/trang…" and "Nhập…" buttons.
class PartButtons extends StatelessWidget {
  const PartButtons({super.key, required this.d, required this.kind, this.id, this.importHint});
  final Designer d;

  /// What the export button exports (floor, room, page); null = import only.
  final String? kind;
  final String? id;
  final String? importHint;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (kind != null && id != null)
          EvoButton(label: 'Xuất ${_kindName[kind]}…', icon: Icons.file_upload_outlined, small: true, onPressed: () => exportPart(context, d, kind!, id!)),
        EvoButton(label: importHint ?? 'Nhập từ file…', icon: Icons.file_download_outlined, small: true, onPressed: () => importPart(context, d)),
      ],
    );
  }
}

Future<void> exportPart(BuildContext context, Designer d, String kind, String id) async {
  final part = makePart(d.doc, kind, id);
  if (part == null) return;
  final dir = d.p.projectDir;
  final loc = await getSaveLocation(
    acceptedTypeGroups: const [_partType],
    suggestedName: '${safeName((part['name'] ?? kind).toString())} (${_kindName[kind]}).evoknxpart',
    initialDirectory: dir,
    confirmButtonText: 'Xuất',
  );
  if (loc == null) return;
  final file = loc.path.toLowerCase().endsWith('.evoknxpart') ? loc.path : '${loc.path}.evoknxpart';
  try {
    await File(file).writeAsString(const JsonEncoder.withIndent('  ').convert(part));
    if (context.mounted) {
      toast(context, 'Đã xuất ${_kindName[kind]} “${part['name']}” (${jsonList(part['groupAddresses']).length} địa chỉ nhóm) ra ${baseName(file)}');
    }
  } catch (e) {
    if (context.mounted) toast(context, 'Không ghi được file: $e');
  }
}

/// Imports a floor (added at the end), a room (into the selected floor) or a
/// page (into the selected room).
Future<void> importPart(BuildContext context, Designer d) async {
  final f = await openFile(acceptedTypeGroups: const [_partType], confirmButtonText: 'Nhập');
  if (f == null) return;
  Object? o;
  try {
    o = jsonDecode(await f.readAsString());
  } catch (_) {
    o = null;
  }
  if (!context.mounted) return;
  if (o is! Map || !isPart(o)) {
    toast(context, 'File không phải tầng/phòng/trang EVOKNX.');
    return;
  }
  final part = o.cast<String, dynamic>();
  final kind = part['kind'] as String;
  final floorId = d.floor?['id'] as String?;
  final roomId = d.room?['id'] as String?;
  final where = switch (kind) {
    'room' => 'vào tầng “${d.floor?['title'] ?? ''}”',
    'page' => 'vào phòng “${d.room?['title'] ?? ''}”',
    _ => 'thành tầng mới',
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Nhập ${_kindName[kind]} “${part['name']}”?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 460,
        child: Text(
          'Sẽ thêm $where. Địa chỉ nhóm trùng địa chỉ KNX với dự án này được dùng lại, địa chỉ mới được thêm vào danh sách. Có thể hoàn tác (Ctrl+Z).',
        ),
      ),
      actions: [
        EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(c, false)),
        EvoButton(label: 'Nhập', primary: true, onPressed: () => Navigator.pop(c, true)),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  late PartResult res;
  d.p.mutate((doc) => res = applyPart(doc, part, floorId: floorId, roomId: roomId));
  if (!context.mounted) return;
  if (res.error != null) {
    toast(context, res.error!);
    return;
  }
  final id = res.firstId;
  if (id != null) {
    if (kind == 'floor') d.selectFloor(id);
    if (kind == 'room') d.selectRoom(id);
    if (kind == 'page' && roomId != null) d.selectSub(roomId, id);
  }
  toast(
    context,
    'Đã nhập ${res.floors > 0 ? '${res.floors} tầng, ' : ''}${res.rooms > 0 ? '${res.rooms} phòng, ' : ''}${res.pages} trang, ${res.widgets} thành phần. '
    'Địa chỉ nhóm: ${res.reusedAddresses} dùng lại, ${res.newAddresses} thêm mới.',
  );
}
