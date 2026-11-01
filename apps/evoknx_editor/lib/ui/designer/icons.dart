import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:knx_config/knx_config.dart';

/// Icon keys used in project files (shared with the web editor) mapped to
/// Material icons.
const Map<String, IconData> kIconData = {
  // lights
  'bulb': Icons.lightbulb_outline,
  'downlight': Icons.light,
  'spot': Icons.highlight,
  'ceiling': Icons.light_outlined,
  'pendant': Icons.emoji_objects_outlined,
  'chandelier': Icons.wb_iridescent_outlined,
  'wall': Icons.wb_incandescent_outlined,
  'strip': Icons.linear_scale,
  'flood': Icons.flashlight_on,
  'table': Icons.emoji_objects,
  'sun': Icons.wb_sunny_outlined,
  // devices
  'blind': Icons.blinds,
  'curtain': Icons.curtains,
  'thermo': Icons.thermostat,
  'drop': Icons.water_drop_outlined,
  'snow': Icons.ac_unit,
  'fan': Icons.air,
  'tv': Icons.tv,
  'camera': Icons.videocam_outlined,
  'plug': Icons.power_outlined,
  'power': Icons.power_settings_new,
  'door': Icons.door_front_door_outlined,
  'button': Icons.radio_button_checked,
  'star': Icons.star_outline,
  'link': Icons.link,
  'globe': Icons.language,
  'layout': Icons.grid_view,
  'flame': Icons.local_fire_department_outlined,
  'acauto': Icons.autorenew,
  // rooms / floors
  'home': Icons.home_outlined,
  'sofa': Icons.weekend_outlined,
  'bed': Icons.bed_outlined,
  'kids': Icons.child_care_outlined,
  'kitchen': Icons.kitchen_outlined,
  'dining': Icons.dining_outlined,
  'bath': Icons.bathtub_outlined,
  'desk': Icons.desk,
  'cinema': Icons.theaters_outlined,
  'gym': Icons.fitness_center,
  'laundry': Icons.local_laundry_service_outlined,
  'stairs': Icons.stairs_outlined,
  'garage': Icons.garage_outlined,
  'balcony': Icons.balcony,
  'leaf': Icons.yard_outlined,
  'pool': Icons.pool,
};

IconData iconOf(String? key) => kIconData[key] ?? Icons.lightbulb_outline;

const List<(String, String)> kLightIcons = [
  ('bulb', 'Bóng đèn'),
  ('downlight', 'Đèn downlight'),
  ('spot', 'Đèn spotlight'),
  ('ceiling', 'Đèn ốp trần'),
  ('pendant', 'Đèn thả'),
  ('chandelier', 'Đèn chùm'),
  ('wall', 'Đèn tường'),
  ('strip', 'Đèn LED dây'),
  ('flood', 'Đèn pha'),
  ('table', 'Đèn bàn'),
  ('sun', 'Ánh sáng'),
];

const List<(String, String)> kDeviceIcons = [
  ('blind', 'Rèm cuốn'),
  ('curtain', 'Rèm vải'),
  ('thermo', 'Nhiệt độ'),
  ('drop', 'Độ ẩm'),
  ('snow', 'Máy lạnh'),
  ('fan', 'Quạt'),
  ('tv', 'TV'),
  ('camera', 'Camera'),
  ('plug', 'Ổ cắm'),
  ('power', 'Nguồn'),
  ('door', 'Cửa'),
  ('button', 'Nút'),
  ('star', 'Cảnh'),
  ('link', 'Liên kết'),
  ('globe', 'Trang web'),
  ('layout', 'Khung lưới'),
];

const List<(String, String)> kRoomIcons = [
  ('home', 'Cả nhà'),
  ('sofa', 'Phòng khách'),
  ('bed', 'Phòng ngủ'),
  ('kids', 'Phòng trẻ em'),
  ('kitchen', 'Bếp'),
  ('dining', 'Phòng ăn'),
  ('bath', 'Phòng tắm'),
  ('desk', 'Phòng làm việc'),
  ('cinema', 'Phòng giải trí'),
  ('gym', 'Phòng gym'),
  ('laundry', 'Phòng giặt'),
  ('stairs', 'Cầu thang'),
  ('door', 'Sảnh, lối vào'),
  ('garage', 'Garage'),
  ('balcony', 'Ban công'),
  ('leaf', 'Sân vườn'),
  ('pool', 'Hồ bơi'),
];

const List<(String, String)> kFloorIcons = [
  ('stairs', 'Cầu thang'),
  ('home', 'Nhà'),
  ('door', 'Sảnh'),
  ('garage', 'Tầng hầm, garage'),
  ('balcony', 'Sân thượng, ban công'),
  ('leaf', 'Sân vườn'),
];

String iconName(String? key) {
  for (final l in [kLightIcons, kDeviceIcons, kRoomIcons]) {
    for (final i in l) {
      if (i.$1 == key) return i.$2;
    }
  }
  return key ?? '';
}

// ------------------------------------------------------------------ custom icons

/// A user-uploaded icon stored in the project (`icons` list), shared with
/// the web editor format: {id, name, data: data URL (SVG or PNG)}.
class CustomIcon {
  CustomIcon(this.id, this.name, this.data, this.bytes, this.svg);
  final String id, name, data;
  final Uint8List bytes;
  final bool svg;
}

final Map<String, CustomIcon> _custom = {};

/// Decodes a data URL (base64 or plain text SVG). Returns null if invalid.
({Uint8List bytes, bool svg})? decodeIconData(String data) {
  final m = RegExp(r'^data:image/(svg\+xml|png)(;[^,]*)?,(.*)$', dotAll: true).firstMatch(data);
  if (m == null) return null;
  final svg = m[1] == 'svg+xml';
  try {
    final payload = m[3]!;
    final bytes = (m[2] ?? '').contains('base64') ? base64Decode(payload) : Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
    return (bytes: bytes, svg: svg);
  } catch (_) {
    return null;
  }
}

/// Refreshes the icon registry from the project (cheap when unchanged).
void syncCustomIcons(Json doc) {
  final seen = <String>{};
  for (final i in jsonList(doc['icons'])) {
    final id = (i['id'] ?? '').toString();
    final data = (i['data'] ?? '').toString();
    final name = (i['name'] ?? id).toString();
    if (id.isEmpty) continue;
    seen.add(id);
    final cur = _custom[id];
    if (cur != null && cur.data == data) {
      if (cur.name != name) _custom[id] = CustomIcon(id, name, data, cur.bytes, cur.svg);
      continue;
    }
    final dec = decodeIconData(data);
    if (dec != null) _custom[id] = CustomIcon(id, name, data, dec.bytes, dec.svg);
  }
  _custom.removeWhere((k, _) => !seen.contains(k));
}

List<CustomIcon> get customIcons => _custom.values.toList();
bool isCustomIcon(String? key) => key != null && _custom.containsKey(key);

/// Draws an icon by key: built-in Material icon or a custom (tinted) icon.
Widget iconWidget(String? key, double size, Color color) {
  final c = key == null ? null : _custom[key];
  if (c == null) return Icon(iconOf(key), size: size, color: color);
  return SizedBox(
    width: size,
    height: size,
    child: c.svg
        ? SvgPicture.memory(c.bytes, fit: BoxFit.contain, colorFilter: ColorFilter.mode(color, BlendMode.srcIn))
        : Image.memory(c.bytes, fit: BoxFit.contain, color: color, colorBlendMode: BlendMode.srcIn, filterQuality: FilterQuality.medium, gaplessPlayback: true),
  );
}

String iconLabel(String? key) => _custom[key]?.name ?? iconName(key);
