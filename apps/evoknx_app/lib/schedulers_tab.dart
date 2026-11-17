import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:knx_config/knx_config.dart';

import 'app_store.dart';

/// Settings › Schedulers: the timers of the EvoKNX Box. They are made here, on the phone, and run by the box when the App is closed.
/// Nothing is sent until Save is pressed. The box keeps the timers, so any phone of the home can read, change and save them.
class SchedulersTab extends StatefulWidget {
  const SchedulersTab({super.key, required this.store, required this.pal});
  final AppStore store;
  final AppPalette pal;

  @override
  State<SchedulersTab> createState() => _SchedulersTabState();
}

class _SchedulersTabState extends State<SchedulersTab> {
  AppPalette get pal => widget.pal;
  Json get cfg => widget.store.config ?? <String, dynamic>{};
  Json get box => boxOf(cfg);

  List<Json> _timers = [];
  String _rev = '';
  bool _loading = true, _dirty = false, _busy = false, _loaded = false;
  String? _error, _info;
  Json? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _say({String? error, String? info}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _info = info;
    });
  }

  /// Reads the timers and the state of the box.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    final c = await boxConfig(box);
    if (!mounted) return;
    if (!c.ok) {
      setState(() {
        _loading = false;
        _error = c.error;
      });
      return;
    }
    final d = c.data!;
    final st = await boxStatus(box);
    if (!mounted) return;
    setState(() {
      _timers = [
        for (final t in (d['ui'] is List ? d['ui'] as List : const []))
          if (t is Map) Map<String, dynamic>.from(t),
      ];
      _rev = (d['rev'] ?? '').toString();
      _status = st.ok ? st.data : null;
      _loading = false;
      _loaded = true;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final problems = boxProblems(cfg, _timers);
    if (problems.isNotEmpty) return _say(error: problems.first);
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    // Did another phone save in the meantime?
    final st = await boxStatus(box);
    if (!mounted) return;
    if (!st.ok) return _say(error: st.error);
    final now = (st.data!['rev'] ?? '').toString();
    if (now != _rev && !(_rev.isEmpty && now.isEmpty)) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('The box has other timers'),
          content: const Text('Another phone saved timers after you opened this page. Saving now replaces them with yours.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Replace')),
          ],
        ),
      );
      if (go != true) return _say();
      if (!mounted) return;
    }
    final wire = boxTimersWire(cfg, _timers);
    final r = await boxPush(box, wire);
    if (!mounted) return;
    if (!r.ok) return _say(error: r.error);
    setState(() {
      _rev = (wire['rev'] ?? '').toString();
      _dirty = false;
    });
    final running = (wire['timers'] as List).length;
    _say(info: 'Saved. The box runs $running of ${_timers.length} timers.');
    final s2 = await boxStatus(box);
    if (mounted && s2.ok) setState(() => _status = s2.data);
  }

  Future<void> _run(Json t) async {
    setState(() => _busy = true);
    final r = await boxRun(box, t['id'].toString());
    _say(error: r.ok ? null : r.error, info: r.ok ? 'The box ran “${_name(t)}” now.' : null);
  }

  Future<void> _time(String what) async {
    setState(() => _busy = true);
    final r = what == 'sync' ? await boxSetTime(box, sync: true) : await boxSetTime(box, epoch: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000);
    if (!mounted) return;
    if (!r.ok) return _say(error: r.error);
    _say(info: what == 'sync' ? 'The box is synchronising its time.' : 'The time of the box was set from this phone.');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final s = await boxStatus(box);
    if (mounted && s.ok) setState(() => _status = s.data);
  }

  Future<void> _showLog() async {
    setState(() => _busy = true);
    final r = await boxLog(box);
    if (!mounted) return;
    if (!r.ok) return _say(error: r.error);
    _say();
    final tz = (_status?['tz'] as num?)?.toInt() ?? 0;
    final events = [
      for (final e in (r.data!['events'] is List ? r.data!['events'] as List : const []))
        if (e is Map) e,
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: pal.panel,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (c, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'What the box did in the last 7 days',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.ink),
            ),
            const SizedBox(height: 10),
            if (events.isEmpty) Text('Nothing yet.', style: TextStyle(color: pal.muted)),
            for (final e in events.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${_stamp((e['t'] as num?)?.toInt() ?? 0, tz)}  ${_kind(e['k'])}  ${e['x'] ?? ''}',
                  style: TextStyle(fontSize: 13, color: e['k'] == 'E' ? pal.danger : pal.ink),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _stamp(int t, int tz) {
    if (t == 0) return '--/-- --:--';
    final d = DateTime.fromMillisecondsSinceEpoch((t + tz * 60) * 1000, isUtc: true);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  static String _kind(Object? k) => switch (k) {
    'S' => 'Schedule',
    'C' => 'Countdown started',
    'X' => 'Countdown cancelled',
    'R' => 'Countdown wrote',
    'E' => 'Error',
    'M' => 'Run by hand',
    'U' => 'KNX connected',
    'D' => 'KNX disconnected',
    'B' => 'Box started',
    'P' => 'Timers or settings received',
    'T' => 'Time',
    _ => '${k ?? ''}',
  };

  // ------------------------------------------------------------------ describing a timer

  String _name(Json t) {
    final title = (t['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    final tg = boxTarget(cfg, t['tg']?.toString());
    return tg == null ? (t['kind'] == 'countdown' ? 'Countdown' : 'Schedule') : tg.title;
  }

  String _dayText(List<int> d) {
    if (d.length == 7) return 'Every day';
    if (d.length == 5 && d.every((x) => x <= 5)) return 'Mon–Fri';
    if (d.length == 2 && d.contains(6) && d.contains(7)) return 'Sat, Sun';
    const n = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return (d.toList()..sort()).map((x) => n[x - 1]).join(', ');
  }

  String _durText(int s) => s % 3600 == 0 ? '${s ~/ 3600} h' : (s % 60 == 0 ? '${s ~/ 60} min' : '$s s');

  String _summary(Json t) {
    final tg = boxTarget(cfg, t['tg']?.toString());
    final what = '${tg?.title ?? 'Not available'} ${t['act'] == 'on' ? 'On' : 'Off'}';
    if (t['kind'] == 'countdown') {
      final w = boxTarget(cfg, t['wtg']?.toString());
      return 'When ${w?.title ?? 'Not available'} is ${t['wval'] == 'off' ? 'Off' : 'On'}, after ${_durText((t['secs'] as num?)?.toInt() ?? 0)}: $what';
    }
    return '${t['time']} · ${_dayText(jsonDays(t))} · $what';
  }

  // ------------------------------------------------------------------ editing

  void _change(void Function() fn) => setState(() {
    fn();
    _dirty = true;
    _info = null;
  });

  Future<void> _edit(Json t, {required bool isNew}) async {
    final r = await showDialog<Json>(
      context: context,
      builder: (c) => _TimerDialog(timer: Map<String, dynamic>.from(t), cfg: cfg, pal: pal),
    );
    if (r == null) return;
    _change(() {
      if (isNew) {
        _timers.add(r);
      } else {
        final i = _timers.indexWhere((x) => x['id'] == t['id']);
        if (i >= 0) _timers[i] = r;
      }
    });
  }

  Future<void> _add() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: pal.panel,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.schedule, color: pal.muted),
              title: Text('Schedule', style: TextStyle(color: pal.ink)),
              subtitle: Text('Switch at a time of day', style: TextStyle(color: pal.muted)),
              onTap: () => Navigator.pop(c, 'schedule'),
            ),
            ListTile(
              leading: Icon(Icons.timer_outlined, color: pal.muted),
              title: Text('Countdown', style: TextStyle(color: pal.ink)),
              subtitle: Text('Switch some time after something is turned on or off', style: TextStyle(color: pal.muted)),
              onTap: () => Navigator.pop(c, 'countdown'),
            ),
          ],
        ),
      ),
    );
    if (kind == null) return;
    await _edit(makeBoxTimer(kind), isNew: true);
  }

  // ------------------------------------------------------------------ build

  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: pal.tile,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: pal.tileEdge),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );

  Widget _message() {
    if (_error != null) {
      return _card([
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 18, color: pal.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_error!, style: TextStyle(color: pal.danger)),
            ),
          ],
        ),
      ]);
    }
    if (_info != null) {
      return _card([
        Row(
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: pal.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_info!, style: TextStyle(color: pal.ink)),
            ),
          ],
        ),
      ]);
    }
    return const SizedBox.shrink();
  }

  Widget _statusCard() {
    final s = _status;
    if (s == null) return const SizedBox.shrink();
    final up = s['busUp'] == true;
    final timeOk = s['timeOk'] == true;
    Widget line(String a, String b, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(a, style: TextStyle(color: pal.muted)),
          ),
          Text(
            b,
            style: TextStyle(color: color ?? pal.ink, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return _card([
      Text(
        (s['name'] ?? 'EvoKNX Box').toString(),
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.ink),
      ),
      const SizedBox(height: 6),
      line('KNX bus', up ? 'Connected' : 'Not connected', color: up ? null : pal.danger),
      line('Time of the box', timeOk ? (s['time'] ?? '').toString() : 'Not set', color: timeOk ? null : pal.danger),
      line('Running now', '${s['count'] ?? 0} timers'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton.icon(onPressed: _busy ? null : () => _time('sync'), icon: const Icon(Icons.sync, size: 18), label: const Text('Synchronise now')),
          TextButton.icon(
            onPressed: _busy ? null : () => _time('set'),
            icon: const Icon(Icons.phone_android, size: 18),
            label: const Text('Set time from phone'),
          ),
          TextButton.icon(onPressed: _busy ? null : _showLog, icon: const Icon(Icons.history, size: 18), label: const Text('Log (7 days)')),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final targets = boxTargets(cfg);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          _message(),
          if (!_loaded)
            _card([
              Text(
                'The box cannot be reached.',
                style: TextStyle(fontWeight: FontWeight.w700, color: pal.ink),
              ),
              const SizedBox(height: 6),
              Text(
                'Check that the phone is on the home network, or that the external address is set. If the address of the box changed, send the configuration again from the Editor: only the address is updated, the timers stay as they are.',
                style: TextStyle(color: pal.muted, height: 1.35),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Try again')),
              ),
            ])
          else ...[
            _statusCard(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'TIMERS',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: pal.sMuted),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy || _timers.length >= kBoxMaxTimers || targets.isEmpty ? null : _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (targets.isEmpty)
              _card([
                Text(
                  'No address is available for timers. Choose addresses in the Editor, tab Schedulers, and send the configuration again.',
                  style: TextStyle(color: pal.muted),
                ),
              ]),
            if (_timers.isEmpty && targets.isNotEmpty) _card([Text('No timers yet. Press Add.', style: TextStyle(color: pal.muted))]),
            for (final t in _timers) _timerCard(t),
            if (_dirty) ...[
              const SizedBox(height: 4),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: pal.accent),
                onPressed: _busy ? null : _save,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                label: const Text('Save to the box'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('The changes are only on this phone until you save.', style: TextStyle(fontSize: 12.5, color: pal.sMuted)),
              ),
            ],
          ],
        ],
      ],
    );
  }

  Widget _timerCard(Json t) {
    final on = t['on'] != false;
    final bad = boxProblems(cfg, [t]).isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: pal.tile,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bad ? pal.danger : pal.tileEdge),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _edit(t, isNew: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Icon(t['kind'] == 'countdown' ? Icons.timer_outlined : Icons.schedule, color: on ? pal.accent : pal.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name(t),
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: on ? pal.ink : pal.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(_summary(t), style: TextStyle(fontSize: 13, color: pal.muted)),
                    if (bad) Text('Needs attention: tap to fix', style: TextStyle(fontSize: 12.5, color: pal.danger)),
                  ],
                ),
              ),
              Switch(value: on, activeColor: pal.accent, onChanged: (v) => _change(() => t['on'] = v)),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: pal.muted),
                color: pal.panel,
                onSelected: (v) {
                  if (v == 'run') {
                    if (_dirty) return _say(error: 'Save to the box first, then run the timer.');
                    _run(t);
                  } else if (v == 'del') {
                    _change(() => _timers.removeWhere((x) => x['id'] == t['id']));
                  }
                },
                itemBuilder: (c) => [
                  const PopupMenuItem(value: 'run', child: Text('Run now')),
                  PopupMenuItem(
                    value: 'del',
                    child: Text('Delete', style: TextStyle(color: pal.danger)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Make or change one timer.
class _TimerDialog extends StatefulWidget {
  const _TimerDialog({required this.timer, required this.cfg, required this.pal});
  final Json timer, cfg;
  final AppPalette pal;

  @override
  State<_TimerDialog> createState() => _TimerDialogState();
}

class _TimerDialogState extends State<_TimerDialog> {
  late final Json t = widget.timer;
  AppPalette get pal => widget.pal;
  String? _problem;

  bool get _cd => t['kind'] == 'countdown';
  List<BoxTarget> get _targets => boxTargets(widget.cfg);

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Text(
      s,
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.muted),
    ),
  );

  Widget _targetPicker(String key, {bool watch = false}) {
    final list = _targets.where((e) => !watch || boxCanWatch(e)).toList();
    final cur = t[key]?.toString();
    return DropdownButton<String>(
      isExpanded: true,
      value: list.any((e) => e.key == cur) ? cur : null,
      hint: const Text('Choose'),
      dropdownColor: pal.panel,
      items: [
        for (final e in list)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.title, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() => t[key] = v),
    );
  }

  Widget _onOff(String key, {required bool value}) => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(value: true, label: Text('On')),
      ButtonSegment(value: false, label: Text('Off')),
    ],
    selected: {value},
    showSelectedIcon: false,
    onSelectionChanged: (s) => setState(() => t[key] = s.first ? 'on' : 'off'),
  );

  Future<void> _pickTime() async {
    final m = boxMinutes((t['time'] ?? '').toString()) ?? 22 * 60;
    final r = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (r == null) return;
    setState(() => t['time'] = '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')}');
  }

  void _ok() {
    final problems = boxProblems(widget.cfg, [t]);
    if (problems.isNotEmpty) {
      setState(() => _problem = problems.first.replaceFirst(RegExp(r'^Timer 1(?: “[^”]*”)?: '), ''));
      return;
    }
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    final days = jsonDays(t);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return AlertDialog(
      backgroundColor: pal.panel,
      title: Text(_cd ? 'Countdown' : 'Schedule', style: TextStyle(color: pal.ink)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: TextEditingController(text: (t['title'] ?? '').toString()),
                decoration: const InputDecoration(labelText: 'Name (optional)'),
                onChanged: (v) => t['title'] = v,
              ),
              if (_cd) ...[
                _label('When this'),
                _targetPicker('wtg', watch: true),
                _onOff('wval', value: t['wval'] != 'off'),
                _label('Wait'),
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: TextEditingController(text: '${t['amount'] ?? 10}'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          t['amount'] = num.tryParse(v.trim()) ?? 0;
                          t['secs'] = boxSeconds(t['amount'] as num, (t['unit'] ?? 'm').toString());
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: (t['unit'] ?? 'm').toString(),
                      dropdownColor: pal.panel,
                      items: const [
                        DropdownMenuItem(value: 's', child: Text('seconds')),
                        DropdownMenuItem(value: 'm', child: Text('minutes')),
                        DropdownMenuItem(value: 'h', child: Text('hours')),
                      ],
                      onChanged: (v) => setState(() {
                        t['unit'] = v;
                        t['secs'] = boxSeconds((t['amount'] as num?) ?? 0, v ?? 'm');
                      }),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start again when it happens again'),
                  value: t['restart'] != false,
                  activeColor: pal.accent,
                  onChanged: (v) => setState(() => t['restart'] = v),
                ),
                _label('Then switch'),
              ] else ...[
                _label('Time'),
                OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule), label: Text((t['time'] ?? '22:00').toString())),
                _label('Days'),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 1; i <= 7; i++)
                      FilterChip(
                        label: Text(names[i - 1]),
                        selected: days.contains(i),
                        onSelected: (v) => setState(() {
                          final d = jsonDays(t).toSet();
                          v ? d.add(i) : d.remove(i);
                          t['days'] = d.toList()..sort();
                        }),
                      ),
                  ],
                ),
                _label('Switch'),
              ],
              _targetPicker('tg'),
              _onOff('act', value: t['act'] != 'off'),
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_problem!, style: TextStyle(color: pal.danger)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _ok, child: const Text('OK')),
      ],
    );
  }
}
