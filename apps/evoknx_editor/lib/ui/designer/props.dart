import 'dart:convert';
import 'dart:math';

import 'package:file_selector/file_selector.dart';

import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';
import 'icons.dart';
import 'model.dart';

/// Right-hand properties panel of the Structure workspace.
class PropsPanel extends StatelessWidget {
  const PropsPanel({super.key, required this.d});
  final Designer d;

  @override
  Widget build(BuildContext context) {
    final w = d.widget;
    final List<Widget> body;
    if (w != null) {
      body = [_WidgetProps(key: ValueKey('wp-${w['id']}'), d: d, w: w)];
    } else if (d.view == 'overview') {
      body = [_OverviewProps(d: d)];
    } else if (d.view == 'floor' && d.floor != null) {
      body = [_FloorProps(key: ValueKey('fp-${d.floor!['id']}'), d: d, f: d.floor!)];
    } else {
      body = [
        if (d.cell != null) _CellBox(d: d),
        if (d.room != null) _RoomProps(key: ValueKey('rp-${d.room!['id']}-${d.sub?['id']}'), d: d),
        if (d.room == null) const _Hint('Chọn một phòng ở cột bên trái, hoặc thêm phòng mới.'),
      ];
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 30), children: body);
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(color: context.evo.muted));
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children, {this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title, trailing: trailing),
        for (var i = 0; i < children.length; i++) ...[children[i], if (i < children.length - 1) const SizedBox(height: 12)],
      ],
    ),
  );
}

class StepRow extends StatelessWidget {
  const StepRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = 'px',
    this.step = 1,
  });
  final String label, unit;
  final int value, min, max, step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    Widget b(IconData i, int d) => InkWell(
      onTap: (d < 0 ? value <= min : value >= max) ? null : () => onChanged((value + d).clamp(min, max)),
      child: SizedBox(width: 30, height: 30, child: Icon(i, size: 16, color: (d < 0 ? value <= min : value >= max) ? c.lineStrong : c.ink)),
    );
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 13.5, color: c.ink)),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              b(Icons.remove, -step),
              Container(
                width: 58,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.symmetric(vertical: BorderSide(color: c.line)),
                ),
                child: Text('$value $unit', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              b(Icons.add, step),
            ],
          ),
        ),
      ],
    );
  }
}

List<(String, String)> _iconItems(List<(String, String)> l) => l;

// ------------------------------------------------------------------ widget

class _WidgetProps extends StatefulWidget {
  const _WidgetProps({super.key, required this.d, required this.w});
  final Designer d;
  final Json w;
  @override
  State<_WidgetProps> createState() => _WidgetPropsState();
}

class _WidgetPropsState extends State<_WidgetProps> {
  String q = '';

  Designer get d => widget.d;
  Json get w => widget.w;
  String get id => w['id'] as String;

  void set(String key, Object? v, {String? coalesce}) => d.editWidget(id, (x) => x[key] = v, coalesce: coalesce);

  void setSize(String k, int v) {
    final s = d.sub;
    if (s == null) return;
    final box = containerOf(s, id) ?? s;
    var x = pi(w, 'x'), y = pi(w, 'y'), ww = pi(w, 'w'), hh = pi(w, 'h');
    if (k == 'w') ww = v;
    if (k == 'h') hh = v;
    if (x + ww > cols(box)) x = max(0, cols(box) - ww);
    if (!isFree(box, x, y, ww, hh, id)) {
      toast(context, 'Không đủ chỗ: vùng mới bị trùng với thành phần khác.');
      return;
    }
    d.editWidget(id, (o) => o['pos'] = {'x': x, 'y': y, 'w': ww, 'h': hh});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final type = (w['type'] ?? '').toString();
    final def = kWidgetTypes[type];
    final s = d.sub;
    final box = s == null ? null : (containerOf(s, id) ?? s);
    final maxCols = box == null ? 4 : cols(box);
    final inGroup = box != null && box['type'] == 'group';
    final maxH = type == 'group' || type == 'webview' ? (box == null ? 12 : rows(box)) : min(6, box == null ? 12 : rows(box));
    final text = jsonMap(w['text']);
    final gas = jsonList(d.doc['groupAddresses']);
    final bind = jsonMap(w['bind']);
    final fq = fold(q.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(iconOf(def?.icon), size: 20, color: c.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(def?.name ?? type, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            EvoButton(
              label: 'Sao chép',
              icon: Icons.copy_outlined,
              small: true,
              onPressed: () {
                final m = d.copy();
                if (m != null) toast(context, m);
              },
            ),
            const SizedBox(width: 6),
            EvoButton(label: 'Xoá', icon: Icons.delete_outline, small: true, danger: true, onPressed: d.deleteWidget),
          ],
        ),
        const SizedBox(height: 16),
        _Section('Chung', [
          FieldLabel(
            'Tên hiển thị',
            SyncedField(
              value: (w['label'] ?? '').toString(),
              onChanged: (v) => set('label', v, coalesce: 'label-$id'),
            ),
          ),
          if (type != 'group')
            FieldLabel(
              'Biểu tượng',
              EvoDropdown<String>(value: (w['icon'] ?? '').toString(), items: [...kLightIcons, ...kDeviceIcons], onChanged: (v) => set('icon', v)),
            ),
          Row(
            children: [
              Expanded(
                child: FieldLabel(
                  'Rộng (ô)',
                  EvoDropdown<int>(value: pi(w, 'w'), items: [for (var i = 1; i <= maxCols; i++) (i, '$i')], onChanged: (v) => setSize('w', v)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FieldLabel(
                  'Cao (hàng)',
                  EvoDropdown<int>(value: pi(w, 'h'), items: [for (var i = 1; i <= max(maxH, pi(w, 'h')); i++) (i, '$i')], onChanged: (v) => setSize('h', v)),
                ),
              ),
            ],
          ),
          if (inGroup) Text('Nằm trong khung lưới “${box['label'] ?? ''}”: vị trí tính theo lưới của khung.', style: TextStyle(fontSize: 12.5, color: c.muted)),
        ]),
        ..._typeSpecific(context, type),
        _Section('Cỡ chữ', [
          for (final k in fsKeysFor(type))
            StepRow(
              label: kFs[k]!.name,
              value: fs(w, k).toInt(),
              min: kFs[k]!.min,
              max: kFs[k]!.max,
              onChanged: (v) => d.editWidget(id, (o) {
                final t = jsonMap(o['text']);
                t[k] = v;
                o['text'] = t;
              }, coalesce: 'fs-$id-$k'),
            ),
          if (text.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => set('text', <String, dynamic>{}), child: const Text('Về cỡ mặc định')),
            ),
        ]),
        if (slotsFor(w).isNotEmpty)
          _Section('Liên kết địa chỉ nhóm', [
            SearchField(hint: 'Tìm theo địa chỉ hoặc tên', width: double.infinity, onChanged: (v) => setState(() => q = v)),
            for (final sl in slotsFor(w))
              FieldLabel(
                '${sl.label}${sl.required ? ' *' : ''}',
                EvoDropdown<String>(
                  value: (bind[sl.key] ?? '').toString(),
                  warn: sl.required && bind[sl.key] == null,
                  items: [
                    ('', fq.isEmpty ? 'Chưa gán' : 'Chưa gán (đang lọc: ${q.trim()})'),
                    for (final g
                        in (gas
                            .where((g) => (slotAccepts(sl, g) && (fq.isEmpty || fold('${g['address']} ${g['name']}').contains(fq))) || g['id'] == bind[sl.key])
                            .toList()
                          ..sort((a, b) => gaSortKey(a['address'].toString()).compareTo(gaSortKey(b['address'].toString())))))
                      (g['id'].toString(), '${g['address']}   ${g['name']}'),
                    if (bind[sl.key] != null && byId(gas, bind[sl.key] as String) == null) (bind[sl.key].toString(), 'Địa chỉ đã bị xoá'),
                  ],
                  onChanged: (v) => d.editWidget(id, (o) {
                    final b = jsonMap(o['bind']);
                    if (v.isEmpty) {
                      b.remove(sl.key);
                    } else {
                      b[sl.key] = v;
                    }
                    o['bind'] = b;
                  }),
                ),
              ),
          ]),
      ],
    );
  }

  List<Widget> _typeSpecific(BuildContext context, String type) {
    switch (type) {
      case 'link':
      case 'webview':
        return [
          _Section('Trang web', [
            FieldLabel(
              'Địa chỉ web',
              SyncedField(
                value: (w['url'] ?? '').toString(),
                hint: 'https://…',
                onChanged: (v) => set('url', v.trim(), coalesce: 'url-$id'),
              ),
            ),
            if (type == 'link')
              FieldLabel(
                'Cách mở',
                EvoDropdown<String>(
                  value: (w['openIn'] ?? 'inApp').toString(),
                  items: const [('inApp', 'Mở trong App'), ('external', 'Mở bằng trình duyệt')],
                  onChanged: (v) => set('openIn', v),
                ),
              ),
            if (type == 'webview') ...[
              for (final o in const [
                ('showHeader', 'Hiện tên và biểu tượng phía trên'),
                ('interactive', 'Cho phép thao tác trên trang'),
                ('fullscreen', 'Cho phép mở toàn màn hình'),
              ])
                _Check(
                  o.$2,
                  jsonMap(w['web'])[o.$1] != false,
                  (v) => d.editWidget(id, (x) {
                    final m = jsonMap(x['web']);
                    m[o.$1] = v;
                    x['web'] = m;
                  }),
                ),
              FieldLabel(
                'Tự làm mới',
                EvoDropdown<int>(
                  value: ((jsonMap(w['web'])['refresh'] as num?) ?? 0).toInt(),
                  items: const [(0, 'Không'), (30, 'Mỗi 30 giây'), (60, 'Mỗi phút'), (300, 'Mỗi 5 phút'), (900, 'Mỗi 15 phút')],
                  onChanged: (v) => d.editWidget(id, (x) {
                    final m = jsonMap(x['web']);
                    m['refresh'] = v;
                    x['web'] = m;
                  }),
                ),
              ),
            ],
          ]),
        ];
      case 'switch':
      case 'dimmer':
        final st = jsonMap(w['style']);
        final feat = jsonMap(w['features']);
        final tw = jsonMap(w['tw']);
        void setStyle(String k, Object v, {String? co}) => d.editWidget(id, (x) {
          final m = jsonMap(x['style']);
          m[k] = v;
          x['style'] = m;
        }, coalesce: co);
        return [
          _Section('Màu và trạng thái', [
            FieldLabel(
              'Màu khi bật',
              _ColorPicker(
                value: (st['colorOn'] ?? '#EE9B2A').toString(),
                onChanged: (v) => setStyle('colorOn', v, co: 'con-$id'),
              ),
            ),
            FieldLabel(
              'Màu khi tắt',
              _ColorPicker(
                value: (st['colorOff'] ?? '#8A938F').toString(),
                onChanged: (v) => setStyle('colorOff', v, co: 'coff-$id'),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: FieldLabel(
                    'Chữ khi bật',
                    SyncedField(
                      value: (st['textOn'] ?? 'Đang bật').toString(),
                      onChanged: (v) => setStyle('textOn', v, co: 'ton-$id'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'Chữ khi tắt',
                    SyncedField(
                      value: (st['textOff'] ?? 'Đang tắt').toString(),
                      onChanged: (v) => setStyle('textOff', v, co: 'toff-$id'),
                    ),
                  ),
                ),
              ],
            ),
          ]),
          if (type == 'dimmer')
            _Section('Tính năng đèn', [
              _Check(
                'Nhiệt độ màu (Tunable White, DPT 7.600)',
                feat['tw'] == true,
                (v) => d.editWidget(id, (x) {
                  final m = jsonMap(x['features']);
                  m['tw'] = v;
                  x['features'] = m;
                }),
              ),
              if (feat['tw'] == true)
                Row(
                  children: [
                    Expanded(
                      child: FieldLabel(
                        'Ấm nhất (K)',
                        SyncedField(
                          value: '${tw['min'] ?? 2700}',
                          number: true,
                          onChanged: (v) => d.editWidget(id, (x) {
                            final m = jsonMap(x['tw']);
                            m['min'] = int.tryParse(v) ?? 2700;
                            x['tw'] = m;
                          }, coalesce: 'twmin-$id'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FieldLabel(
                        'Lạnh nhất (K)',
                        SyncedField(
                          value: '${tw['max'] ?? 6500}',
                          number: true,
                          onChanged: (v) => d.editWidget(id, (x) {
                            final m = jsonMap(x['tw']);
                            m['max'] = int.tryParse(v) ?? 6500;
                            x['tw'] = m;
                          }, coalesce: 'twmax-$id'),
                        ),
                      ),
                    ),
                  ],
                ),
              _Check(
                'Màu RGB (DPT 232.600 / 251.600)',
                feat['rgb'] == true,
                (v) => d.editWidget(id, (x) {
                  final m = jsonMap(x['features']);
                  m['rgb'] = v;
                  x['features'] = m;
                }),
              ),
            ]),
        ];
      case 'shutter':
        return [
          _Section('Rèm', [
            FieldLabel(
              'Kiểu rèm',
              Seg<String>(
                items: const [('roller', 'Rèm cuốn'), ('curtain', 'Rèm vải')],
                value: (w['shStyle'] ?? 'roller').toString(),
                onChanged: (v) => d.editWidget(id, (x) {
                  x['shStyle'] = v;
                  x['icon'] = v == 'curtain' ? 'curtain' : 'blind';
                }),
              ),
            ),
            FieldLabel(
              'Cách điều khiển',
              EvoDropdown<String>(
                value: (w['shCtrl'] ?? 'buttons').toString(),
                items: const [('buttons', 'Nút lên / dừng / xuống'), ('slider', 'Thanh kéo vị trí'), ('both', 'Cả nút và thanh kéo')],
                onChanged: (v) => set('shCtrl', v),
              ),
            ),
            _Check('Hiện nút dừng', w['showStop'] != false, (v) => set('showStop', v)),
            _Check('Đảo chiều lên/xuống (gửi 1 khi lên, 0 khi xuống)', w['udInvert'] == true, (v) => set('udInvert', v)),
          ]),
        ];
      case 'ac':
        final ac = jsonMap(w['ac']);
        final modes = jsonMap(ac['modes']);
        final names = jsonMap(ac['names']);
        final values = jsonMap(ac['values']);
        final sep = ac['modeAddr'] == 'separate';
        void setAc(String k, Object? v, {String? co}) => d.editWidget(id, (x) {
          final m = jsonMap(x['ac']);
          m[k] = v;
          x['ac'] = m;
        }, coalesce: co);
        void setAcMap(String k, String key, Object? v, {String? co}) => d.editWidget(id, (x) {
          final m = jsonMap(x['ac']);
          final mm = jsonMap(m[k]);
          if (v == null || (v is String && v.trim().isEmpty)) {
            mm.remove(key);
          } else {
            mm[key] = v;
          }
          m[k] = mm;
          x['ac'] = m;
        }, coalesce: co);
        return [
          _Section('Máy lạnh', [
            Row(
              children: [
                Expanded(
                  child: FieldLabel(
                    'Nhiệt độ thấp nhất',
                    SyncedField(
                      value: '${ac['min'] ?? 16}',
                      number: true,
                      onChanged: (v) => setAc('min', num.tryParse(v.replaceAll(',', '.')) ?? 16, co: 'acmin-$id'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'Nhiệt độ cao nhất',
                    SyncedField(
                      value: '${ac['max'] ?? 30}',
                      number: true,
                      onChanged: (v) => setAc('max', num.tryParse(v.replaceAll(',', '.')) ?? 30, co: 'acmax-$id'),
                    ),
                  ),
                ),
              ],
            ),
            FieldLabel(
              'Bước tăng giảm',
              EvoDropdown<num>(value: (ac['step'] as num?) == 1 ? 1 : 0.5, items: const [(0.5, '0,5 °C'), (1, '1 °C')], onChanged: (v) => setAc('step', v)),
            ),
            _Check('Hiện nhiệt độ phòng (cần gán ô Nhiệt độ phòng)', ac['showCur'] != false, (v) => setAc('showCur', v)),
            FieldLabel(
              'Nút chế độ hiển thị',
              EvoDropdown<String>(
                value: (ac['modeLabel'] ?? 'both').toString(),
                items: const [('both', 'Biểu tượng và chữ'), ('icon', 'Chỉ biểu tượng'), ('text', 'Chỉ chữ')],
                onChanged: (v) => setAc('modeLabel', v),
              ),
            ),
            FieldLabel(
              'Cách gửi chế độ',
              EvoDropdown<String>(
                value: sep ? 'separate' : 'single',
                items: const [('single', 'Một địa chỉ chung, mỗi chế độ một giá trị'), ('separate', 'Mỗi chế độ một địa chỉ riêng (1 bit)')],
                onChanged: (v) => d.editWidget(id, (x) {
                  final m = jsonMap(x['ac']);
                  m['modeAddr'] = v;
                  x['ac'] = m;
                  final b = jsonMap(x['bind']);
                  if (v == 'separate') {
                    b.remove('mode');
                    b.remove('modeSt');
                  } else {
                    b.removeWhere((k, _) => k.startsWith('mode_') || k.startsWith('modeSt_'));
                  }
                  x['bind'] = b;
                }),
              ),
            ),
            Text('Chế độ: đánh dấu để hiện, đặt tên và giá trị gửi', style: TextStyle(fontSize: 12.5, color: context.evo.muted)),
            Row(
              children: [
                const SizedBox(width: 40),
                Icon(Icons.power_settings_new, size: 16, color: context.evo.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: SyncedField(
                    value: (names['off'] ?? '').toString(),
                    hint: 'Tắt',
                    onChanged: (v) => setAcMap('names', 'off', v, co: 'acn-off-$id'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: Text(
                    'Bật/tắt',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: context.evo.muted),
                  ),
                ),
              ],
            ),
            for (final m in kAcModes)
              Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Checkbox(
                      value: modes.containsKey(m.key) ? modes[m.key] == true : m.key != 'heat',
                      onChanged: (v) => setAcMap('modes', m.key, v ?? false),
                    ),
                  ),
                  Icon(iconOf(m.icon), size: 16, color: context.evo.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SyncedField(
                      value: (names[m.key] ?? '').toString(),
                      hint: m.name,
                      onChanged: (v) => setAcMap('names', m.key, v, co: 'acn-${m.key}-$id'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 64,
                    child: sep
                        ? Text(
                            'Gửi 1',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: context.evo.muted),
                          )
                        : SyncedField(
                            value: '${values[m.key] ?? m.value}',
                            number: true,
                            onChanged: (v) => setAcMap('values', m.key, int.tryParse(v) ?? m.value, co: 'acv-${m.key}-$id'),
                          ),
                  ),
                ],
              ),
          ]),
        ];
      case 'scene':
        return [
          _Section('Cảnh', [
            FieldLabel(
              'Số cảnh',
              EvoDropdown<int>(
                value: ((w['sceneNumber'] as num?) ?? 1).toInt(),
                items: [for (var i = 1; i <= 64; i++) (i, 'Cảnh $i')],
                onChanged: (v) => set('sceneNumber', v),
              ),
            ),
          ]),
        ];
      case 'button':
        return [
          _Section('Nút nhấn', [
            FieldLabel(
              'Giá trị gửi',
              SyncedField(
                value: (w['sendValue'] ?? '1').toString(),
                onChanged: (v) => set('sendValue', v.trim(), coalesce: 'sv-$id'),
              ),
            ),
          ]),
        ];
      case 'value':
        final f = jsonMap(w['format']);
        return [
          _Section('Hiển thị giá trị', [
            Row(
              children: [
                Expanded(
                  child: FieldLabel(
                    'Đơn vị',
                    SyncedField(
                      value: (f['unit'] ?? '').toString(),
                      hint: '°C',
                      onChanged: (v) => d.editWidget(id, (o) {
                        final ff = jsonMap(o['format']);
                        ff['unit'] = v;
                        o['format'] = ff;
                      }, coalesce: 'unit-$id'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'Số lẻ',
                    EvoDropdown<int>(
                      value: ((f['decimals'] as num?) ?? 1).toInt(),
                      items: const [(0, '0'), (1, '1'), (2, '2')],
                      onChanged: (v) => d.editWidget(id, (o) {
                        final ff = jsonMap(o['format']);
                        ff['decimals'] = v;
                        o['format'] = ff;
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ]),
        ];
      case 'group':
        final l = jsonMap(w['layout']);
        return [
          _Section('Khung lưới', [
            Row(
              children: [
                Expanded(
                  child: FieldLabel(
                    'Số hàng của khung',
                    EvoDropdown<int>(
                      value: ((l['rows'] as num?) ?? 4).toInt(),
                      items: [for (var i = 1; i <= 12; i++) (i, '$i')],
                      onChanged: (v) => d.editWidget(id, (o) => jsonMap(o['layout'])['rows'] = v),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'Số cột của khung',
                    EvoDropdown<int>(
                      value: ((l['columns'] as num?) ?? 4).toInt(),
                      items: [for (var i = 1; i <= 6; i++) (i, '$i')],
                      onChanged: (v) => d.editWidget(id, (o) => Designer.repackCols(o, v)),
                    ),
                  ),
                ),
              ],
            ),
            FieldLabel(
              'Kiểu khung',
              EvoDropdown<String>(
                value: (w['gstyle'] ?? 'card').toString(),
                items: const [('card', 'Nền thẻ'), ('line', 'Chỉ có viền'), ('none', 'Trong suốt')],
                onChanged: (v) => set('gstyle', v),
              ),
            ),
            CheckboxListTile(
              value: w['showTitle'] != false,
              onChanged: (v) => set('showTitle', v ?? true),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Hiện tiêu đề khung'),
            ),
            if (w['showTitle'] != false)
              FieldLabel(
                'Canh tiêu đề',
                Seg<String>(
                  items: const [('left', 'Trái'), ('center', 'Giữa'), ('right', 'Phải')],
                  value: (w['titleAlign'] ?? 'left').toString(),
                  onChanged: (v) => set('titleAlign', v),
                ),
              ),
            if (w['showTitle'] != false)
              StepRow(
                label: 'Khoảng cách tiêu đề',
                value: ((w['titleGap'] as num?) ?? 10).toInt(),
                min: 0,
                max: 40,
                step: 2,
                onChanged: (v) => set('titleGap', v, coalesce: 'tg-$id'),
              ),
          ]),
        ];
    }
    return const [];
  }
}

// ------------------------------------------------------------------ cell

class _CellBox extends StatelessWidget {
  const _CellBox({required this.d});
  final Designer d;
  @override
  Widget build(BuildContext context) {
    final c = d.cell!;
    final g = c.g == null || d.sub == null ? null : findWidget(d.sub!, c.g);
    return _Section('Ô đã chọn', [
      Text('${g != null ? 'Trong khung “${g['label'] ?? ''}”, ' : ''}hàng ${c.y + 1}, cột ${c.x + 1}', style: const TextStyle(fontSize: 14)),
      Text('Bấm một thành phần trên thanh công cụ để thêm vào đúng ô này.', style: TextStyle(fontSize: 12.5, color: context.evo.muted)),
      if (d.clip != null)
        Align(
          alignment: Alignment.centerLeft,
          child: EvoButton(
            label: 'Dán “${d.clip!['label'] ?? ''}” vào đây',
            icon: Icons.content_paste,
            primary: true,
            small: true,
            onPressed: () {
              final m = d.paste();
              if (m != null) toast(context, m);
            },
          ),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ room + page

class _RoomProps extends StatelessWidget {
  const _RoomProps({super.key, required this.d});
  final Designer d;

  @override
  Widget build(BuildContext context) {
    final r = d.room!;
    final s = d.sub;
    final rid = r['id'] as String;
    final floors = floorsOf(d.doc);
    final subs = subsOf(r);
    final si = s == null ? -1 : subs.indexWhere((x) => x['id'] == s['id']);
    void editRoom(void Function(Json r) fn, {String? coalesce}) => d.p.mutate((doc) {
      final x = byId(jsonList(doc['pages']), rid);
      if (x != null) fn(x);
    }, coalesce: coalesce);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          'Phòng',
          [
            FieldLabel(
              'Tên phòng',
              SyncedField(
                value: (r['title'] ?? '').toString(),
                onChanged: (v) => editRoom((x) => x['title'] = v, coalesce: 'rt-$rid'),
              ),
            ),
            FieldLabel(
              'Thuộc tầng',
              EvoDropdown<String>(
                value: (r['floorId'] ?? '').toString(),
                items: [for (final f in floors) (f['id'].toString(), (f['title'] ?? '').toString())],
                onChanged: (v) => editRoom((x) => x['floorId'] = v),
              ),
            ),
            FieldLabel(
              'Biểu tượng phòng',
              EvoDropdown<String>(value: (r['icon'] ?? 'sofa').toString(), items: _iconItems(kRoomIcons), onChanged: (v) => editRoom((x) => x['icon'] = v)),
            ),
            Row(
              children: [
                EvoButton(label: 'Lên', icon: Icons.arrow_upward, small: true, onPressed: () => d.moveRoom(rid, -1)),
                const SizedBox(width: 6),
                EvoButton(label: 'Xuống', icon: Icons.arrow_downward, small: true, onPressed: () => d.moveRoom(rid, 1)),
              ],
            ),
          ],
          trailing: EvoButton(
            label: 'Xoá phòng',
            icon: Icons.delete_outline,
            small: true,
            danger: true,
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text('Xoá phòng “${r['title']}”?'),
                  content: const Text('Toàn bộ trang và thành phần trong phòng sẽ bị xoá. Bạn có thể hoàn tác (Ctrl+Z).'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xoá phòng')),
                  ],
                ),
              );
              if (ok == true) d.deleteRoom();
            },
          ),
        ),
        if (s != null)
          _Section(
            'Trang ${si + 1}/${subs.length} của phòng',
            [
              FieldLabel(
                'Tên trang',
                SyncedField(
                  value: (s['title'] ?? '').toString(),
                  onChanged: (v) => d.editSub((x) => x['title'] = v, coalesce: 'st-${s['id']}'),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: FieldLabel(
                      'Số hàng',
                      EvoDropdown<int>(
                        value: rows(s),
                        items: [for (var i = devRange(d.doc)[0]; i <= devRange(d.doc)[1]; i++) (i, '$i')],
                        onChanged: (v) => d.editSub((x) => jsonMap(x['layout'])['rows'] = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FieldLabel(
                      'Số cột',
                      EvoDropdown<int>(
                        value: cols(s),
                        items: [for (var i = devRange(d.doc)[2]; i <= devRange(d.doc)[3]; i++) (i, '$i')],
                        onChanged: (v) => d.editSub((x) => Designer.repackCols(x, v)),
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  EvoButton(
                    label: 'Trang trước',
                    icon: Icons.chevron_left,
                    small: true,
                    onPressed: si > 0 ? () => d.moveInList('', s['id'] as String, -1, roomForSubs: rid) : null,
                  ),
                  EvoButton(
                    label: 'Trang sau',
                    icon: Icons.chevron_right,
                    small: true,
                    onPressed: si < subs.length - 1 ? () => d.moveInList('', s['id'] as String, 1, roomForSubs: rid) : null,
                  ),
                  EvoButton(label: 'Thêm trang trong phòng', icon: Icons.add, small: true, onPressed: d.addSub),
                ],
              ),
            ],
            trailing: subs.length > 1
                ? EvoButton(
                    label: 'Xoá trang',
                    icon: Icons.delete_outline,
                    small: true,
                    danger: true,
                    onPressed: () {
                      final m = d.deleteSub();
                      if (m != null) toast(context, m);
                    },
                  )
                : null,
          ),
        Text(
          'Kéo thành phần từ thanh công cụ vào ô trống, hoặc bấm vào một ô trống rồi bấm thành phần. Bấm vào thành phần để chỉnh tên, kích thước và địa chỉ nhóm.',
          style: TextStyle(fontSize: 12.5, color: context.evo.muted),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ floor

class _FloorProps extends StatelessWidget {
  const _FloorProps({super.key, required this.d, required this.f});
  final Designer d;
  final Json f;

  @override
  Widget build(BuildContext context) {
    final fid = f['id'] as String;
    void editFloor(void Function(Json f) fn, {String? coalesce}) => d.p.mutate((doc) {
      final x = byId(jsonList(doc['floors']), fid);
      if (x != null) fn(x);
    }, coalesce: coalesce);
    final n = roomsOf(d.doc, fid).length;
    return _Section(
      'Tầng',
      [
        FieldLabel(
          'Tên tầng',
          SyncedField(
            value: (f['title'] ?? '').toString(),
            onChanged: (v) => editFloor((x) => x['title'] = v, coalesce: 'ft-$fid'),
          ),
        ),
        FieldLabel(
          'Biểu tượng tầng',
          EvoDropdown<String>(value: (f['icon'] ?? 'stairs').toString(), items: kFloorIcons, onChanged: (v) => editFloor((x) => x['icon'] = v)),
        ),
        CheckboxListTile(
          value: f['showIcon'] != false,
          onChanged: (v) => editFloor((x) => x['showIcon'] = v ?? true),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Ẩn/hiện biểu tượng'),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            EvoButton(label: 'Thêm phòng', icon: Icons.add, small: true, onPressed: () => d.addRoom(fid)),
            EvoButton(label: 'Lên', icon: Icons.arrow_upward, small: true, onPressed: () => d.moveInList('floors', fid, -1)),
            EvoButton(label: 'Xuống', icon: Icons.arrow_downward, small: true, onPressed: () => d.moveInList('floors', fid, 1)),
          ],
        ),
        Text('Tầng này có $n phòng.', style: TextStyle(fontSize: 12.5, color: context.evo.muted)),
      ],
      trailing: EvoButton(
        label: 'Xoá tầng',
        icon: Icons.delete_outline,
        small: true,
        danger: true,
        onPressed: () {
          final m = d.deleteFloor(fid);
          if (m != null) toast(context, m);
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ overview

class _OverviewProps extends StatelessWidget {
  const _OverviewProps({required this.d});
  final Designer d;

  @override
  Widget build(BuildContext context) {
    final theme = jsonMap(d.doc['theme']);
    void editTheme(void Function(Json t) fn, {String? coalesce}) => d.p.mutate((doc) {
      final t = jsonMap(doc['theme']);
      fn(t);
      doc['theme'] = t;
    }, coalesce: coalesce);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.settings_outlined, size: 20, color: context.evo.accent),
            const SizedBox(width: 8),
            const Text('Tổng quan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 16),
        _Section('Thiết bị sử dụng', [
          for (final dv in const [('mobile', 'Mobile', '12 × 4'), ('tabletP', 'Tablet dọc', '16 × 6'), ('tabletL', 'Tablet ngang', '10 × 8')])
            _Check('${dv.$2}   (${dv.$3})', dv.$1 == 'mobile' ? jsonMap(d.doc['devices'])['mobile'] != false : jsonMap(d.doc['devices'])[dv.$1] == true, (v) {
              final devs = jsonMap(d.doc['devices']);
              final on = ['mobile', 'tabletP', 'tabletL'].where((k) => k == 'mobile' ? devs['mobile'] != false : devs[k] == true).toList();
              if (!v && on.length <= 1) {
                toast(context, 'Cần dùng ít nhất một thiết bị.');
                return;
              }
              d.p.mutate((doc) {
                final m = jsonMap(doc['devices']);
                m[dv.$1] = v;
                doc['devices'] = m;
                if (!v && doc['activeDev'] == dv.$1) {
                  swapDevice(doc, on.firstWhere((k) => k != dv.$1));
                }
              });
            }),
        ]),
        _SplashSettings(d: d),
        _Section('Giao diện App', [
          StepRow(
            label: 'Tỉ lệ hiển thị trên tablet',
            unit: '%',
            step: 5,
            value: ((theme['tabletScale'] as num?) ?? 120).toInt(),
            min: 100,
            max: 150,
            onChanged: (v) => editTheme((x) => x['tabletScale'] = v, coalesce: 'tscale'),
          ),
          for (final t in kTfs)
            StepRow(
              label: t.name,
              value: tfs(d.doc, t.key).toInt(),
              min: t.min,
              max: t.max,
              onChanged: (v) => editTheme((x) => x[t.key] = v, coalesce: 'tfs-${t.key}'),
            ),
          FieldLabel(
            'Giao diện mặc định',
            EvoDropdown<String>(
              value: (theme['mode'] ?? 'light').toString(),
              items: const [('light', 'Sáng'), ('dark', 'Tối'), ('system', 'Theo cài đặt của máy')],
              onChanged: (v) => editTheme((x) => x['mode'] = v),
            ),
          ),
          CheckboxListTile(
            value: theme['hideTitle'] == true,
            onChanged: (v) => editTheme((x) => x['hideTitle'] = v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Ẩn tiêu đề phòng (dùng thanh chọn phòng làm tiêu đề)'),
          ),
          CheckboxListTile(
            value: theme['pageArrows'] != false,
            onChanged: (v) => editTheme((x) => x['pageArrows'] = v ?? true),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Hiện nút ‹ › để chuyển trang trong phòng'),
          ),
        ]),
      ],
    );
  }
}

/// Row/column ranges per device: [minRows, maxRows, minCols, maxCols].
List<int> devRange(Json doc) => switch (doc['activeDev']) {
  'tabletP' => const [8, 24, 4, 10],
  'tabletL' => const [6, 16, 4, 12],
  _ => const [6, 18, 3, 6],
};

class _Check extends StatelessWidget {
  const _Check(this.label, this.value, this.onChanged);
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    child: Row(
      children: [
        SizedBox(
          width: 32,
          child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        ),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
      ],
    ),
  );
}

const _kSwatches = ['#EE9B2A', '#F5C542', '#FF6B4A', '#E84A8A', '#8B6BF2', '#3E8EF7', '#2BB3C0', '#1E7F57', '#8A938F', '#1B2320'];

Color? _hex(String s) {
  final t = s.replaceAll('#', '');
  final v = t.length == 6 ? int.tryParse(t, radix: 16) : null;
  return v == null ? null : Color(0xFF000000 | v);
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final h in _kSwatches)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onChanged(h),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _hex(h),
                      shape: BoxShape.circle,
                      border: Border.all(color: value.toUpperCase() == h ? c.ink : c.line, width: value.toUpperCase() == h ? 2 : 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: SyncedField(
            value: value.toUpperCase(),
            onChanged: (v) {
              final t = v.trim().startsWith('#') ? v.trim() : '#${v.trim()}';
              if (_hex(t) != null) onChanged(t.toUpperCase());
            },
          ),
        ),
      ],
    );
  }
}

class _SplashSettings extends StatelessWidget {
  const _SplashSettings({required this.d});
  final Designer d;

  void _set(String k, Object? v, {String? co}) => d.p.mutate((doc) {
    final m = jsonMap(doc['splash']);
    if (v == null) {
      m.remove(k);
    } else {
      m[k] = v;
    }
    doc['splash'] = m;
  }, coalesce: co);

  Future<void> _pickLogo(BuildContext context) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Logo PNG', extensions: ['png']),
      ],
      confirmButtonText: 'Chọn logo',
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!context.mounted) return;
    if (bytes.length > 300 * 1024) {
      toast(context, 'File nặng ${bytes.length ~/ 1024} KB, vượt quá 300 KB. Hãy nén lại rồi thử lại.');
      return;
    }
    try {
      final img = await decodeImageFromList(bytes);
      final longSide = max(img.width, img.height);
      if (!context.mounted) return;
      if (longSide < 256) {
        toast(context, 'Logo ${img.width} × ${img.height} px quá nhỏ, sẽ bị mờ. Cạnh dài cần tối thiểu 256 px (nên dùng 512 × 512 px).');
        return;
      }
      if (longSide > 2048) {
        toast(context, 'Logo ${img.width} × ${img.height} px quá lớn. Cạnh dài tối đa 2048 px.');
        return;
      }
    } catch (_) {
      if (context.mounted) toast(context, 'Không đọc được hình trong file.');
      return;
    }
    _set('logo', 'data:image/png;base64,${base64Encode(bytes)}');
    if (context.mounted) toast(context, 'Đã cập nhật logo.');
    d.previewSplash(2000);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final sp = jsonMap(d.doc['splash']);
    final logo = (sp['logo'] ?? '').toString();
    final custom = sp['greetMode'] == 'custom';
    final dur = ((sp['duration'] as num?) ?? 2).toDouble();
    return _Section('Màn hình chào', [
      _Check('Hiện màn hình chào khi mở App', sp['enabled'] != false, (v) => _set('enabled', v)),
      Row(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: _hex((sp['bg'] ?? '#1B2320').toString()) ?? const Color(0xFF1B2320),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line),
            ),
            alignment: Alignment.center,
            child: logo.startsWith('data:image/png;base64,')
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.memory(base64Decode(logo.substring(22)), fit: BoxFit.contain),
                  )
                : Text(logo.isEmpty ? 'Chưa có' : 'SVG', style: const TextStyle(color: Color(0xFF9AA59F), fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EvoButton(label: logo.isEmpty ? 'Tải logo lên' : 'Đổi logo', icon: Icons.upload_outlined, small: true, onPressed: () => _pickLogo(context)),
                if (logo.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  EvoButton(label: 'Bỏ logo', icon: Icons.delete_outline, small: true, danger: true, onPressed: () => _set('logo', null)),
                ],
              ],
            ),
          ),
        ],
      ),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(8)),
        child: Text(
          'PNG nền trong suốt. Logo vuông 512 × 512 px, logo ngang 1024 × 512 px. Dung lượng dưới 300 KB.',
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
      ),
      FieldLabel(
        'Lời chào',
        EvoDropdown<String>(
          value: custom ? 'custom' : 'auto',
          items: const [('auto', 'Tự động theo giờ (sáng / trưa / chiều / tối)'), ('custom', 'Tự đặt lời chào')],
          onChanged: (v) => _set('greetMode', v),
        ),
      ),
      if (custom)
        FieldLabel(
          'Nội dung lời chào',
          SyncedField(
            value: (sp['greet'] ?? 'Chào mừng về nhà').toString(),
            onChanged: (v) => _set('greet', v, co: 'sp-greet'),
          ),
        )
      else
        FieldLabel(
          'Tên chủ nhà (không bắt buộc)',
          SyncedField(
            value: (sp['owner'] ?? '').toString(),
            hint: 'Ví dụ: anh Nam',
            onChanged: (v) => _set('owner', v, co: 'sp-owner'),
          ),
        ),
      FieldLabel(
        'Dòng phụ (không bắt buộc)',
        SyncedField(
          value: (sp['sub'] ?? '').toString(),
          hint: 'Ví dụ: Biệt thự Ecopark',
          onChanged: (v) => _set('sub', v, co: 'sp-sub'),
        ),
      ),
      FieldLabel(
        'Màu nền',
        _ColorPicker(
          value: (sp['bg'] ?? '#1B2320').toString(),
          onChanged: (v) => _set('bg', v, co: 'sp-bg'),
        ),
      ),
      FieldLabel(
        'Thời gian hiển thị',
        EvoDropdown<double>(
          value: [1.0, 1.5, 2.0, 2.5, 3.0].contains(dur) ? dur : 2.0,
          items: const [(1.0, '1 giây'), (1.5, '1,5 giây'), (2.0, '2 giây'), (2.5, '2,5 giây'), (3.0, '3 giây')],
          onChanged: (v) => _set('duration', v),
        ),
      ),
    ], trailing: EvoButton(label: 'Xem thử', icon: Icons.play_arrow_outlined, small: true, onPressed: () => d.previewSplash((dur * 1000).round())));
  }
}
