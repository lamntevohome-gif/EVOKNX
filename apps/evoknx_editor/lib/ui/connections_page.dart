import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:knx_config/knx_config.dart';
import 'package:knx_core/knx_core.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';
import 'import_dialog.dart';

/// Kết nối workspace: KNX connections (left) and group addresses (right).
class ConnectionsPage extends StatelessWidget {
  const ConnectionsPage({super.key, required this.project});
  final ProjectController project;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 360,
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(right: BorderSide(color: c.line)),
          ),
          child: _ConnectionList(project: project),
        ),
        Expanded(child: GaTable(project: project)),
      ],
    );
  }
}

class _ConnectionList extends StatelessWidget {
  const _ConnectionList({required this.project});
  final ProjectController project;

  void _edit(String id, void Function(Json c) fn, {String? field}) {
    project.mutate((d) {
      for (final c in jsonList(d['connections'])) {
        if (c['id'] == id) fn(c);
      }
    }, coalesce: field == null ? null : 'conn:$id:$field');
  }

  void _move(int from, int to) {
    project.mutate((d) {
      final l = d['connections'] as List;
      final x = l.removeAt(from);
      l.insert(to, x);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final list = project.connections;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionTitle(
          'Kết nối KNX',
          trailing: EvoButton(
            label: 'Thêm kết nối',
            icon: Icons.add,
            small: true,
            onPressed: () => project.mutate(
              (d) => (d['connections'] as List).add({
                'id': uid('conn_'),
                'name': 'Kết nối ${list.length + 1}',
                'type': 'tunneling',
                'host': '',
                'port': 3671,
                'natMode': true,
              }),
            ),
          ),
        ),
        for (var i = 0; i < list.length; i++)
          Container(
            key: ValueKey(list[i]['id']),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.panel,
              border: Border.all(color: i == 0 ? c.accent.withValues(alpha: 0.6) : c.line),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SyncedField(
                        value: (list[i]['name'] as String?) ?? '',
                        hint: 'Tên kết nối',
                        bold: true,
                        onChanged: (v) => _edit(list[i]['id'] as String, (x) => x['name'] = v, field: 'name'),
                      ),
                    ),
                    if (i == 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(5)),
                        child: Text(
                          'Mặc định',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.accentInk),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                FieldLabel(
                  'Kiểu kết nối',
                  EvoDropdown<bool>(
                    width: double.infinity,
                    value: list[i]['natMode'] == true,
                    items: const [(false, 'Local (mạng nội bộ)'), (true, 'NAT mode')],
                    onChanged: (v) => _edit(list[i]['id'] as String, (x) => x['natMode'] = v),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FieldLabel(
                        'IP / tên miền',
                        SyncedField(
                          value: (list[i]['host'] as String?) ?? '',
                          hint: '192.168.1.50',
                          onChanged: (v) => _edit(list[i]['id'] as String, (x) => x['host'] = v.trim(), field: 'host'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 84,
                      child: FieldLabel(
                        'Cổng',
                        SyncedField(
                          value: '${list[i]['port'] ?? 3671}',
                          number: true,
                          onChanged: (v) => _edit(list[i]['id'] as String, (x) => x['port'] = int.tryParse(v) ?? 3671, field: 'port'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (i > 0) EvoButton(label: 'Đặt làm mặc định', small: true, onPressed: () => _move(i, 0)),
                    if (i > 1) EvoButton(label: '', icon: Icons.arrow_upward, small: true, tooltip: 'Đưa lên', onPressed: () => _move(i, i - 1)),
                    if (i > 0 && i < list.length - 1)
                      EvoButton(label: '', icon: Icons.arrow_downward, small: true, tooltip: 'Đưa xuống', onPressed: () => _move(i, i + 1)),
                    if (list.length > 1)
                      EvoButton(
                        label: 'Xoá',
                        icon: Icons.delete_outline,
                        small: true,
                        danger: true,
                        onPressed: () {
                          final id = list[i]['id'];
                          project.mutate((d) => (d['connections'] as List).removeWhere((x) => x is Map && x['id'] == id));
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- GA table

class GaTable extends StatefulWidget {
  const GaTable({super.key, required this.project});
  final ProjectController project;
  @override
  State<GaTable> createState() => _GaTableState();
}

class _GaTableState extends State<GaTable> {
  String query = '';
  String filter = 'all';
  final Set<String> selected = {};
  int? lastIndex;
  String bulkDpt = '';

  ProjectController get p => widget.project;

  List<Json> _filtered() {
    final q = fold(query.trim());
    final list = p.groupAddresses.where((g) {
      if (q.isNotEmpty && !fold('${g['address']} ${g['name']}').contains(q)) return false;
      final dpt = (g['dpt'] as String?) ?? '';
      if (filter == 'none') return dpt.isEmpty;
      if (filter != 'all') return '${dptMain(dpt)}' == filter;
      return true;
    }).toList()..sort((a, b) => gaSortKey(a['address'] as String).compareTo(gaSortKey(b['address'] as String)));
    return list;
  }

  void _toggle(List<Json> list, int i, bool? on) {
    setState(() {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (shift && lastIndex != null) {
        final lo = lastIndex! < i ? lastIndex! : i, hi = lastIndex! < i ? i : lastIndex!;
        for (var k = lo; k <= hi && k < list.length; k++) {
          on == true ? selected.add(list[k]['id'] as String) : selected.remove(list[k]['id'] as String);
        }
      } else {
        on == true ? selected.add(list[i]['id'] as String) : selected.remove(list[i]['id'] as String);
      }
      lastIndex = i;
    });
  }

  void _edit(String id, void Function(Json g) fn, {String? field}) {
    p.mutate((d) {
      for (final g in jsonList(d['groupAddresses'])) {
        if (g['id'] == id) fn(g);
      }
    }, coalesce: field == null ? null : 'ga:$id:$field');
  }

  void _delete(Set<String> ids) {
    var unlinked = 0;
    p.mutate((d) {
      (d['groupAddresses'] as List).removeWhere((g) => g is Map && ids.contains(g['id']));
      for (final w in allWidgets(d)) {
        final b = jsonMap(w['bind']);
        b.removeWhere((k, v) {
          final hit = ids.contains(v);
          if (hit) unlinked++;
          return hit;
        });
      }
    });
    setState(() => selected.removeAll(ids));
    toast(context, 'Đã xoá ${ids.length} địa chỉ${unlinked > 0 ? ', gỡ $unlinked liên kết' : ''}. Có thể hoàn tác (Ctrl+Z).');
  }

  Future<void> _addManual() async {
    final r = await showDialog<Json>(
      context: context,
      builder: (_) => _AddGaDialog(existing: p.groupAddresses.map((g) => g['address'] as String).toSet()),
    );
    if (r == null) return;
    p.mutate((d) => (d['groupAddresses'] as List).add(r));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    selected.removeWhere((id) => p.gaById(id) == null);
    final list = _filtered();
    final used = gaUsage(p.doc);
    final mains = p.groupAddresses.map((g) => dptMain(g['dpt'] as String?)).whereType<int>().toSet().toList()..sort();
    final nNone = p.groupAddresses.where((g) => ((g['dpt'] as String?) ?? '').isEmpty).length;
    final nSel = list.where((g) => selected.contains(g['id'])).length;

    Widget head(String t, {double? w, int flex = 0}) {
      final txt = Text(
        t,
        style: TextStyle(fontSize: 12.5, color: c.muted, fontWeight: FontWeight.w500),
      );
      return flex > 0 ? Expanded(flex: flex, child: txt) : SizedBox(width: w, child: txt);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Địa chỉ nhóm ',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: '${p.groupAddresses.length}',
                      style: TextStyle(fontSize: 14, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SearchField(onChanged: (v) => setState(() => query = v)),
              EvoDropdown<String>(
                value: filter,
                items: [('all', 'Tất cả DPT'), ('none', 'Chưa có DPT ($nNone)'), for (final m in mains) ('$m', 'DPT $m.x')],
                onChanged: (v) => setState(() => filter = v),
              ),
              const SizedBox(width: 24),
              EvoButton(label: 'Thêm thủ công', icon: Icons.add, small: true, onPressed: _addManual),
              EvoButton(label: 'Nhập từ ETS', icon: Icons.upload_outlined, small: true, primary: true, onPressed: () => runEtsImport(context, p)),
            ],
          ),
        ),
        if (selected.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: c.accentSoft,
            child: Row(
              children: [
                Text(
                  'Đã chọn ${selected.length} địa chỉ',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.accentInk),
                ),
                const SizedBox(width: 12),
                EvoDropdown<String>(
                  width: 240,
                  value: bulkDpt,
                  items: dptItems(bulkDpt, none: 'Chọn DPT để gán…'),
                  onChanged: (v) => setState(() => bulkDpt = v),
                ),
                const SizedBox(width: 8),
                EvoButton(
                  label: 'Gán DPT',
                  small: true,
                  primary: true,
                  onPressed: bulkDpt.isEmpty
                      ? null
                      : () {
                          final ids = Set<String>.from(selected);
                          p.mutate((d) {
                            for (final g in jsonList(d['groupAddresses'])) {
                              if (ids.contains(g['id'])) g['dpt'] = bulkDpt;
                            }
                          });
                          toast(context, 'Đã gán DPT $bulkDpt cho ${ids.length} địa chỉ.');
                        },
                ),
                const SizedBox(width: 8),
                EvoButton(label: 'Xoá', icon: Icons.delete_outline, small: true, danger: true, onPressed: () => _delete(Set<String>.from(selected))),
                const Spacer(),
                EvoButton(label: 'Bỏ chọn', small: true, onPressed: () => setState(selected.clear)),
              ],
            ),
          ),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Checkbox(
                  tristate: true,
                  value: list.isEmpty ? false : (nSel == 0 ? false : (nSel == list.length ? true : null)),
                  onChanged: (_) => setState(() {
                    if (nSel == list.length) {
                      for (final g in list) {
                        selected.remove(g['id']);
                      }
                    } else {
                      for (final g in list) {
                        selected.add(g['id'] as String);
                      }
                    }
                  }),
                ),
              ),
              head('Địa chỉ', w: 100),
              head('Tên', flex: 1),
              head('DPT', w: 250),
              head('Đang dùng', w: 120),
              const SizedBox(width: 40),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    p.groupAddresses.isEmpty ? 'Chưa có địa chỉ nhóm. Bấm “Nhập từ ETS” hoặc “Thêm thủ công”.' : 'Không có địa chỉ nào khớp bộ lọc.',
                    style: TextStyle(color: c.muted),
                  ),
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemExtent: 44,
                  itemBuilder: (context, i) {
                    final g = list[i];
                    final id = g['id'] as String;
                    final sel = selected.contains(id);
                    final dpt = (g['dpt'] as String?) ?? '';
                    return Container(
                      key: ValueKey(id),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: sel ? c.accentSoft : c.panel,
                        border: Border(bottom: BorderSide(color: c.line)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Checkbox(value: sel, onChanged: (v) => _toggle(list, i, v)),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              g['address'] as String,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: SyncedField(
                                value: (g['name'] as String?) ?? '',
                                hint: 'Chưa đặt tên',
                                borderless: true,
                                onChanged: (v) => _edit(id, (x) {
                                  x['name'] = v;
                                  x['nameEdited'] = true;
                                }, field: 'name'),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 250,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: EvoDropdown<String>(
                                width: 230,
                                value: dpt,
                                warn: dpt.isEmpty,
                                items: dptItems(dpt),
                                onChanged: (v) => _edit(id, (x) => x['dpt'] = v),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(used[id] != null ? '${used[id]} thành phần' : '', style: TextStyle(fontSize: 12.5, color: c.muted)),
                          ),
                          SizedBox(
                            width: 40,
                            child: IconButton(
                              tooltip: 'Xoá ${g['address']}',
                              icon: Icon(Icons.close, size: 17, color: c.muted),
                              onPressed: () => _delete({id}),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AddGaDialog extends StatefulWidget {
  const _AddGaDialog({required this.existing});
  final Set<String> existing;
  @override
  State<_AddGaDialog> createState() => _AddGaDialogState();
}

class _AddGaDialogState extends State<_AddGaDialog> {
  final _addr = TextEditingController();
  final _name = TextEditingController();
  String dpt = '';
  String? error;

  @override
  void dispose() {
    _addr.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final a = _addr.text.trim();
    final ga = GroupAddress.tryParse(a);
    if (ga == null || !a.contains('/')) {
      setState(() => error = 'Địa chỉ không hợp lệ. Dùng dạng 1/1/1 (3 cấp) hoặc 1/25 (2 cấp).');
      return;
    }
    if (widget.existing.contains(a)) {
      setState(() => error = 'Địa chỉ $a đã có trong danh sách.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{'id': gaId(a), 'address': a, 'name': _name.text.trim(), 'dpt': dpt, 'nameEdited': true});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm địa chỉ nhóm', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: FieldLabel(
                    'Địa chỉ',
                    TextField(
                      controller: _addr,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: '1/1/1'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'DPT',
                    EvoDropdown<String>(width: double.infinity, value: dpt, items: dptItems(dpt), onChanged: (v) => setState(() => dpt = v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FieldLabel(
              'Tên',
              TextField(
                controller: _name,
                decoration: const InputDecoration(hintText: 'Đèn trần phòng khách'),
                onSubmitted: (_) => _submit(),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  error!,
                  style: TextStyle(color: context.evo.danger, fontSize: kUiText),
                ),
              ),
          ],
        ),
      ),
      actions: [
        EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(context)),
        EvoButton(label: 'Thêm địa chỉ', primary: true, onPressed: _submit),
      ],
    );
  }
}
