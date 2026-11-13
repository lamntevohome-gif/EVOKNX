import 'dart:convert';

import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, floorsOf, roomsOf, subsOf;
import 'package:knx_config/knx_config.dart';
import 'package:knx_core/knx_core.dart' show dpt16Text;

import '../app/theme.dart';
import '../state/bus_controller.dart';
import '../state/ha_link.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// The tab Scripts: lists of actions (write, Home Assistant, wait, go to, show message) that a scene card or a
/// push button runs when it is pressed. A script can be tried here in the Simulator (nothing is sent) or in Live Mode.
class ScriptsPage extends StatefulWidget {
  const ScriptsPage({super.key, required this.project, required this.bus, required this.link});
  final ProjectController project;
  final BusController bus;
  final HaLinkController link;

  @override
  State<ScriptsPage> createState() => _ScriptsPageState();
}

class _ScriptsPageState extends State<ScriptsPage> implements ScriptHost {
  ProjectController get p => widget.project;
  String? _sel;
  bool _live = false;
  final List<String> _log = [];

  late final ScriptRunner _runner = ScriptRunner(() => p.doc, this, onStep: (id, i, st) => _add('Step ${i + 1}: ${_what(st)}'));

  @override
  void dispose() {
    _runner.stop();
    super.dispose();
  }

  // ------------------------------------------------------------------ what a test run does

  void _add(String line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 40) _log.removeLast();
    });
  }

  String _what(Json st) => switch (st['type']) {
    'write' => 'Write',
    'ha' => 'Home Assistant ${st['service'] ?? ''}',
    'wait' => 'Wait ${st['seconds'] ?? 0} s',
    'goto' => 'Go to ${st['kind'] ?? ''}',
    _ => 'Show message',
  };

  @override
  Future<String?> write(Json ga, Object value) async {
    _add('  Write ${ga['address']} = $value${_live ? '' : '  (simulated)'}');
    if (!_live) return null;
    if (isHaAddress(ga)) return _writeHa(ga, value);
    return widget.bus.write(ga, value);
  }

  /// A virtual Home Assistant address: its function becomes the service call, as the App does.
  Future<String?> _writeHa(Json ga, Object value) async {
    final h = jsonMap(ga['ha']);
    final id = (h['entity'] ?? '').toString();
    if (!widget.link.connected) return 'Connect to Home Assistant first (tab Extensions).';
    final e = widget.link.entities?.where((x) => x.id == id).firstOrNull;
    if (e == null) return 'press “Get entities” in the tab Extensions so that “$id” is known.';
    final call = haCommand(e, (h['attr'] ?? '').toString(), value);
    if (call == null) return 'this function cannot be written.';
    if (identical(call, HaCall.none)) return null;
    return widget.link.callService('${call.domain}.${call.service}', id, call.data);
  }

  @override
  Future<String?> callHa(String service, String entity, Json data) async {
    _add('  $service${entity.isEmpty ? '' : ' → $entity'}${data.isEmpty ? '' : ' $data'}${_live ? '' : '  (simulated)'}');
    if (!_live) return null;
    return widget.link.callService(service, entity, data);
  }

  @override
  String? goTo(String kind, String id) {
    final ok = kind == 'floor'
        ? floorsOf(p.doc).any((f) => f['id'] == id)
        : (kind == 'room' ? jsonList(p.doc['pages']).any((r) => r['id'] == id) : jsonList(p.doc['pages']).any((r) => subsOf(r).any((s) => s['id'] == id)));
    if (!ok) return 'the ${kind.isEmpty ? 'floor, room or page' : kind} does not exist.';
    _add('  Opens the $kind (the preview does not move)');
    return null;
  }

  @override
  void message(String text) => _add('  Message: $text');

  // ------------------------------------------------------------------ editing

  Json? _script(Json doc) => scriptsOf(doc).where((s) => s['id'] == _sel).firstOrNull;

  void _edit(void Function(Json s) fn, {String? coalesce}) => p.mutate((doc) {
    final s = _script(doc);
    if (s != null) fn(s);
  }, coalesce: coalesce);

  void _editStep(int i, void Function(Json st) fn, {String? coalesce}) => _edit((s) {
    final steps = jsonList(s['steps']);
    if (i < steps.length) fn(steps[i]);
    s['steps'] = steps;
  }, coalesce: coalesce);

  void _addStep(String type) => _edit((s) {
    final steps = jsonList(s['steps']);
    if (steps.length >= kScriptMaxSteps) return;
    steps.add(makeStep(type));
    s['steps'] = steps;
  });

  void _newScript() => p.mutate((doc) {
    final l = scriptsOf(doc);
    final sc = makeScript('Script ${l.length + 1}');
    l.add(sc);
    doc['scripts'] = l;
    _sel = sc['id'] as String;
  });

  void _duplicate(Json s) => p.mutate((doc) {
    final l = scriptsOf(doc);
    final copy = (jsonDecode(jsonEncode(s)) as Map).cast<String, dynamic>();
    copy['id'] = uid('script_');
    copy['title'] = '${s['title'] ?? 'Script'} copy';
    l.add(copy);
    doc['scripts'] = l;
    _sel = copy['id'] as String;
  });

  void _delete(Json s) {
    _runner.stop(s['id'] as String?);
    p.mutate((doc) {
      final l = scriptsOf(doc)..removeWhere((x) => x['id'] == s['id']);
      doc['scripts'] = l;
    });
    if (_sel == s['id']) setState(() => _sel = null);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return ListenableBuilder(
      listenable: Listenable.merge([p, widget.link]),
      builder: (context, _) {
        final scripts = scriptsOf(p.doc);
        if (_sel != null && scripts.every((s) => s['id'] != _sel)) _sel = null;
        _sel ??= scripts.isEmpty ? null : scripts.first['id'] as String;
        final cur = _sel == null ? null : scripts.where((s) => s['id'] == _sel).firstOrNull;
        return Container(
          color: c.paper,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 280,
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border(right: BorderSide(color: c.line)),
                ),
                child: _list(context, scripts),
              ),
              Expanded(
                child: cur == null
                    ? Center(
                        child: Text(
                          scripts.isEmpty ? 'No scripts yet. Click “Add script” to create one.' : 'Select a script.',
                          style: TextStyle(color: c.muted),
                        ),
                      )
                    : _editor(context, cur),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _list(BuildContext context, List<Json> scripts) {
    final c = context.evo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text('Scripts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              EvoButton(label: 'Add script', icon: Icons.add, small: true, onPressed: _newScript),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final s in scripts)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _sel = s['id'] as String),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                    decoration: BoxDecoration(color: s['id'] == _sel ? c.accent.withValues(alpha: 0.14) : null, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((s['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text('${jsonList(s['steps']).length} steps', style: TextStyle(fontSize: 12, color: c.muted)),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Script',
                          icon: Icon(Icons.more_horiz, size: 18, color: c.muted),
                          onSelected: (v) => v == 'dup' ? _duplicate(s) : _delete(s),
                          itemBuilder: (_) => const [PopupMenuItem(value: 'dup', child: Text('Duplicate')), PopupMenuItem(value: 'del', child: Text('Delete'))],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _editor(BuildContext context, Json s) {
    final c = context.evo;
    final id = s['id'] as String;
    final steps = jsonList(s['steps']);
    final running = _runner.isRunning(id);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: SyncedField(
                value: (s['title'] ?? '').toString(),
                hint: 'Script name',
                onChanged: (v) => _edit((x) => x['title'] = v, coalesce: 'sct-$id'),
              ),
            ),
            const SizedBox(width: 12),
            Seg<bool>(items: const [(false, 'Simulator'), (true, 'Live Mode')], value: _live, onChanged: (v) => setState(() => _live = v)),
            const SizedBox(width: 8),
            EvoButton(
              label: running ? 'Running…' : 'Run',
              icon: Icons.play_arrow,
              primary: true,
              onPressed: running
                  ? null
                  : () => _runner.run(id).whenComplete(() {
                      if (mounted) setState(() {});
                    }),
            ),
            const SizedBox(width: 6),
            EvoButton(label: 'Stop', icon: Icons.stop, onPressed: running ? () => _runner.stop(id) : null),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _live
              ? 'Live Mode: values are written to the bus (connect in the Monitor tab) and to Home Assistant (connect in the Extensions tab).'
              : 'Simulator: nothing is sent; the steps that would run are listed below.',
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
        const SizedBox(height: 16),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: steps.length,
          onReorder: (o, n) => _edit((x) {
            final l = jsonList(x['steps']);
            if (n > o) n--;
            l.insert(n, l.removeAt(o));
            x['steps'] = l;
          }),
          itemBuilder: (context, i) => KeyedSubtree(key: ValueKey('$id-$i'), child: _stepCard(context, i, steps[i])),
        ),
        if (steps.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('No steps yet. Add the first one below.', style: TextStyle(color: c.muted)),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in kScriptStepTypes)
              EvoButton(label: t.$2, icon: Icons.add, small: true, onPressed: steps.length >= kScriptMaxSteps ? null : () => _addStep(t.$1)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'A script runs its steps one after the other when a scene card or a push button that uses it is pressed. At most $kScriptMaxSteps steps; a Wait is at most ${kScriptMaxWait.toInt()} s.',
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              const Text('Run log', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              EvoButton(label: 'Clear', small: true, onPressed: () => setState(_log.clear)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final l in _log.take(30)) Text(l, style: TextStyle(fontSize: 12.5, color: c.muted))],
            ),
          ),
        ],
      ],
    );
  }

  /// The description of the chosen service, its fields (a click adds one to the data) and what is wrong in the data.
  List<Widget> _dataHelp(BuildContext context, int i, Json st) {
    final c = context.evo;
    final service = (st['service'] ?? '').toString().trim();
    final at = service.indexOf('.');
    final info = at < 0 ? null : widget.link.serviceInfo?[service.substring(0, at)]?[service.substring(at + 1)];
    if (info == null) return const [];
    final (data, bad) = scriptData((st['data'] ?? '').toString());
    // What Home Assistant takes besides the fields: the targets.
    const targets = {'entity_id', 'device_id', 'area_id', 'floor_id', 'label_id'};
    final keys = data?.keys.toSet() ?? <String>{};
    final known = {for (final f in info.fields) f.key};
    final unknown = info.fields.isEmpty
        ? <String>[]
        : [
            for (final k in keys)
              if (!known.contains(k) && !targets.contains(k)) k,
          ];
    final missing = [
      for (final f in info.fields)
        if (f.required && bad == null && !keys.contains(f.key)) f.key,
    ];
    return [
      if (info.description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(info.description, style: TextStyle(fontSize: 12.5, color: c.muted)),
        ),
      if (info.fields.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in info.fields)
                Tooltip(
                  message: [if (f.name.isNotEmpty) f.name, if (f.description.isNotEmpty) f.description].join(' · '),
                  child: EvoButton(
                    label: '${f.key}${f.required ? ' *' : ''}',
                    icon: keys.contains(f.key) ? Icons.check : Icons.add,
                    small: true,
                    onPressed: bad != null || keys.contains(f.key)
                        ? null
                        : () => _editStep(i, (x) {
                            final (m, err) = scriptData((x['data'] ?? '').toString());
                            if (err != null) return;
                            m!.putIfAbsent(f.key, () => f.sample ?? '');
                            x['data'] = jsonEncode(m);
                          }),
                  ),
                ),
            ],
          ),
        ),
      if (unknown.isNotEmpty) Text('Not a field of $service: ${unknown.join(', ')}', style: TextStyle(fontSize: 12.5, color: c.warn)),
      if (missing.isNotEmpty) Text('Required: ${missing.join(', ')}', style: TextStyle(fontSize: 12.5, color: c.warn)),
    ];
  }

  /// The services to suggest: all of them, or those of the domain of the chosen entity.
  List<(String, String)> _serviceOptions(String entity) {
    final all = widget.link.services;
    if (all == null) return const [];
    final dom = entity.contains('.') ? entity.split('.').first : '';
    final keys = all.keys.where((d) => dom.isEmpty || d == dom || d == 'homeassistant' || !all.containsKey(dom)).toList()..sort();
    return [
      for (final d in keys)
        for (final s in all[d]!) ('$d.$s', ''),
    ];
  }

  /// The entities to suggest: all of them, or those of the domain of the chosen service.
  List<(String, String)> _entityOptions(String service) {
    final list = widget.link.entities;
    if (list == null) return const [];
    final dom = service.contains('.') ? service.split('.').first : '';
    final inDom = list.where((e) => e.domain == dom).toList();
    final use = (dom.isEmpty || dom == 'homeassistant' || inDom.isEmpty) ? list : inDom;
    return [for (final e in (use.toList()..sort((a, b) => a.id.compareTo(b.id)))) (e.id, e.name == e.id ? '' : e.name)];
  }

  List<(String, String)> _targets() {
    final doc = p.doc;
    final out = <(String, String)>[('', 'Not assigned')];
    for (final f in floorsOf(doc)) {
      out.add(('floor:${f['id']}', 'Floor · ${f['title']}'));
      for (final r in roomsOf(doc, f['id'] as String)) {
        out.add(('room:${r['id']}', '    Room · ${f['title']} › ${r['title']}'));
        for (final s in subsOf(r)) {
          out.add(('page:${s['id']}', '        Page · ${r['title']} › ${s['title']}'));
        }
      }
    }
    return out;
  }

  Widget _stepCard(BuildContext context, int i, Json st) {
    final c = context.evo;
    final type = (st['type'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: i,
                child: Icon(Icons.drag_indicator, size: 18, color: c.muted),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 22,
                child: Text('${i + 1}', style: TextStyle(color: c.muted)),
              ),
              SizedBox(
                width: 200,
                child: EvoDropdown<String>(
                  value: type,
                  items: [for (final t in kScriptStepTypes) (t.$1, t.$2)],
                  onChanged: (v) => _edit((x) {
                    final l = jsonList(x['steps']);
                    l[i] = makeStep(v);
                    x['steps'] = l;
                  }),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Delete step',
                icon: Icon(Icons.close, size: 18, color: c.muted),
                onPressed: () => _edit((x) {
                  final l = jsonList(x['steps'])..removeAt(i);
                  x['steps'] = l;
                }),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._fields(context, i, st, type),
        ],
      ),
    );
  }

  List<Widget> _fields(BuildContext context, int i, Json st, String type) {
    final c = context.evo;
    final id = _sel ?? '';
    switch (type) {
      case 'write':
        final gas = jsonList(p.doc['groupAddresses']).where((g) => g['ha'] is! Map || true).toList()
          ..sort((a, b) => gaSortKey(a['address'].toString()).compareTo(gaSortKey(b['address'].toString())));
        final gid = (st['ga'] ?? '').toString();
        final ga = gas.where((g) => g['id'] == gid).firstOrNull;
        final dpt = (ga?['dpt'] ?? '').toString();
        final raw = (st['value'] ?? '').toString();
        return [
          FieldLabel(
            'Address',
            GaPickerField(
              value: gid,
              items: [
                ('', 'Not assigned'),
                for (final g in gas) (g['id'].toString(), '${g['address']}   ${g['name']}'),
                if (gid.isNotEmpty && ga == null) (gid, 'The address was deleted'),
              ],
              onChanged: (v) => _editStep(i, (x) => x['ga'] = v.isEmpty ? null : v),
            ),
          ),
          FieldLabel(
            'Value',
            SyncedField(
              value: raw,
              hint: '1',
              onChanged: (v) => _editStep(i, (x) => x['value'] = v.trim(), coalesce: 'scv-$id-$i'),
            ),
          ),
          Text(
            ga != null && isHaAddress(ga)
                ? 'Sent to Home Assistant as written: “$raw”'
                : dpt.startsWith('16')
                ? 'Text address (DPT $dpt): sent as “${dpt16Text(raw, latin1: dpt.startsWith('16.001'))}”'
                : (ga == null ? 'Choose the address to write to.' : (dpt.isEmpty ? 'The address has no DPT yet.' : 'A number, encoded as DPT $dpt.')),
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
        ];
      case 'ha':
        return [
          FieldLabel(
            'Service',
            SuggestField(
              value: (st['service'] ?? '').toString(),
              hint: 'light.turn_on',
              options: _serviceOptions((st['entity'] ?? '').toString()),
              onChanged: (v) => _editStep(i, (x) => x['service'] = v.trim(), coalesce: 'scs-$id-$i'),
            ),
          ),
          FieldLabel(
            'Entity (optional)',
            SuggestField(
              value: (st['entity'] ?? '').toString(),
              hint: 'light.living_room',
              options: _entityOptions((st['service'] ?? '').toString()),
              onChanged: (v) => _editStep(i, (x) => x['entity'] = v.trim(), coalesce: 'sce-$id-$i'),
            ),
          ),
          FieldLabel(
            'Data (JSON, optional)',
            SyncedField(
              value: (st['data'] ?? '').toString(),
              hint: '{"brightness_pct": 40}',
              onChanged: (v) => _editStep(i, (x) => x['data'] = v, coalesce: 'scd-$id-$i'),
            ),
          ),
          if (scriptData((st['data'] ?? '').toString()).$2 != null) Text('The data is not valid JSON.', style: TextStyle(fontSize: 12.5, color: c.warn)),
          ..._dataHelp(context, i, st),
          Text(
            'To run a script or a scene of Home Assistant use script.turn_on or scene.turn_on with its entity.',
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
        ];
      case 'wait':
        return [
          FieldLabel(
            'Seconds',
            SyncedField(
              value: '${st['seconds'] ?? 0}',
              number: true,
              width: 120,
              onChanged: (v) =>
                  _editStep(i, (x) => x['seconds'] = (double.tryParse(v.replaceAll(',', '.')) ?? 0).clamp(0.0, kScriptMaxWait), coalesce: 'scw-$id-$i'),
            ),
          ),
        ];
      case 'goto':
        final cur = (st['kind'] ?? '').toString().isEmpty ? '' : '${st['kind']}:${st['id']}';
        final items = _targets();
        if (!items.any((x) => x.$1 == cur)) items.add((cur, 'Missing ${st['kind']} (deleted)'));
        return [
          FieldLabel(
            'Open',
            EvoDropdown<String>(
              value: cur,
              items: items,
              onChanged: (v) => _editStep(i, (x) {
                final at = v.indexOf(':');
                x['kind'] = at < 0 ? '' : v.substring(0, at);
                x['id'] = at < 0 ? '' : v.substring(at + 1);
              }),
            ),
          ),
        ];
      default:
        return [
          FieldLabel(
            'Text',
            SyncedField(
              value: (st['text'] ?? '').toString(),
              hint: 'Shown on the screen',
              onChanged: (v) => _editStep(i, (x) => x['text'] = v, coalesce: 'scm-$id-$i'),
            ),
          ),
        ];
    }
  }
}
