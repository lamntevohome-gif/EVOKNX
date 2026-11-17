import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// "Transfer to App": finds the phones that have "Receive from computer" on (or takes the address typed here) and sends them the
/// configuration. The person accepts on the phone.
Future<void> showTransferToAppDialog(BuildContext context, ProjectController p) => showDialog<void>(
  context: context,
  builder: (_) => _TransferDialog(p: p),
);

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.p});
  final ProjectController p;
  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  List<FoundApp> found = const [];
  bool scanning = false;
  bool scanned = false;
  final TextEditingController manual = TextEditingController();

  /// Per address: 'sending', 'ok' or an error message.
  final Map<String, String> status = {};

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    manual.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => scanning = true);
    final r = await discoverApps();
    if (!mounted) return;
    setState(() {
      found = r;
      scanning = false;
      scanned = true;
    });
  }

  Future<void> _send(String address) async {
    setState(() => status[address] = 'sending');
    final err = await pushConfigToApp(address, thisComputerName(), widget.p.appConfig());
    if (!mounted) return;
    setState(() => status[address] = err ?? 'ok');
  }

  Widget _state(String address, EvoColors c) {
    final s = status[address];
    if (s == null) return const SizedBox.shrink();
    if (s == 'sending') {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Waiting for you to accept on the phone…',
                style: TextStyle(fontSize: kUiText - 1, color: c.muted),
              ),
            ),
          ],
        ),
      );
    }
    final ok = s == 'ok';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline, size: 16, color: ok ? const Color(0xFF14AE5C) : c.danger),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              ok ? 'Sent. The App now uses this configuration.' : s,
              style: TextStyle(fontSize: kUiText - 1, color: ok ? c.muted : c.danger),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    Widget device(String title, String address, {String? sub}) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smartphone, size: 20, color: c.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      sub ?? address,
                      style: TextStyle(fontSize: kUiText - 1, color: c.muted),
                    ),
                  ],
                ),
              ),
              EvoButton(
                label: 'Send',
                icon: Icons.send_outlined,
                primary: true,
                small: true,
                onPressed: status[address] == 'sending' ? null : () => _send(address),
              ),
            ],
          ),
          _state(address, c),
        ],
      ),
    );
    return AlertDialog(
      title: const Text('Transfer to App'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'On the phone (same Wi-Fi as this computer): open the EvoKNX App → Settings → turn on “Receive from computer”. The phone appears below; choose Send, then accept on the phone.',
                style: TextStyle(height: 1.45, color: c.muted),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text('Phones found', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (scanning)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    EvoButton(label: 'Search again', icon: Icons.refresh, small: true, onPressed: _scan),
                ],
              ),
              const SizedBox(height: 8),
              if (found.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    scanning
                        ? 'Searching…'
                        : scanned
                        ? 'No phone found. Check that “Receive from computer” is on and both are on the same Wi-Fi, or type the phone\'s address below.'
                        : '',
                    style: TextStyle(color: c.muted),
                  ),
                ),
              for (final f in found) device(f.name, f.address),
              const SizedBox(height: 6),
              Text('Or type the address', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: manual,
                      decoration: InputDecoration(isDense: true, hintText: '192.168.1.30', border: const OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  EvoButton(
                    label: 'Send',
                    icon: Icons.send_outlined,
                    small: true,
                    onPressed: manual.text.trim().isEmpty || status[manual.text.trim()] == 'sending' ? null : () => _send(manual.text.trim()),
                  ),
                ],
              ),
              if (manual.text.trim().isNotEmpty) _state(manual.text.trim(), c),
              const SizedBox(height: 12),
              Text(
                'The first time, Windows may ask about the firewall: choose Allow on private networks. The configuration contains the camera password; it is sent only on the home network, and only after you accept on the phone.',
                style: TextStyle(fontSize: kUiText - 1, height: 1.4, color: c.muted),
              ),
            ],
          ),
        ),
      ),
      actions: [EvoButton(label: 'Close', primary: true, onPressed: () => Navigator.pop(context))],
    );
  }
}
