import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text;
import 'package:knx_config/knx_config.dart';
import 'package:knx_core/knx_core.dart' show dptMain;

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// The tab Schedulers: the 1-bit group addresses that the timers of the phone may switch (On or Off). The timers themselves are made on the
/// phone (Settings, Schedulers) and run by the EvoKNX Box, which is added in the Connections tab.
class SchedulersPage extends StatelessWidget {
  const SchedulersPage({super.key, required this.project});
  final ProjectController project;

  void _edit(void Function(List<Json> extra) fn, {String? coalesce}) => project.mutate((doc) {
    final b = jsonMap(doc['box']);
    final l = jsonList(b['extra']);
    fn(l);
    b['extra'] = l;
    doc['box'] = b;
  }, coalesce: coalesce);

  /// The addresses that can be chosen: 1-bit, not from Home Assistant.
  List<(String, String)> _choices(Set<Object?> used, Object? keep) {
    final out = <(String, String)>[];
    for (final g in project.groupAddresses) {
      if (isHaAddress(g) || dptMain((g['dpt'] ?? '').toString()) != 1) continue;
      if (used.contains(g['id']) && g['id'] != keep) continue;
      out.add((g['id'].toString(), '${g['address']}   ${g['name']}'));
    }
    if (keep != null && keep != '' && !out.any((e) => e.$1 == keep)) out.add((keep.toString(), 'Not available (deleted or not 1-bit)'));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return ListenableBuilder(
      listenable: project,
      builder: (context, _) {
        final extra = boxExtra(project.doc);
        final used = {for (final e in extra) e['ga']};
        final declared = boxDeclared(project.doc);
        final any = project.groupAddresses.any((g) => !isHaAddress(g) && dptMain((g['dpt'] ?? '').toString()) == 1);
        return Container(
          color: c.paper,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Addresses for timers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                          EvoButton(label: 'Add address', icon: Icons.add, onPressed: !any ? null : () => _edit((l) => l.add({'ga': '', 'name': ''}))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose the 1-bit group addresses that the timers on the phone may switch On or Off. The timers are made on the phone (Settings, Schedulers) and run by the EvoKNX Box.',
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: c.muted),
                      ),
                      if (!declared) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.panel,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: c.warn.withValues(alpha: 0.6)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 18, color: c.warn),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'There is no EvoKNX Box yet. Add one in Connections (Add connection, EvoKNX Box). Until then the phone does not show Schedulers.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (!any)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            'No 1-bit address in the project. Give an address the type 1.xxx (On/Off) in Connections.',
                            style: TextStyle(color: c.muted),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (extra.isEmpty && any)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text('No address yet. Add the addresses the timers should switch.', style: TextStyle(color: c.muted)),
                          ),
                        ),
                      for (var i = 0; i < extra.length; i++) _row(context, i, extra[i], used),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, int i, Json e, Set<Object?> used) {
    final c = context.evo;
    final choices = _choices(used, e['ga']);
    final ga = project.gaById(e['ga']?.toString());
    return Container(
      key: ValueKey('extra-$i-${e['ga']}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: 300,
            child: FieldLabel(
              'Group address',
              EvoDropdown<String>(
                width: 300,
                value: (e['ga'] ?? '').toString(),
                items: [('', 'Choose an address'), ...choices],
                onChanged: (v) => _edit((l) {
                  l[i]['ga'] = v;
                  if ((l[i]['name'] ?? '').toString().trim().isEmpty) l[i]['name'] = (project.gaById(v)?['name'] ?? '').toString();
                }),
              ),
            ),
          ),
          SizedBox(
            width: 240,
            child: FieldLabel(
              'Name on the phone',
              SyncedField(
                value: (e['name'] ?? '').toString(),
                hint: (ga?['name'] ?? '').toString(),
                onChanged: (v) => _edit((l) => l[i]['name'] = v, coalesce: 'box-extra-$i'),
              ),
            ),
          ),
          EvoButton(label: 'Delete', icon: Icons.delete_outline, danger: true, onPressed: () => _edit((l) => l.removeAt(i))),
        ],
      ),
    );
  }
}
