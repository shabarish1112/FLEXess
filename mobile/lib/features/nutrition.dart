import 'package:flutter/material.dart';
import '../core/diary_store.dart';
import '../ui/design_system.dart';
import 'diary/domain.dart';

class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key, required this.diary, required this.date});
  final DiaryStore diary;
  final DateTime date;
  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage> {
  int days = 7;
  late Future<List<DiaryEntry>> data = load();
  Future<List<DiaryEntry>> load() => widget.diary.history(
    diaryDate(
      DateTime(widget.date.year, widget.date.month, widget.date.day - days + 1),
    ),
    diaryDate(widget.date),
  );
  void reload() {
    setState(() => data = load());
  }

  @override
  void initState() {
    super.initState();
    widget.diary.remoteDiaryRevision.addListener(reload);
  }

  @override
  void dispose() {
    widget.diary.remoteDiaryRevision.removeListener(reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nutrition analytics')),
    body: FutureBuilder(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: reload,
              child: const Text('Could not load nutrition. Retry'),
            ),
          );
        }
        if (!snapshot.hasData) return const LoadingCards();
        final entries = snapshot.requireData;
        final recorded = entries.map((e) => e.day).toSet().length;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Patterns, not perfection',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final range in [1, 7, 30])
                  ChoiceChip(
                    label: Text(range == 1 ? 'Daily' : '$range days'),
                    selected: days == range,
                    onSelected: (_) {
                      days = range;
                      reload();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '$recorded recorded ${recorded == 1 ? 'day' : 'days'} · dates without entries are not treated as zero intake.',
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No food records in this range. Log a meal to begin.',
                ),
              ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Energy over time',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ValueBars(
                        unit: 'kcal',
                        values: [
                          for (var i = days - 1; i >= 0; i--)
                            _day(
                              entries,
                              diaryDate(
                                DateTime(
                                  widget.date.year,
                                  widget.date.month,
                                  widget.date.day - i,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (entries.any(
                        (e) => e.amounts[Nutrient.energy] == null,
                      ))
                        const Text(
                          'Some energy values are unknown; bars show known totals only.',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Average macros per recorded day',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ValueBars(
                        unit: 'g',
                        color: teal,
                        values: [
                          for (final n in [
                            Nutrient.protein,
                            Nutrient.carbs,
                            Nutrient.fat,
                          ])
                            (
                              '${n.label}${total(entries, n).missing > 0 ? ' · incomplete' : ''}',
                              total(entries, n).missing == entries.length
                                  ? null
                                  : total(entries, n).known / 1000 / recorded,
                            ),
                        ],
                      ),
                      const Text('These are grams, not percentages of energy.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Daily nutrient details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final day
                  in entries.map((e) => e.day).toSet().toList()
                    ..sort((a, b) => b.compareTo(a))) ...[
                const SizedBox(height: 12),
                FutureBuilder(
                  future: widget.diary.tracking.goals(day),
                  builder: (context, goals) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            day,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final n in Nutrient.values)
                            Builder(
                              builder: (context) {
                                final group = entries
                                    .where((e) => e.day == day)
                                    .toList();
                                final sum = total(group, n);
                                final target = switch (n) {
                                  Nutrient.energy => goals.data?.energy,
                                  Nutrient.protein => goals.data?.protein,
                                  Nutrient.carbs => goals.data?.carbs,
                                  Nutrient.fat => goals.data?.fat,
                                  _ => null,
                                };
                                return Text(
                                  '${n.label}: ${sum.missing == group.length ? 'Unknown' : (sum.known / 1000).toStringAsFixed(1)} ${n.unit}${target == null ? '' : ' / $target goal'}${sum.missing > 0 ? ' · incomplete' : ''}',
                                );
                              },
                            ),
                          if (goals.hasError)
                            const Text('Targets could not be loaded.'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    ),
  );
  (String, double?) _day(List<DiaryEntry> all, String date) {
    final rows = all.where((e) => e.day == date).toList();
    final sum = total(rows, Nutrient.energy);
    return (
      date,
      rows.isEmpty || sum.missing == rows.length ? null : sum.known / 1000,
    );
  }
}
