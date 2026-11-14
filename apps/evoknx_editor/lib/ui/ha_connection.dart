import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/ha_link.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// The Home Assistant connection of the project, in the Connections tab: the address and the token, Connect and
/// Update Entity (which saves the list of entities so that they can be chosen on the cards without a connection).
class HaConnectionCard extends StatelessWidget {
  const HaConnectionCard({super.key, required this.project, required this.link});
  final ProjectController project;
  final HaLinkController link;

  void _set(String key, Object? v) {
    project.mutate((d) {
      final h = Map<String, dynamic>.from(haSettings(d));
      h[key] = v;
      d['ha'] = h;
    }, coalesce: 'ha-$key');
  }

  Future<void> _toggle() async {
    if (link.connected) {
      await link.disconnect();
      return;
    }
    final h = haSettings(project.doc);
    await link.connect((h['url'] ?? '').toString(), (h['token'] ?? '').toString());
  }

  Future<void> _update(BuildContext context) async {
    final list = await link.updateEntities();
    if (!context.mounted) return;
    toast(context, list == null ? (link.message ?? 'Could not update the entities.') : '${list.length} entities saved.');
  }

  Future<void> _remove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove the Home Assistant connection?'),
        content: const Text(
          'The address and the token are removed from the project. The cards that follow an entity will not work until a connection is added again. Can be undone (Ctrl+Z).',
        ),
        actions: [
          EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Remove', danger: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true) return;
    await link.disconnect();
    project.mutate((d) => d['ha'] = <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return ListenableBuilder(
      listenable: Listenable.merge([project, link]),
      builder: (context, _) {
        final h = haSettings(project.doc);
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
              // Like the name box of a KNX connection.
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.home_outlined, size: 17, color: c.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Home Assistant',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (h['enabled'] != true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Turned off for this project.', style: TextStyle(color: c.warn)),
                      ),
                      EvoButton(label: 'Turn on', small: true, onPressed: () => _set('enabled', true)),
                    ],
                  ),
                ),
              FieldLabel(
                'Address',
                SyncedField(
                  value: (h['url'] ?? '').toString(),
                  hint: 'e.g. 192.168.1.5:8123 or https://xxx.ui.nabu.casa',
                  onChanged: (v) => _set('url', v.trim()),
                ),
              ),
              const SizedBox(height: 10),
              FieldLabel('Token (Long-lived access token)', _TokenField(value: (h['token'] ?? '').toString(), onChanged: (v) => _set('token', v.trim()))),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: EvoButton(
                      label: link.connected ? 'Disconnect' : 'Connect',
                      primary: !link.connected,
                      fit: true,
                      keepSize: true,
                      onPressed: link.connecting ? null : _toggle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 11,
                    child: EvoButton(label: 'Update Entity', fit: true, keepSize: true, onPressed: link.connected ? () => _update(context) : null),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 9,
                    child: EvoButton(label: 'Delete', icon: Icons.delete_outline, danger: true, fit: true, keepSize: true, onPressed: () => _remove(context)),
                  ),
                ],
              ),
              Padding(padding: const EdgeInsets.only(top: 12), child: _status(c)),
            ],
          ),
        );
      },
    );
  }

  Widget _status(EvoColors c) {
    final ok = link.connected && link.message == null;
    final (IconData icon, Color color, String text) = switch (link.state) {
      HaConnection.connected => (
        link.message == null ? Icons.check_circle_outline : Icons.error_outline,
        link.message == null ? const Color(0xFF14AE5C) : c.warn,
        link.message ?? 'Connected · Home Assistant ${link.version ?? ''}${link.entities == null ? '' : ' · ${link.entities!.length} entities'}',
      ),
      HaConnection.connecting => (Icons.sync, c.muted, 'Connecting…'),
      HaConnection.failed => (Icons.error_outline, c.warn, link.message ?? 'Could not connect.'),
      HaConnection.disconnected => (
        Icons.link_off,
        c.muted,
        (link.entities ?? const []).isEmpty ? 'Not connected.' : 'Not connected · ${link.entities!.length} entities saved.',
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: ok || link.state == HaConnection.connecting || link.state == HaConnection.disconnected ? c.ink : c.warn)),
        ),
      ],
    );
  }
}

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
          tooltip: hide ? tr('Show token') : tr('Hide token'),
          icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
          onPressed: () => setState(() => hide = !hide),
        ),
      ),
    );
  }
}
