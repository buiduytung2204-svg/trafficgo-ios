import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/design/components.dart';
import 'store.dart';

class ExpenseWeekChart extends StatelessWidget {
  final JourneyStore store;
  final DateTime today;
  const ExpenseWeekChart({super.key, required this.store, required this.today});
  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final values = days
        .map((d) => store.total(d, d.add(const Duration(days: 1))))
        .toList();
    if (values.every((v) => v == 0)) {
      return const EmptyPanel(
        icon: Icons.bar_chart,
        title: 'Chưa có chi phí trong 7 ngày',
        message:
            'Ghi khoản chi thực tế để xem biểu đồ. TrafficGo không tự tạo giao dịch.',
      );
    }
    final colors = Theme.of(context).colorScheme;
    return TrafficCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chi phí 7 ngày',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text('Đơn vị biểu đồ: nghìn VNĐ • Chạm cột để xem số tiền'),
          const SizedBox(height: 24),
          Semantics(
            label: 'Biểu đồ khoản chi thực tế trong 7 ngày',
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
                          if (i < 0 || i >= 7) return const SizedBox.shrink();
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
                    7,
                    (i) => BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: values[i] / 1000,
                          color: colors.primary,
                          width: 18,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // A readable equivalent of the chart for large text and screen readers.
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (var i = 0; i < 7; i++)
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
