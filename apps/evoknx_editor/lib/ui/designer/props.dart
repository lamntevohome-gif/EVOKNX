import 'dart:convert';
import 'dart:math';

import 'package:file_selector/file_selector.dart';

import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';
import 'icon_picker.dart';
import 'icons.dart';
import 'model.dart';
import 'parts_ui.dart';
import 'tiles.dart';

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
            FieldLabel('Biểu tượng', IconField(d: d, value: w['icon'] as String?, scope: IconScope.widget, onChanged: (v) => set('icon', v))),
          FieldLabel(
            type == 'group' ? 'Màu nền khung' : 'Màu nền thẻ',
            _BgPicker(
              value: (type == 'group' ? w['gbg'] : jsonMap(w['style'])['bg']) as String?,
              onChanged: (v) => d.editWidget(id, (x) {
                if (type == 'group') {
                  if (v == null) {
                    x.remove('gbg');
                  } else {
                    x['gbg'] = v;
                  }
                } else {
                  final m = jsonMap(x['style']);
                  if (v == null) {
                    m.remove('bg');
                  } else {
                    m['bg'] = v;
                  }
                  x['style'] = m;
                }
              }, coalesce: 'bg-$id'),
            ),
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
        final simple = w['look'] == 'simple';
        return [
          _Section('Kiểu hiển thị', [
            FieldLabel(
              'Kiểu thẻ',
              Seg<String>(
                items: const [('full', 'Đầy đủ'), ('simple', 'Đơn giản')],
                value: w['look'] == 'simple' ? 'simple' : 'full',
                onChanged: (v) => set('look', v),
              ),
            ),
            Text(
              simple
                  ? (w['type'] == 'dimmer'
                        ? 'Chỉ có biểu tượng và tên; khi bật, thẻ đổi sang màu khi bật. Bấm thẻ để bật/tắt, bấm biểu tượng chỉnh để mở thanh độ sáng${feat['tw'] == true || feat['rgb'] == true ? ', nhiệt độ màu, màu RGB' : ''}.'
                        : 'Chỉ có biểu tượng và tên; khi bật, cả thẻ đổi sang màu khi bật.')
                  : 'Biểu tượng, tên và dòng trạng thái.',
              style: TextStyle(fontSize: 12, color: context.evo.muted),
            ),
            if (simple && w['type'] == 'dimmer')
              FieldLabel(
                'Biểu tượng mở bảng chỉnh',
                IconField(d: d, value: (w['tuneIcon'] ?? 'mdi:tune-vertical').toString(), scope: IconScope.widget, onChanged: (v) => set('tuneIcon', v)),
              ),
          ]),
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
        final fan = jsonMap(ac['fan']);
        void setFan(String k, Object? v) => d.editWidget(id, (x) {
          final m = jsonMap(x['ac']);
          final f = jsonMap(m['fan']);
          f[k] = v;
          m['fan'] = f;
          x['ac'] = m;
        });
        return [
          _Section('Kiểu hiển thị', [
            FieldLabel(
              'Kiểu thẻ',
              Seg<String>(
                items: const [('full', 'Đầy đủ'), ('simple', 'Đơn giản')],
                value: w['look'] == 'simple' ? 'simple' : 'full',
                onChanged: (v) => set('look', v),
              ),
            ),
            if (w['look'] == 'simple') ...[
              Text(
                'Biểu tượng bật/tắt, nhiệt độ cài với nút − +, tốc độ quạt. Bấm biểu tượng chỉnh để mở đầy đủ chế độ.',
                style: TextStyle(fontSize: 12, color: context.evo.muted),
              ),
              FieldLabel(
                'Biểu tượng mở đầy đủ chế độ',
                IconField(d: d, value: (ac['moreIcon'] ?? 'mdi:tune-variant').toString(), scope: IconScope.widget, onChanged: (v) => setAc('moreIcon', v)),
              ),
            ],
          ]),
          _Section('Tốc độ quạt', [
            Row(
              children: [
                Checkbox(value: fan['enabled'] == true, onChanged: (v) => setFan('enabled', v == true)),
                const Expanded(child: Text('Điều khiển tốc độ quạt')),
              ],
            ),
            if (fan['enabled'] == true) ...[
              Row(
                children: [
                  Expanded(
                    child: FieldLabel(
                      'Số mức',
                      EvoDropdown<int>(
                        value: ((fan['levels'] as num?) ?? 3).toInt().clamp(2, 5),
                        items: const [(2, '2 mức'), (3, '3 mức'), (4, '4 mức'), (5, '5 mức')],
                        onChanged: (v) => setFan('levels', v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FieldLabel(
                      'Tự động',
                      Seg<bool>(items: const [(true, 'Có'), (false, 'Không')], value: fan['auto'] != false, onChanged: (v) => setFan('auto', v)),
                    ),
                  ),
                ],
              ),
              Text(
                'Giá trị gửi cho từng mức (mặc định theo DPT 5.010: Tự động = 0, mức 1…N = 1…N; nếu địa chỉ dùng phần trăm, nhập ví dụ 33, 67, 100):',
                style: TextStyle(fontSize: 12, color: context.evo.muted),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final lv in acFanLevels(ac))
                    SizedBox(
                      width: 86,
                      child: FieldLabel(
                        lv == 'auto' ? 'Tự động' : 'Mức $lv',
                        SyncedField(
                          value: '${acFanValue(ac, lv)}',
                          onChanged: (v) {
                            final n = num.tryParse(v.trim());
                            if (n == null) return;
                            d.editWidget(id, (x) {
                              final m = jsonMap(x['ac']);
                              final f = jsonMap(m['fan']);
                              final vals = jsonMap(f['values']);
                              vals[lv] = n;
                              f['values'] = vals;
                              m['fan'] = f;
                              x['ac'] = m;
                            }, coalesce: 'fanv-$id-$lv');
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ]),
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
        final sImg = w['btnStyle'] == 'image';
        final pp = jsonMap(w['popup']);
        void setPop(String k, Object? v, {String? co}) => d.editWidget(id, (x) {
          final m = jsonMap(x['popup']);
          m[k] = v;
          x['popup'] = m;
        }, coalesce: co);
        return [
          _Section('Cảnh', [
            FieldLabel(
              'Giá trị gửi',
              SyncedField(
                value: sceneSendValue(w),
                onChanged: (v) => set('sendValue', v.trim(), coalesce: 'sv-$id'),
              ),
            ),
            Text(
              'Giá trị gửi tới địa chỉ ghi khi bấm, giống nút nhấn. Với địa chỉ cảnh KNX (DPT 17.001), cảnh 1 = 0, cảnh 2 = 1…',
              style: TextStyle(fontSize: 12, color: context.evo.muted),
            ),
            FieldLabel(
              'Kiểu hiển thị',
              Seg<String>(items: const [('card', 'Thẻ thường'), ('image', 'Hình ảnh')], value: sImg ? 'image' : 'card', onChanged: (v) => set('btnStyle', v)),
            ),
          ]),
          if (sImg) _ButtonImageSettings(d: d, w: w),
          _Section('Popup khi bấm', [
            Row(
              children: [
                Checkbox(value: pp['enabled'] != false, onChanged: (v) => setPop('enabled', v == true)),
                const Expanded(child: Text('Hiện popup và làm mờ giao diện phía sau')),
              ],
            ),
            if (pp['enabled'] != false) ...[
              FieldLabel(
                'Nội dung popup ({tên} = tên cảnh)',
                SyncedField(
                  value: (pp['text'] ?? 'Đã bật cảnh {tên}').toString(),
                  onChanged: (v) => setPop('text', v, co: 'ptext-$id'),
                ),
              ),
              StepRow(
                label: 'Độ mờ nền',
                unit: '',
                value: ((pp['blur'] as num?) ?? 8).toInt(),
                min: 0,
                max: 30,
                step: 2,
                onChanged: (v) => setPop('blur', v, co: 'pblur-$id'),
              ),
              StepRow(
                label: 'Cỡ chữ',
                value: ((pp['size'] as num?) ?? 20).toInt(),
                min: 12,
                max: 40,
                onChanged: (v) => setPop('size', v, co: 'psize-$id'),
              ),
              FieldLabel(
                'Thời gian hiện',
                EvoDropdown<double>(
                  value: const [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0].contains(((pp['seconds'] as num?) ?? 2).toDouble())
                      ? ((pp['seconds'] as num?) ?? 2).toDouble()
                      : 2.0,
                  items: const [
                    (1.0, '1 giây'),
                    (1.5, '1,5 giây'),
                    (2.0, '2 giây'),
                    (2.5, '2,5 giây'),
                    (3.0, '3 giây'),
                    (4.0, '4 giây'),
                    (5.0, '5 giây (tối đa)'),
                  ],
                  onChanged: (v) => setPop('seconds', v),
                ),
              ),
              Text('Thử ở chế độ Chạy thử: bấm thẻ cảnh để xem popup. Bấm vào popup để tắt sớm.', style: TextStyle(fontSize: 12, color: context.evo.muted)),
            ],
          ]),
        ];
      case 'camera':
        final cam = jsonMap(w['cam']);
        final rtsp = cam['protocol'] != 'http';
        void setCam(String k, Object? v, {String? co}) => d.editWidget(id, (x) {
          final m = jsonMap(x['cam']);
          m[k] = v;
          x['cam'] = m;
        }, coalesce: co);
        return [
          _Section('Camera', [
            FieldLabel(
              'Giao thức',
              Seg<String>(
                items: const [('rtsp', 'RTSP'), ('http', 'HTTP')],
                value: rtsp ? 'rtsp' : 'http',
                onChanged: (v) => d.editWidget(id, (x) {
                  final m = jsonMap(x['cam']);
                  final oldDef = m['protocol'] == 'http' ? 80 : 554;
                  m['protocol'] = v;
                  if (m['port'] == null || m['port'] == oldDef) m['port'] = v == 'http' ? 80 : 554;
                  x['cam'] = m;
                }),
              ),
            ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: FieldLabel(
                    'Địa chỉ IP',
                    SyncedField(
                      value: (cam['host'] ?? '').toString(),
                      hint: '192.168.1.64',
                      onChanged: (v) => setCam('host', v.trim(), co: 'ch-$id'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'Cổng',
                    SyncedField(
                      value: '${cam['port'] ?? (rtsp ? 554 : 80)}',
                      number: true,
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null && n > 0 && n < 65536) setCam('port', n, co: 'cp-$id');
                      },
                    ),
                  ),
                ),
              ],
            ),
            FieldLabel(
              'Đường dẫn',
              SyncedField(
                value: (cam['path'] ?? '').toString(),
                hint: rtsp ? '/Streaming/Channels/101' : '/cgi-bin/snapshot.cgi',
                onChanged: (v) => setCam('path', v.trim(), co: 'cpath-$id'),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: FieldLabel(
                    'Tài khoản',
                    SyncedField(
                      value: (cam['user'] ?? '').toString(),
                      onChanged: (v) => setCam('user', v, co: 'cu-$id'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'Mật khẩu',
                    _SecretField(
                      value: (cam['pass'] ?? '').toString(),
                      onChanged: (v) => setCam('pass', v, co: 'cpw-$id'),
                    ),
                  ),
                ),
              ],
            ),
            if (cameraUrl(cam).isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: context.evo.paper, borderRadius: BorderRadius.circular(8)),
                child: SelectableText(cameraUrl(cam, hidePass: true), style: const TextStyle(fontSize: 12, fontFamily: 'Consolas')),
              ),
            Text(
              rtsp
                  ? 'Đường dẫn thường gặp: Hikvision /Streaming/Channels/101 (luồng chính) hoặc 102 (luồng phụ, nhẹ hơn); Dahua /cam/realmonitor?channel=1&subtype=1. Nên dùng luồng phụ cho điện thoại.'
                  : 'HTTP: đường dẫn ảnh chụp (snapshot) hoặc luồng MJPEG của camera. Ở Chạy thử, Editor hiện ảnh chụp để kiểm tra địa chỉ; video RTSP chỉ phát trong App.',
              style: TextStyle(fontSize: 12, color: context.evo.muted),
            ),
            Text(
              'Mật khẩu camera được lưu trong file dự án và file cấu hình App. Nên tạo tài khoản chỉ có quyền xem trên camera.',
              style: TextStyle(fontSize: 12, color: context.evo.warn),
            ),
          ]),
          _Section('Kiểu hiển thị', [
            Seg<String>(
              items: const [('live', 'Luôn hiển thị'), ('button', 'Nút mở popup')],
              value: cam['view'] == 'button' ? 'button' : 'live',
              onChanged: (v) => setCam('view', v),
            ),
            Text(
              cam['view'] == 'button'
                  ? 'Thẻ như một nút bấm; bấm vào sẽ mở video camera trong popup.'
                  : 'Video phát trực tiếp ngay trong thẻ, như trang web nhúng. Nên đặt thẻ rộng 4 cột, cao 3 hàng trở lên.',
              style: TextStyle(fontSize: 12, color: context.evo.muted),
            ),
            if (cam['view'] != 'button')
              Row(
                children: [
                  Checkbox(value: w['showHeader'] != false, onChanged: (v) => set('showHeader', v == true)),
                  const Expanded(child: Text('Hiện tên camera phía trên video')),
                ],
              ),
          ]),
        ];
      case 'button':
        final imgStyle = w['btnStyle'] == 'image';
        return [
          _Section('Nút nhấn', [
            FieldLabel(
              'Giá trị gửi',
              SyncedField(
                value: (w['sendValue'] ?? '1').toString(),
                onChanged: (v) => set('sendValue', v.trim(), coalesce: 'sv-$id'),
              ),
            ),
            FieldLabel(
              'Kiểu hiển thị',
              Seg<String>(
                items: const [('card', 'Thẻ thường'), ('image', 'Hình ảnh')],
                value: imgStyle ? 'image' : 'card',
                onChanged: (v) => set('btnStyle', v),
              ),
            ),
          ]),
          if (imgStyle) _ButtonImageSettings(d: d, w: w),
        ];
      case 'value':
        final f = jsonMap(w['format']);
        return [
          _Section('Hiển thị giá trị', [
            FieldLabel(
              'Kiểu thẻ',
              Seg<String>(
                items: const [('full', 'Đầy đủ'), ('simple', 'Đơn giản')],
                value: w['look'] == 'simple' ? 'simple' : 'full',
                onChanged: (v) => set('look', v),
              ),
            ),
            if (w['look'] == 'simple')
              Text('Một hàng: biểu tượng và tên bên trái, giá trị bên phải. Hợp với thẻ cao 1 ô.', style: TextStyle(fontSize: 12, color: context.evo.muted)),
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
              IconField(d: d, value: (r['icon'] ?? 'sofa').toString(), scope: IconScope.room, onChanged: (v) => editRoom((x) => x['icon'] = v)),
            ),
            Row(
              children: [
                EvoButton(label: 'Lên', icon: Icons.arrow_upward, small: true, onPressed: () => d.moveRoom(rid, -1)),
                const SizedBox(width: 6),
                EvoButton(label: 'Xuống', icon: Icons.arrow_downward, small: true, onPressed: () => d.moveRoom(rid, 1)),
              ],
            ),
            PartButtons(d: d, kind: 'room', id: rid, importHint: 'Nhập trang vào phòng này…'),
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
              if (kEnablePageScroll && (d.doc['activeDev'] ?? 'mobile') == 'mobile') ...[
                Row(
                  children: [
                    Checkbox(
                      value: s['scroll'] == true,
                      onChanged: (v) => d.editSub((x) {
                        x['scroll'] = v == true;
                        if (v == true && x['scrollRows'] == null) x['scrollRows'] = rows(x) * 2;
                      }),
                    ),
                    const Expanded(child: Text('Cho phép cuộn dọc khi nội dung dài hơn màn hình (chỉ điện thoại)')),
                  ],
                ),
                if (s['scroll'] == true) ...[
                  FieldLabel(
                    'Tổng số hàng của trang (màn hình hiện ${rows(s)} hàng)',
                    EvoDropdown<int>(
                      value: pageRows(s, d.doc).clamp(rows(s) + 1, 60),
                      items: [for (var i = rows(s) + 1; i <= 60; i++) (i, '$i hàng')],
                      onChanged: (v) => d.editSub((x) => x['scrollRows'] = v),
                    ),
                  ),
                  Text(
                    'Người dùng cuộn lên xuống trong trang này, vẫn vuốt ngang để sang trang khác. Thẻ có thanh kéo ngang (đèn dim, rèm) dùng bình thường; tránh đặt thanh kéo dọc. Bố cục tablet luôn cố định.',
                    style: TextStyle(fontSize: 12, color: context.evo.muted),
                  ),
                ],
              ],
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
              PartButtons(d: d, kind: 'page', id: s['id'] as String, importHint: 'Nhập trang…'),
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
          IconField(d: d, value: (f['icon'] ?? 'stairs').toString(), scope: IconScope.floor, onChanged: (v) => editFloor((x) => x['icon'] = v)),
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
        PartButtons(d: d, kind: 'floor', id: fid, importHint: 'Nhập phòng vào tầng này…'),
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
        _Section('Nhập tầng / phòng / trang', [
          Text(
            'Nhập từ file .evoknxpart (xuất từ dự án khác ở bảng thuộc tính của tầng, phòng hoặc trang). '
            'Tầng được thêm vào cuối, phòng vào tầng đang chọn, trang vào phòng đang chọn.',
            style: TextStyle(fontSize: 12.5, color: context.evo.muted),
          ),
          PartButtons(d: d, kind: null, importHint: 'Nhập từ file…'),
        ]),
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
        _ScreenBgSettings(d: d),
        _Section('Kiểu thẻ (tất cả thẻ)', [
          StepRow(
            label: 'Độ cong góc',
            value: ((theme['cardRadius'] as num?) ?? 12).toInt(),
            min: 0,
            max: 32,
            onChanged: (v) => editTheme((x) => x['cardRadius'] = v, coalesce: 'crad'),
          ),
          StepRow(
            label: 'Độ dày viền',
            value: ((theme['cardBorder'] as num?) ?? 1).toInt(),
            min: 0,
            max: 4,
            onChanged: (v) => editTheme((x) => x['cardBorder'] = v, coalesce: 'cbor'),
          ),
          StepRow(
            label: 'Đổ bóng',
            unit: '',
            value: ((theme['cardShadow'] as num?) ?? 0).toInt(),
            min: 0,
            max: 20,
            onChanged: (v) => editTheme((x) => x['cardShadow'] = v, coalesce: 'cshd'),
          ),
          Text('Mặc định: góc 12, viền 1, không đổ bóng. Áp dụng cho mọi thẻ và khung lưới.', style: TextStyle(fontSize: 12, color: context.evo.muted)),
        ]),
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
              value: const ['light', 'dark', 'graphite', 'sand'].contains(theme['mode']) ? theme['mode'] as String : 'light',
              items: const [('light', 'Sáng'), ('dark', 'Tối'), ('graphite', 'Xám than'), ('sand', 'Kem')],
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
  const _ColorPicker({required this.value, required this.onChanged, this.swatches = _kSwatches});
  final String value;
  final ValueChanged<String> onChanged;
  final List<String> swatches;
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
              for (final h in swatches)
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

const _kBgSwatches = ['#FFFFFF', '#F3F4F6', '#E3F1E9', '#FDF1DC', '#E6EEF9', '#FBE9E5', '#2A3035', '#1B2320', '#0F1A2B', '#3A2D17'];

/// "Mặc định" + colour swatches for card / frame backgrounds (null = default).
class _BgPicker extends StatelessWidget {
  const _BgPicker({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final transparent = value == 'transparent';
    final isDefault = !transparent && (value == null || _hex(value!) == null);
    Widget chip(String text, bool on, VoidCallback tap) => Material(
      color: on ? c.accentSoft : c.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: on ? c.accent : c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? c.accentInk : c.ink),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            chip('Mặc định', isDefault, () => onChanged(null)),
            const SizedBox(width: 6),
            chip('Trong suốt', transparent, () => onChanged('transparent')),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                transparent ? 'Chỉ còn viền, thấy nền giao diện phía sau' : (isDefault ? 'Theo giao diện Sáng/Tối của App' : 'Chữ tự đổi sáng/tối cho dễ đọc'),
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ColorPicker(value: isDefault || transparent ? '' : value!, swatches: _kBgSwatches, onChanged: onChanged),
      ],
    );
  }
}

/// Overview → "Nền giao diện": default, colour, or an uploaded image.
class _ScreenBgSettings extends StatelessWidget {
  const _ScreenBgSettings({required this.d});
  final Designer d;

  void _set(Map<String, Object?> kv, {String? co}) => d.p.mutate((doc) {
    final t = jsonMap(doc['theme']);
    kv.forEach((k, v) {
      if (v == null) {
        t.remove(k);
      } else {
        t[k] = v;
      }
    });
    doc['theme'] = t;
  }, coalesce: co);

  Future<void> _pick(BuildContext context) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Ảnh nền (JPG, PNG)', extensions: ['jpg', 'jpeg', 'png']),
      ],
      confirmButtonText: 'Chọn ảnh',
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!context.mounted) return;
    if (bytes.length > 2 * 1024 * 1024) {
      toast(context, 'Ảnh nặng ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB, vượt quá 2 MB. Hãy nén lại (ví dụ xuất JPG chất lượng 80%).');
      return;
    }
    try {
      final img = await decodeImageFromList(bytes);
      if (!context.mounted) return;
      if (min(img.width, img.height) < 600) {
        toast(context, 'Ảnh ${img.width} × ${img.height} px quá nhỏ, sẽ bị vỡ hình. Nên dùng 1290 × 2796 px.');
        return;
      }
    } catch (_) {
      if (context.mounted) toast(context, 'Không đọc được ảnh.');
      return;
    }
    final png = f.name.toLowerCase().endsWith('.png');
    _set({'bgMode': 'image', 'bgImage': 'data:image/${png ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}'});
    if (context.mounted) toast(context, 'Đã đặt ảnh nền.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final t = jsonMap(d.doc['theme']);
    final mode = (t['bgMode'] ?? 'default').toString();
    final img = (t['bgImage'] ?? '').toString();
    final i = img.indexOf('base64,');
    return _Section('Nền giao diện', [
      Seg<String>(
        items: const [('default', 'Mặc định'), ('color', 'Màu'), ('image', 'Hình ảnh')],
        value: mode,
        onChanged: (v) => _set({'bgMode': v, if (v == 'color' && t['bgColor'] == null) 'bgColor': '#E3F1E9'}),
      ),
      if (mode == 'default') Text('Dùng màu nền theo giao diện Sáng/Tối của App.', style: TextStyle(fontSize: 12.5, color: c.muted)),
      if (mode == 'color')
        _ColorPicker(
          value: (t['bgColor'] ?? '#E3F1E9').toString(),
          swatches: _kBgSwatches,
          onChanged: (v) => _set({'bgColor': v}, co: 'bgc'),
        ),
      if (mode == 'image') ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 128,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.paper,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.line),
              ),
              child: i > 0
                  ? Image.memory(base64Decode(img.substring(i + 7)), fit: BoxFit.cover, gaplessPlayback: true)
                  : Center(
                      child: Text('Chưa có', style: TextStyle(fontSize: 12, color: c.muted)),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EvoButton(label: i > 0 ? 'Đổi ảnh' : 'Tải ảnh lên', icon: Icons.image_outlined, small: true, onPressed: () => _pick(context)),
                  if (i > 0) ...[
                    const SizedBox(height: 6),
                    EvoButton(
                      label: 'Bỏ ảnh',
                      icon: Icons.delete_outline,
                      small: true,
                      danger: true,
                      onPressed: () => _set({'bgImage': null, 'bgMode': 'default'}),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'JPG hoặc PNG, ảnh dọc theo màn hình điện thoại, nên dùng 1290 × 2796 px, dưới 2 MB. Ảnh tự cắt vừa cả mobile và tablet.',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        StepRow(
          label: 'Làm tối ảnh (giúp chữ dễ đọc)',
          unit: '%',
          step: 10,
          value: ((t['bgDim'] as num?) ?? 30).toInt(),
          min: 0,
          max: 80,
          onChanged: (v) => _set({'bgDim': v}, co: 'bgdim'),
        ),
      ],
      if (mode != 'default')
        FieldLabel(
          'Màu chữ trên nền (tiêu đề, tên trang)',
          EvoDropdown<String>(
            value: (t['bgText'] ?? 'auto').toString(),
            items: const [('auto', 'Tự động theo nền'), ('dark', 'Chữ đậm'), ('light', 'Chữ trắng')],
            onChanged: (v) => _set({'bgText': v}),
          ),
        ),
    ]);
  }
}

/// Button "Hình ảnh" style: picture, its size, label on/off.
class _ButtonImageSettings extends StatelessWidget {
  const _ButtonImageSettings({required this.d, required this.w});
  final Designer d;
  final Json w;

  String get id => w['id'] as String;

  Future<void> _pick(BuildContext context) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Hình ảnh (PNG, JPG, SVG)', extensions: ['png', 'jpg', 'jpeg', 'svg']),
      ],
      confirmButtonText: 'Chọn ảnh',
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!context.mounted) return;
    if (bytes.length > 500 * 1024) {
      toast(context, 'Ảnh nặng ${bytes.length ~/ 1024} KB, vượt quá 500 KB. Nên dùng PNG nền trong suốt khoảng 512 × 512 px.');
      return;
    }
    final name = f.name.toLowerCase();
    String mime;
    if (name.endsWith('.svg')) {
      if (!utf8.decode(bytes, allowMalformed: true).contains('<svg')) {
        toast(context, 'File SVG không hợp lệ.');
        return;
      }
      mime = 'svg+xml';
    } else {
      try {
        final img = await decodeImageFromList(bytes);
        if (!context.mounted) return;
        if (max(img.width, img.height) < 64) {
          toast(context, 'Ảnh ${img.width} × ${img.height} px quá nhỏ, sẽ bị mờ. Nên dùng khoảng 512 × 512 px.');
          return;
        }
      } catch (_) {
        if (context.mounted) toast(context, 'Không đọc được ảnh.');
        return;
      }
      mime = name.endsWith('.png') ? 'png' : 'jpeg';
    }
    d.editWidget(id, (x) => x['image'] = 'data:image/$mime;base64,${base64Encode(bytes)}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final img = imageFromData((w['image'] ?? '').toString(), fit: BoxFit.contain);
    final useIcon = w['imgSource'] == 'icon';
    final iconColor = w['imgColor'] as String?;
    return _Section('Hình ảnh', [
      Seg<String>(
        items: const [('image', 'Ảnh tải lên'), ('icon', 'Biểu tượng (MDI…)')],
        value: useIcon ? 'icon' : 'image',
        onChanged: (v) => d.editWidget(id, (x) => x['imgSource'] = v),
      ),
      if (useIcon) ...[
        IconField(
          d: d,
          value: (w['imgIcon'] ?? 'mdi:gesture-tap-button').toString(),
          scope: IconScope.widget,
          onChanged: (v) => d.editWidget(id, (x) => x['imgIcon'] = v),
        ),
        FieldLabel(
          'Màu biểu tượng',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ChoiceChip(label: const Text('Mặc định'), selected: iconColor == null, onSelected: (_) => d.editWidget(id, (x) => x.remove('imgColor'))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Mặc định: theo màu chữ của thẻ', style: TextStyle(fontSize: 12, color: c.muted)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ColorPicker(
                value: iconColor ?? '',
                onChanged: (v) => d.editWidget(id, (x) => x['imgColor'] = v, coalesce: 'imgc-$id'),
              ),
            ],
          ),
        ),
      ],
      if (!useIcon)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: c.paper,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.line),
              ),
              child: img ?? Center(child: Icon(Icons.image_outlined, color: c.muted)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EvoButton(label: img == null ? 'Chọn ảnh' : 'Đổi ảnh', icon: Icons.image_outlined, small: true, onPressed: () => _pick(context)),
                  if (img != null) ...[
                    const SizedBox(height: 6),
                    EvoButton(
                      label: 'Bỏ ảnh',
                      icon: Icons.delete_outline,
                      small: true,
                      danger: true,
                      onPressed: () => d.editWidget(id, (x) => x.remove('image')),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'PNG nền trong suốt, JPG hoặc SVG; nên dùng ảnh vuông khoảng 512 × 512 px, dưới 500 KB.',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      StepRow(
        label: useIcon ? 'Kích thước biểu tượng' : 'Kích thước ảnh',
        unit: '%',
        step: 5,
        value: ((w['imageSize'] as num?) ?? 70).toInt(),
        min: 20,
        max: 100,
        onChanged: (v) => d.editWidget(id, (x) => x['imageSize'] = v, coalesce: 'imgsize-$id'),
      ),
      FieldLabel(
        'Chữ trên nút',
        Seg<bool>(
          items: const [(true, 'Có chữ'), (false, 'Không chữ')],
          value: w['showLabel'] != false,
          onChanged: (v) => d.editWidget(id, (x) => x['showLabel'] = v),
        ),
      ),
    ]);
  }
}

/// Password field with a show/hide eye.
class _SecretField extends StatefulWidget {
  const _SecretField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  bool _show = false;

  @override
  void didUpdateWidget(covariant _SecretField old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text && !FocusScope.of(context).hasFocus) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    obscureText: !_show,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      isDense: true,
      suffixIcon: IconButton(
        tooltip: _show ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
        onPressed: () => setState(() => _show = !_show),
      ),
    ),
  );
}
