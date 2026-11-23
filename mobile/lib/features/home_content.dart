part of '../app.dart';

extension _HomeSections on _DiaryHomeState {
  Widget energySummary(
    List<DiaryEntry> entries,
    AsyncValue<(Targets, int)> goal,
    String day,
  ) {
    final energy = total(entries, Nutrient.energy);
    final targets = goal.asData?.value.$1;
    final credit = goal.asData?.value.$2 ?? 0;
    final target = targets?.energy;
    final budget = target == null ? null : target + credit;
    final remaining = budget == null ? null : budget * 1000 - energy.known;
    final ring = GoalRing(
      value: budget == null ? null : energy.known / (budget * 1000),
      label: amount(energy.known),
      detail: energy.missing > 0 ? 'known kcal · incomplete' : 'kcal consumed',
    );
    final numbers = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Daily energy', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          target == null
              ? 'Set a goal when you’re ready'
              : '${(remaining!.abs() / 1000).toStringAsFixed(0)} kcal ${remaining < 0 ? 'over' : 'remaining'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (target != null)
          Text('$target kcal goal · ~$credit exercise adjustment'),
        const SizedBox(height: 12),
        goal.when(
          data: (r) => TextButton(
            onPressed: () => changeGoal(day, r.$1),
            child: Text(target == null ? 'Set nutrition goals' : 'Edit goals'),
          ),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(goalProvider(day)),
            child: const Text('Retry loading goal'),
          ),
          loading: () => const LinearProgressIndicator(),
        ),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.maxWidth >= 500)
                Row(
                  children: [
                    ring,
                    const SizedBox(width: 32),
                    Expanded(child: numbers),
                  ],
                )
              else
                Center(
                  child: Column(
                    children: [ring, const SizedBox(height: 24), numbers],
                  ),
                ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 20,
                runSpacing: 16,
                children: [
                  for (final n in [
                    Nutrient.protein,
                    Nutrient.carbs,
                    Nutrient.fat,
                  ])
                    SizedBox(
                      width: c.maxWidth >= 500
                          ? (c.maxWidth - 40) / 3
                          : c.maxWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.label,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            formatTotal(entries, n) + goalSuffix(targets, n),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _macroProgress(entries, targets, n),
                            color: switch (n) {
                              Nutrient.protein => violet,
                              Nutrient.carbs => teal,
                              _ => amber,
                            },
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(4),
                            semanticsLabel: '${n.label} goal progress',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _macroProgress(List<DiaryEntry> entries, Targets? goals, Nutrient n) {
    final target = switch (n) {
      Nutrient.protein => goals?.protein,
      Nutrient.carbs => goals?.carbs,
      Nutrient.fat => goals?.fat,
      _ => null,
    };
    return target == null
        ? 0
        : (total(entries, n).known / (target * 1000)).clamp(0, 1);
  }

  Widget dayContent(
    List<DiaryEntry> entries,
    AsyncValue<(Targets, int)> goal,
    String day,
    int mode,
  ) {
    final prefs =
        ref.watch(preferencesProvider).asData?.value ?? <String, dynamic>{};
    final tracks = ref.watch(trackingSummaryProvider(day));
    final all = tracks.asData?.value.$1 ?? const <TrackRecord>[];
    final water = all
        .where((r) => r.kind == TrackKind.water)
        .fold(0, (n, r) => n + r.value);
    final activity = all
        .where((r) => r.kind == TrackKind.exercise)
        .fold(0, (n, r) => n + r.value);
    final weight = tracks.asData?.value.$2;
    final imperial = prefs['units'] == 'imperial';
    final tiles = <Widget>[
      MetricCard(
        title: 'Water',
        value: imperial
            ? '${(water / 29.5735295625).toStringAsFixed(1)} fl oz'
            : '$water mL',
        icon: Icons.water_drop_outlined,
        detail: goal.asData?.value.$1.water == null
            ? 'Build your hydration habit'
            : 'Goal: ${goal.asData!.value.$1.water!} mL',
        onTap: () => openTrackingKind(day, TrackKind.water),
        color: teal,
      ),
      MetricCard(
        title: 'Activity',
        value: '$activity min',
        icon: Icons.directions_walk_outlined,
        detail: prefs['activityMinutes'] == null
            ? 'Every movement counts'
            : 'Daily target: ${prefs['activityMinutes']} min',
        onTap: () => openTrackingKind(day, TrackKind.exercise),
        color: amber,
      ),
      MetricCard(
        title: 'Weight',
        value: weight == null
            ? 'Not logged'
            : imperial
            ? '${(weight / 453.59237).toStringAsFixed(1)} lb'
            : '${(weight / 1000).toStringAsFixed(1)} kg',
        icon: Icons.monitor_weight_outlined,
        detail: 'Latest measurement on or before today',
        onTap: () => openTrackingKind(day, TrackKind.weight),
        color: violet,
      ),
    ];
    final diary = <Widget>[
      if (mode == 1) draftList(day),
      for (final meal in Meal.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: mealCard(
            meal,
            entries.where((e) => e.meal == meal).toList(),
            day,
          ),
        ),
      if (mode == 1)
        OutlinedButton.icon(
          onPressed: () => editNote(day),
          icon: const Icon(Icons.edit_note),
          label: const Text('Diary notes'),
        ),
    ];
    return ListView(
      key: PageStorageKey('day-$mode'),
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode == 0
                        ? 'Hello${(prefs['name'] as String?)?.isNotEmpty == true ? ', ${prefs['name'] as String}' : ''}'
                        : ['', 'Food diary', 'Nutrition'][mode],
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (mode == 0)
                    Text(
                      'A little progress, every day.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (mode != 0)
              IconButton(
                tooltip: 'Choose diary date',
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: pickDate,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous day',
              onPressed: mode == 0 ? null : () => move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(child: Text(day, textAlign: TextAlign.center)),
            IconButton(
              tooltip: 'Next day',
              onPressed: mode == 0 ? null : () => move(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                energySummary(entries, goal, day),
                const SizedBox(height: 20),
                if (mode == 0) ...[
                  FilledButton.icon(
                    onPressed: () => selectTab(1),
                    icon: const Icon(Icons.add),
                    label: const Text('Open diary'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => openNutrition(day),
                    icon: const Icon(Icons.insights_outlined),
                    label: const Text('Nutrition analytics'),
                  ),
                  if (prefs['onboarded'] != true)
                    TextButton(
                      onPressed: openSetup,
                      child: const Text('Set up your profile'),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Foods logged: ${entries.length} · Meals: ${entries.map((e) => e.meal).toSet().length}',
                  ),
                ],
                if (mode == 2)
                  OutlinedButton.icon(
                    onPressed: () => openNutrition(day),
                    icon: const Icon(Icons.bar_chart),
                    label: const Text('View daily and weekly trends'),
                  ),
              ],
            );
            final right = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: mode == 0
                  ? [
                      if (tracks.isLoading) const LinearProgressIndicator(),
                      if (tracks.hasError)
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(trackingSummaryProvider(day)),
                          child: const Text('Could not load activity. Retry'),
                        ),
                      if (tracks.hasValue)
                        for (final tile in tiles)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: tile,
                          ),
                    ]
                  : diary,
            );
            return c.maxWidth >= 900
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: left),
                      const SizedBox(width: 24),
                      Expanded(flex: 4, child: right),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [left, const SizedBox(height: 24), right],
                  );
          },
        ),
      ],
    );
  }
}
