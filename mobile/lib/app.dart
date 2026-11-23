import 'core/tracking_store.dart';
import 'core/product_store.dart';
import 'features/profile.dart';
import 'features/custom_food.dart';
import 'features/nutrition.dart';
import 'ui/design_system.dart';
import 'features/tracking.dart';
import 'dart:async';
import 'core/catalog.dart';
import 'core/service_api.dart';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/diary_store.dart';
import 'core/sync_http.dart';
import 'core/account_ui.dart';
import 'core/guest_transfer.dart';
import 'features/diary/domain.dart';

part 'features/home_content.dart';

final trackingSummaryProvider = FutureProvider.autoDispose
    .family<(List<TrackRecord>, int?), String>((ref, day) async {
      final store = (await ref.watch(storeProvider.future)).tracking;
      return (await store.records(day, day), await store.latestWeight(day));
    });

final storeProvider = FutureProvider<DiaryStore>((ref) {
  final account = ref.watch(
    accountProvider.select((state) => state.asData?.value),
  );
  return DiaryStore.open(accountId: account);
});
final diaryProvider = FutureProvider.family<List<DiaryEntry>, String>(
  (ref, day) async => (await ref.watch(storeProvider.future)).read(day),
);
final goalProvider = FutureProvider.autoDispose.family<(Targets, int), String>((
  ref,
  day,
) async {
  final store = (await ref.watch(storeProvider.future)).tracking;
  final goals = await store.goals(day);
  final credit = goals.exerciseCredit
      ? (await store.records(day, day))
            .where((r) => r.kind == TrackKind.exercise)
            .fold(0, (n, r) => n + (r.energy ?? 0))
      : 0;
  return (goals, credit);
});

final draftsProvider = FutureProvider.autoDispose.family<List<Draft>, String>(
  (ref, day) async => (await ref.watch(storeProvider.future)).drafts(day),
);
final searchProvider = FutureProvider.autoDispose.family<List<Food>, String>(
  (ref, query) async => (await ref.watch(storeProvider.future)).search(query),
);

final onlineCatalogProvider = FutureProvider.autoDispose
    .family<List<Food>, String>((ref, query) async {
      final id = ref.watch(accountProvider).asData?.value;
      if (id == null) throw StateError('Sign in to search the online catalog.');
      final api = ServiceApi(
        ref.watch(identityConfigProvider).api,
        () => ref.read(accountProvider.notifier).tokenFor(id),
      );
      ref.onDispose(api.close);
      final response = await api.call(
        '/v1/catalog',
        query: {'q': query.trim(), 'limit': '50'},
      );
      return [
        for (final row in response['items'] as List)
          Food(
            row['id'] as String,
            row['name'] as String,
            {
              Nutrient.energy: (row['energy_kcal'] as int) * 1000,
              Nutrient.protein: row['protein_mg'] as int,
              Nutrient.carbs: row['carbs_mg'] as int,
              Nutrient.fat: row['fat_mg'] as int,
              Nutrient.fiber: null,
            },
            [
              const Serving('100 g', 100),
              Serving(
                '${row['serving_grams']} g serving',
                row['serving_grams'] as int,
              ),
            ],
            source: 'FLEX verified catalog',
            version: 'catalog-${row['revision']}',
          ),
      ];
    });

final foodCollectionProvider = FutureProvider.autoDispose
    .family<List<Food>, String>((ref, kind) async {
      final store = ProductStore((await ref.watch(storeProvider.future)).db);
      return kind == 'Favorites'
          ? store.favorites()
          : store.loggedFoods(frequent: kind == 'Frequent');
    });
final savedMealsProvider = FutureProvider.autoDispose(
  (ref) async =>
      ProductStore((await ref.watch(storeProvider.future)).db).savedMeals(),
);

// Explicit development entry point. The guest UI does not schedule sync.
final applyDiaryChangesProvider = Provider((ref) {
  return (DiaryStore expected, SyncHttp transport) async {
    final inbox = expected.inbox;
    if (inbox == null ||
        !identical(await ref.read(storeProvider.future), expected)) {
      throw StateError('The active store is not the requested account.');
    }
    // Bound a refresh even when a remote producer continuously appends changes.
    for (var batch = 0; batch < 20; batch++) {
      final position = await inbox.cursor();
      final page = await transport.changes(inbox.accountId, position);
      if (!ref.mounted ||
          !identical(await ref.read(storeProvider.future), expected)) {
        return;
      }
      if (page.isEmpty) return;
      final applied = await inbox.apply(page);
      if (!ref.mounted ||
          !identical(await ref.read(storeProvider.future), expected)) {
        return;
      }
      if (applied > position) {
        ref.invalidate(diaryProvider);
        ref.invalidate(goalProvider);
      }
      if (page.length < 50 || applied <= position) return;
    }
  };
});

final preferencesProvider = FutureProvider<Map<String, dynamic>>(
  (ref) async =>
      ProductStore((await ref.watch(storeProvider.future)).db).preferences(),
);

String amount(int value) {
  final whole = value ~/ 1000;
  final fraction = (value % 1000)
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}

class FitnessApp extends ConsumerWidget {
  const FitnessApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    key: ValueKey(
      ref.watch(accountProvider.select((state) => state.asData?.value)),
    ),
    title: 'FLEX',
    darkTheme: flexTheme(Brightness.dark),
    theme: flexTheme(Brightness.light),
    themeMode: switch (ref.watch(preferencesProvider).asData?.value['theme']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    },
    home: const DiaryHome(),
  );
}

class DiaryHome extends ConsumerStatefulWidget {
  const DiaryHome({super.key});
  @override
  ConsumerState<DiaryHome> createState() => _DiaryHomeState();
}

class _DiaryHomeState extends ConsumerState<DiaryHome> {
  final collapsedMeals = <Meal>{};
  var date = DateTime.now();
  var tab = 0;

  void move(int delta) =>
      setState(() => date = DateTime(date.year, date.month, date.day + delta));

  Future<String> _transferGuest() async {
    final account = await ref.read(storeProvider.future);
    final id = account.outbox?.accountId;
    if (id == null || !mounted) throw StateError('Verified account required.');
    String? active() =>
        mounted ? ref.read(accountProvider).asData?.value : null;
    if (active() != id) throw StateError('Account changed.');
    final guest = await DiaryStore.open();
    final transfer = GuestTransfer(guest, account);
    final snapshots = await transfer.preview();
    if (!mounted || active() != id) throw StateError('Account changed.');
    if (snapshots.values.every((items) => items.isEmpty)) {
      return 'No guest records to transfer.';
    }
    if (!context.mounted) throw StateError('View closed.');
    final selected = <String>{};
    final approved = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Transfer guest records?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose what to copy to this account. Guest originals and drafts stay on this device. Manual sync uploads the queued copies.',
                ),
                for (final group in snapshots.entries.where(
                  (entry) => entry.value.isNotEmpty,
                ))
                  CheckboxListTile(
                    title: Text('${group.key} (${group.value.length})'),
                    value: selected.contains(group.key),
                    onChanged: (checked) => refresh(() {
                      if (checked == true) {
                        selected.add(group.key);
                      } else {
                        selected.remove(group.key);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep guest data local'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected.toSet()),
              child: const Text('Queue selected records'),
            ),
          ],
        ),
      ),
    );
    if (approved == null) return 'Guest data stays local.';
    final count = await transfer.stage(snapshots, approved, active);
    if (mounted && active() == id) {
      ref.invalidate(diaryProvider);
      ref.invalidate(goalProvider);
    }
    return '$count record(s) queued. Use manual sync to upload.';
  }

  Future<String> _syncDiary() async {
    final store = await ref.read(storeProvider.future);
    final outbox = store.outbox;
    if (outbox == null) throw StateError('Account required.');
    final account = ref.read(accountProvider.notifier);
    final config = ref.read(identityConfigProvider);
    final transport = SyncHttp(Uri.parse(config.api), account.tokenFor);
    try {
      await outbox.drain(
        signedInAccount: () =>
            mounted ? ref.read(accountProvider).asData?.value : null,
        submit: transport.submit,
      );
      if (!mounted) throw StateError('Account view closed.');
      await ref.read(applyDiaryChangesProvider)(store, transport);
      if (!mounted ||
          ref.read(accountProvider).asData?.value != outbox.accountId) {
        throw StateError('Account session changed.');
      }
      final counts = await outbox.statusCounts();
      final incomingConflicts = await store.db.query(
        'sync_remote_record',
        columns: ['record_id'],
        where: 'account_id = ? AND conflict = 1',
        whereArgs: [outbox.accountId],
        limit: 1,
      );
      if ((counts['conflict'] ?? 0) != 0 || incomingConflicts.isNotEmpty) {
        return 'Conflict needs review.';
      }
      if ((counts['rejected'] ?? 0) != 0) return 'Some changes were rejected.';
      final pending = counts['pending'] ?? 0;
      return pending > 0
          ? '$pending pending uploads'
          : 'Diary updated from the server.';
    } finally {
      transport.close();
    }
  }

  void selectTab(int index) {
    if (index == 2) {
      quickAdd();
      return;
    }
    setState(() => tab = index);
  }

  void account() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AccountPage(
        sync: const bool.fromEnvironment('FLEX_ENABLE_DIARY_SYNC')
            ? _syncDiary
            : null,
        transfer: const bool.fromEnvironment('FLEX_ENABLE_GUEST_TRANSFER')
            ? _transferGuest
            : null,
      ),
    ),
  );
  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (mounted && picked != null) setState(() => date = picked);
  }

  Future<void> openSetup() async {
    await openPage((db) => OnboardingPage(diary: db));
    if (mounted) {
      ref.invalidate(preferencesProvider);
      ref.invalidate(goalProvider);
      ref.invalidate(trackingSummaryProvider);
    }
  }

  Future<void> openNutrition(String day) =>
      openPage((db) => NutritionPage(diary: db, date: DateTime.parse(day)));
  Future<void> openTrackingKind(String day, TrackKind kind) async {
    await openPage(
      (db) =>
          TrackingPage(diary: db, date: DateTime.parse(day), initialKind: kind),
    );
    if (mounted) {
      ref.invalidate(trackingSummaryProvider);
      ref.invalidate(goalProvider);
    }
  }

  Future<void> openPage(Widget Function(DiaryStore) build) async {
    try {
      final db = await ref.read(storeProvider.future);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => build(db)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this view. Try again.')),
        );
      }
    }
  }

  Future<void> quickAdd() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('What would you like to log?')),
            for (final row in [
              ('Food', Icons.restaurant_outlined),
              ('Water', Icons.water_drop_outlined),
              ('Weight', Icons.monitor_weight_outlined),
              ('Exercise', Icons.directions_run),
            ])
              ListTile(
                leading: Icon(row.$2),
                title: Text(row.$1),
                onTap: () => Navigator.pop(context, row.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final day = tab == 0 ? diaryDate(DateTime.now()) : diaryDate(date);
    if (choice == 'Food') {
      final meal = await showModalBottomSheet<Meal>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in Meal.values)
                ListTile(
                  title: Text(m.name),
                  onTap: () => Navigator.pop(context, m),
                ),
            ],
          ),
        ),
      );
      if (!mounted || meal == null) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => SearchPage(day: day, meal: meal),
        ),
      );
    } else {
      try {
        final db = await ref.read(storeProvider.future);
        if (!mounted) return;
        final kind = switch (choice) {
          'Water' => TrackKind.water,
          'Weight' => TrackKind.weight,
          _ => TrackKind.exercise,
        };
        await Navigator.push<TrackRecord>(
          context,
          MaterialPageRoute(
            builder: (_) => RecordEditor(
              kind: kind,
              date: DateTime.parse(day),
              store: db.tracking,
              imperial:
                  ref.read(preferencesProvider).asData?.value['units'] ==
                  'imperial',
            ),
          ),
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open logging. Try again.')),
          );
        }
      }
    }
    if (mounted) {
      ref.invalidate(trackingSummaryProvider);
      ref.invalidate(goalProvider);
    }
  }

  Future<void> editNote(String day) async {
    try {
      final db = await ref.read(storeProvider.future);
      final store = ProductStore(db.db);
      final initial = await store.note(day);
      if (!mounted) return;
      final controller = TextEditingController(text: initial);
      String? error;
      bool busy = false;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: const Text('Diary notes'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    maxLength: 2000,
                    maxLines: 5,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Notes for this day',
                    ),
                  ),
                  if (error != null) Text(error!),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        refresh(() => busy = true);
                        try {
                          await store.saveNote(day, controller.text);
                          if (context.mounted) Navigator.pop(context);
                        } catch (_) {
                          if (context.mounted) {
                            refresh(() {
                              busy = false;
                              error = 'Could not save. Retry.';
                            });
                          }
                        }
                      },
                child: const Text('Save note'),
              ),
            ],
          ),
        ),
      );
      controller.dispose();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open notes. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = tab == 0 ? diaryDate(DateTime.now()) : diaryDate(date);
    final data = ref.watch(diaryProvider(day));
    final goal = ref.watch(goalProvider(day));
    final store = ref.watch(storeProvider);
    const labels = ['Home', 'Diary', 'Add', 'Progress', 'Profile'];
    const icons = [
      Icons.space_dashboard_outlined,
      Icons.calendar_today_outlined,
      Icons.add_circle_outline,
      Icons.insights_outlined,
      Icons.person_outline,
    ];
    final content = store.when(
      loading: () => const LoadingCards(),
      error: (_, _) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(storeProvider),
          child: const Text('Could not load your diary. Retry'),
        ),
      ),
      data: (db) => IndexedStack(
        index: tab,
        children: [
          for (var mode = 0; mode < 3; mode++)
            data.when(
              loading: () => const LoadingCards(),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(diaryProvider(day)),
                  child: const Text('Could not load your diary. Retry'),
                ),
              ),
              data: (entries) => dayContent(entries, goal, day, mode),
            ),
          ProgressPage(diary: db, end: date),
          ProfilePage(
            diary: db,
            onChanged: () {
              ref.invalidate(preferencesProvider);
              ref.invalidate(goalProvider);
            },
            onAccount: account,
          ),
        ],
      ),
    );
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => tab = 0);
      },
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 840;
          return Scaffold(
            appBar: tab == 3
                ? null
                : AppBar(
                    title: const Text('FLEX'),
                    actions: [
                      IconButton(
                        tooltip: 'Nutrition',
                        icon: const Icon(Icons.pie_chart_outline),
                        onPressed: () => openNutrition(day),
                      ),
                      IconButton(
                        tooltip: 'Account',
                        icon: const Icon(Icons.manage_accounts_outlined),
                        onPressed: account,
                      ),
                      IconButton(
                        tooltip: 'Fitness tracking',
                        icon: const Icon(Icons.monitor_heart_outlined),
                        onPressed: () => openTracking(day),
                      ),
                    ],
                  ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    height:
                        80 +
                        (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(
                              0,
                              36,
                            ) *
                            2,
                    selectedIndex: tab,
                    onDestinationSelected: selectTab,
                    destinations: [
                      for (var i = 0; i < labels.length; i++)
                        NavigationDestination(
                          icon: Icon(icons[i]),
                          label: labels[i],
                        ),
                    ],
                  ),
            body: SafeArea(
              child: Row(
                children: [
                  if (wide)
                    NavigationRail(
                      selectedIndex: tab,
                      onDestinationSelected: selectTab,
                      extended: c.maxWidth >= 1200,
                      labelType: c.maxWidth >= 1200
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      destinations: [
                        for (var i = 0; i < labels.length; i++)
                          NavigationRailDestination(
                            icon: Icon(icons[i]),
                            label: Text(labels[i]),
                          ),
                      ],
                    ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: content,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget draftList(String day) => ref
      .watch(draftsProvider(day))
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => TextButton(
          onPressed: () => ref.invalidate(draftsProvider(day)),
          child: const Text('Could not load drafts. Retry'),
        ),
        data: (drafts) => Column(
          children: [
            for (final draft in drafts)
              ListTile(
                title: Text('Resume draft: ${draft.food.name}'),
                subtitle: Text(
                  '${draft.meal.name} · ${draft.quantity} serving(s)',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => EntryEditor(
                      food: draft.food,
                      meal: draft.meal,
                      day: day,
                      draft: draft,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  String formatTotal(List<DiaryEntry> entries, Nutrient n) {
    final value = total(entries, n);
    if (entries.isNotEmpty && value.missing == entries.length) return 'Unknown';
    return '${amount(value.known)} ${n.unit}${value.missing > 0 ? ' · incomplete' : ''}';
  }

  Widget mealCard(Meal meal, List<DiaryEntry> entries, String day) => Card(
    child: AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(
                collapsedMeals.contains(meal)
                    ? Icons.expand_more
                    : Icons.expand_less,
              ),
              onTap: () => setState(() {
                if (!collapsedMeals.remove(meal)) collapsedMeals.add(meal);
              }),
              title: Text(meal.name[0].toUpperCase() + meal.name.substring(1)),
              subtitle: Text(formatTotal(entries, Nutrient.energy)),
              trailing: tab == 1
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Add food to ${meal.name}',
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SearchPage(day: day, meal: meal),
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Meal actions',
                          onSelected: (action) =>
                              mealAction(action, meal, entries, day),
                          itemBuilder: (_) => [
                            if (entries.isNotEmpty)
                              const PopupMenuItem(
                                value: 'copy',
                                child: Text('Copy to another date'),
                              ),
                            if (entries.isNotEmpty)
                              const PopupMenuItem(
                                value: 'save',
                                child: Text('Save this meal'),
                              ),
                            const PopupMenuItem(
                              value: 'load',
                              child: Text('Add a saved meal'),
                            ),
                          ],
                        ),
                      ],
                    )
                  : null,
            ),
            if (!collapsedMeals.contains(meal)) ...[
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('No entries'),
                ),
              if (tab == 2 && entries.isNotEmpty)
                for (final n in Nutrient.values.skip(1))
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 3,
                    ),
                    child: Text('${n.label}  ${formatTotal(entries, n)}'),
                  ),
              if (tab == 1)
                for (final entry in entries)
                  ListTile(
                    title: Text(entry.food.name),
                    subtitle: Text(
                      '${amount(entry.quantity)} × ${entry.serving.label}',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<bool>(
                        builder: (_) => EntryEditor(
                          food: entry.food,
                          meal: meal,
                          day: day,
                          existing: entry,
                        ),
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Actions for ${entry.food.name}',
                      onSelected: (action) => action == 'delete'
                          ? deleteEntry(entry)
                          : duplicateEntry(entry),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Duplicate entry'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete entry'),
                        ),
                      ],
                    ),
                  ),
            ],
          ],
        ),
      ),
    ),
  );

  Future<void> duplicateEntry(DiaryEntry entry) async {
    try {
      await (await ref.read(
        storeProvider.future,
      )).addMeal([entry], entry.day, entry.meal);
      if (!mounted) return;
      ref.invalidate(diaryProvider(entry.day));
      unawaited(HapticFeedback.lightImpact());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry duplicated.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not duplicate this entry.')),
        );
      }
    }
  }

  Future<void> mealAction(
    String action,
    Meal meal,
    List<DiaryEntry> entries,
    String day,
  ) async {
    if (action == 'load') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SearchPage(day: day, meal: meal, collection: 'Saved meals'),
        ),
      );
      return;
    }
    try {
      final db = await ref.read(storeProvider.future);
      if (!mounted) return;
      if (action == 'copy') {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.parse(day).add(const Duration(days: 1)),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked == null || !mounted) return;
        final target = diaryDate(picked);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Copy this meal?'),
            content: Text(
              'Add ${entries.length} foods to ${meal.name} on $target? Existing foods stay in place.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Copy meal'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await db.addMeal(entries, target, meal);
        if (mounted) {
          ref.invalidate(diaryProvider(target));
          ref.invalidate(foodCollectionProvider);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Meal copied to $target.')));
        }
      } else {
        final input = TextEditingController(text: meal.name);
        String? error;
        bool saving = false;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
            builder: (context, refresh) => AlertDialog(
              title: const Text('Save meal'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: input,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Meal name'),
                    enabled: !saving,
                  ),
                  if (error != null) Text(error!),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (input.text.trim().isEmpty) {
                            refresh(() => error = 'Enter a meal name.');
                            return;
                          }
                          refresh(() => saving = true);
                          try {
                            await ProductStore(
                              db.db,
                            ).saveMeal(input.text, entries);
                            if (context.mounted) {
                              ref.invalidate(savedMealsProvider);
                              Navigator.pop(context);
                            }
                          } catch (_) {
                            if (context.mounted) {
                              refresh(() {
                                saving = false;
                                error = 'Could not save this meal. Retry.';
                              });
                            }
                          }
                        },
                  child: const Text('Save meal'),
                ),
              ],
            ),
          ),
        );
        input.dispose();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not complete the meal action. No partial copy was saved.',
            ),
          ),
        );
      }
    }
  }

  Future<void> deleteEntry(DiaryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete diary entry?'),
        content: Text(entry.food.name),
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
    if (!mounted || confirmed != true) return;
    try {
      await (await ref.read(storeProvider.future)).remove(entry.id);
      if (mounted) ref.invalidate(diaryProvider(entry.day));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete entry.')),
        );
      }
    }
  }

  String goalSuffix(Targets? goals, Nutrient nutrient) {
    final target = switch (nutrient) {
      Nutrient.protein => goals?.protein,
      Nutrient.carbs => goals?.carbs,
      Nutrient.fat => goals?.fat,
      _ => null,
    };
    return target == null ? '' : ' / $target g goal';
  }

  Future<void> openTracking(String day) async {
    try {
      final db = await ref.read(storeProvider.future);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => TrackingPage(diary: db, date: DateTime.parse(day)),
        ),
      );
      if (mounted) ref.invalidate(goalProvider(day));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open tracking.')),
        );
      }
    }
  }

  Future<void> changeGoal(String day, Targets goals) async {
    try {
      final db = await ref.read(storeProvider.future);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<bool>(
          builder: (_) =>
              GoalsPage(store: db.tracking, day: day, initial: goals),
        ),
      );
      if (mounted) ref.invalidate(goalProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open goals.')));
      }
    }
  }
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({
    super.key,
    required this.day,
    required this.meal,
    this.collection = 'Search',
  });
  final String day;
  final Meal meal;
  final String collection;
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  var query = '';
  late String collection = widget.collection;
  bool savingMeal = false;
  Timer? debounce;

  Future<void> choose(Food food) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EntryEditor(food: food, meal: widget.meal, day: widget.day),
      ),
    );
    if (mounted && saved == true) {
      ref.invalidate(foodCollectionProvider);
      Navigator.pop(context);
    }
  }

  Future<void> toggleFavorite(Food food, bool selected) async {
    try {
      final db = await ref.read(storeProvider.future);
      await ProductStore(db.db).favorite(food, selected: !selected);
      if (mounted) ref.invalidate(foodCollectionProvider('Favorites'));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update favorite. Retry.')),
        );
      }
    }
  }

  Future<void> custom() async {
    try {
      final db = await ref.read(storeProvider.future);
      if (!mounted) return;
      final food = await Navigator.push<Food>(
        context,
        MaterialPageRoute(builder: (_) => CustomFoodPage(store: db)),
      );
      if (mounted && food != null) {
        ref.invalidate(searchProvider);
        await choose(food);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open custom food. Retry.')),
        );
      }
    }
  }

  Future<void> addSavedMeal(Map<String, Object?> row) async {
    if (savingMeal) return;
    setState(() => savingMeal = true);
    try {
      final db = await ref.read(storeProvider.future);
      final entries = ProductStore(
        db.db,
      ).mealEntries(row['payload'] as String, widget.day, widget.meal);
      await db.addMeal(entries, widget.day, widget.meal);
      if (mounted) {
        ref.invalidate(diaryProvider(widget.day));
        ref.invalidate(foodCollectionProvider);
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not add this meal. No partial meal was saved.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => savingMeal = false);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = collection == 'Search'
        ? ref.watch(searchProvider(query))
        : collection == 'Online catalog'
        ? ref.watch(onlineCatalogProvider(query))
        : ref.watch(foodCollectionProvider(collection));
    final foods = results.value ?? const <Food>[];
    final favorites =
        ref.watch(foodCollectionProvider('Favorites')).asData?.value ??
        const <Food>[];
    return Scaffold(
      appBar: AppBar(title: Text('Add food · ${widget.meal.name}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              collection == 'Online catalog'
                  ? 'Verified online foods · internet required'
                  : 'Offline catalog · source shown on each food',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in [
                  'Search',
                  'Recent',
                  'Frequent',
                  'Favorites',
                  'Saved meals',
                  if (ref.watch(accountProvider).asData?.value != null)
                    'Online catalog',
                ])
                  ChoiceChip(
                    label: Text(item),
                    selected: collection == item,
                    onSelected: (_) => setState(() => collection = item),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (collection == 'Search' || collection == 'Online catalog')
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search foods',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (text) {
                  debounce?.cancel();
                  debounce = Timer(
                    const Duration(milliseconds: 200),
                    () => setState(() => query = text),
                  );
                },
              ),
            if (collection == 'Search')
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: custom,
                    icon: const Icon(Icons.add),
                    label: const Text('Create custom food'),
                  ),
                  TextButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Barcode scanning unavailable'),
                        content: const Text(
                          'Camera scanning is not installed in this build. Search foods by name or enter a custom food from its label.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Search by name'),
                          ),
                        ],
                      ),
                    ),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Barcode options'),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            if (collection == 'Saved meals')
              ref
                  .watch(savedMealsProvider)
                  .when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => TextButton(
                      onPressed: () => ref.invalidate(savedMealsProvider),
                      child: const Text('Could not load saved meals. Retry'),
                    ),
                    data: (meals) => Column(
                      children: [
                        if (meals.isEmpty)
                          const Text(
                            'No saved meals. Save a logged meal from its diary menu.',
                          ),
                        if (savingMeal) const LinearProgressIndicator(),
                        for (final meal in meals)
                          ListTile(
                            title: Text(meal['name'] as String),
                            subtitle: const Text('Add all foods to this meal'),
                            trailing: const Icon(Icons.add_circle_outline),
                            onTap: savingMeal ? null : () => addSavedMeal(meal),
                          ),
                      ],
                    ),
                  ),
            if (collection != 'Saved meals' && results.isLoading)
              const LinearProgressIndicator(),
            if (collection != 'Saved meals' && results.hasError)
              TextButton(
                onPressed: () {
                  if (collection == 'Search') {
                    ref.invalidate(searchProvider(query));
                  } else if (collection == 'Online catalog') {
                    ref.invalidate(onlineCatalogProvider(query));
                  } else {
                    ref.invalidate(foodCollectionProvider(collection));
                  }
                },
                child: const Text('Could not search the catalog. Retry'),
              ),
            if (collection != 'Saved meals' &&
                results.hasValue &&
                foods.isEmpty)
              Text(
                collection == 'Search'
                    ? 'No matching foods. Try a different search.'
                    : 'No foods here yet. Log a food or add a favorite to begin.',
              ),
            if (collection != 'Saved meals')
              for (final food in foods)
                ListTile(
                  title: Text(food.name),
                  subtitle: Text(food.source),
                  trailing: IconButton(
                    tooltip:
                        favorites.any(
                          (f) => f.id == food.id && f.source == food.source,
                        )
                        ? 'Remove favorite'
                        : 'Add favorite',
                    icon: Icon(
                      favorites.any(
                            (f) => f.id == food.id && f.source == food.source,
                          )
                          ? Icons.star
                          : Icons.star_outline,
                    ),
                    onPressed: () => toggleFavorite(
                      food,
                      favorites.any(
                        (f) => f.id == food.id && f.source == food.source,
                      ),
                    ),
                  ),
                  onTap: () => choose(food),
                ),
          ],
        ),
      ),
    );
  }
}

class EntryEditor extends ConsumerStatefulWidget {
  const EntryEditor({
    super.key,
    required this.food,
    required this.meal,
    required this.day,
    this.existing,
    this.draft,
  });
  final Food food;
  final Meal meal;
  final String day;
  final DiaryEntry? existing;
  final Draft? draft;
  @override
  ConsumerState<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends ConsumerState<EntryEditor> {
  late Meal meal = widget.draft?.meal ?? widget.meal;
  late Serving serving =
      widget.existing?.serving ??
      widget.draft?.serving ??
      widget.food.servings.first;
  late String quantity =
      widget.draft?.quantity ?? amount(widget.existing?.quantity ?? 1000);
  late final id =
      widget.existing?.id ??
      widget.draft?.id ??
      DateTime.now().microsecondsSinceEpoch.toString();
  var saving = false;
  String? error;

  Future<void> pending = Future.value();

  @override
  void initState() {
    super.initState();
    remember();
  }

  void remember() {
    if (widget.existing != null) return;
    final draft = Draft(id, widget.day, meal, widget.food, serving, quantity);
    final store = ref.read(storeProvider.future);
    pending = pending.then((_) async {
      try {
        await (await store).saveDraft(draft);
        if (mounted) ref.invalidate(draftsProvider(draft.day));
      } catch (_) {
        if (mounted) {
          setState(() => error = 'Could not save draft. Retry before leaving.');
        }
      }
    });
  }

  Future<void> finishDraft({required bool discard}) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await pending;
      final store = await ref.read(storeProvider.future);
      if (discard) {
        await store.discard(id);
      } else {
        await store.saveDraft(
          Draft(id, widget.day, meal, widget.food, serving, quantity),
        );
      }
      if (!mounted) return;
      ref.invalidate(draftsProvider(widget.day));
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not update draft. Retry.';
        });
      }
    }
  }

  Future<void> save(int value) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final store = await ref.read(storeProvider.future);
      await pending;
      await store.save(
        DiaryEntry(id, widget.day, meal, widget.food, serving, value, {}),
        editing: widget.existing != null,
      );
      if (!mounted) return;
      ref.invalidate(diaryProvider(widget.day));
      ref.invalidate(draftsProvider(widget.day));
      Navigator.pop(context, true);
    } catch (failure) {
      developer.log(
        'Diary write failed (${failure.runtimeType})',
        name: 'fitness_diary',
      );
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not save. Your changes are still here.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = parseQuantity(quantity);
    final preview = value == null ? null : widget.food.scale(serving, value);
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.existing == null ? 'Serving preview' : 'Edit entry',
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.food.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                '${widget.food.source} · ${widget.food.version} · ${widget.day}',
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<Serving>(
                isExpanded: true,
                initialValue: serving,
                decoration: const InputDecoration(labelText: 'Serving'),
                items: [
                  for (final item in widget.food.servings)
                    DropdownMenuItem(value: item, child: Text(item.label)),
                ],
                onChanged: saving
                    ? null
                    : (item) {
                        setState(() => serving = item!);
                        remember();
                      },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: quantity,
                enabled: !saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  errorText: value == null
                      ? 'Enter 0.001–100, up to three decimal places.'
                      : null,
                ),
                onChanged: (text) {
                  setState(() => quantity = text);
                  remember();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Meal>(
                isExpanded: true,
                initialValue: meal,
                decoration: const InputDecoration(labelText: 'Meal'),
                items: [
                  for (final item in Meal.values)
                    DropdownMenuItem(value: item, child: Text(item.name)),
                ],
                onChanged: saving
                    ? null
                    : (item) {
                        setState(() => meal = item!);
                        remember();
                      },
              ),
              const SizedBox(height: 20),
              if (preview != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final n in Nutrient.values)
                          Text(
                            '${n.label}  ${preview[n] == null ? 'Unknown' : '${amount(preview[n]!)} ${n.unit}'}',
                          ),
                      ],
                    ),
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Semantics(liveRegion: true, child: Text(error!)),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: value == null || saving ? null : () => save(value),
                child: Text(
                  saving
                      ? 'Saving…'
                      : widget.existing == null
                      ? 'Add to diary'
                      : 'Save changes',
                ),
              ),
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              if (widget.existing == null) ...[
                TextButton(
                  onPressed: saving ? null : () => finishDraft(discard: false),
                  child: const Text('Save draft'),
                ),
                TextButton(
                  onPressed: saving ? null : () => finishDraft(discard: true),
                  child: const Text('Discard draft'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
