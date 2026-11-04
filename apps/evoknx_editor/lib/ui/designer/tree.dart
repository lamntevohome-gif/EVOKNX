import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import 'designer.dart';
import 'icons.dart';
import 'model.dart';

/// Left panel: Overview + floors › rooms › pages.
class StructureTree extends StatelessWidget {
  const StructureTree({super.key, required this.d});
  final Designer d;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final doc = d.doc;
    final curRoom = d.room;
    final curSub = d.sub;
    Widget row({
      required Widget leading,
      required String text,
      String? trailing,
      required bool on,
      required VoidCallback onTap,
      double indent = 0,
      bool bold = false,
    }) => Material(
      color: on ? c.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 28,
          padding: EdgeInsets.only(left: 12 + indent, right: 12),
          child: Row(
            children: [
              SizedBox(width: 16, child: Center(child: leading)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: kUiText, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: c.ink),
                ),
              ),
              if (trailing != null) Text(trailing, style: TextStyle(fontSize: 11, color: c.muted)),
            ],
          ),
        ),
      ),
    );
    Widget link(String text, VoidCallback onTap, double indent) => InkWell(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: EdgeInsets.only(left: 12 + indent),
        child: Row(
          children: [
            SizedBox(width: 16, child: Icon(Icons.add, size: 13, color: c.muted)),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(fontSize: 11.5, color: c.muted)),
          ],
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        row(
          leading: Icon(Icons.tune, size: 14, color: c.muted),
          text: 'Tổng quan',
          on: d.view == 'overview',
          onTap: d.overview,
        ),
        const SizedBox(height: 6),
        for (final f in floorsOf(doc)) ...[
          row(
            leading: iconWidget(f['icon'] as String? ?? 'stairs', 14, c.muted),
            text: (f['title'] ?? '').toString(),
            trailing: '${roomsOf(doc, f['id'] as String?).length}',
            on: d.view == 'floor' && d.floor?['id'] == f['id'],
            bold: true,
            onTap: () => d.selectFloor(f['id'] as String),
          ),
          for (final r in roomsOf(doc, f['id'] as String?)) ...[
            row(
              indent: 16,
              leading: iconWidget(r['icon'] as String?, 14, c.muted),
              text: (r['title'] ?? '').toString(),
              trailing: '${subsOf(r).fold<int>(0, (n, s) => n + jsonList(s['widgets']).length)}',
              on: false,
              onTap: () => d.selectRoom(r['id'] as String),
            ),
            if (curRoom?['id'] == r['id'])
              for (final s in subsOf(r))
                row(
                  indent: 32,
                  leading: Icon(Icons.crop_portrait, size: 13, color: s['id'] == curSub?['id'] ? c.accent : c.muted),
                  text: (s['title'] ?? '').toString(),
                  trailing: '${jsonList(s['widgets']).length}',
                  on: d.view == 'room' && s['id'] == curSub?['id'],
                  onTap: () => d.selectSub(r['id'] as String, s['id'] as String),
                ),
            if (curRoom?['id'] == r['id']) link('Thêm trang', d.addSub, 32),
          ],
          link('Thêm phòng', () => d.addRoom(f['id'] as String), 16),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}
