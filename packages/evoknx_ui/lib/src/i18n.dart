import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' hide Text;
import 'package:flutter/widgets.dart' as w show Text;

import 'i18n_en.dart';

/// Language of the labels of the Editor and the App ('vi' or 'en').
///
/// Only the labels of the program are translated. The content made by the
/// person who sets a project up (names, card texts…) is never touched: the
/// cards are drawn with the plain Flutter Text, and the dictionary has no
/// default content.
class AppLang extends ChangeNotifier {
  String _code = 'vi';
  String get code => _code;
  bool get isEn => _code == 'en';

  void set(String code) {
    if ((code != 'vi' && code != 'en') || code == _code) return;
    _code = code;
    _cache.clear();
    notifyListeners();
  }
}

final AppLang appLang = AppLang();

final Map<String, String> _cache = {};
List<(RegExp, String)>? _templates;

List<(RegExp, String)> _compile() {
  final out = <(RegExp, String, int)>[];
  kEnTemplates.forEach((vi, en) {
    final parts = vi.split('{}');
    final re = RegExp('^${parts.map(RegExp.escape).join('(.*?)')}\$', dotAll: true);
    out.add((re, en, parts.join().length));
  });
  // The most specific (longest fixed text) first.
  out.sort((a, b) => b.$3.compareTo(a.$3));
  return [for (final o in out) (o.$1, o.$2)];
}

/// Translates a value that was put into a text, keeping its spaces around.
String _part(String g) {
  final t = g.trim();
  if (t.isEmpty) return g;
  final start = g.indexOf(t);
  return g.substring(0, start) + tr(t) + g.substring(start + t.length);
}

String _fill(String en, List<String?> groups) {
  var next = 0;
  return en.replaceAllMapped(RegExp(r'\{(\d*)\}'), (m) {
    final k = m[1]!.isEmpty ? next++ : int.parse(m[1]!) - 1;
    return k < groups.length ? _part(groups[k] ?? '') : '';
  });
}

String _translate(String vi) {
  final exact = kEn[vi];
  if (exact != null) return exact;
  for (final t in (_templates ??= _compile())) {
    final m = t.$1.firstMatch(vi);
    if (m != null) return _fill(t.$2, [for (var i = 1; i <= m.groupCount; i++) m[i]]);
  }
  return vi;
}

/// A label of the program in the current language (Vietnamese is the key).
/// Anything that is not in the dictionary is returned unchanged.
String tr(String vi) {
  if (!appLang.isEn || vi.isEmpty) return vi;
  return _cache[vi] ??= _translate(vi);
}

/// Makes everything that depends on it rebuild when the language changes.
class LangScope extends InheritedNotifier<AppLang> {
  const LangScope({super.key, required AppLang lang, required super.child}) : super(notifier: lang);

  /// Call from a build method to be rebuilt on a language change.
  static void watch(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LangScope>();
}

/// The Flutter Text, with its string translated when the language is English.
/// Files that show labels of the program use this one (`hide Text` from
/// material); the cards use the plain Flutter Text.
class Text extends StatelessWidget {
  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  static InlineSpan _span(InlineSpan s) {
    if (s is TextSpan) {
      return TextSpan(
        text: s.text == null ? null : tr(s.text!),
        children: s.children?.map(_span).toList(),
        style: s.style,
        recognizer: s.recognizer,
        mouseCursor: s.mouseCursor,
        onEnter: s.onEnter,
        onExit: s.onExit,
        semanticsLabel: s.semanticsLabel,
      );
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    LangScope.watch(context);
    if (textSpan != null) {
      return w.Text.rich(
        _span(textSpan!),
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    return w.Text(
      tr(data!),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
