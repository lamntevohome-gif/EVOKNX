import 'dart:convert';
import 'dart:io' show exitCode;
import 'package:knx_config/knx_config.dart';

void check(bool c, String m) {
  print('${c ? "OK  " : "FAIL"} $m');
  if (!c) exitCode = 1;
}

void main() {
  const pw = 'Mật khẩu 123';
  for (final f in ['ets6', 'ets5']) {
    final tag = f == 'ets6' ? 'ETS 6' : 'ETS 5';
    final b = base64.decode(f == 'ets6' ? _ets6 : _ets5);
    try {
      parseEts(b, fileName: 'x.knxproj');
      check(false, '$tag: should ask for a password');
    } on EtsPasswordRequired {
      check(true, '$tag: asks for a password');
    }
    try {
      parseEts(b, fileName: 'x.knxproj', password: 'sai mat khau');
      check(false, '$tag: wrong password must fail');
    } on EtsWrongPassword {
      check(true, '$tag: wrong password refused');
    }
    final sw = Stopwatch()..start();
    final r = parseEts(b, fileName: 'x.knxproj', password: pw);
    check(r.items.length == 6 && r.projectName == 'Villa Test',
        '$tag: right password imports ${r.items.length} addresses, project "${r.projectName}" (${sw.elapsedMilliseconds} ms)');
    check(
        r.items[3].dpt == '9.001' && r.items[2].dpt == '5.001', '$tag: DPTs read from the manufacturer data still work (${r.items[2].dpt}, ${r.items[3].dpt})');
  }
}

// Projects protected with the password above, made with pyzipper (WinZip AES-256)
// the way ETS 6 (derived key) and ETS 5 (raw password) do.
const String _ets6 =
    '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';
const String _ets5 =
    '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';
