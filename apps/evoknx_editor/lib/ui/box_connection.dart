import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text;
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// The EvoKNX Box in the Connections tab: where it is, how it reaches the bus, and the buttons to connect it to this project (Connect gives
/// it a hidden key once) and to send it its settings. The timers are not here: they are made on the phone.
class BoxConnectionCard extends StatefulWidget {
  const BoxConnectionCard({super.key, required this.project});
  final ProjectController project;

  @override
  State<BoxConnectionCard> createState() => _BoxConnectionCardState();
}

class _BoxConnectionCardState extends State<BoxConnectionCard> {
  ProjectController get p => widget.project;
  bool _busy = false;
  (bool, String)? _result;

  void _edit(void Function(Json box) fn, {String? coalesce}) => p.mutate((doc) {
    final b = jsonMap(doc['box']);
    fn(b);
    doc['box'] = b;
  }, coalesce: coalesce);

  void _editBus(void Function(Json bus) fn, {String? coalesce}) => _edit((b) {
    final x = jsonMap(b['bus']);
    fn(x);
    b['bus'] = x;
  }, coalesce: coalesce);

  Json get _box => boxOf(p.doc);

  Future<void> _find() async {
    final f = await showDialog<FoundBox>(context: context, builder: (_) => const BoxFindDialog());
    if (f == null) return;
    _edit((b) {
      b['host'] = f.address;
      if ((b['name'] ?? '').toString().trim().isEmpty) b['name'] = f.name;
      b['id'] = f.id;
    });
  }

  void _done(bool ok, String text) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = (ok, text);
    });
  }

  /// Gives the box the key of this project (once), then sends it its settings.
  Future<void> _connect() async {
    final host = boxHost(p.doc);
    if (host.isEmpty) return setState(() => _result = (false, 'Enter the address of the box, or use Find box.'));
    setState(() {
      _busy = true;
      _result = null;
    });
    var key = (_box['key'] ?? '').toString();
    if (key.length != 32) {
      key = makeBoxKey();
      _edit((b) => b['key'] = key);
    }
    final info = await boxInfo(host);
    if (!info.ok) return _done(false, info.error!);
    _edit((b) => b['id'] = (info.data!['id'] ?? b['id'] ?? '').toString());
    if (info.data!['claimed'] == true) {
      final r = await boxStatus(_box);
      if (!r.ok) {
        return _done(
          false,
          'This box already belongs to another project (or to an earlier copy of this one). Hold the BOOT button for 3 seconds while powering it on, then press Connect again.',
        );
      }
    } else {
      final r = await boxClaim(host, key);
      if (!r.ok) return _done(false, r.error!);
    }
    await _save(quiet: true);
  }

  Future<void> _save({bool quiet = false}) async {
    final problems = boxSettingsProblems(p.doc);
    if (problems.isNotEmpty) return _done(false, problems.first);
    if (!quiet) {
      setState(() {
        _busy = true;
        _result = null;
      });
    }
    final r = await boxPushSettings(_box, boxSettingsWire(p.doc));
    _done(r.ok, r.ok ? 'Connected. The box has its settings. Send the configuration to the phones so that they can reach it.' : r.error!);
  }

  Future<void> _check() async {
    if (boxHost(p.doc).isEmpty) return setState(() => _result = (false, 'Enter the address of the box, or use Find box.'));
    if ((_box['key'] ?? '').toString().length != 32) return setState(() => _result = (false, 'Press Connect first.'));
    setState(() {
      _busy = true;
      _result = null;
    });
    final r = await boxStatus(_box);
    if (!r.ok) return _done(false, r.error!);
    final d = r.data!;
    final bus = d['busUp'] == true ? 'KNX bus connected (${d['mode']})' : 'KNX bus NOT connected';
    final time = d['timeOk'] == true ? 'time ${d['time']}' : 'time not set yet';
    _done(d['busUp'] == true, 'Box online · $bus · $time · ${d['count'] ?? 0} timers · firmware ${d['fw'] ?? '?'}');
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove the EvoKNX Box?'),
        content: const Text(
          'The box is removed from this project: the phones will not show Schedulers. The timers stay in the box. The key is kept, so adding the box again reconnects it. Can be undone (Ctrl+Z).',
        ),
        actions: [
          EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Remove', danger: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true) return;
    p.mutate((d) {
      final b = boxOf(d);
      d['box'] = <String, dynamic>{if (b['key'] != null) 'key': b['key'], if (b['id'] != null) 'id': b['id'], if (b['extra'] != null) 'extra': b['extra']};
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final box = _box;
        final bus = jsonMap(box['bus']);
        final mode = boxMode(box);
        final tz = (box['tz'] as num?)?.toInt() ?? DateTime.now().timeZoneOffset.inMinutes;
        final zones = _boxZones;
        final knx = p.connections.isEmpty ? <String, dynamic>{} : p.connections.first;
        final hasKey = (box['key'] ?? '').toString().length == 32;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.developer_board_outlined, size: 18, color: c.muted),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('EvoKNX Box', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 10),
              FieldLabel(
                'Name',
                SyncedField(
                  value: (box['name'] ?? '').toString(),
                  hint: 'EvoKNX Box',
                  onChanged: (v) => _edit((b) => b['name'] = v, coalesce: 'box-name'),
                ),
              ),
              const SizedBox(height: 8),
              FieldLabel(
                'Address on the home network',
                Row(
                  children: [
                    Expanded(
                      child: SyncedField(
                        value: (box['host'] ?? '').toString(),
                        hint: '192.168.1.60',
                        onChanged: (v) => _edit((b) => b['host'] = v.trim(), coalesce: 'box-host'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    EvoButton(label: 'Find box', icon: Icons.search, small: true, onPressed: _busy ? null : _find),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FieldLabel(
                'External address (optional, host:port)',
                SyncedField(
                  value: (box['wan'] ?? '').toString(),
                  hint: 'myhome.example.com:8080',
                  onChanged: (v) => _edit((b) => b['wan'] = v.trim(), coalesce: 'box-wan'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'To use the timers away from home, forward a port of the router to the box (port 80) and enter it here. The phone tries the home address first. Give the box a fixed address in the router (DHCP reservation).',
                  style: TextStyle(fontSize: 12, height: 1.35, color: c.muted),
                ),
              ),
              const SizedBox(height: 8),
              FieldLabel(
                'Time zone',
                EvoDropdown<int>(
                  width: 170,
                  value: tz,
                  items: [
                    ...zones,
                    if (!zones.any((z) => z.$1 == tz)) (tz, 'UTC${tz < 0 ? '-' : '+'}${tz.abs() ~/ 60}:${(tz.abs() % 60).toString().padLeft(2, '0')}'),
                  ],
                  onChanged: (v) => _edit((b) => b['tz'] = v),
                ),
              ),
              const SizedBox(height: 8),
              FieldLabel(
                'The box reaches the KNX bus through',
                Seg<String>(
                  items: const [('routing', 'KNX IP Router'), ('tunnel', 'KNX IP Interface')],
                  value: mode,
                  onChanged: (v) => _editBus((x) {
                    x['mode'] = v;
                    if (v == 'tunnel' && (x['host'] ?? '').toString().isEmpty) {
                      x['host'] = (knx['host'] ?? '').toString();
                      x['port'] = (knx['port'] as num?)?.toInt() ?? 3671;
                    }
                  }),
                ),
              ),
              if (mode == 'tunnel') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SyncedField(
                        value: (bus['host'] ?? '').toString(),
                        hint: 'Interface 192.168.1.50',
                        onChanged: (v) => _editBus((x) => x['host'] = v.trim(), coalesce: 'box-bus-host'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 72,
                      child: SyncedField(
                        value: '${(bus['port'] as num?)?.toInt() ?? 3671}',
                        number: true,
                        onChanged: (v) => _editBus((x) => x['port'] = int.tryParse(v.trim()) ?? 3671, coalesce: 'box-bus-port'),
                      ),
                    ),
                  ],
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  mode == 'routing'
                      ? 'Router: the box listens and writes on the KNX multicast address; it uses no tunnel channel.'
                      : 'Interface: the box takes one tunnel channel of the interface.',
                  style: TextStyle(fontSize: 12, height: 1.35, color: c.muted),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  EvoButton(label: hasKey ? 'Connect again' : 'Connect', icon: Icons.link, primary: true, small: true, onPressed: _busy ? null : _connect),
                  EvoButton(label: 'Check connection', icon: Icons.network_check, small: true, onPressed: _busy ? null : _check),
                  EvoButton(label: 'Save to box', icon: Icons.upload_outlined, small: true, onPressed: _busy || !hasKey ? null : _save),
                  EvoButton(label: 'Remove', icon: Icons.delete_outline, small: true, danger: true, onPressed: _busy ? null : _remove),
                ],
              ),
              if (_result != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_result!.$1 ? Icons.check_circle_outline : Icons.error_outline, size: 16, color: _result!.$1 ? const Color(0xFF14AE5C) : c.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_result!.$2, style: TextStyle(fontSize: 12.5, color: _result!.$1 ? c.ink : c.danger)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Time zones as hours from UTC (every half hour that is in use).
List<(int, String)> get _boxZones => [
  for (final m in [
    -720,
    -660,
    -600,
    -540,
    -480,
    -420,
    -360,
    -300,
    -240,
    -210,
    -180,
    -120,
    -60,
    0,
    60,
    120,
    180,
    210,
    240,
    270,
    300,
    330,
    345,
    360,
    390,
    420,
    480,
    525,
    540,
    570,
    600,
    660,
    720,
    765,
    780,
    840,
  ])
    (m, 'UTC${m < 0 ? '-' : '+'}${(m.abs() ~/ 60).toString().padLeft(2, '0')}:${(m.abs() % 60).toString().padLeft(2, '0')}'),
];

class BoxFindDialog extends StatefulWidget {
  const BoxFindDialog();
  @override
  State<BoxFindDialog> createState() => BoxFindDialogState();
}

class BoxFindDialogState extends State<BoxFindDialog> {
  List<FoundBox> found = const [];
  bool scanning = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => scanning = true);
    final r = await discoverBoxes();
    if (!mounted) return;
    setState(() {
      found = r;
      scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return AlertDialog(
      title: const Text('Find box'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Boxes on this network', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (scanning)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  EvoButton(label: 'Search again', icon: Icons.refresh, small: true, onPressed: _scan),
              ],
            ),
            const SizedBox(height: 8),
            if (found.isEmpty)
              Text(
                scanning
                    ? 'Searching…'
                    : 'No box found. Check the power and the network cable, and that this computer is on the same network, or type the address of the box.',
                style: TextStyle(color: c.muted),
              ),
            for (final f in found)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                decoration: BoxDecoration(
                  color: c.paper,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    Icon(Icons.developer_board_outlined, size: 20, color: c.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${f.address}${f.fw.isEmpty ? '' : ' · firmware ${f.fw}'}', style: TextStyle(fontSize: 12.5, color: c.muted)),
                        ],
                      ),
                    ),
                    EvoButton(label: 'Use', small: true, primary: true, onPressed: () => Navigator.pop(context, f)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [EvoButton(label: 'Close', onPressed: () => Navigator.pop(context))],
    );
  }
}
