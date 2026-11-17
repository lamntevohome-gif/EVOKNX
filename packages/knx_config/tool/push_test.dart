import 'package:knx_config/knx_config.dart';

void check(bool c, String m) => print('${c ? "OK  " : "FAIL"} $m');

Future<void> main() async {
  final doc = exportProject(newProject('Villa'));
  String? seenFrom;
  var accept = true;
  final rx = LanReceiver((from, cfg) async {
    seenFrom = from;
    return accept && jsonMap(cfg['project'])['name'] == 'Villa';
  }, name: 'Pixel 7');
  check(await rx.start() == null && rx.running, 'receiver started on ${rx.port}');
  final addr = '127.0.0.1:${rx.port}';
  var err = await pushConfigToApp(addr, 'PC-HOME', doc);
  check(err == null && seenFrom == 'PC-HOME', 'accepted push: $err');
  accept = false;
  err = await pushConfigToApp(addr, 'PC-HOME', doc);
  check((err ?? '').contains('Declined'), 'declined push: $err');
  err = await pushConfigToApp('127.0.0.1:1', 'PC-HOME', doc);
  check((err ?? '').contains('Could not connect'), 'no listener: $err');
  final found = await discoverApps(wait: const Duration(milliseconds: 500));
  print('discovered (depends on the sandbox network): ${found.map((f) => '${f.name}@${f.address}').toList()}');
  await rx.stop();
  err = await pushConfigToApp(addr, 'PC-HOME', doc);
  check(err != null, 'stopped receiver refuses: $err');
}
