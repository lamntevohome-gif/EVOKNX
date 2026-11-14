import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;
import 'package:flutter/services.dart';
import 'package:knx_config/knx_config.dart';
import 'package:knx_core/knx_core.dart';

import '../app/theme.dart';
import '../state/ha_link.dart';
import '../state/project_controller.dart';
import 'common.dart';
import 'ha_connection.dart';
import 'import_dialog.dart';

/// Kết nối workspace: KNX connections (left) and group addresses (right).
class ConnectionsPage extends StatelessWidget {
  const ConnectionsPage({super.key, required this.project, required this.link});
  final ProjectController project;
  final HaLinkController link;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    // The connections panel on the left; the address table takes the rest.
    return LayoutBuilder(
      builder: (context, bc) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: sidePanelWidth(bc.maxWidth),
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(right: BorderSide(color: c.line)),
            ),
            child: _ConnectionList(project: project, link: link),
          ),
          Expanded(
            child: GaTable(project: project, link: link),
          ),
        ],
      ),
    );
  }
}

class _ConnectionList extends StatelessWidget {
  const _ConnectionList({required this.project, required this.link});
  final ProjectController project;
  final HaLinkController link;

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
          'Connections',
          trailing: Builder(
            builder: (ctx) => EvoButton(
              label: 'Add connection',
              icon: Icons.add,
              small: true,
              onPressed: () async {
                final box = ctx.findRenderObject() as RenderBox;
                final at = box.localToGlobal(Offset(0, box.size.height));
                final added = haAdded(project.doc);
                final v = await showMenu<String>(
                  context: ctx,
                  position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
                  items: [
                    const PopupMenuItem(value: 'knx', child: Text('KNX connection')),
                    PopupMenuItem(value: 'ha', enabled: !added, child: Text(added ? 'Home Assistant (already added)' : 'Home Assistant')),
                  ],
                );
                if (v == 'knx') {
                  project.mutate(
                    (d) => (d['connections'] as List).add({
                      'id': uid('conn_'),
                      'name': 'Connection ${list.length + 1}',
                      'type': 'tunneling',
                      'host': '',
                      'port': 3671,
                      'natMode': true,
                    }),
                  );
                } else if (v == 'ha') {
                  project.mutate((d) => d['ha'] = {...haSettings(d), 'added': true, 'enabled': true});
                }
              },
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
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SyncedField(
                          value: (list[i]['name'] as String?) ?? '',
                          hint: 'Connection name',
                          bold: true,
                          onChanged: (v) => _edit(list[i]['id'] as String, (x) => x['name'] = v, field: 'name'),
                        ),
                      ),
                      if (i == 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(4)),
                          child: Text(
                            'Default',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.accentInk),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FieldLabel(
                  'Connection type',
                  EvoDropdown<bool>(
                    width: double.infinity,
                    value: list[i]['natMode'] == true,
                    items: const [(false, 'Local (LAN)'), (true, 'NAT mode')],
                    onChanged: (v) => _edit(list[i]['id'] as String, (x) => x['natMode'] = v),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FieldLabel(
                        'IP / domain name',
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
                        'Port',
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
                    if (i > 0) EvoButton(label: 'Set as default', onPressed: () => _move(i, 0)),
                    if (i > 1) EvoButton(label: '', icon: Icons.arrow_upward, tooltip: tr('Move up'), onPressed: () => _move(i, i - 1)),
                    if (i > 0 && i < list.length - 1)
                      EvoButton(label: '', icon: Icons.arrow_downward, tooltip: tr('Move down'), onPressed: () => _move(i, i + 1)),
                    if (list.length > 1)
                      EvoButton(
                        label: 'Delete',
                        icon: Icons.delete_outline,
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
        if (haAdded(project.doc)) HaConnectionCard(project: project, link: link),
      ],
    );
  }
}

// ---------------------------------------------------------------- GA table

class GaTable extends StatefulWidget {
  const GaTable({super.key, required this.project, required this.link});
  final ProjectController project;
  final HaLinkController link;
  @override
  State<GaTable> createState() => _GaTableState();
}

class _GaTableState extends State<GaTable> {
  String query = '';
  String filter = 'all';
  final Set<String> selected = {};
  int? lastIndex;
  String bulkDpt = '';

  /// 0 = KNX group addresses, 1 = Home Assistant entities.
  int tab = 0;
  String haQuery = '';
  String haFilter = 'all';

  ProjectController get p => widget.project;

  /// The addresses of ETS and the ones typed in: the virtual Home Assistant
  /// addresses are managed in the "HA" tab.
  List<Json> get _gas => [
    for (final g in p.groupAddresses)
      if (g['ha'] is! Map) g,
  ];

  List<Json> _filtered() {
    final q = fold(query.trim());
    final list = _gas.where((g) {
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
    toast(context, 'Deleted ${ids.length} addresses${unlinked > 0 ? ', unlinked $unlinked links' : ''}. Can be undone (Ctrl+Z).');
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
    return ListenableBuilder(
      listenable: widget.link,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                _GaTab(label: 'KNX Group Address', count: _gas.length, selected: tab == 0, onTap: () => setState(() => tab = 0)),
                _GaTab(label: 'Home Assistant Entity', count: widget.link.entities?.length ?? 0, selected: tab == 1, onTap: () => setState(() => tab = 1)),
              ],
            ),
          ),
          Expanded(child: tab == 0 ? _gaView(context) : _haView(context)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ Home Assistant entities

  Widget _haView(BuildContext context) {
    final c = context.evo;
    final all = widget.link.entities ?? const <HaEntity>[];
    final domains = {for (final e in all) e.domain}.toList()..sort();
    final use = <String, int>{};
    for (final w in allWidgets(p.doc)) {
      final e = widgetEntity(w);
      if (e.isNotEmpty) use[e] = (use[e] ?? 0) + 1;
    }
    final q = fold(haQuery.trim());
    final filter = domains.contains(haFilter) ? haFilter : 'all';
    final list = all.where((e) {
      if (filter != 'all' && e.domain != filter) return false;
      return q.isEmpty || fold('${e.id} ${e.name}').contains(q);
    }).toList()..sort((a, b) => a.id.compareTo(b.id));

    Widget head(String t, {double? w, int flex = 0}) {
      final txt = Text(
        t,
        style: TextStyle(fontSize: 13.5, color: c.muted, fontWeight: FontWeight.w500),
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
              SearchField(hint: 'Search by entity or name', framed: true, onChanged: (v) => setState(() => haQuery = v)),
              EvoDropdown<String>(
                value: filter,
                items: [('all', 'All types'), for (final d in domains) (d, '$d (${all.where((e) => e.domain == d).length})')],
                onChanged: (v) => setState(() => haFilter = v),
              ),
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
          child: Row(children: [head('Entity', flex: 5), head('Name', flex: 5), head('Type', w: 140), head('In use', w: 120)]),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      all.isEmpty ? 'No entities yet. Connect to Home Assistant and click "Update Entity".' : 'No entities match the filter.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemExtent: 44,
                  itemBuilder: (context, i) {
                    final e = list[i];
                    return Container(
                      key: ValueKey(e.id),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: c.panel,
                        border: Border(bottom: BorderSide(color: c.line)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Text(
                              e.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: Text(e.domain, style: TextStyle(fontSize: 13.5, color: c.muted)),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(use[e.id] != null ? '${use[e.id]} components' : '', style: TextStyle(fontSize: 13.5, color: c.muted)),
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

  // ------------------------------------------------------------ KNX group addresses

  Widget _gaView(BuildContext context) {
    final c = context.evo;
    selected.removeWhere((id) => p.gaById(id) == null);
    final list = _filtered();
    final used = gaUsage(p.doc);
    final mains = _gas.map((g) => dptMain(g['dpt'] as String?)).whereType<int>().toSet().toList()..sort();
    final nNone = _gas.where((g) => ((g['dpt'] as String?) ?? '').isEmpty).length;
    final nSel = list.where((g) => selected.contains(g['id'])).length;

    Widget head(String t, {double? w, int flex = 0}) {
      final txt = Text(
        t,
        style: TextStyle(fontSize: 13.5, color: c.muted, fontWeight: FontWeight.w500),
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
              SearchField(framed: true, onChanged: (v) => setState(() => query = v)),
              EvoDropdown<String>(
                value: filter,
                items: [
                  ('all', 'All DPT'),
                  ('none', 'No DPT ($nNone)'),
                  for (final m in mains) ('$m', kDptGroups.where((g) => g.main == m).map((g) => g.label).firstOrNull ?? 'DPT $m.*'),
                ],
                onChanged: (v) => setState(() => filter = v),
              ),
              const SizedBox(width: 16),
              EvoButton(label: 'Add manually', icon: Icons.add, onPressed: _addManual),
              EvoButton(label: 'Import from ETS', icon: Icons.upload_outlined, primary: true, onPressed: () => runEtsImport(context, p)),
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
                  '${selected.length} addresses selected',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.accentInk),
                ),
                const SizedBox(width: 12),
                EvoDropdown<String>(
                  width: 240,
                  value: bulkDpt,
                  items: dptItems(bulkDpt, none: 'Select a DPT to assign…'),
                  onChanged: (v) => setState(() => bulkDpt = v),
                ),
                const SizedBox(width: 8),
                EvoButton(
                  label: 'Assign DPT',
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
                          toast(context, 'Assigned DPT $bulkDpt to ${ids.length} addresses.');
                        },
                ),
                const SizedBox(width: 8),
                EvoButton(label: 'Delete', icon: Icons.delete_outline, danger: true, onPressed: () => _delete(Set<String>.from(selected))),
                const Spacer(),
                EvoButton(label: 'Deselect', onPressed: () => setState(selected.clear)),
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
              head('Address', w: 100),
              head('Name', flex: 1),
              head('DPT', w: 392),
              head('In use', w: 100),
              const SizedBox(width: 40),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    _gas.isEmpty ? 'No group addresses yet. Click "Import from ETS" or "Add manually".' : 'No addresses match the filter.',
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
                                hint: 'Untitled',
                                borderless: true,
                                onChanged: (v) => _edit(id, (x) {
                                  x['name'] = v;
                                  x['nameEdited'] = true;
                                }, field: 'name'),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 392,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: EvoDropdown<String>(
                                width: 372,
                                value: dpt,
                                warn: dpt.isEmpty,
                                items: dptItems(dpt),
                                onChanged: (v) => _edit(id, (x) => x['dpt'] = v),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(used[id] != null ? '${used[id]} components' : '', style: TextStyle(fontSize: 13.5, color: c.muted)),
                          ),
                          SizedBox(
                            width: 40,
                            child: IconButton(
                              tooltip: tr('Delete ${g['address']}'),
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
      setState(() => error = 'Invalid address. Use the form 1/1/1 (3 levels) or 1/25 (2 levels).');
      return;
    }
    if (widget.existing.contains(a)) {
      setState(() => error = 'The address $a is already in the list.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{'id': gaId(a), 'address': a, 'name': _name.text.trim(), 'dpt': dpt, 'nameEdited': true});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add group address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                    'Address',
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
              'Name',
              TextField(
                controller: _name,
                decoration: InputDecoration(hintText: tr('Ceiling light in the living room')),
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
        EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        EvoButton(label: 'Add address', primary: true, onPressed: _submit),
      ],
    );
  }
}

/// A tab of the address list: the label with its count, an accent line under the chosen one.
class _GaTab extends StatelessWidget {
  const _GaTab({required this.label, required this.count, required this.selected, required this.onTap});
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? c.accent : Colors.transparent, width: 2)),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: label,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: selected ? c.ink : c.muted),
              ),
              TextSpan(
                text: '  $count',
                style: TextStyle(fontSize: 14.5, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
