import 'package:flutter/material.dart';
import '../core/diary_store.dart';
import '../core/tracking_store.dart';
import '../core/product_store.dart';
import '../ui/design_system.dart';
import 'diary/domain.dart';

const goalLabels = [
  'Daily energy (kcal)',
  'Protein (g)',
  'Carbohydrate (g)',
  'Fat (g)',
  'Water (mL)',
  'Goal weight (kg)',
];
const goalLimits = [20000, 2000, 2000, 2000, 20000, 1000];

class GoalsPage extends StatefulWidget {
  const GoalsPage({
    super.key,
    required this.store,
    required this.day,
    required this.initial,
  });
  final TrackingStore store;
  final String day;
  final Targets initial;

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  late final List<int?> values = [
    widget.initial.energy,
    widget.initial.protein,
    widget.initial.carbs,
    widget.initial.fat,
    widget.initial.water,
    widget.initial.weight,
  ];
  late bool credit = widget.initial.exerciseCredit;
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;

  Future<void> save() async {
    if (busy) return;
    if (!form.currentState!.validate()) return;
    form.currentState!.save();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.saveGoals(
        widget.day,
        Targets(
          energy: values[0],
          protein: values[1],
          carbs: values[2],
          fat: values[3],
          water: values[4],
          weight: values[5],
          exerciseCredit: credit,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not save goals.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Goals')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Effective from ${widget.day}. Leave a goal blank to clear it.'),
          for (var i = 0; i < goalLabels.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextFormField(
                initialValue: values[i] == null
                    ? null
                    : i == 5
                    ? (values[i]! / 1000).toString()
                    : values[i].toString(),
                enabled: !busy,
                decoration: InputDecoration(labelText: goalLabels[i]),
                keyboardType: TextInputType.numberWithOptions(decimal: i == 5),
                validator: (text) {
                  final raw = text?.trim() ?? '';
                  if (raw.isEmpty) return null;
                  final value = i == 5
                      ? double.tryParse(raw)
                      : int.tryParse(raw);
                  return value == null ||
                          !value.isFinite ||
                          value < 1 ||
                          value > goalLimits[i]
                      ? 'Enter 1–${goalLimits[i]}.'
                      : null;
                },
                onSaved: (text) =>
                    values[i] = text == null || text.trim().isEmpty
                    ? null
                    : i == 5
                    ? (double.parse(text.trim()) * 1000).round()
                    : int.parse(text.trim()),
              ),
            ),
          SwitchListTile(
            title: const Text(
              'Include estimated exercise energy in calories left',
            ),
            value: credit,
            onChanged: busy ? null : (value) => setState(() => credit = value),
          ),
          if (error != null) Semantics(liveRegion: true, child: Text(error!)),
          FilledButton(
            onPressed: busy ? null : save,
            child: const Text('Save goals'),
          ),
        ],
      ),
    ),
  );
}

class TrackingPage extends StatefulWidget {
  const TrackingPage({
    super.key,
    required this.diary,
    required this.date,
    this.initialKind = TrackKind.weight,
  });
  final DiaryStore diary;
  final DateTime date;
  final TrackKind initialKind;

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  late final store = widget.diary.tracking;
  late DateTime date = widget.date;
  late TrackKind kind = widget.initialKind;
  bool busy = false;
  bool imperial = false;
  String? error;
  late Future<(List<TrackRecord>, Targets)> data = read();

  Future<(List<TrackRecord>, Targets)> read() async => (
    await store.records(diaryDate(date), diaryDate(date)),
    await store.goals(diaryDate(date)),
  );

  @override
  void initState() {
    super.initState();
    widget.diary.remoteTrackerRevision.addListener(reload);
    loadUnits();
  }

  Future<void> loadUnits() async {
    try {
      final prefs = await ProductStore(widget.diary.db).preferences();
      if (mounted) setState(() => imperial = prefs['units'] == 'imperial');
    } catch (_) {
      /* The unit control remains available if preferences cannot load. */
    }
  }

  @override
  void dispose() {
    widget.diary.remoteTrackerRevision.removeListener(reload);
    super.dispose();
  }

  void reload() {
    final next = read();
    setState(() {
      data = next;
    });
  }

  String valueLabel(TrackRecord record) => switch (record.kind) {
    TrackKind.weight =>
      imperial
          ? '${(record.value / 453.59237).toStringAsFixed(1)} lb'
          : '${(record.value / 1000).toStringAsFixed(2)} kg',
    TrackKind.water =>
      imperial
          ? '${(record.value / 29.5735295625).toStringAsFixed(1)} US fl oz'
          : '${record.value} mL',
    TrackKind.exercise =>
      '${record.value} min · ${record.energy == null ? 'No energy estimate' : '≈${record.energy} kcal'}',
  };

  Future<void> write(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) reload();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save the change. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([TrackRecord? existing]) async {
    final old = existing;
    final entry = await Navigator.push<TrackRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordEditor(
          kind: kind,
          date: date,
          existing: old,
          store: store,
          imperial: imperial,
        ),
      ),
    );
    if (mounted && entry != null) reload();
  }

  Future<void> remove(TrackRecord entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text(valueLabel(entry)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (mounted && yes == true) await write(() => store.remove(entry));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tracking'),
      actions: [
        IconButton(
          tooltip: 'Progress history',
          icon: const Icon(Icons.insights_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ProgressPage(diary: widget.diary, end: date),
            ),
          ),
        ),
      ],
    ),
    body: FutureBuilder(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: reload,
              child: const Text('Could not load tracking. Retry'),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final (records, goals) = snapshot.requireData;
        final selected = records.where((r) => r.kind == kind).toList();
        final sum = selected.fold(0, (value, row) => value + row.value);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final option in TrackKind.values)
                  ChoiceChip(
                    label: Text(option.name),
                    selected: kind == option,
                    onSelected: busy
                        ? null
                        : (_) => setState(() => kind = option),
                  ),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(diaryDate(date)),
              onPressed: busy
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (mounted && picked != null) {
                        date = picked;
                        reload();
                      }
                    },
            ),
            if (kind != TrackKind.exercise)
              SwitchListTile(
                title: Text(
                  kind == TrackKind.weight
                      ? 'Display pounds'
                      : 'Display US fluid ounces',
                ),
                value: imperial,
                onChanged: (value) => setState(() => imperial = value),
              ),
            if (kind == TrackKind.weight && goals.weight != null)
              Text(
                'Goal weight: ${valueLabel(TrackRecord(kind: kind, day: diaryDate(date), value: goals.weight!))}',
              ),
            if (kind == TrackKind.water) ...[
              Text(
                goals.water == null
                    ? '$sum mL logged'
                    : '$sum / ${goals.water} mL',
              ),
              if (goals.water != null)
                LinearProgressIndicator(
                  value: (sum / goals.water!).clamp(0, 1),
                  semanticsLabel: 'Water goal progress',
                ),
              Wrap(
                spacing: 8,
                children: [
                  for (final ml in [250, 500, 750])
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => write(
                              () => store.save(
                                TrackRecord(
                                  kind: kind,
                                  day: diaryDate(date),
                                  value: ml,
                                ),
                              ),
                            ),
                      child: Text('+$ml mL'),
                    ),
                ],
              ),
            ],
            if (kind == TrackKind.exercise)
              Text(
                '$sum min · ≈${selected.fold(0, (total, item) => total + (item.energy ?? 0))} kcal estimated'
                '${selected.any((item) => item.energy == null) ? ' · incomplete' : ''}',
              ),
            FilledButton.icon(
              onPressed: busy ? null : () => edit(),
              icon: const Icon(Icons.add),
              label: Text('Add ${kind.name}'),
            ),
            if (error != null) Semantics(liveRegion: true, child: Text(error!)),
            if (selected.isEmpty) Text('No ${kind.name} records for this day.'),
            for (final item in selected)
              ListTile(
                title: Text(item.name.isEmpty ? valueLabel(item) : item.name),
                subtitle: item.name.isEmpty
                    ? null
                    : Text('${item.category} · ${valueLabel(item)}'),
                onTap: busy ? null : () => edit(item),
                trailing: IconButton(
                  tooltip: 'Delete ${item.kind.name} record',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: busy ? null : () => remove(item),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class RecordEditor extends StatefulWidget {
  const RecordEditor({
    super.key,
    required this.kind,
    required this.date,
    required this.store,
    this.existing,
    this.imperial = false,
  });
  final TrackKind kind;
  final DateTime date;
  final TrackingStore store;
  final TrackRecord? existing;
  final bool imperial;

  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final form = GlobalKey<FormState>();
  late DateTime date = widget.existing == null
      ? widget.date
      : DateTime.parse(widget.existing!.day);
  late String name = widget.existing?.name ?? '';
  late String intensity = widget.existing?.intensity.isNotEmpty == true
      ? widget.existing!.intensity
      : 'Unspecified';
  late String category = widget.existing?.category.isNotEmpty == true
      ? widget.existing!.category
      : 'Cardio';
  late final input = TextEditingController(text: initial());
  late bool alternative = widget.imperial;
  bool busy = false;
  String? error;

  String initial() {
    final value = widget.existing?.value;
    if (value == null) return '';
    return switch (widget.kind) {
      TrackKind.weight =>
        (value / (widget.imperial ? 453.59237 : 1000)).toStringAsFixed(3),
      TrackKind.water =>
        widget.imperial
            ? (value / 29.5735295625).toStringAsFixed(3)
            : value.toString(),
      TrackKind.exercise => value.toString(),
    };
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  int? parse(String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null || !value.isFinite || value <= 0 || value > 20000) {
      return null;
    }
    return switch (widget.kind) {
      TrackKind.weight => weightGrams(value, pounds: alternative),
      TrackKind.water => waterMilliliters(value, ounces: alternative),
      TrackKind.exercise => value == value.round() ? value.round() : null,
    };
  }

  Future<void> save() async {
    if (busy) return;
    if (!form.currentState!.validate()) return;
    final value = parse(input.text)!;
    final day = diaryDate(date);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final energy = widget.kind == TrackKind.exercise
          ? exerciseEstimate(
              value,
              await widget.store.latestWeight(day),
              intensity,
            )
          : null;
      final record = TrackRecord(
        id: widget.existing?.id,
        kind: widget.kind,
        day: day,
        value: value,
        name: name.trim(),
        category: widget.kind == TrackKind.exercise ? category : '',
        intensity: widget.kind == TrackKind.exercise ? intensity : '',
        energy: energy,
      );
      await widget.store.save(record);
      if (mounted) Navigator.pop(context, record);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not save. Your input is still here.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final units = switch (kind) {
      TrackKind.weight => alternative ? 'lb' : 'kg',
      TrackKind.water => alternative ? 'US fl oz' : 'mL',
      TrackKind.exercise => 'minutes',
    };
    final limits = switch (kind) {
      TrackKind.weight => (1000, 1000000),
      TrackKind.water => (1, 20000),
      TrackKind.exercise => (1, 1440),
    };
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${widget.existing == null ? 'Add' : 'Edit'} ${kind.name}',
          ),
        ),
        body: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text(diaryDate(date)),
                onPressed: busy
                    ? null
                    : () async {
                        final day = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (mounted && day != null) setState(() => date = day);
                      },
              ),
              if (kind != TrackKind.exercise)
                SwitchListTile(
                  title: Text(
                    kind == TrackKind.weight
                        ? 'Enter pounds'
                        : 'Enter US fluid ounces',
                  ),
                  value: alternative,
                  onChanged: busy
                      ? null
                      : (change) {
                          final current = parse(input.text);
                          if (current != null) {
                            input.text = kind == TrackKind.weight
                                ? (current / (change ? 453.59237 : 1000))
                                      .toStringAsFixed(3)
                                : (current / (change ? 29.5735295625 : 1))
                                      .toStringAsFixed(3);
                          }
                          setState(() => alternative = change);
                        },
                ),
              if (kind == TrackKind.exercise) ...[
                TextFormField(
                  initialValue: name,
                  enabled: !busy,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Exercise name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a name.'
                      : null,
                  onChanged: (value) => name = value,
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final v in ['Cardio', 'Strength', 'Mobility', 'Other'])
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() => category = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: intensity,
                  decoration: const InputDecoration(labelText: 'Intensity'),
                  items: [
                    for (final v in [
                      'Unspecified',
                      'Light',
                      'Moderate',
                      'Vigorous',
                    ])
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() => intensity = value!),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Energy is an approximation using logged weight and intensity. No estimate if either is missing.',
                  ),
                ),
              ],
              TextFormField(
                controller: input,
                enabled: !busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      '${kind == TrackKind.exercise ? 'Duration' : 'Amount'} ($units)',
                ),
                validator: (text) {
                  final value = parse(text ?? '');
                  return value == null || value < limits.$1 || value > limits.$2
                      ? 'Enter a supported positive amount.'
                      : null;
                },
              ),
              if (error != null)
                Semantics(liveRegion: true, child: Text(error!)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : save,
                child: const Text('Save record'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key, required this.diary, required this.end});
  final DiaryStore diary;
  final DateTime end;

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  int days = 7;
  late Future<(List<TrackRecord>, List<DiaryEntry>, Map<String, Targets>)>
  data = history();

  @override
  void initState() {
    super.initState();
    widget.diary.remoteDiaryRevision.addListener(_refreshHistory);
    widget.diary.remoteTrackerRevision.addListener(_refreshHistory);
  }

  @override
  void didUpdateWidget(covariant ProgressPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diary != widget.diary) {
      oldWidget.diary.remoteDiaryRevision.removeListener(_refreshHistory);
      oldWidget.diary.remoteTrackerRevision.removeListener(_refreshHistory);
      widget.diary.remoteDiaryRevision.addListener(_refreshHistory);
      widget.diary.remoteTrackerRevision.addListener(_refreshHistory);
    }
    if (oldWidget.diary != widget.diary || oldWidget.end != widget.end) {
      data = history();
    }
  }

  @override
  void dispose() {
    widget.diary.remoteDiaryRevision.removeListener(_refreshHistory);
    widget.diary.remoteTrackerRevision.removeListener(_refreshHistory);
    super.dispose();
  }

  void _refreshHistory() {
    final next = history();
    setState(() {
      data = next;
    });
  }

  Future<(List<TrackRecord>, List<DiaryEntry>, Map<String, Targets>)>
  history() async {
    final end = widget.end;
    final first = diaryDate(DateTime(end.year, end.month, end.day - days + 1));
    final last = diaryDate(end);
    final tracking = widget.diary.tracking;
    final records = await tracking.records(first, last);
    final entries = await widget.diary.history(first, last);
    final targets = <String, Targets>{};
    for (final day in {
      ...entries.map((e) => e.day),
      ...records.map((r) => r.day),
      last,
    }) {
      targets[day] = await tracking.goals(day);
    }
    return (records, entries, targets);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Progress')),
    body: FutureBuilder(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: _refreshHistory,
              child: const Text('Could not load history. Retry'),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final (tracking, food, goals) = snapshot.requireData;
        final dates = {
          ...tracking.map((r) => r.day),
          ...food.map((r) => r.day),
        }.toList()..sort((a, b) => b.compareTo(a));
        final weight = <String, int>{};
        for (final item in tracking.where(
          (item) => item.kind == TrackKind.weight,
        )) {
          weight.putIfAbsent(item.day, () => item.value);
        }
        final maxWeight = weight.values.fold(
          1,
          (max, value) => value > max ? value : max,
        );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final range in [7, 30, 90])
                  ChoiceChip(
                    label: Text('$range days'),
                    selected: days == range,
                    onSelected: (_) => setState(() {
                      days = range;
                      data = history();
                    }),
                  ),
              ],
            ),
            if (dates.isEmpty) const Text('No records in this range.'),
            if (weight.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weight over time',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ValueBars(
                        unit: 'kg',
                        values: [
                          for (final row in weight.entries.toList().reversed)
                            (row.key, row.value / 1000),
                        ],
                      ),
                      if (weight.length > 1)
                        Text(
                          'Recorded change: ${((weight.values.first - weight.values.last) / 1000).toStringAsFixed(2)} kg across this range.',
                        ),
                      if (goals[diaryDate(widget.end)]?.weight != null)
                        Text(
                          'Goal weight: ${(goals[diaryDate(widget.end)]!.weight! / 1000).toStringAsFixed(2)} kg',
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (tracking.any((r) => r.kind == TrackKind.water)) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily hydration',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ValueBars(
                        unit: 'mL',
                        color: teal,
                        values: [
                          for (final day in dates.reversed)
                            if (tracking.any(
                              (r) => r.day == day && r.kind == TrackKind.water,
                            ))
                              (
                                day,
                                tracking
                                    .where(
                                      (r) =>
                                          r.day == day &&
                                          r.kind == TrackKind.water,
                                    )
                                    .fold<double>(0.0, (v, r) => v + r.value),
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (weight.isNotEmpty)
              Text(
                'Weight trend',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            for (final row in weight.entries.toList().reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row.key} · ${(row.value / 1000).toStringAsFixed(2)} kg',
                    ),
                    ExcludeSemantics(
                      child: LinearProgressIndicator(
                        value: row.value / maxWeight,
                      ),
                    ),
                  ],
                ),
              ),
            for (final day in dates) ...[
              const Divider(),
              Text(day, style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrackingPage(
                        diary: widget.diary,
                        date: DateTime.parse(day),
                      ),
                    ),
                  );
                  if (mounted) _refreshHistory();
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit tracking records'),
              ),
              if (food.any((e) => e.day == day))
                for (final nutrient in Nutrient.values)
                  Text(
                    nutritionLine(
                      food.where((e) => e.day == day).toList(),
                      nutrient,
                      nutrient == Nutrient.energy ? goals[day]?.energy : null,
                    ),
                  ),
              if (tracking.any(
                (r) => r.day == day && r.kind == TrackKind.water,
              ))
                Text(
                  'Water: ${tracking.where((r) => r.day == day && r.kind == TrackKind.water).fold(0, (n, r) => n + r.value)} mL',
                ),
              if (tracking.any(
                (r) => r.day == day && r.kind == TrackKind.exercise,
              ))
                Text(
                  'Exercise: ${tracking.where((r) => r.day == day && r.kind == TrackKind.exercise).fold(0, (n, r) => n + r.value)} min',
                ),
            ],
          ],
        );
      },
    ),
  );

  String nutritionLine(List<DiaryEntry> entries, Nutrient nutrient, int? goal) {
    final summary = total(entries, nutrient);
    final value = summary.missing == entries.length
        ? 'unknown'
        : '${(summary.known / 1000).toStringAsFixed(1)} ${nutrient.unit}';
    return '${nutrient.label}: $value${goal == null ? '' : ' / $goal kcal goal'}'
        '${summary.missing > 0 ? ' · incomplete' : ''}';
  }
}
