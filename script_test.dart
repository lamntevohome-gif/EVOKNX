// Test of the scripts (pure Dart). Run: dart run tool/script_test.dart
import 'package:knx_config/knx_config.dart';

int _fail = 0, _pass = 0;
void check(bool ok, String name) {
  if (ok) {
    _pass++;
  } else {
    _fail++;
    print('FAIL: $name');
  }
}

class Host implements ScriptHost {
  final List<String> log = [];
  String? failWrite;

  @override
  Future<String?> write(Json ga, Object value) async {
    log.add('write ${ga['address']} ${value.runtimeType}:$value');
    return failWrite;
  }

  @override
  Future<String?> callHa(String service, String entity, Json data) async {
    log.add('ha $service $entity $data');
    return null;
  }

  @override
  String? goTo(String kind, String id) {
    log.add('goto $kind $id');
    return id == 'gone' ? 'the $kind does not exist.' : null;
  }

  @override
  void message(String text) => log.add('msg $text');
}

Future<void> main() async {
  final doc = <String, dynamic>{
    'groupAddresses': [
      {'id': 'g1', 'address': '1/1/1', 'dpt': '1.001'},
      {'id': 'g2', 'address': '1/1/2', 'dpt': '5.001'},
      {'id': 'g3', 'address': '1/1/3', 'dpt': '16.000'},
    ],
    'floors': [
      {'id': 'f1', 'title': 'Floor 1'},
    ],
    'pages': [
      {
        'id': 'r1',
        'floorId': 'f1',
        'title': 'Room',
        'subpages': [
          {'id': 's1', 'title': 'Page 1'},
        ],
      },
    ],
    'scripts': [
      {
        'id': 'sc1',
        'title': 'Movie',
        'steps': [
          {'type': 'write', 'ga': 'g1', 'value': '1'},
          {'type': 'write', 'ga': 'g2', 'value': '40,5'},
          {'type': 'write', 'ga': 'g3', 'value': 'Xem phim'},
          {'type': 'ha', 'service': 'light.turn_on', 'entity': 'light.tv', 'data': '{"brightness_pct": 20}'},
          {'type': 'wait', 'seconds': 0.05},
          {'type': 'goto', 'kind': 'page', 'id': 's1'},
          {'type': 'message', 'text': 'Enjoy'},
        ],
      },
      {
        'id': 'sc2',
        'title': 'Broken',
        'steps': [
          {'type': 'message', 'text': 'first'},
          {'type': 'goto', 'kind': 'room', 'id': 'gone'},
          {'type': 'message', 'text': 'never'},
        ],
      },
      {
        'id': 'sc3',
        'title': 'Bad service',
        'steps': [
          {'type': 'ha', 'service': 'turn on', 'entity': '', 'data': ''},
          {'type': 'message', 'text': 'never'},
        ],
      },
      {
        'id': 'sc4',
        'title': 'Long',
        'steps': [
          {'type': 'wait', 'seconds': 500},
          {'type': 'message', 'text': 'after'},
        ],
      },
      {
        'id': 'sc5',
        'title': 'Bad data',
        'steps': [
          {'type': 'ha', 'service': 'light.turn_on', 'entity': '', 'data': '{oops'},
        ],
      },
    ],
  };
  final host = Host();
  final runner = ScriptRunner(() => doc, host);

  await runner.run('sc1');
  check(host.log.length == 6, 'all steps ran (${host.log.length})');
  check(host.log[0] == 'write 1/1/1 int:1', 'write 1 bit as a number: ${host.log[0]}');
  check(host.log[1] == 'write 1/1/2 double:40.5', 'a comma is a decimal point: ${host.log[1]}');
  check(host.log[2] == 'write 1/1/3 String:Xem phim', 'a text address gets the text: ${host.log[2]}');
  check(host.log[3] == 'ha light.turn_on light.tv {brightness_pct: 20}', 'home assistant step: ${host.log[3]}');
  check(host.log[4] == 'goto page s1' && host.log[5] == 'msg Enjoy', 'order is kept');
  check(!runner.isRunning('sc1'), 'finished');

  host.log.clear();
  await runner.run('sc2');
  check(host.log.length == 3 && host.log[0] == 'msg first' && host.log[1] == 'goto room gone', 'the step that fails runs: ${host.log}');
  check(host.log[2] == 'msg Script “Broken”, step 2: the room does not exist.', 'the error tells the step: ${host.log.last}');

  host.log.clear();
  await runner.run('sc3');
  check(host.log.length == 1 && host.log[0].contains('step 1') && host.log[0].contains('domain.service'), 'bad service stops: ${host.log}');
  host.log.clear();
  await runner.run('sc5');
  check(host.log.length == 1 && host.log[0].contains('JSON'), 'bad data stops: ${host.log}');

  host.log.clear();
  host.failWrite = 'Connect before writing.';
  await runner.run('sc1');
  check(host.log.length == 2 && host.log[1] == 'msg Script “Movie”, step 1: Connect before writing.', 'a failed write stops: ${host.log}');
  host.failWrite = null;

  host.log.clear();
  await runner.run('nope');
  check(host.log.length == 1 && host.log[0].contains('does not exist'), 'unknown script');

  // A long wait ends at once when the script is stopped; running twice does nothing.
  host.log.clear();
  final run = runner.run('sc4');
  await Future<void>.delayed(const Duration(milliseconds: 30));
  check(runner.isRunning('sc4'), 'running');
  await runner.run('sc4');
  runner.stop('sc4');
  await run;
  check(host.log.isEmpty && !runner.isRunning('sc4'), 'stop ends the wait and nothing after it runs: ${host.log}');

  // Problems of the project
  check(scriptProblems(doc).length == 3, 'problems: ${scriptProblems(doc)}');
  doc['scripts'] = [
    {
      'id': 'x',
      'title': 'X',
      'steps': [
        {'type': 'write', 'ga': 'missing', 'value': '1'},
        {'type': 'goto', 'kind': 'page', 'id': 'zzz'},
      ],
    },
  ];
  final pr = scriptProblems(doc);
  check(pr.length == 2 && pr[0].contains('step 1') && pr[1].contains('target page does not exist'), 'problems of a deleted address and target: $pr');
  check(makeScript()['steps'] is List && makeStep('wait')['seconds'] == 1.0, 'new script and step');

  print('script test: $_pass passed, $_fail failed');
  if (_fail > 0) throw Exception('failed');
}
