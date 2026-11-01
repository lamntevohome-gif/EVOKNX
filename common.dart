import 'package:flutter/material.dart';
import 'package:knx_core/knx_core.dart';

import '../app/theme.dart';

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
}

/// Flat EVOKNX button (outlined, primary or danger).
class EvoButton extends StatelessWidget {
  const EvoButton({super.key, required this.label, this.icon, this.onPressed, this.primary = false, this.danger = false, this.small = false, this.tooltip});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary, danger, small;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final enabled = onPressed != null;
    final bg = primary ? c.accent : c.panel;
    final fg = primary ? Colors.white : (danger ? c.danger : c.ink);
    final border = primary ? c.accent : c.line;
    Widget child = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Container(
            height: small ? 30 : 34,
            padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 0 : (small ? 10 : 12)),
            constraints: BoxConstraints(minWidth: small ? 30 : 34),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) Icon(icon, size: small ? 16 : 17, color: fg),
                if (icon != null && label.isNotEmpty) const SizedBox(width: 6),
                if (label.isNotEmpty)
                  Text(
                    label,
                    style: TextStyle(color: fg, fontSize: small ? 13 : 13.5, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) child = Tooltip(message: tooltip!, child: child);
    return child;
  }
}

/// Segmented control.
class Seg<T> extends StatelessWidget {
  const Seg({super.key, required this.items, required this.value, required this.onChanged});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.paper,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final it in items)
            GestureDetector(
              onTap: () => onChanged(it.$1),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: it.$1 == value ? c.panel : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: it.$1 == value ? const [BoxShadow(color: Color(0x1A000000), blurRadius: 2, offset: Offset(0, 1))] : null,
                  ),
                  child: Text(
                    it.$2,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: it.$1 == value ? c.ink : c.muted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.evo.muted),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, this.child, {super.key});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: context.evo.muted),
        ),
        const SizedBox(height: 5),
        child,
      ],
    );
  }
}

/// Bordered dropdown with EVOKNX styling.
class EvoDropdown<T> extends StatelessWidget {
  const EvoDropdown({super.key, required this.value, required this.items, required this.onChanged, this.width, this.warn = false});
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T>? onChanged;
  final double? width;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final has = items.any((i) => i.$1 == value);
    return Container(
      width: width,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: warn ? c.warn : c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: has ? value : null,
          isExpanded: width != null,
          isDense: true,
          focusColor: Colors.transparent,
          style: TextStyle(fontSize: 13.5, color: warn ? c.warn : c.ink, fontFamily: 'Segoe UI'),
          items: [
            for (final i in items)
              DropdownMenuItem<T>(
                value: i.$1,
                child: Text(i.$2, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (v) {
                  if (v != null) onChanged!(v);
                },
        ),
      ),
    );
  }
}

List<(String, String)> dptItems(String current, {String none = 'Chưa có DPT'}) => [
  ('', none),
  if (current.isNotEmpty && !kCommonDpts.any((d) => d.id == current)) (current, current),
  for (final d in kCommonDpts) (d.id, '${d.id} · ${d.name}'),
];

/// Text field that keeps its own controller in sync with an external value.
class SyncedField extends StatefulWidget {
  const SyncedField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.width,
    this.number = false,
    this.bold = false,
    this.borderless = false,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final double? width;
  final bool number, bold, borderless;

  @override
  State<SyncedField> createState() => _SyncedFieldState();
}

class _SyncedFieldState extends State<SyncedField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();

  @override
  void didUpdateWidget(SyncedField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final field = TextField(
      controller: _c,
      focusNode: _f,
      onChanged: widget.onChanged,
      keyboardType: widget.number ? TextInputType.number : TextInputType.text,
      style: TextStyle(fontSize: 14, fontWeight: widget.bold ? FontWeight.w600 : FontWeight.w400, color: c.ink),
      decoration: InputDecoration(
        hintText: widget.hint,
        filled: !widget.borderless,
        fillColor: widget.borderless ? Colors.transparent : c.panel,
        border: widget.borderless ? OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(6)) : null,
        enabledBorder: widget.borderless
            ? OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.transparent),
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      ),
    );
    return widget.width == null ? field : SizedBox(width: widget.width, child: field);
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.on, this.size = 9});
  final bool on;
  final double size;
  @override
  Widget build(BuildContext context) {
    final col = on ? const Color(0xFF2FA36B) : const Color(0xFFD9463B);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: col,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: col.withValues(alpha: 0.3), spreadRadius: 3)],
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Tìm theo địa chỉ hoặc tên', this.width = 280});
  final ValueChanged<String> onChanged;
  final String hint;
  final double width;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search, size: 18), prefixIconConstraints: const BoxConstraints(minWidth: 34)),
      ),
    );
  }
}

/// Removes Vietnamese diacritics for accent-insensitive search.
String fold(String s) {
  const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}
