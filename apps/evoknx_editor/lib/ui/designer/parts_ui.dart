import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;
import 'package:knx_config/knx_config.dart';

import '../../state/card_library.dart';
import '../../state/project_files.dart';
import '../common.dart';
import 'designer.dart';

const _partType = XTypeGroup(label: 'Tầng / phòng / trang / thẻ EvoKNX', extensions: ['evoknxpart']);
const _kindName = {'floor': 'tầng', 'room': 'phòng', 'page': 'trang', 'card': 'thẻ'};

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
    confirmButtonText: tr('Xuất'),
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
/// [only] limits what the place accepts: the "Nhập trang" button of a room
/// takes page files only, the one of a page takes cards only, and so on.
Future<void> importPart(BuildContext context, Designer d, {String? only}) async {
  final f = await openFile(acceptedTypeGroups: const [_partType], confirmButtonText: tr('Nhập'));
  if (f == null) return;
  Object? o;
  try {
    o = jsonDecode(await f.readAsString());
  } catch (_) {
    o = null;
  }
  if (!context.mounted) return;
  if (o is! Map || !isPart(o)) {
    toast(context, 'File không phải tầng/phòng/trang EvoKNX.');
    return;
  }
  final part = o.cast<String, dynamic>();
  final kind = part['kind'] as String;
  if (only != null && kind != only) {
    toast(
      context,
      'File này là ${_kindName[kind]}, không phải ${_kindName[only]}. Nhập ${_kindName[kind]} ở ${switch (kind) {
        'floor' => 'Tổng quan (chuột phải)',
        'room' => 'tầng',
        'page' => 'phòng',
        _ => 'trang',
      }}.',
    );
    return;
  }
  if (kind == 'card') {
    await _importCard(context, d, part);
    return;
  }
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
      title: Text('Nhập ${_kindName[kind]} “${part['name']}”?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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

/// Exports the selected card (a grid frame with its cards): asks for the card
/// name, then where to save it; optionally also adds it to the card library.
Future<void> exportCard(BuildContext context, Designer d, Json w) async {
  final ctl = TextEditingController(
    text: (w['label'] ?? '').toString().trim().isEmpty ? (kWidgetTypes[w['type']]?.name ?? 'Thẻ') : (w['label'] ?? '').toString().trim(),
  );
  var toLibrary = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: const Text('Xuất thẻ'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel('Tên thẻ', TextField(controller: ctl, autofocus: true, onSubmitted: (_) => Navigator.pop(c, true))),
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(value: toLibrary, onChanged: (v) => setS(() => toLibrary = v == true)),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Thêm vào Thư viện thẻ')),
                ],
              ),
            ],
          ),
        ),
        actions: [
          EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Xuất…', primary: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    ),
  );
  final name = ctl.text.trim();
  ctl.dispose();
  if (ok != true || !context.mounted) return;
  final part = makeCardPart(d.doc, w);
  if (name.isNotEmpty) part['name'] = name;
  final loc = await getSaveLocation(
    acceptedTypeGroups: const [_partType],
    suggestedName: '${safeName((part['name'] ?? 'The').toString())} (thẻ).evoknxpart',
    initialDirectory: d.p.projectDir,
    confirmButtonText: tr('Xuất'),
  );
  if (loc == null) return;
  final file = loc.path.toLowerCase().endsWith('.evoknxpart') ? loc.path : '${loc.path}.evoknxpart';
  try {
    await File(file).writeAsString(const JsonEncoder.withIndent('  ').convert(part));
    if (toLibrary) await cardLibrary.add(part);
    if (context.mounted) toast(context, 'Đã xuất thẻ “${part['name']}” ra ${baseName(file)}${toLibrary ? ' và thêm vào Thư viện thẻ' : ''}');
  } catch (e) {
    if (context.mounted) toast(context, 'Không ghi được file: $e');
  }
}

Future<void> _importCard(BuildContext context, Designer d, Json part) async {
  final sub = d.sub;
  if (sub == null) {
    toast(context, 'Hãy chọn một trang để nhập thẻ vào.');
    return;
  }
  final nGa = jsonList(part['groupAddresses']).length;
  var keep = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text('Nhập thẻ “${part['name']}”?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Thẻ được đặt vào chỗ trống đầu tiên của trang “${sub['title'] ?? ''}”, giữ nguyên mọi cài đặt (kiểu, màu, biểu tượng, chế độ…).'),
              const SizedBox(height: 12),
              RadioListTile<bool>(
                value: true,
                groupValue: keep,
                onChanged: (v) => setS(() => keep = true),
                title: const Text('Giữ địa chỉ nhóm đã gán'),
                subtitle: Text(nGa == 0 ? 'Thẻ chưa gán địa chỉ nào.' : '$nGa địa chỉ; địa chỉ trùng với dự án này được dùng lại.'),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: keep,
                onChanged: (v) => setS(() => keep = false),
                title: const Text('Bỏ địa chỉ nhóm, gán lại sau'),
                subtitle: const Text('Dùng thẻ như mẫu cho phòng khác.'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        actions: [
          EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Nhập', primary: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final sid = sub['id'];
  late PartResult res;
  d.p.mutate((doc) {
    final target = allSubpages(doc).firstWhere((x) => x['id'] == sid);
    res = applyCardPart(doc, part, target, keepAddresses: keep);
  });
  if (!context.mounted) return;
  if (res.error != null) {
    toast(context, res.error!);
    return;
  }
  if (res.firstId != null) d.selectWidget(res.firstId!);
  toast(
    context,
    'Đã nhập ${res.widgets} thẻ${keep ? '. Địa chỉ nhóm: ${res.reusedAddresses} dùng lại, ${res.newAddresses} thêm mới.' : ', chưa gán địa chỉ nhóm.'}',
  );
}

/// "+" of the card library: adds card files (.evoknxpart) to the library.
Future<void> importCardsToLibrary(BuildContext context) async {
  final files = await openFiles(acceptedTypeGroups: const [_partType], confirmButtonText: tr('Thêm vào thư viện'));
  if (files.isEmpty) return;
  var n = 0, skipped = 0;
  for (final f in files) {
    try {
      final o = jsonDecode(await f.readAsString());
      if (o is Map && isPart(o) && o['kind'] == 'card') {
        await cardLibrary.add(o.cast<String, dynamic>());
        n++;
      } else {
        skipped++;
      }
    } catch (_) {
      skipped++;
    }
  }
  if (context.mounted) {
    toast(context, 'Đã thêm $n thẻ vào thư viện${skipped > 0 ? '; bỏ qua $skipped file không phải thẻ' : ''}.');
  }
}
