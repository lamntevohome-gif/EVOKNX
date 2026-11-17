import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:knx_config/knx_config.dart';

/// The Reminders list: the cards that were marked "Remind me when it is on" and are on now. Each has a button to go to its page and
/// one to turn it off, and one to hide it until the App is opened again.
void showReminders(BuildContext context, CardEngine engine, AppPalette pal, void Function(Json sub) goTo) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: pal.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => _RemindersSheet(
      engine: engine,
      pal: pal,
      goTo: (sub) {
        Navigator.pop(c);
        goTo(sub);
      },
    ),
  );
}

class _RemindersSheet extends StatelessWidget {
  const _RemindersSheet({required this.engine, required this.pal, required this.goTo});
  final CardEngine engine;
  final AppPalette pal;
  final void Function(Json sub) goTo;

  String _stateText(Json w) {
    if (w['type'] == 'value') {
      final st = engine.st(w['id'] as String);
      final v = valueView(w, st['val'] ?? st['raw'], dpt: (engine.gaOf(w, 'status')?['dpt'] ?? '').toString());
      return v.unit.isEmpty ? v.text : '${v.text} ${v.unit}';
    }
    if (CardEngine.remindMode(w) == 'off') return 'Off';
    if (w['type'] == 'dimmer') return 'On · ${(((engine.st(w['id'] as String)['val'] as num?) ?? 0)).round()}%';
    return 'On';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final list = engine.reminders();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Text(
                    'Reminders',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.ink),
                  ),
                ),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    child: Text('Nothing to remind. Everything is as you asked.', style: TextStyle(fontSize: 15, color: pal.muted)),
                  )
                else
                  Flexible(
                    child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [for (final w in list) _row(context, w)]),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, Json w) {
    final at = engine.locate(w['id'] as String);
    final where = at == null ? '' : (at.room['title'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
      decoration: BoxDecoration(color: pal.tile, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              iconWidget(w['icon'] as String?, 26, pal.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (w['label'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.ink),
                    ),
                    Text(
                      where.isEmpty ? _stateText(w) : '$where · ${_stateText(w)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: pal.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr('Hide until the App is opened again'),
                icon: Icon(Icons.close, size: 20, color: pal.muted),
                onPressed: () => engine.dismissReminder(w),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (at != null) TextButton.icon(onPressed: () => goTo(at.sub), icon: const Icon(Icons.arrow_forward, size: 18), label: const Text('Go to')),
              const Spacer(),
              if (w['type'] != 'value')
                FilledButton(
                  onPressed: () => CardEngine.remindMode(w) == 'off' ? engine.turnOn(w) : engine.turnOff(w),
                  style: FilledButton.styleFrom(backgroundColor: pal.accent),
                  child: Text(CardEngine.remindMode(w) == 'off' ? 'Turn on' : 'Turn off'),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}
