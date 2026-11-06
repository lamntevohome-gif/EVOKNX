import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// The "HA" workspace: the project's Home Assistant connection and the entities
/// wired to virtual addresses (main group 32). Cards use those addresses like
/// any other; the App sends them to Home Assistant instead of the KNX bus.
class HaPage extends StatefulWidget {
  const HaPage({super.key, required this.project});
  final ProjectController project;

  @override
  State<HaPage> createState() => _HaPageState();
}

class _HaPageState extends State<HaPage> {
  List<HaEntity>? entities;
  String? status;
  bool statusOk = false;
  bool busy = false;

  ProjectController get p => widget.project;

  void _setHa(String key, Object? v, {String? coalesce}) {
    p.mutate((d) {
      final h = Map<String, dynamic>.from(haSettings(d));
      h[key] = v;
      d['ha'] = h;
    }, coalesce: coalesce ?? 'ha-$key');
  }

  Future<bool> _fetch() async {
    final h = haSettings(p.doc);
    final url = (h['url'] ?? '').toString().trim(), token = (h['token'] ?? '').toString().trim();
    if (url.isEmpty || token.isEmpty) {
      setState(() {
        status = 'Nhập địa chỉ và token trước.';
        statusOk = false;
      });
      return false;
    }
    setState(() {
      busy = true;
      status = 'Đang kết nối…';
      statusOk = false;
    });
    try {
      final r = await haFetchEntities(url, token);
      if (!mounted) return false;
      setState(() {
        entities = r.entities;
        status = 'Đã kết nối · Home Assistant ${r.version ?? ''} · ${r.entities.length} thực thể';
        statusOk = true;
        busy = false;
      });
      return true;
    } on HaException catch (e) {
      if (mounted) {
        setState(() {
          status = e.message;
          statusOk = false;
          busy = false;
        });
      }
      return false;
    }
  }

  Future<void> _add() async {
    if (entities == null && !await _fetch()) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _AddEntityDialog(project: p, entities: entities!),
    );
  }

  Future<void> _remove(String entityId, String title) async {
    final uses = haEntityUses(p.doc, entityId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Gỡ “$title”?'),
        content: Text(
          uses > 0
              ? 'Có $uses ô địa chỉ của thẻ đang dùng thực thể này; chúng sẽ bị gỡ liên kết. Có thể hoàn tác (Ctrl+Z).'
              : 'Các địa chỉ ảo của thực thể này sẽ bị xoá. Có thể hoàn tác (Ctrl+Z).',
        ),
        actions: [
          EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Gỡ', danger: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok == true) p.mutate((d) => removeHaEntity(d, entityId));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final h = haSettings(p.doc);
        final mapped = haAddresses(p.doc);
        // Group the virtual addresses by entity, in address order.
        final byEntity = <String, List<Json>>{};
        for (final g in mapped) {
          (byEntity[(g['ha']['entity'] ?? '').toString()] ??= []).add(g);
        }
        return LayoutBuilder(
          builder: (context, bc) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: (bc.maxWidth * 0.34).clamp(360.0, 560.0).toDouble(),
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border(right: BorderSide(color: c.line)),
                ),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Home Assistant',
                      style: TextStyle(fontSize: kUiText + 2, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(value: h['enabled'] == true, onChanged: (v) => _setHa('enabled', v == true)),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Dùng Home Assistant trong dự án này')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FieldLabel(
                      'Địa chỉ',
                      SyncedField(
                        value: (h['url'] ?? '').toString(),
                        hint: 'vd 192.168.1.5:8123 hoặc https://xxx.ui.nabu.casa',
                        onChanged: (v) => _setHa('url', v.trim()),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FieldLabel(
                      'Token (Long-lived access token)',
                      _TokenField(value: (h['token'] ?? '').toString(), onChanged: (v) => _setHa('token', v.trim())),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        EvoButton(label: 'Thử kết nối', primary: true, onPressed: busy ? null : _fetch),
                        const SizedBox(width: 8),
                        EvoButton(label: 'Thêm thực thể…', icon: Icons.add, onPressed: busy ? null : _add),
                      ],
                    ),
                    if (status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(statusOk ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: statusOk ? const Color(0xFF14AE5C) : c.warn),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(status!, style: TextStyle(color: statusOk ? c.ink : c.warn)),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'Mỗi thực thể được gán các địa chỉ ảo nhóm chính 32 (ngoài dải KNX 0–31 nên không bao giờ trùng địa chỉ thật). '
                      'Địa chỉ lệnh 32/m/k, địa chỉ trạng thái 32/m/(100+k). Thẻ gán các địa chỉ này như địa chỉ KNX bình thường; '
                      'App gửi chúng tới Home Assistant, không đưa ra bus. Địa chỉ, token được lưu trong file dự án.',
                      style: TextStyle(fontSize: kUiText - 1, height: 1.45, color: c.muted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: byEntity.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Chưa có thực thể nào. Bấm “Thêm thực thể…” để chọn đèn, công tắc, rèm, máy lạnh… từ Home Assistant.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.muted),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Thực thể đã gán (${byEntity.length})',
                              style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                            ),
                          ),
                          for (final e in byEntity.entries) _entityCard(c, e.key, e.value),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _entityCard(EvoColors c, String entityId, List<Json> gas) {
    final title = (gas.first['name'] ?? entityId).toString().split(' · ').first;
    // One row per attribute: its command and status address.
    final byAttr = <String, Map<String, Json>>{};
    for (final g in gas) {
      final h = g['ha'] as Map;
      (byAttr[(h['attr'] ?? '').toString()] ??= {})[(h['role'] ?? '').toString()] = g;
    }
    final keys = byAttr.keys.toList()..sort((a, b) => kHaAttrs.indexWhere((x) => x.key == a).compareTo(kHaAttrs.indexWhere((x) => x.key == b)));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                      ),
                      Text(
                        entityId,
                        style: TextStyle(fontSize: kUiText - 1, color: c.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Gỡ thực thể này',
                  icon: Icon(Icons.delete_outline, color: c.danger),
                  onPressed: () => _remove(entityId, title),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          for (final k in keys)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(haAttr(k)?.label ?? k, style: TextStyle(color: c.ink)),
                  ),
                  SizedBox(
                    width: 150,
                    child: Text(byAttr[k]!['cmd'] == null ? '' : 'Lệnh ${byAttr[k]!['cmd']!['address']}', style: TextStyle(color: c.muted)),
                  ),
                  SizedBox(
                    width: 170,
                    child: Text(byAttr[k]!['status'] == null ? '' : 'Trạng thái ${byAttr[k]!['status']!['address']}', style: TextStyle(color: c.muted)),
                  ),
                  Text('DPT ${(byAttr[k]!.values.first['dpt'] ?? '').toString()}', style: TextStyle(color: c.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A password-style box for the token (with a show / hide button).
class _TokenField extends StatefulWidget {
  const _TokenField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TokenField> createState() => _TokenFieldState();
}

class _TokenFieldState extends State<_TokenField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  bool hide = true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      obscureText: hide,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        suffixIcon: IconButton(
          tooltip: hide ? 'Hiện token' : 'Ẩn token',
          icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
          onPressed: () => setState(() => hide = !hide),
        ),
      ),
    );
  }
}

/// Picks entities of Home Assistant and the things of each one to use.
class _AddEntityDialog extends StatefulWidget {
  const _AddEntityDialog({required this.project, required this.entities});
  final ProjectController project;
  final List<HaEntity> entities;

  @override
  State<_AddEntityDialog> createState() => _AddEntityDialogState();
}

class _AddEntityDialogState extends State<_AddEntityDialog> {
  String q = '';
  String domain = '';
  HaEntity? sel;
  final Set<String> keys = {};
  int added = 0;

  List<HaEntity> get usable => [
    for (final e in widget.entities)
      if (haSuggest(e).isNotEmpty) e,
  ];

  String _fold(String s) => s.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final mappedIds = {for (final g in haAddresses(widget.project.doc)) (g['ha']['entity'] ?? '').toString()};
    final domains = {for (final e in usable) e.domain}.toList()..sort();
    final list = [
      for (final e in usable)
        if ((domain.isEmpty || e.domain == domain) && (q.isEmpty || _fold('${e.name} ${e.id}').contains(_fold(q)))) e,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return AlertDialog(
      title: const Text('Thêm thực thể từ Home Assistant'),
      content: SizedBox(
        width: 720,
        height: 460,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchField(hint: 'Tìm theo tên hoặc mã thực thể', width: double.infinity, onChanged: (v) => setState(() => q = v)),
                  const SizedBox(height: 8),
                  EvoDropdown<String>(
                    value: domain,
                    items: [('', 'Tất cả loại (${usable.length})'), for (final d in domains) (d, d)],
                    onChanged: (v) => setState(() => domain = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final e = list[i];
                        final on = sel?.id == e.id;
                        return InkWell(
                          onTap: () => setState(() {
                            sel = e;
                            keys
                              ..clear()
                              ..addAll(haSuggest(e).map((a) => a.key));
                          }),
                          child: Container(
                            color: on ? c.accentSoft : null,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: c.ink),
                                      ),
                                      Text(
                                        e.id,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: kUiText - 2, color: c.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (mappedIds.contains(e.id)) Icon(Icons.check, size: 16, color: c.accentInk),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 4,
              child: sel == null
                  ? Center(
                      child: Text('Chọn một thực thể bên trái.', style: TextStyle(color: c.muted)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sel!.name,
                          style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                        ),
                        Text(
                          sel!.id,
                          style: TextStyle(fontSize: kUiText - 1, color: c.muted),
                        ),
                        const SizedBox(height: 10),
                        Text('Dùng để:', style: TextStyle(color: c.muted)),
                        for (final a in haSuggest(sel!))
                          Row(
                            children: [
                              Checkbox(value: keys.contains(a.key), onChanged: (v) => setState(() => v == true ? keys.add(a.key) : keys.remove(a.key))),
                              Expanded(child: Text('${a.label}  ·  DPT ${a.dpt}')),
                            ],
                          ),
                        const Spacer(),
                        EvoButton(
                          label: 'Thêm vào dự án',
                          primary: true,
                          onPressed: keys.isEmpty
                              ? null
                              : () {
                                  final e = sel!;
                                  var n = 0;
                                  widget.project.mutate((d) => n = addHaEntity(d, e, keys.toList()).length);
                                  setState(() {
                                    added += n > 0 ? 1 : 0;
                                    sel = null;
                                  });
                                  if (n == 0) toast(context, 'Các địa chỉ này đã có.');
                                },
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [EvoButton(label: added > 0 ? 'Xong ($added đã thêm)' : 'Đóng', primary: added > 0, onPressed: () => Navigator.pop(context))],
    );
  }
}
