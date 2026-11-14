import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_config/knx_config.dart';

int _p = 0, _f = 0;
void check(bool ok, String n) {
  if (ok) {
    _p++;
  } else {
    _f++;
    stderr.writeln('FAIL: $n');
  }
}

Uint8List zip(Map<String, String> files) {
  // Build a STORED zip in memory.
  final out = BytesBuilder();
  final central = BytesBuilder();
  var offset = 0;
  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  files.forEach((name, content) {
    final data = utf8.encode(content);
    final nm = utf8.encode(name);
    final local = BytesBuilder();
    u32(local, 0x04034b50);
    u16(local, 20);
    u16(local, 0);
    u16(local, 0);
    u16(local, 0);
    u16(local, 0);
    u32(local, 0);
    u32(local, data.length);
    u32(local, data.length);
    u16(local, nm.length);
    u16(local, 0);
    local.add(nm);
    local.add(data);
    final lb = local.toBytes();
    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, data.length);
    u32(central, data.length);
    u16(central, nm.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(nm);
    out.add(lb);
    offset += lb.length;
  });
  final c = central.toBytes();
  out.add(c);
  final e = BytesBuilder();
  u32(e, 0x06054b50);
  u16(e, 0);
  u16(e, 0);
  u16(e, files.length);
  u16(e, files.length);
  u32(e, c.length);
  u32(e, offset);
  u16(e, 0);
  out.add(e.toBytes());
  return out.toBytes();
}

void main() {
  // CSV
  final csv =
      '"Group name";"Address";"Central";"Unfiltered";"Description";"DatapointType";"Security"\n"Main";"1/-/-";"";"";"";"";"Auto"\n"Bếp đèn";"5/0/1";"";"";"";"DPST-1-1";"Auto"\n"Bếp nhiệt";"5/0/2";"";"";"";"DPST-9-1";"Auto"\n';
  final r = parseEts(Uint8List.fromList(utf8.encode(csv)), fileName: 'ga.csv');
  check(r.items.length == 2 && r.items[0].name == 'Bếp đèn' && r.items[1].dpt == '9.001', 'csv');
  // XML
  final xml =
      '<GroupAddress-Export><GroupRange Name="A"><GroupAddress Name="Đèn &amp; quạt" Address="1/1/1" DPTs="DPST-1-1"/></GroupRange></GroupAddress-Export>';
  final rx = parseEts(Uint8List.fromList(utf8.encode(xml)));
  check(rx.items.single.name == 'Đèn & quạt' && rx.items.single.dpt == '1.001', 'xml');
  // knxproj
  final kp = zip({
    'knx_master.xml': '<KNX/>',
    'P-0A1B/project.xml': '<KNX><Project><ProjectInformation Name="Nhà anh Nam" GroupAddressStyle="ThreeLevel"/></Project></KNX>',
    'P-0A1B/0.xml': '<KNX><GroupAddress Id="x" Address="2305" Name="Đèn trần" DatapointType="DPST-1-1"/><GroupAddress Address="6145" Name="Nhiệt độ" DatapointType="DPST-9-1"/></KNX>',
  });
  final rk = parseEts(kp, fileName: 'a.knxproj');
  check(rk.projectName == 'Nhà anh Nam' && rk.items.map((e) => e.address).join(',') == '1/1/1,3/0/1', 'knxproj ${rk.items.map((e) => e.address)}');
  try {
    parseEts(zip({'knx_master.xml': '<KNX/>', 'P-0A1B.zip': 'x'}), fileName: 'b.knxproj');
    check(false, 'protected');
  } on EtsException catch (e) {
    check(e.message.contains('password'), 'protected msg');
  }
  // Project + import
  final doc = newProject('Test');
  check(isProject(doc), 'isProject');
  var res = applyEts(doc, rk);
  check(res.added == 2 && jsonList(doc['groupAddresses']).length == 2, 'apply add');
  final room = makeRoom('Living room', floorId: jsonList(doc['floors']).first['id'] as String);
  (doc['pages'] as List).add(room);
  final w = makeWidget('switch', 0, 0)..['bind'] = {'write': 'ga_1_1_1', 'status': 'ga_3_0_1'};
  (jsonList(room['subpages']).first['widgets'] as List).add(w);
  final st = importStats(doc, r.items);
  check(st.fresh == 2 && st.gone == 2 && st.links == 2, 'stats ${st.fresh} ${st.gone} ${st.links}');
  res = applyEts(doc, r, replace: true);
  check(res.removed == 2 && res.unlinked == 2 && jsonMap(w['bind']).isEmpty, 'replace');
  // Migration from web v1
  final v1 = jsonDecode(
    '{"schemaVersion":1,"project":{"id":"x","name":"Cu","revision":0},"connections":[{"id":"main","type":"tunneling","host":"1.2.3.4","port":3671}],"groupAddresses":[],"pages":[{"id":"page_a","title":"Sảnh","icon":"home","layout":{"type":"grid","columns":4},"widgets":[{"id":"w1","type":"switch","label":"Đèn","icon":"bulb","pos":{"x":0,"y":1,"w":2,"h":1},"bind":{}}]}]}',
  ) as Map<String, dynamic>;
  final m = migrate(v1);
  final mw = jsonList(jsonList(jsonList(m['pages']).first['subpages']).first['widgets']).first;
  check(
    m['schemaVersion'] == kSchemaVersion && jsonMap(mw['pos'])['y'] == 2 && jsonMap(mw['pos'])['h'] == 2 && jsonList(m['floors']).length == 1,
    'migrate v1',
  );
  // Export with tablet
  m['devices'] = {'mobile': true, 'tabletP': true, 'tabletL': false};
  final ex = exportProject(m);
  final ew = jsonList(jsonList(jsonList(ex['pages']).first['subpages']).first['widgets']).first;
  check(jsonMap(ew['posBy']).containsKey('tabletP') && jsonMap(ew['posBy']).containsKey('mobile'), 'export devices');
  // slots
  final ac = makeWidget('ac', 0, 0);
  (ac['ac'] as Map)['modeAddr'] = 'separate';
  check(slotsFor(ac).any((s) => s.key == 'mode_cool') && !slotsFor(ac).any((s) => s.key == 'mode'), 'ac slots');
  // media player card: addresses only with the source KNX
  final mp = makeWidget('media', 0, 0);
  check(slotsFor(mp).isEmpty && !mediaIsKnx(mp), 'media ha has no slots');
  check(switchMediaSource(mp, 'knx') && mediaIsKnx(mp) && slotsFor(mp).any((s) => s.key == 'volume'), 'media knx slots');
  check(widgetEntity(mp).isEmpty, 'media knx has no entity');
  mp['bind'] = {'play': 'x'};
  check(switchMediaSource(mp, 'ha') && !mediaIsKnx(mp) && jsonMap(mp['bind']).isEmpty, 'media back to ha');
  // remote control card: layout, hiding, KNX modes
  final rm = makeWidget('remote', 0, 0);
  void rset(String k, Object v) => rm['remote'] = <String, dynamic>{...Map<String, dynamic>.from(rm['remote'] as Map), k: v};
  var its = remoteItems(rm);
  check(its.first.id == 'poweron' && its.first.r == 0 && its[1].id == 'poweroff' && its[1].r == 0, 'remote: On and Off are in the first row');
  check(its.firstWhere((i) => i.id == 'dpad').r == 1 && its.firstWhere((i) => i.id == 'dpad').rh == 3, 'remote: the ring is below, 3 x 3');
  check(!its.any((i) => i.id == 'touchpad') && its.length == 12, 'remote: the touchpad is hidden by default, 12 parts shown');
  bool overlap(List<RemoteItem> l) {
    for (var a = 0; a < l.length; a++) {
      for (var b = a + 1; b < l.length; b++) {
        if (l[a].c < l[b].c + l[b].cw && l[b].c < l[a].c + l[a].cw && l[a].r < l[b].r + l[b].rh && l[b].r < l[a].r + l[a].rh) return true;
      }
    }
    return false;
  }

  check(!overlap(its) && remoteRows(its) == 7, 'remote: no overlap, 7 rows');
  rset('hide', {'back': true});
  rset('custom', [
    {'id': 'rc_1', 'label': 'Netflix', 'icon': '', 'cmd': 'NETFLIX'},
  ]);
  its = remoteItems(rm);
  check(!its.any((i) => i.id == 'back') && its.any((i) => i.id == 'rc_1') && !overlap(its), 'remote: a hidden key is left out, a custom button is placed');
  rset('layout', {
    'rc_1': {'c': 0, 'r': 0},
  });
  its = remoteItems(rm);
  check(its.firstWhere((i) => i.id == 'rc_1').r == 0 && !overlap(its), 'remote: a dragged part keeps its cell, the ring moves out of its way');
  check(remoteCommand(rm, 'rc_1') == 'NETFLIX' && remoteCall(rm, 'poweron') == null, 'remote: custom key name; no call without a remote');
  rset('entity', 'remote.tv');
  check(
    remoteCall(rm, 'poweron')!.service == 'remote.turn_on' && remoteCall(rm, 'rc_1')!.data['command'] == 'NETFLIX',
    'remote: power on and the custom key call the remote',
  );
  check(slotsFor(rm).isEmpty && switchRemoteSource(rm, 'knx') && remoteIsKnx(rm), 'remote: KNX gives address fields');
  check(
    slotsFor(rm).any((s) => s.key == 'rk_up') && slotsFor(rm).any((s) => s.key == 'rk_rc_1') && slotsFor(rm).any((s) => s.key == 'rk_poweron'),
    'remote: one address for each key',
  );
  check(remoteKnxSend(rm, 'up')!.slot == 'rk_up' && remoteKnxSend(rm, 'up')!.value == '1', 'remote: each key sends 1 on its address');
  rset('knxMode', 'single');
  check(
    slotsFor(rm).length == 1 && slotsFor(rm).first.key == 'rk_all' && remoteKnxSend(rm, 'down')!.slot == 'rk_all' && remoteKnxSend(rm, 'down')!.value == '4',
    'remote: one address for all, the number of the key',
  );
  rset('values', {'down': '77'});
  check(remoteKnxSend(rm, 'down')!.value == '77', 'remote: own value');
  check(widgetEntity(rm).isEmpty && remoteProblem(rm) == null, 'remote: KNX has no entity and no problem');
  stdout.writeln('knx_config selftest: $_p passed, $_f failed');
  exit(_f == 0 ? 0 : 1);
}
