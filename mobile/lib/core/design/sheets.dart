import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';
import 'components.dart';

/// Retain existing stateful editor validation/save handlers inside a responsive
/// Wolt page rather than duplicating form logic in a second implementation.
Future<T?> showTrafficEditor<T>(BuildContext context, Widget editor) =>
    WoltModalSheet.show<T>(
      context: context,
      pageListBuilder: (c) => [
        WoltModalSheetPage(
          hasTopBarLayer: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * .82,
            child: editor,
          ),
        ),
      ],
    );

Future<T?> showTrafficSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
}) => WoltModalSheet.show<T>(
  context: context,
  pageListBuilder: (sheetContext) => [
    WoltModalSheetPage(
      hasTopBarLayer: false,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              builder(sheetContext),
            ],
          ),
        ),
      ),
    ),
  ],
);

/// Shadcn is deliberately limited to calendar selection. It does not introduce
/// another general-purpose button/input style into the app.
Future<DateTime?> pickTrafficDate(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  var selected = initialDate;
  return showTrafficSheet<DateTime>(
    context,
    title: 'Chọn ngày',
    builder: (c) => StatefulBuilder(
      builder: (c, update) {
        final dark = Theme.of(c).brightness == Brightness.dark;
        final scheme =
            (dark
                    ? const ShadSlateColorScheme.dark()
                    : const ShadSlateColorScheme.light())
                .copyWith(
                  primary: Theme.of(c).colorScheme.primary,
                  primaryForeground: Theme.of(c).colorScheme.onPrimary,
                );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ShadTheme(
                data: ShadThemeData(
                  brightness: Theme.of(c).brightness,
                  colorScheme: scheme,
                ),
                child: ShadCalendar(
                  selected: selected,
                  initialMonth: initialDate,
                  fromMonth: firstDate,
                  toMonth: lastDate,
                  weekStartsOn: 1,
                  formatMonthYear: (d) => 'Tháng ${d.month}/${d.year}',
                  formatWeekday: (d) =>
                      ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][d.weekday - 1],
                  selectableDayPredicate: (d) =>
                      !d.isBefore(DateUtils.dateOnly(firstDate)) &&
                      !d.isAfter(DateUtils.dateOnly(lastDate)),
                  onChanged: (d) {
                    if (d != null) update(() => selected = d);
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            TrafficButton(
              label: 'Chọn ${selected.day}/${selected.month}/${selected.year}',
              onPressed: () => Navigator.pop(c, selected),
            ),
          ],
        );
      },
    ),
  );
}
