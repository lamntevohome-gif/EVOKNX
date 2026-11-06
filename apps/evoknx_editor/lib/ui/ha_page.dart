import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// The "Mở rộng" workspace: the project's Home Assistant connection and, in
/// rooms (tabs), the entities wired to virtual addresses. Cards use those
/// addresses like any other; the App sends them to Home Assistant instead of
/// the KNX bus.
class HaPage extends StatefulWidget {
  const HaPage({super.key, required this.project});
  final ProjectController project;

  @override
  State<HaPage> createState() => _HaPageState();
}

/// Id of the tab that holds addresses made before rooms existed.
const String _kNoRoom = '__none__';

class _HaPageState extends State<HaPage> {
  List<HaEntity>? entities;
  String? status;
  bool statusOk = false;
  bool busy = false;
  String? roomId;

  ProjectController get p => widget.project;

  void _setHa(String key, Object? v, {String? coalesce}) {
    p.mutate((d) {
      final h = Map<String, dynamic>.from(haSettings(d));
      h[key] = v;
      d['ha'] = h;
    }, coalesce: coalesce ?? 'ha-$key');
  }

  Future<bool> _fetch() async {
    final h = haSettings(p.doc);
    final url = (h['url'] ?? '').toString().trim(), token = (h['token'] ?? '').toString().trim();
    if (url.isEmpty || token.isEmpty) {
      setState(() {
        status = 'Nhập địa chỉ và token trước.';
        statusOk = false;
      });
      return false;
    }
    setState(() {
      busy = true;
      status = 'Đang kết nối…';
      statusOk = false;
    });
    try {
      final r = await haFetchEntities(url, token);
      if (!mounted) return false;
      setState(() {
        entities = r.entities;
        status = 'Đã kết nối · Home Assistant ${r.version ?? ''} · ${r.entities.length} thực thể';
        statusOk = true;
        busy = false;
      });
      return true;
    } on HaException catch (e) {
      if (mounted) {
        setState(() {
          status = e.message;
          statusOk = false;
          busy = false;
        });
      }
      return false;
    }
  }

  // ------------------------------------------------------------ rooms

  Future<void> _newRoom() async {
    final r = await _roomDialog(context, doc: p.doc, title: 'Phòng mới');
    if (r == null) return;
    late Json room;
    p.mutate((d) => room = addHaRoom(d, r.name, r.main));
    setState(() => roomId = room['id'] as String);
  }

  Future<void> _renameRoom(Json room) async {
    final r = await _roomDialog(
      context,
      doc: p.doc,
      title: 'Sửa tên phòng',
      name: room['name'].toString(),
      main: (room['main'] as num).toInt(),
      editMain: false,
      exceptRoom: room['id'] as String,
    );
    if (r != null) p.mutate((d) => renameHaRoom(d, room['id'] as String, r.name));
  }

  Future<void> _moveRoom(Json room) async {
    final r = await _roomDialog(
      context,
      doc: p.doc,
      title: 'Sửa nhóm chính của phòng',
      name: room['name'].toString(),
      main: (room['main'] as num).toInt(),
      editName: false,
      exceptRoom: room['id'] as String,
    );
    if (r == null) return;
    String? err;
    p.mutate((d) => err = moveHaRoom(d, room['id'] as String, r.main));
    if (err != null && mounted) toast(context, err!);
  }

  Future<void> _deleteRoom(Json room) async {
    final id = room['id'] as String;
    final ents = {
      for (final g in haAddresses(p.doc))
        if (g['ha']['room'] == id) (g['ha']['entity'] ?? '').toString(),
    };
    final uses = ents.fold<int>(0, (n, e) => n + haEntityUses(p.doc, e));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Xoá phòng “${room['name']}”?'),
        content: Text(
          '${ents.isEmpty ? 'Phòng chưa có thực thể nào.' : 'Xoá luôn ${ents.length} thực thể và các địa chỉ ảo của chúng.'}'
          '${uses > 0 ? ' Có $uses ô địa chỉ của thẻ đang dùng, chúng sẽ bị gỡ liên kết.' : ''} Có thể hoàn tác (Ctrl+Z).',
        ),
        actions: [
          EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Xoá phòng', danger: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true) return;
    p.mutate((d) => removeHaRoom(d, id));
    setState(() => roomId = null);
  }

  Future<void> _roomMenu(Offset at, Json room) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final c = context.evo;
    final v = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem(value: 0, height: 34, child: Text('Sửa tên')),
        const PopupMenuItem(value: 1, height: 34, child: Text('Sửa nhóm chính (địa chỉ)')),
        const PopupMenuDivider(height: 9),
        PopupMenuItem(
          value: 2,
          height: 34,
          child: Text('Xoá phòng', style: TextStyle(color: c.danger)),
        ),
      ],
    );
    switch (v) {
      case 0:
        await _renameRoom(room);
      case 1:
        await _moveRoom(room);
      case 2:
        await _deleteRoom(room);
    }
  }

  // ------------------------------------------------------------ entities

  Future<void> _add() async {
    if (haRooms(p.doc).isEmpty) {
      await _newRoom();
      if (haRooms(p.doc).isEmpty) return;
    }
    if (entities == null && !await _fetch()) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _AddEntityDialog(project: p, entities: entities!, initialRoom: _current(haRooms(p.doc))?['id'] as String?),
    );
  }

  Future<void> _renameEntity(String entityId, String title) async {
    final t = await _prompt(context, 'Đổi tên thực thể', 'Tên hiển thị (mã thực thể Home Assistant giữ nguyên: $entityId)', title);
    if (t != null && t.trim().isNotEmpty) p.mutate((d) => renameHaEntity(d, entityId, t));
  }

  Future<void> _removeEntity(String entityId, String title) async {
    final uses = haEntityUses(p.doc, entityId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Gỡ “$title”?'),
        content: Text(
          uses > 0
              ? 'Có $uses ô địa chỉ của thẻ đang dùng thực thể này; chúng sẽ bị gỡ liên kết. Có thể hoàn tác (Ctrl+Z).'
              : 'Các địa chỉ ảo của thực thể này sẽ bị xoá. Có thể hoàn tác (Ctrl+Z).',
        ),
        actions: [
          EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Gỡ', danger: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok == true) p.mutate((d) => removeHaEntity(d, entityId));
  }

  Json? _current(List<Json> rooms) {
    for (final r in rooms) {
      if (r['id'] == roomId) return r;
    }
    return rooms.isEmpty ? null : rooms.first;
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final h = haSettings(p.doc);
        final rooms = haRooms(p.doc);
        final orphans = [
          for (final g in haAddresses(p.doc))
            if (g['ha']['room'] == null || haRoomById(p.doc, g['ha']['room'] as String?) == null) g,
        ];
        final cur = roomId == _kNoRoom && orphans.isNotEmpty ? null : _current(rooms);
        final showOrphans = orphans.isNotEmpty && (roomId == _kNoRoom || cur == null);
        return LayoutBuilder(
          builder: (context, bc) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: sidePanelWidth(bc.maxWidth),
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border(right: BorderSide(color: c.line)),
                ),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Home Assistant',
                      style: TextStyle(fontSize: kUiText + 2, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(value: h['enabled'] == true, onChanged: (v) => _setHa('enabled', v == true)),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Dùng Home Assistant trong dự án này')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FieldLabel(
                      'Địa chỉ',
                      SyncedField(
                        value: (h['url'] ?? '').toString(),
                        hint: 'vd 192.168.1.5:8123 hoặc https://xxx.ui.nabu.casa',
                        onChanged: (v) => _setHa('url', v.trim()),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FieldLabel(
                      'Token (Long-lived access token)',
                      _TokenField(value: (h['token'] ?? '').toString(), onChanged: (v) => _setHa('token', v.trim())),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        EvoButton(label: 'Thử kết nối', primary: true, onPressed: busy ? null : _fetch),
                        const SizedBox(width: 8),
                        EvoButton(label: 'Thêm thực thể…', icon: Icons.add, onPressed: busy ? null : _add),
                      ],
                    ),
                    if (status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(statusOk ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: statusOk ? const Color(0xFF14AE5C) : c.warn),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(status!, style: TextStyle(color: statusOk ? c.ink : c.warn)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _tabs(c, rooms, cur, orphans.isNotEmpty, showOrphans),
                    Divider(height: 1, color: c.line),
                    Expanded(child: _body(c, rooms, cur, showOrphans ? orphans : null)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tabs(EvoColors c, List<Json> rooms, Json? cur, bool hasOrphans, bool orphansOn) {
    Widget tab(String label, String? sub, bool on, VoidCallback onTap, {void Function(Offset at)? onMenu}) => InkWell(
      onTap: onTap,
      onSecondaryTapDown: onMenu == null ? null : (e) => onMenu(e.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: on ? c.accent : Colors.transparent, width: 2)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? c.ink : c.muted),
            ),
            if (sub != null) ...[
              const SizedBox(width: 6),
              Text(
                sub,
                style: TextStyle(fontSize: kUiText - 2, color: c.muted),
              ),
            ],
          ],
        ),
      ),
    );
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final r in rooms)
                  tab(
                    r['name'].toString(),
                    '${r['main']}',
                    !orphansOn && r['id'] == cur?['id'],
                    () => setState(() => roomId = r['id'] as String),
                    onMenu: (at) => _roomMenu(at, r),
                  ),
                if (hasOrphans) tab('Chưa phân phòng', null, orphansOn, () => setState(() => roomId = _kNoRoom)),
              ],
            ),
          ),
          Tooltip(
            message: 'Thêm phòng',
            child: IconButton(icon: const Icon(Icons.add), onPressed: _newRoom),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _body(EvoColors c, List<Json> rooms, Json? cur, List<Json>? orphans) {
    List<Json> gas;
    if (orphans != null) {
      gas = orphans;
    } else if (cur == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Chưa có phòng nào. Bấm + để tạo phòng, rồi “Thêm thực thể…” để chọn đèn, công tắc, rèm, máy lạnh… từ Home Assistant.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted),
          ),
        ),
      );
    } else {
      gas = [
        for (final g in haAddresses(p.doc))
          if (g['ha']['room'] == cur['id']) g,
      ];
    }
    final byEntity = <String, List<Json>>{};
    for (final g in gas) {
      (byEntity[(g['ha']['entity'] ?? '').toString()] ??= []).add(g);
    }
    final order = byEntity.keys.toList()
      ..sort((a, b) => ((byEntity[a]!.first['ha']['n'] as num?) ?? 0).compareTo((byEntity[b]!.first['ha']['n'] as num?) ?? 0));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            cur == null ? 'Địa chỉ chưa thuộc phòng nào' : 'Phòng ${cur['name']} · nhóm chính ${cur['main']} · ${byEntity.length} thực thể',
            style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
          ),
        ),
        if (byEntity.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Chưa có thực thể trong phòng này. Bấm “Thêm thực thể…”.', style: TextStyle(color: c.muted)),
          ),
        for (final e in order) _entityCard(c, e, byEntity[e]!),
      ],
    );
  }

  Widget _entityCard(EvoColors c, String entityId, List<Json> gas) {
    final title = (gas.first['ha']['title'] ?? (gas.first['name'] ?? entityId).toString().split(' · ').first).toString();
    // One row per function: its command and status address.
    final byAttr = <String, Map<String, Json>>{};
    for (final g in gas) {
      final h = g['ha'] as Map;
      (byAttr[(h['attr'] ?? '').toString()] ??= {})[(h['role'] ?? '').toString()] = g;
    }
    final keys = byAttr.keys.toList()..sort((a, b) => kHaAttrs.indexWhere((x) => x.key == a).compareTo(kHaAttrs.indexWhere((x) => x.key == b)));
    Widget addr(Json? g, String label) => g == null
        ? SizedBox(
            width: 210,
            child: Text('$label  —', style: TextStyle(color: c.muted)),
          )
        : SizedBox(
            width: 210,
            child: Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(label, style: TextStyle(color: c.muted)),
                ),
                _AddrField(
                  value: g['address'].toString(),
                  onCommit: (t) {
                    final err = haValidateAddress(p.doc, t, exceptId: g['id'] as String);
                    if (err != null) return err;
                    p.mutate((d) => haSetAddress(d, g['id'] as String, t));
                    return null;
                  },
                ),
              ],
            ),
          );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                  ),
                ),
                IconButton(
                  tooltip: 'Đổi tên thực thể',
                  icon: Icon(Icons.edit_outlined, size: 16, color: c.muted),
                  onPressed: () => _renameEntity(entityId, title),
                ),
                Expanded(
                  child: Text(
                    entityId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: kUiText - 1, color: c.muted),
                  ),
                ),
                IconButton(
                  tooltip: 'Gỡ thực thể này',
                  icon: Icon(Icons.delete_outline, color: c.danger),
                  onPressed: () => _removeEntity(entityId, title),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          for (final k in keys)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(haAttr(k)?.label ?? k, style: TextStyle(color: c.ink)),
                  ),
                  addr(byAttr[k]!['cmd'], 'Lệnh'),
                  addr(byAttr[k]!['status'], 'Trạng thái'),
                  Text('DPT ${(byAttr[k]!.values.first['dpt'] ?? '').toString()}', style: TextStyle(color: c.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// An address box: the new value is checked and applied when Enter is pressed
/// or the box loses focus; a wrong value is refused with a message.
class _AddrField extends StatefulWidget {
  const _AddrField({required this.value, required this.onCommit});
  final String value;

  /// Returns an error text (the old value is put back) or null when applied.
  final String? Function(String text) onCommit;

  @override
  State<_AddrField> createState() => _AddrFieldState();
}

class _AddrFieldState extends State<_AddrField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (!_f.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _AddrField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  void _commit() {
    final t = _c.text.trim();
    if (t == widget.value) return;
    final err = widget.onCommit(t);
    if (err != null) {
      if (mounted) toast(context, err);
      _c.text = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: TextField(
        controller: _c,
        focusNode: _f,
        onSubmitted: (_) => _commit(),
        style: const TextStyle(fontSize: kUiText),
      ),
    );
  }
}

/// A password-style box for the token (with a show / hide button).
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
          tooltip: hide ? 'Hiện token' : 'Ẩn token',
          icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
          onPressed: () => setState(() => hide = !hide),
        ),
      ),
    );
  }
}

/// A one-line text box in a dialog; null when cancelled.
Future<String?> _prompt(BuildContext context, String title, String hint, String initial) async {
  final ctl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hint,
              style: TextStyle(fontSize: kUiText - 1, color: context.evo.muted),
            ),
            const SizedBox(height: 10),
            TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(c, v)),
          ],
        ),
      ),
      actions: [
        EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(c)),
        EvoButton(label: 'Lưu', primary: true, onPressed: () => Navigator.pop(c, ctl.text)),
      ],
    ),
  );
  ctl.dispose();
  return r;
}

/// Name and main group of a room. The main group must be above 31 and free.
Future<({String name, int main})?> _roomDialog(
  BuildContext context, {
  required Json doc,
  required String title,
  String name = '',
  int? main,
  bool editName = true,
  bool editMain = true,
  String? exceptRoom,
}) {
  final nameCtl = TextEditingController(text: name);
  final mainCtl = TextEditingController(text: '${main ?? haNextMain(doc)}');
  return showDialog<({String name, int main})>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) {
        final m = int.tryParse(mainCtl.text.trim());
        final err = !editMain ? null : (m == null ? 'Nhập số, ví dụ ${haNextMain(doc)}.' : haValidateMain(doc, m, exceptRoom: exceptRoom));
        final nameOk = !editName || nameCtl.text.trim().isNotEmpty;
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (editName) FieldLabel('Tên phòng', TextField(controller: nameCtl, autofocus: true, onChanged: (_) => setS(() {}))),
                if (editName && editMain) const SizedBox(height: 12),
                if (editMain) ...[
                  FieldLabel(
                    'Nhóm chính (lớn hơn 31)',
                    TextField(controller: mainCtl, autofocus: !editName, keyboardType: TextInputType.number, onChanged: (_) => setS(() {})),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      err ?? 'Địa chỉ trong phòng có dạng ${m ?? '…'}/nhóm giữa/nhóm phụ.',
                      style: TextStyle(fontSize: kUiText - 1, color: err != null ? c.evo.warn : c.evo.muted),
                    ),
                  ),
                  if (!editName)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Mọi địa chỉ của phòng sẽ đổi theo nhóm chính mới.',
                        style: TextStyle(fontSize: kUiText - 1, color: c.evo.muted),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            EvoButton(label: 'Huỷ', onPressed: () => Navigator.pop(c)),
            EvoButton(
              label: 'Lưu',
              primary: true,
              onPressed: err != null || !nameOk ? null : () => Navigator.pop(c, (name: nameCtl.text.trim(), main: editMain ? m! : (main ?? 0))),
            ),
          ],
        );
      },
    ),
  ).whenComplete(() {
    nameCtl.dispose();
    mainCtl.dispose();
  });
}

/// Picks entities of Home Assistant, the room and the functions to use.
class _AddEntityDialog extends StatefulWidget {
  const _AddEntityDialog({required this.project, required this.entities, this.initialRoom});
  final ProjectController project;
  final List<HaEntity> entities;
  final String? initialRoom;

  @override
  State<_AddEntityDialog> createState() => _AddEntityDialogState();
}

class _AddEntityDialogState extends State<_AddEntityDialog> {
  String q = '';
  String domain = '';
  HaEntity? sel;
  final Set<String> keys = {};
  int added = 0;
  late String room = widget.initialRoom ?? (haRooms(widget.project.doc).firstOrNull?['id'] as String? ?? '');

  List<HaEntity> get usable => [
    for (final e in widget.entities)
      if (haSuggest(e).isNotEmpty) e,
  ];

  String _fold(String s) => s.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final doc = widget.project.doc;
    final rooms = haRooms(doc);
    final mappedIds = {for (final g in haAddresses(doc)) (g['ha']['entity'] ?? '').toString()};
    final domains = {for (final e in usable) e.domain}.toList()..sort();
    final list = [
      for (final e in usable)
        if ((domain.isEmpty || e.domain == domain) && (q.isEmpty || _fold('${e.name} ${e.id}').contains(_fold(q)))) e,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    // An entity already in the project stays in its room.
    final fixedRoom = sel == null ? null : haEntityRoom(doc, sel!.id);
    final effectiveRoom = fixedRoom ?? room;
    return AlertDialog(
      title: const Text('Thêm thực thể từ Home Assistant'),
      content: SizedBox(
        width: 740,
        height: 480,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchField(hint: 'Tìm theo tên hoặc mã thực thể', width: double.infinity, onChanged: (v) => setState(() => q = v)),
                  const SizedBox(height: 8),
                  EvoDropdown<String>(
                    value: domain,
                    items: [('', 'Tất cả loại (${usable.length})'), for (final d in domains) (d, d)],
                    onChanged: (v) => setState(() => domain = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final e = list[i];
                        final on = sel?.id == e.id;
                        return InkWell(
                          onTap: () => setState(() {
                            sel = e;
                            keys
                              ..clear()
                              ..addAll(haSuggest(e).map((a) => a.key));
                          }),
                          child: Container(
                            color: on ? c.accentSoft : null,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: c.ink),
                                      ),
                                      Text(
                                        e.id,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: kUiText - 2, color: c.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (mappedIds.contains(e.id)) Icon(Icons.check, size: 16, color: c.accentInk),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 4,
              child: sel == null
                  ? Center(
                      child: Text('Chọn một thực thể bên trái.', style: TextStyle(color: c.muted)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sel!.name,
                          style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                        ),
                        Text(
                          sel!.id,
                          style: TextStyle(fontSize: kUiText - 1, color: c.muted),
                        ),
                        const SizedBox(height: 12),
                        FieldLabel(
                          'Thêm vào phòng',
                          EvoDropdown<String>(
                            value: effectiveRoom,
                            items: [for (final r in rooms) (r['id'] as String, '${r['name']} (${r['main']})')],
                            onChanged: fixedRoom != null ? null : (v) => setState(() => room = v),
                          ),
                        ),
                        if (fixedRoom != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Thực thể đã có trong phòng này.',
                              style: TextStyle(fontSize: kUiText - 2, color: c.muted),
                            ),
                          ),
                        const SizedBox(height: 10),
                        Text('Dùng để:', style: TextStyle(color: c.muted)),
                        for (final a in haSuggest(sel!))
                          Row(
                            children: [
                              Checkbox(value: keys.contains(a.key), onChanged: (v) => setState(() => v == true ? keys.add(a.key) : keys.remove(a.key))),
                              Expanded(child: Text('${a.label}  ·  DPT ${a.dpt}')),
                            ],
                          ),
                        const Spacer(),
                        EvoButton(
                          label: 'Thêm vào dự án',
                          primary: true,
                          onPressed: keys.isEmpty || effectiveRoom.isEmpty
                              ? null
                              : () {
                                  final e = sel!;
                                  var n = 0;
                                  String? err;
                                  try {
                                    widget.project.mutate((d) => n = addHaEntity(d, e, keys.toList(), roomId: effectiveRoom).length);
                                  } on StateError catch (x) {
                                    err = x.message;
                                  }
                                  if (err != null) {
                                    toast(context, err);
                                    return;
                                  }
                                  setState(() {
                                    added += n > 0 ? 1 : 0;
                                    sel = null;
                                  });
                                  if (n == 0) toast(context, 'Các địa chỉ này đã có.');
                                },
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [EvoButton(label: added > 0 ? 'Xong ($added đã thêm)' : 'Đóng', primary: added > 0, onPressed: () => Navigator.pop(context))],
    );
  }
}
