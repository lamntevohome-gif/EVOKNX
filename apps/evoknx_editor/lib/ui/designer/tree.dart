import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
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
    }) => Padding(
      padding: EdgeInsets.only(left: indent, bottom: 2),
      child: Material(
        color: on ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: on ? c.accentInk : c.ink),
                  ),
                ),
                if (trailing != null) Text(trailing, style: TextStyle(fontSize: 12, color: c.muted)),
              ],
            ),
          ),
        ),
      ),
    );
    Widget link(String text, VoidCallback onTap, double indent) => Padding(
      padding: EdgeInsets.only(left: indent, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add, size: 16),
          label: Text(text, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
              child: Material(
                color: d.view == 'overview' ? c.accentSoft : c.panel,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: d.view == 'overview' ? c.accent : c.line),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: d.overview,
                  child: SizedBox(
                    height: 32,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.settings_outlined, size: 15, color: c.accent),
                        const SizedBox(width: 6),
                        Text(
                          'Tổng quan',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: d.view == 'overview' ? c.accentInk : c.ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 32,
                child: EvoButton(label: 'Thêm tầng', icon: Icons.add, small: true, onPressed: d.addFloor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final f in floorsOf(doc)) ...[
          row(
            leading: iconWidget(f['icon'] as String? ?? 'stairs', 18, c.muted),
            text: (f['title'] ?? '').toString(),
            trailing: '${roomsOf(doc, f['id'] as String?).length} phòng',
            on: d.view == 'floor' && d.floor?['id'] == f['id'],
            bold: true,
            onTap: () => d.selectFloor(f['id'] as String),
          ),
          for (final r in roomsOf(doc, f['id'] as String?)) ...[
            row(
              indent: 12,
              leading: iconWidget(r['icon'] as String?, 18, c.muted),
              text: (r['title'] ?? '').toString(),
              trailing: '${subsOf(r).fold<int>(0, (n, s) => n + jsonList(s['widgets']).length)}',
              on: d.view == 'room' && curRoom?['id'] == r['id'] && subsOf(r).length < 2,
              onTap: () => d.selectRoom(r['id'] as String),
            ),
            if (curRoom?['id'] == r['id'] && subsOf(r).length > 1)
              for (final s in subsOf(r))
                row(
                  indent: 36,
                  leading: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: s['id'] == curSub?['id'] ? c.accent : c.lineStrong, shape: BoxShape.circle),
                  ),
                  text: (s['title'] ?? '').toString(),
                  trailing: '${jsonList(s['widgets']).length}',
                  on: d.view == 'room' && s['id'] == curSub?['id'],
                  onTap: () => d.selectSub(r['id'] as String, s['id'] as String),
                ),
            if (curRoom?['id'] == r['id']) link('Thêm trang trong phòng', d.addSub, 36),
          ],
          link('Thêm phòng', () => d.addRoom(f['id'] as String), 12),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}
