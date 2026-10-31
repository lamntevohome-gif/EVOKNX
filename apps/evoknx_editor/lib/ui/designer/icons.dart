import 'package:flutter/material.dart';

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
