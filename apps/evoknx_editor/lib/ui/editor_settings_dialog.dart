import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../state/app_settings.dart';
import 'common.dart';

/// ⚙ Cài đặt Editor: theme, autosave, default folder, about.
class EditorSettingsDialog extends StatelessWidget {
  const EditorSettingsDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(context: context, builder: (_) => const EditorSettingsDialog());

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
        final c = context.evo;
        Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted),
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        );
        final folder = appSettings.defaultFolder;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.settings_outlined, color: c.accent),
              const SizedBox(width: 10),
              const Text('Cài đặt Editor', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section('Giao diện', [
                    Seg<ThemeMode>(
                      items: const [(ThemeMode.light, 'Sáng'), (ThemeMode.dark, 'Tối')],
                      value: appSettings.themeMode,
                      onChanged: appSettings.setThemeMode,
                    ),
                  ]),
                  section('Tự lưu vào file dự án', [
                    EvoDropdown<int>(
                      value: appSettings.autosaveMinutes,
                      items: const [(0, 'Tắt'), (1, 'Mỗi 1 phút'), (2, 'Mỗi 2 phút'), (5, 'Mỗi 5 phút'), (10, 'Mỗi 10 phút')],
                      onChanged: appSettings.setAutosaveMinutes,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Chỉ áp dụng cho dự án đã lưu thành file. Ngoài ra Editor luôn sao lưu ngầm phiên làm việc, '
                      'nên nếu máy tắt đột ngột, lần mở sau dự án vẫn còn nguyên.',
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ]),
                  section('Lịch sử lưu (tạo khi bấm Lưu / Ctrl+S)', [
                    EvoDropdown<int>(
                      value: appSettings.historyKeepDays,
                      items: const [(30, 'Giữ 30 ngày'), (90, 'Giữ 90 ngày'), (180, 'Giữ 180 ngày'), (365, 'Giữ 1 năm'), (0, 'Không tự xoá')],
                      onChanged: (v) => appSettings.setHistory(keepDays: v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: appSettings.historyThin,
                          onChanged: (v) => appSettings.setHistory(thin: v ?? true),
                        ),
                        const Expanded(child: Text('Sau 7 ngày, mỗi ngày chỉ giữ bản lưu cuối cùng')),
                      ],
                    ),
                    Text(
                      'Mỗi dự án có folder riêng mang tên dự án. Mỗi lần bấm Lưu, Editor tạo thêm một bản lịch sử trong folder của ngày đó. '
                      'Tự lưu chỉ ghi vào file chính. File chính không bao giờ bị xoá.',
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ]),
                  section('Thư mục lưu mặc định', [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.paper,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        folder ?? 'Chưa chọn (dùng thư mục Windows đề xuất)',
                        style: TextStyle(fontSize: 13, color: folder == null ? c.muted : c.ink),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        EvoButton(
                          label: 'Chọn thư mục',
                          icon: Icons.folder_open_outlined,
                          small: true,
                          onPressed: () async {
                            final d = await getDirectoryPath(initialDirectory: folder, confirmButtonText: 'Chọn');
                            if (d != null) await appSettings.setDefaultFolder(d);
                          },
                        ),
                        const SizedBox(width: 8),
                        if (folder != null) EvoButton(label: 'Bỏ chọn', small: true, onPressed: () => appSettings.setDefaultFolder(null)),
                      ],
                    ),
                  ]),
                  section('Giới thiệu', [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: c.led,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: c.led.withValues(alpha: 0.25), spreadRadius: 3)],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('EVOKNX Editor', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(width: 8),
                        Text('phiên bản $kEditorVersion', style: TextStyle(color: c.muted)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Thiết kế giao diện điều khiển nhà thông minh KNX.\n© ${DateTime.now().year} Evohome. Bảo lưu mọi quyền.\n\nBiểu tượng: Material Design Icons của Pictogrammers, giấy phép Apache 2.0.',
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          actions: [EvoButton(label: 'Đóng', primary: true, onPressed: () => Navigator.pop(context))],
        );
      },
    );
  }
}
