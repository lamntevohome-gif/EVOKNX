import 'dart:async';
import 'dart:convert';

import 'project.dart';

/// Scripts: a list of actions that run one after the other when a scene card or a push button is pressed.
/// There are no conditions and nothing runs by itself: a script starts only when a person starts it.
///
/// Stored in the project as `scripts: [ {id, title, steps: [ {type, …} ]} ]`. The steps are
///   write   {ga: group address id, value: text}        writes a value (a text for a text address, DPT 16)
///   ha      {service: 'domain.service', entity, data}  calls a Home Assistant service (data is JSON)
///   wait    {seconds}
///   goto    {kind: floor|room|page, id}                 opens a floor, a room or a page
///   message {text}                                      shows a message on the screen

/// At most this many steps are run in one script.
const kScriptMaxSteps = 60;

/// The longest single Wait, and the longest total wait of one run (seconds).
const kScriptMaxWait = 60.0;
const kScriptMaxTotalWait = 300.0;

/// The kinds of step, with the name shown in the Editor.
const kScriptStepTypes = [('write', 'Write address'), ('ha', 'HA Service'), ('wait', 'Wait'), ('goto', 'Go to'), ('message', 'Show message')];

List<Json> scriptsOf(Json doc) => jsonList(doc['scripts']);

Json? _byId(List<Json> l, String? id) {
  if (id == null) return null;
  for (final x in l) {
    if (x['id'] == id) return x;
  }
  return null;
}

Json makeScript([String title = 'New script']) => {'id': uid('script_'), 'title': title, 'steps': <Json>[]};

Json makeStep(String type) => switch (type) {
  'write' => {'type': 'write', 'ga': null, 'value': '1'},
  'ha' => {'type': 'ha', 'service': '', 'entity': '', 'data': ''},
  'wait' => {'type': 'wait', 'seconds': 1.0},
  'goto' => {'type': 'goto', 'kind': '', 'id': ''},
  _ => {'type': 'message', 'text': ''},
};

/// What a Write step sends: the text as it is for a text address (DPT 16), a number for any other address.
Object scriptValue(Json? ga, String raw) {
  if ((ga?['dpt'] ?? '').toString().startsWith('16')) return raw;
  return num.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;
}

final _serviceForm = RegExp(r'^[a-z0-9_]+\.[a-z0-9_]+$');

/// The data of a Home Assistant step (JSON text) as a map, or an error text.
(Json?, String?) scriptData(String text) {
  final t = text.trim();
  if (t.isEmpty) return (<String, dynamic>{}, null);
  try {
    final v = jsonDecode(t);
    if (v is Map) return (v.map((k, e) => MapEntry(k.toString(), e)), null);
  } catch (_) {}
  return (null, 'The data is not valid JSON, for example {"brightness_pct": 40}.');
}

/// What the script needs from the place where it runs (the App, or the Editor).
abstract class ScriptHost {
  /// Writes [value] to the address [ga]. An error text, or null.
  Future<String?> write(Json ga, Object value);

  /// Calls the Home Assistant service ("light.turn_on"); [entity] may be empty. An error text, or null.
  Future<String?> callHa(String service, String entity, Json data);

  /// Opens a floor, a room or a page. An error text when it does not exist, or null.
  String? goTo(String kind, String id);

  void message(String text);
}

/// Runs the scripts of a project, step by step.
class ScriptRunner {
  ScriptRunner(this.doc, this.host, {this.onStep});

  /// The project (read at the moment a script starts).
  final Json Function() doc;
  final ScriptHost host;

  /// Called before each step (its position and the step).
  final void Function(String scriptId, int index, Json step)? onStep;

  final Map<String, Completer<void>> _running = {};

  bool isRunning(String id) => _running.containsKey(id);

  /// Stops a script (or all of them) at the next step; a Wait ends at once.
  void stop([String? id]) {
    for (final e in _running.entries.toList()) {
      if (id == null || e.key == id) {
        if (!e.value.isCompleted) e.value.complete();
      }
    }
  }

  /// Runs a script. Pressing again while it runs does nothing. The first step that fails stops it
  /// and tells why.
  Future<void> run(String id) async {
    final s = _byId(scriptsOf(doc()), id);
    if (s == null) {
      host.message('The script does not exist. Please check.');
      return;
    }
    if (isRunning(id)) return;
    final stop = _running[id] = Completer<void>();
    final title = (s['title'] ?? '').toString();
    try {
      final steps = jsonList(s['steps']);
      var waited = 0.0;
      for (var i = 0; i < steps.length && i < kScriptMaxSteps; i++) {
        if (stop.isCompleted) break;
        final st = steps[i];
        onStep?.call(id, i, st);
        String? err;
        switch (st['type']) {
          case 'write':
            final ga = _byId(jsonList(doc()['groupAddresses']), st['ga']?.toString());
            err = ga == null ? 'the address does not exist.' : await host.write(ga, scriptValue(ga, (st['value'] ?? '').toString()));
          case 'ha':
            final service = (st['service'] ?? '').toString().trim();
            if (!_serviceForm.hasMatch(service)) {
              err = 'the service “$service” is not valid, use the form domain.service.';
              break;
            }
            final (data, bad) = scriptData((st['data'] ?? '').toString());
            err = bad ?? await host.callHa(service, (st['entity'] ?? '').toString().trim(), data!);
          case 'wait':
            var secs = (((st['seconds'] as num?) ?? 0).toDouble()).clamp(0.0, kScriptMaxWait).toDouble();
            if (waited + secs > kScriptMaxTotalWait) secs = (kScriptMaxTotalWait - waited).clamp(0.0, kScriptMaxWait).toDouble();
            waited += secs;
            if (secs > 0) await Future.any([Future<void>.delayed(Duration(milliseconds: (secs * 1000).round())), stop.future]);
          case 'goto':
            err = host.goTo((st['kind'] ?? '').toString(), (st['id'] ?? '').toString());
          case 'message':
            final t = (st['text'] ?? '').toString();
            if (t.trim().isNotEmpty) host.message(t);
        }
        if (err != null) {
          host.message('Script “$title”, step ${i + 1}: $err');
          break;
        }
      }
    } finally {
      _running.remove(id);
    }
  }
}

/// What is wrong in the scripts of a project (shown in the list of problems of the Editor).
List<String> scriptProblems(Json doc) {
  final out = <String>[];
  final gas = jsonList(doc['groupAddresses']);
  final floorIds = {for (final f in jsonList(doc['floors'])) f['id']};
  final roomIds = {for (final r in jsonList(doc['pages'])) r['id']};
  final pageIds = {
    for (final r in jsonList(doc['pages']))
      for (final s in jsonList(r['subpages'])) s['id'],
  };
  for (final s in scriptsOf(doc)) {
    final title = (s['title'] ?? '').toString();
    final steps = jsonList(s['steps']);
    if (steps.length > kScriptMaxSteps) out.add('Script “$title”: only the first $kScriptMaxSteps steps are run.');
    for (var i = 0; i < steps.length; i++) {
      final st = steps[i];
      final where = 'Script “$title”, step ${i + 1}: ';
      switch (st['type']) {
        case 'write':
          if (_byId(gas, st['ga']?.toString()) == null) out.add('${where}the address does not exist.');
        case 'ha':
          final service = (st['service'] ?? '').toString().trim();
          if (!_serviceForm.hasMatch(service)) out.add('${where}the service is not valid, use the form domain.service.');
          if (scriptData((st['data'] ?? '').toString()).$2 != null) out.add('${where}the data is not valid JSON.');
        case 'goto':
          final kind = (st['kind'] ?? '').toString();
          final ok = kind == 'floor'
              ? floorIds.contains(st['id'])
              : (kind == 'room' ? roomIds.contains(st['id']) : (kind == 'page' && pageIds.contains(st['id'])));
          if (!ok) out.add('${where}the target ${kind.isEmpty ? 'floor, room or page' : kind} does not exist. Please check.');
      }
    }
  }
  return out;
}
