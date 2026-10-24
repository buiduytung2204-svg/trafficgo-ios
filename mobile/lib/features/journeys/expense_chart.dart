import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import 'store.dart';

class ExpensePeriodChart extends StatefulWidget {
  final JourneyStore store;
  final DateTime today;
  const ExpensePeriodChart({
    super.key,
    required this.store,
    required this.today,
  });
  @override
  State<ExpensePeriodChart> createState() => _ExpensePeriodChartState();
}

class _ExpensePeriodChartState extends State<ExpensePeriodChart> {
  int days = 7;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TrafficToggle<int>(
        value: days,
        values: const [7, 30],
        label: (v) => '$v ngày',
        icon: (_) => Icons.date_range_rounded,
        onChanged: (v) => setState(() => days = v),
      ),
      const SizedBox(height: 16),
      ExpenseWeekChart(
        store: widget.store,
        today: widget.today,
        daysCount: days,
      ),
    ],
  );
}

class ExpenseWeekChart extends StatefulWidget {
  final JourneyStore store;
  final DateTime today;
  final int daysCount;
  const ExpenseWeekChart({
    super.key,
    required this.store,
    required this.today,
    this.daysCount = 7,
  });
  @override
  State<ExpenseWeekChart> createState() => _ExpenseWeekChartState();
}

class _ExpenseWeekChartState extends State<ExpenseWeekChart> {
  String? signature;
  Widget? cached;
  @override
  Widget build(BuildContext context) {
    final today = widget.today;
    final days = List.generate(
      widget.daysCount,
      (i) => today.subtract(Duration(days: widget.daysCount - 1 - i)),
    );
    final values = days
        .map((d) => widget.store.total(d, d.add(const Duration(days: 1))))
        .toList();
    final nextSignature =
        '${values.join(',')}:${days.first}:${Theme.of(context).hashCode}:${MediaQuery.of(context).hashCode}';
    if (signature == nextSignature && cached != null) return cached!;
    signature = nextSignature;
    if (values.every((v) => v == 0)) {
      return cached = EmptyPanel(
        icon: Icons.bar_chart,
        title: 'Chưa có chi phí trong ${widget.daysCount} ngày',
        message: 'Ghi khoản chi thực tế để xem biểu đồ. TrafficGo không tự tạo giao dịch.',
      );
    }
    final colors = Theme.of(context).colorScheme;
    return cached = TrafficCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chi phí ${widget.daysCount} ngày',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text('Đơn vị biểu đồ: nghìn VNĐ • Chạm cột để xem số tiền'),
          const SizedBox(height: 24),
          Semantics(
            label: 'Biểu đồ khoản chi thực tế trong ${widget.daysCount} ngày',
            child: SizedBox(
              height: 190,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                          BarTooltipItem(
                            formatVnd(values[group.x]),
                            TextStyle(color: colors.onInverseSurface),
                          ),
                    ),
                  ),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: colors.outlineVariant, strokeWidth: .5),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 ||
                              i >= days.length ||
                              (days.length > 7 &&
                                  i % 5 != 0 &&
                                  i != days.length - 1)) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${days[i].day}/${days[i].month}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(
                    days.length,
                    (i) => BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: values[i] / 1000,
                          color: i == days.length - 1
                              ? colors.tertiary
                              : colors.primary,
                          width: days.length > 7 ? 6 : 18,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                duration: TrafficMotion.duration(context),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // A readable equivalent of the chart for large text and screen readers.
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (var i = 0; i < days.length; i++)
                Text(
                  '${days[i].day}/${days[i].month}: ${formatVnd(values[i])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
