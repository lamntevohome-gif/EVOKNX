import 'dart:convert';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
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

  /// The step that Ctrl+C copies and after which Ctrl+V pastes (click the empty part of a step to select it).
  int? _selStep;
  final FocusNode _focus = FocusNode(debugLabel: 'scripts');

  /// Ctrl+C copies the selected step (all the steps when none is selected), Ctrl+V pastes after the selected step
  /// (at the end when none is selected). Inside a text field the keys keep their normal meaning.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = HardwareKeyboard.instance;
    if (!(k.isControlPressed || k.isMetaPressed) || k.isAltPressed) return KeyEventResult.ignored;
    // In a text field Ctrl+C and Ctrl+V keep their normal meaning.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null)) return KeyEventResult.ignored;
    final cur = _sel == null ? null : scriptsOf(p.doc).where((x) => x['id'] == _sel).firstOrNull;
    if (cur == null) return KeyEventResult.ignored;
    final steps = jsonList(cur['steps']);
    if (e.logicalKey == LogicalKeyboardKey.keyC) {
      final i = _selStep;
      if (i != null && i < steps.length) {
        _copySteps([steps[i]], 'Step copied.');
      } else if (steps.isNotEmpty) {
        _copySteps(steps, 'All steps copied.');
      }
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.keyV) {
      final i = _selStep;
      _pasteSteps(i != null && i < steps.length ? i + 1 : steps.length);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  late final ScriptRunner _runner = ScriptRunner(() => p.doc, this, onStep: (id, i, st) => _add('Step ${i + 1}: ${_what(st)}'));

  @override
  void dispose() {
    _focus.dispose();
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
    if (e == null) return 'click Update Entity in the tab Extensions so that “$id” is known.';
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

  /// Steps travel as text on the clipboard, so they can be pasted into another script or another project.
  static const _clipKey = 'evoknx-script-steps';

  Future<void> _copySteps(List<Json> steps, String done) async {
    await Clipboard.setData(ClipboardData(text: jsonEncode({'evoknx': _clipKey, 'steps': steps})));
    if (mounted) toast(context, done);
  }

  /// Pastes the steps of the clipboard at position [at] (a copy of each, the addresses and targets as they were).
  Future<void> _pasteSteps(int at) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final list = <Json>[];
    try {
      final m = jsonDecode(data?.text ?? '');
      if (m is Map && m['evoknx'] == _clipKey && m['steps'] is List) {
        for (final s in m['steps'] as List) {
          if (s is Map && kScriptStepTypes.any((t) => t.$1 == s['type'])) list.add((jsonDecode(jsonEncode(s)) as Map).cast<String, dynamic>());
        }
      }
    } catch (_) {}
    if (!mounted) return;
    if (list.isEmpty) {
      toast(context, 'The clipboard has no script steps. Copy a step first.');
      return;
    }
    var added = 0;
    _edit((s) {
      final steps = jsonList(s['steps']);
      final take = list.take((kScriptMaxSteps - steps.length).clamp(0, kScriptMaxSteps)).toList();
      steps.insertAll(at.clamp(0, steps.length), take);
      s['steps'] = steps;
      added = take.length;
    });
    toast(context, added == 0 ? 'A script has at most $kScriptMaxSteps steps.' : (added == 1 ? 'Step pasted.' : '$added steps pasted.'));
    if (added > 0) setState(() => _selStep = at);
  }

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
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Container(
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
                      : GestureDetector(behavior: HitTestBehavior.translucent, onTap: _pageTap, child: _editor(context, cur)),
                ),
              ],
            ),
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
                  onTap: () => setState(() {
                    _sel = s['id'] as String;
                    _selStep = null;
                  }),
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
            EvoButton(label: 'Paste', icon: Icons.content_paste_go_outlined, small: true, onPressed: () => _pasteSteps(steps.length)),
            EvoButton(
              label: 'Copy all steps',
              icon: Icons.copy_outlined,
              small: true,
              onPressed: steps.isEmpty ? null : () => _copySteps(steps, 'All steps copied.'),
            ),
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

  void _setData(int i, String key, Object? v, {bool typing = false}) => _editStep(i, (x) {
    final (m, err) = scriptData((x['data'] ?? '').toString());
    if (err != null) return;
    m![key] = v;
    x['data'] = jsonEncode(m);
  }, coalesce: typing ? 'scf-${_sel ?? ''}-$i-$key' : null);

  void _removeData(int i, String key) => _editStep(i, (x) {
    final (m, err) = scriptData((x['data'] ?? '').toString());
    if (err != null) return;
    m!.remove(key);
    x['data'] = m.isEmpty ? '' : jsonEncode(m);
  });

  static String _numText(Object? v) => v is num ? (v == v.roundToDouble() ? v.toInt().toString() : v.toString()) : (v ?? '').toString();

  HaService? _svc(String service) {
    final at = service.indexOf('.');
    return at < 0 ? null : widget.link.serviceInfo?[service.substring(0, at)]?[service.substring(at + 1)];
  }

  /// A different service (one that Home Assistant knows) starts with no entity and no data, only its
  /// required fields, so nothing of the old service is left. Typing the same service again changes nothing.
  void _changeService(int i, String v) {
    final nv = v.trim();
    final info = _svc(nv);
    _editStep(i, (x) {
      final old = (x['service'] ?? '').toString();
      final prev = (x['svcKey'] ?? (_svc(old) != null ? old : null))?.toString();
      x['service'] = nv;
      if (info == null) return;
      if (prev != null && prev != nv) {
        x['entity'] = '';
        x['data'] = '';
        x.remove('raw');
      }
      x['svcKey'] = nv;
      if ((x['data'] ?? '').toString().trim().isEmpty) {
        final req = <String, dynamic>{
          for (final f in info.fields)
            if (f.required) f.key: f.sample ?? '',
        };
        if (req.isNotEmpty) x['data'] = jsonEncode(req);
      }
    }, coalesce: 'scs-${_sel ?? ''}-$i');
  }

  /// The data of a service as rows: one per field, with its range and a box for the value. A click on a field
  /// below adds it. Without the description of the service (not connected) the data is a JSON text.
  List<Widget> _dataEditor(BuildContext context, int i, Json st) {
    final c = context.evo;
    final id = _sel ?? '';
    final service = (st['service'] ?? '').toString().trim();
    final at = service.indexOf('.');
    final info = at < 0 ? null : widget.link.serviceInfo?[service.substring(0, at)]?[service.substring(at + 1)];
    final text = (st['data'] ?? '').toString();
    final (data, bad) = scriptData(text);
    final raw = info == null || st['raw'] == true || bad != null;
    final toggle = info == null
        ? const <Widget>[]
        : [
            Align(
              alignment: Alignment.centerRight,
              child: EvoButton(
                label: raw ? 'Fields' : 'Edit as JSON',
                small: true,
                onPressed: bad != null && raw ? null : () => _editStep(i, (x) => raw ? x.remove('raw') : x['raw'] = true),
              ),
            ),
          ];
    if (raw) {
      return [
        FieldLabel(
          'Data (JSON, optional)',
          SyncedField(
            value: text,
            hint: '{"brightness_pct": 40}',
            onChanged: (v) => _editStep(i, (x) => x['data'] = v, coalesce: 'scd-$id-$i'),
          ),
        ),
        if (bad != null) Text('The data is not valid JSON.', style: TextStyle(fontSize: 12.5, color: c.warn)),
        ...toggle,
      ];
    }
    final svc = info!;
    final byKey = {for (final f in svc.fields) f.key: f};
    final map = data ?? <String, dynamic>{};
    const targets = {'entity_id', 'device_id', 'area_id', 'floor_id', 'label_id'};
    final unknown = svc.fields.isEmpty
        ? <String>[]
        : [
            for (final k in map.keys)
              if (!byKey.containsKey(k) && !targets.contains(k)) k,
          ];
    final missing = [
      for (final f in svc.fields)
        if (f.required && !map.containsKey(f.key)) f.key,
    ];
    return [
      Text('Data', style: TextStyle(fontSize: 12.5, color: c.muted)),
      const SizedBox(height: 4),
      if (svc.description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(svc.description, style: TextStyle(fontSize: 12.5, color: c.muted)),
        ),
      for (final k in map.keys) _dataRow(context, i, k, map[k], byKey[k]),
      if (map.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('No data: choose a field below to add it.', style: TextStyle(fontSize: 12.5, color: c.muted)),
        ),
      if (svc.fields.any((f) => !map.containsKey(f.key)))
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in svc.fields)
                if (!map.containsKey(f.key))
                  Tooltip(
                    message: [if (f.name.isNotEmpty) f.name, if (f.description.isNotEmpty) f.description].join(' · '),
                    child: EvoButton(
                      label: '${f.key}${f.required ? ' *' : ''}',
                      icon: Icons.add,
                      small: true,
                      onPressed: () => _setData(i, f.key, f.sample ?? ''),
                    ),
                  ),
            ],
          ),
        ),
      if (unknown.isNotEmpty) Text('Not a field of $service: ${unknown.join(', ')}', style: TextStyle(fontSize: 12.5, color: c.warn)),
      if (missing.isNotEmpty) Text('Required: ${missing.join(', ')}', style: TextStyle(fontSize: 12.5, color: c.warn)),
      ...toggle,
    ];
  }

  /// One field of the data: its name (with the range), a box for the value of the right kind, and a button to remove it.
  Widget _dataRow(BuildContext context, int i, String key, Object? value, HaField? f) {
    final c = context.evo;
    final type = f?.type ?? '';
    var label = key;
    if (f != null && f.spec.isNotEmpty) label += ' (${f.spec})';
    if (f?.required == true) label += ' *';
    final Widget input;
    if (type == 'number') {
      input = SyncedField(
        value: _numText(value),
        number: true,
        onChanged: (v) {
          final n = num.tryParse(v.trim().replaceAll(',', '.'));
          _setData(i, key, n == null ? v : (n == n.roundToDouble() && !v.contains('.') && !v.contains(',') ? n.toInt() : n), typing: true);
        },
      );
    } else if (type == 'constant') {
      input = Align(
        alignment: Alignment.centerLeft,
        child: Text(jsonEncode(f!.selector['value']), style: TextStyle(fontSize: 13, color: c.muted)),
      );
    } else if (type == 'boolean') {
      input = Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 160,
          child: EvoDropdown<bool>(value: value == true, items: const [(true, 'true'), (false, 'false')], onChanged: (v) => _setData(i, key, v)),
        ),
      );
    } else if (type == 'select' && f != null && f.options.isNotEmpty) {
      final opts = [...f.options];
      final cur = (value ?? '').toString();
      if (!opts.any((o) => o.$1 == cur)) opts.add((cur, cur));
      input = Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 260,
          child: EvoDropdown<String>(value: cur, items: opts, onChanged: (v) => _setData(i, key, v)),
        ),
      );
    } else if (value is String || value == null) {
      input = SyncedField(value: (value ?? '').toString(), onChanged: (v) => _setData(i, key, v, typing: true));
    } else {
      // A list or another JSON value: written as JSON.
      input = SyncedField(
        value: jsonEncode(value),
        onChanged: (v) {
          Object? parsed;
          try {
            parsed = jsonDecode(v);
          } catch (_) {
            parsed = v;
          }
          _setData(i, key, parsed, typing: true);
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 250,
            child: Tooltip(
              message: [if (f != null && f.name.isNotEmpty) f.name, if (f != null && f.description.isNotEmpty) f.description].join(' · '),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.ink),
                  ),
                  if (f != null && f.brief.isNotEmpty)
                    Text(
                      f.brief,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: c.muted),
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: input),
          IconButton(
            tooltip: 'Remove field',
            icon: Icon(Icons.close, size: 16, color: c.muted),
            onPressed: () => _removeData(i, key),
          ),
        ],
      ),
    );
  }

  /// The services to suggest: all of them, the ones of the domain of the chosen entity first
  /// (nothing is hidden, so any service can be chosen whatever the entity).
  List<(String, String)> _serviceOptions(String entity) {
    final all = widget.link.services;
    if (all == null) return const [];
    final dom = entity.contains('.') ? entity.split('.').first : '';
    final keys = all.keys.toList()
      ..sort((a, b) {
        if (dom.isNotEmpty && (a == dom) != (b == dom)) return a == dom ? -1 : 1;
        return a.compareTo(b);
      });
    return [
      for (final d in keys)
        for (final s in all[d]!) ('$d.$s', ''),
    ];
  }

  /// The entities to suggest: all of them, the ones of the domain of the chosen service first.
  List<(String, String)> _entityOptions(String service) {
    final list = widget.link.entities;
    if (list == null) return const [];
    final dom = service.contains('.') ? service.split('.').first : '';
    final sorted = list.toList()
      ..sort((a, b) {
        if (dom.isNotEmpty && (a.domain == dom) != (b.domain == dom)) return a.domain == dom ? -1 : 1;
        return a.id.compareTo(b.id);
      });
    return [for (final e in sorted) (e.id, e.name == e.id ? '' : e.name)];
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

  /// A tap on the empty part of the page takes the keyboard (for Ctrl+C and Ctrl+V) and unselects the step.
  void _pageTap() {
    _focus.requestFocus();
    if (_selStep != null) setState(() => _selStep = null);
  }

  /// A step: a tap on its empty part selects it (frame) and takes the keyboard.
  Widget _stepCard(BuildContext context, int i, Json st) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () {
      _focus.requestFocus();
      setState(() => _selStep = i);
    },
    child: _stepCardBody(context, i, st),
  );

  Widget _stepCardBody(BuildContext context, int i, Json st) {
    final c = context.evo;
    final selected = _selStep == i;
    final type = (st['type'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? c.accent : c.line, width: selected ? 1.6 : 1),
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
                tooltip: 'Copy step',
                icon: Icon(Icons.copy_outlined, size: 17, color: c.muted),
                onPressed: () => _copySteps([st], 'Step copied.'),
              ),
              IconButton(
                tooltip: 'Paste below',
                icon: Icon(Icons.content_paste_go_outlined, size: 18, color: c.muted),
                onPressed: () => _pasteSteps(i + 1),
              ),
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
              onChanged: (v) => _changeService(i, v),
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
          ..._dataEditor(context, i, st),
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
