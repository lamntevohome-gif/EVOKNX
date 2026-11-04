import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// Picks an ETS file and imports it, asking replace/update when needed.
Future<void> runEtsImport(BuildContext context, ProjectController project) async {
  final r = await project.pickEts();
  if (!context.mounted) return;
  if (r.error != null) {
    toast(context, r.error!);
    return;
  }
  final ets = r.result;
  if (ets == null) return;
  if (project.groupAddresses.isEmpty) {
    late ImportResult res;
    project.mutate((d) => res = applyEts(d, ets));
    toast(context, 'Đã nhập ${res.added} địa chỉ nhóm.');
    return;
  }
  final stats = importStats(project.doc, ets.items);
  final choice = await showDialog<(bool, bool)>(
    context: context,
    builder: (_) => _ImportDialog(fileName: r.fileName ?? '', count: ets.items.length, stats: stats),
  );
  if (choice == null || !context.mounted) return;
  late ImportResult res;
  project.mutate((d) => res = applyEts(d, ets, replace: choice.$1, keepEditedNames: choice.$2));
  toast(
    context,
    'Đã nhập: ${res.added} mới, cập nhật ${res.updated}${res.removed > 0 ? ', xoá ${res.removed}' : ''}${res.unlinked > 0 ? ', gỡ ${res.unlinked} liên kết' : ''}. Có thể hoàn tác (Ctrl+Z).',
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.fileName, required this.count, required this.stats});
  final String fileName;
  final int count;
  final ImportStats stats;
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool replace = false;
  bool keep = true;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final s = widget.stats;
    Widget stat(int n, String t, {bool warn = false}) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: warn && n > 0 ? c.warn : c.line),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$n',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: warn && n > 0 ? c.warn : c.ink),
            ),
            Text(t, style: TextStyle(fontSize: 11.5, color: c.muted)),
          ],
        ),
      ),
    );
    Widget option(bool value, String title, String desc) => InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () => setState(() => replace = value),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: replace == value ? c.accentSoft : null,
          border: Border.all(color: replace == value ? c.accent : c.line),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(replace == value ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: c.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(fontSize: kUiText, color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return AlertDialog(
      title: const Text('Nhập địa chỉ nhóm từ ETS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File “${widget.fileName}” có ${widget.count} địa chỉ nhóm.', style: TextStyle(color: c.muted)),
            const SizedBox(height: 12),
            Row(
              children: [
                stat(s.fresh, 'địa chỉ mới'),
                const SizedBox(width: 8),
                stat(s.both, 'đã có trong dự án'),
                const SizedBox(width: 8),
                stat(s.gone, 'không còn trong file', warn: true),
              ],
            ),
            const SizedBox(height: 6),
            option(false, 'Cập nhật và thêm mới', 'Giữ toàn bộ địa chỉ hiện có, thêm ${s.fresh} địa chỉ mới, cập nhật tên và DPT cho ${s.both} địa chỉ đã có.'),
            option(
              true,
              'Thay thế toàn bộ',
              'Danh sách địa chỉ sẽ giống hệt file ETS. ${s.gone > 0 ? 'Xoá ${s.gone} địa chỉ không còn trong file${s.links > 0 ? ', gỡ ${s.links} liên kết trên các thành phần' : ''}.' : 'Không có địa chỉ nào bị xoá.'}',
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: keep,
              onChanged: (v) => setState(() => keep = v ?? true),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Giữ tên tôi đã sửa${s.edited > 0 ? ' (${s.edited} địa chỉ)' : ''}, không ghi đè bằng tên trong file',
                style: const TextStyle(fontSize: kUiText),
              ),
            ),
          ],
        ),
      ),
      actions: [
        EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(context)),
        EvoButton(label: 'Nhập', primary: true, onPressed: () => Navigator.pop(context, (replace, keep))),
      ],
    );
  }
}
