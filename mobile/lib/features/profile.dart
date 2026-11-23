import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/diary_store.dart';
import '../core/product_store.dart';
import '../core/tracking_store.dart';
import '../ui/design_system.dart';
import 'diary/domain.dart';
import 'tracking.dart';

Map<String, dynamic> profileDefaults(Map<String, dynamic> saved) => {
  'name': '',
  'height': null,
  'activityMinutes': null,
  'theme': 'system',
  'units': 'metric',
  'goal': 'Build habits',
  'activity': 'Moderate',
  'onboarded': false,
  ...saved,
};

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.diary,
    required this.onChanged,
    required this.onAccount,
  });
  final DiaryStore diary;
  final VoidCallback onChanged, onAccount;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final store = ProductStore(widget.diary.db);
  late Future<Map<String, dynamic>> data = store.preferences();
  bool busy = false;
  String? error;
  void reload() {
    setState(() => data = store.preferences());
    widget.onChanged();
  }

  Future<void> change(
    Map<String, dynamic> prefs,
    String key,
    String value,
  ) async {
    setState(() => busy = true);
    try {
      await store.savePreferences({...profileDefaults(prefs), key: value});
      if (mounted) reload();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save preferences. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> setup() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => OnboardingPage(diary: widget.diary)),
    );
    if (mounted) reload();
  }

  Future<void> export() async {
    setState(() => busy = true);
    try {
      final json = await store.export();
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => ExportPage(json: json)),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not prepare export. Your records are unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void info(String title, String body) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: reload,
            child: const Text('Could not load profile. Retry'),
          ),
        );
      }
      if (!snapshot.hasData) return const LoadingCards();
      final prefs = profileDefaults(snapshot.requireData);
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Profile', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          MetricCard(
            title: (prefs['name'] as String).isEmpty
                ? 'Make FLEX yours'
                : prefs['name'] as String,
            value: prefs['goal'] as String,
            icon: Icons.person_outline,
            detail: '${prefs['activity']} activity · ${prefs['units']} units',
            onTap: setup,
            color: violet,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : setup,
            icon: const Icon(Icons.tune),
            label: Text(
              prefs['onboarded'] == true
                  ? 'Edit profile and goals'
                  : 'Set up your profile',
            ),
          ),
          const SizedBox(height: 24),
          Text('Preferences', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: prefs['theme'] as String,
            decoration: const InputDecoration(labelText: 'Appearance'),
            items: [
              for (final item in ['system', 'light', 'dark'])
                DropdownMenuItem(
                  value: item,
                  child: Text(item[0].toUpperCase() + item.substring(1)),
                ),
            ],
            onChanged: busy ? null : (v) => change(prefs, 'theme', v!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: prefs['units'] as String,
            decoration: const InputDecoration(labelText: 'Display units'),
            items: const [
              DropdownMenuItem(
                value: 'metric',
                child: Text('Metric · kg and mL'),
              ),
              DropdownMenuItem(
                value: 'imperial',
                child: Text('Imperial · lb and US fl oz'),
              ),
            ],
            onChanged: busy ? null : (v) => change(prefs, 'units', v!),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Account and synchronization'),
            subtitle: Text(
              kIsWeb ? 'Browser guest edition' : 'Optional secure sign-in',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onAccount,
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Export local data'),
            subtitle: const Text('Review and copy your JSON records'),
            onTap: busy ? null : export,
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text(
              'Reminder scheduling is not available in this build',
            ),
            onTap: () => info(
              'Notifications',
              'FLEX does not request notification permissions or schedule reminders in this release. Your logging workflows work without notifications.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy and security'),
            onTap: () => info(
              'Your data, your choice',
              kIsWeb
                  ? 'Records are stored in this browser for this site. Clearing site data removes them. Exports include your local health records. Browser records do not synchronize with Android. Reloading the app offline is not currently supported.'
                  : 'Guest records are stored locally. Signing in does not transfer them. Guest transfer requires explicit selection; account synchronization is manual and feature-gated. Refresh credentials use platform secure storage. Keep exported files private.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_remove_outlined),
            title: const Text('Account deletion'),
            onTap: () => info(
              'Account deletion unavailable',
              'Cloud account erasure is not available in this release. It requires a configured service, fresh authentication, token revocation and a retention policy. No deletion request has been submitted. Export local records before removing site data or uninstalling.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help and food sources'),
            onTap: () => info(
              'Using FLEX',
              'Log food from Diary, select its serving, check the quantity, then add it. Drafts do not count toward totals. USDA FoodData Central records retain their source; custom foods are user-entered and unverified. Unknown nutrients remain unknown. Exercise calories are rough estimates and are included only when enabled in Goals. Tracker integrations and camera barcode scanning are unavailable in this build.',
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        ],
      );
    },
  );
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.diary});
  final DiaryStore diary;
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final name = TextEditingController(),
      height = TextEditingController(),
      minutes = TextEditingController();
  final form = GlobalKey<FormState>();
  Map<String, dynamic> prefs = profileDefaults({});
  int step = 0;
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final saved = profileDefaults(
        await ProductStore(widget.diary.db).preferences(),
      );
      if (!mounted) return;
      setState(() {
        prefs = saved;
        name.text = saved['name'] as String;
        height.text = saved['height']?.toString() ?? '';
        minutes.text = saved['activityMinutes']?.toString() ?? '';
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load your profile.');
    }
  }

  @override
  void dispose() {
    name.dispose();
    height.dispose();
    minutes.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ProductStore(widget.diary.db).savePreferences({
        ...prefs,
        'name': name.text.trim(),
        'height': height.text.trim().isEmpty
            ? null
            : double.parse(height.text.trim()),
        'activityMinutes': minutes.text.trim().isEmpty
            ? null
            : int.parse(minutes.text.trim()),
        'onboarded': true,
      });
      if (mounted) setState(() => step = 4);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not save your profile. Check your input and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> goals() async {
    try {
      final day = diaryDate(DateTime.now());
      final goals = await widget.diary.tracking.goals(day);
      if (!mounted) return;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              GoalsPage(store: widget.diary.tracking, day: day, initial: goals),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => error = 'Could not open goals. Try again.');
    }
  }

  Future<void> weight() async {
    await Navigator.push<TrackRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordEditor(
          kind: TrackKind.weight,
          date: DateTime.now(),
          store: widget.diary.tracking,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Make FLEX yours')),
      body: loading
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : TextButton(onPressed: load, child: Text(error!)),
            )
          : Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  LinearProgressIndicator(
                    value: (step + 1) / 5,
                    semanticsLabel: 'Setup step ${step + 1} of 5',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    [
                      'A calmer way to track',
                      'Start with you',
                      'Choose your direction',
                      'Set your own targets',
                      'You’re ready',
                    ][step],
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  if (step == 0) ...[
                    const Text(
                      'Food, hydration and movement in one place. Start offline; an account is optional. Set goals that suit you, without automatic calorie prescriptions.',
                    ),
                    const SizedBox(height: 24),
                    const MetricCard(
                      title: 'FLEX',
                      value: 'Small steps. Real records.',
                      icon: Icons.favorite_outline,
                      detail: 'Your data stays yours.',
                      color: violet,
                    ),
                  ],
                  if (step == 1) ...[
                    TextFormField(
                      controller: name,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Name (optional)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: height,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Height (cm, optional)',
                      ),
                      validator: (s) {
                        if (s == null || s.trim().isEmpty) return null;
                        final v = double.tryParse(s.trim());
                        return v == null || !v.isFinite || v < 50 || v > 250
                            ? 'Enter a height from 50 to 250 cm.'
                            : null;
                      },
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: weight,
                      icon: const Icon(Icons.monitor_weight_outlined),
                      label: const Text('Log your starting weight'),
                    ),
                  ],
                  if (step == 2) ...[
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: prefs['goal'] as String,
                      decoration: const InputDecoration(
                        labelText: 'Your focus',
                      ),
                      items: [
                        for (final v in [
                          'Maintain',
                          'Lose',
                          'Gain',
                          'Build habits',
                        ])
                          DropdownMenuItem(value: v, child: Text(v)),
                      ],
                      onChanged: (v) => prefs['goal'] = v,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: prefs['activity'] as String,
                      decoration: const InputDecoration(
                        labelText: 'Usual activity level',
                      ),
                      items: [
                        for (final v in ['Low', 'Moderate', 'High'])
                          DropdownMenuItem(value: v, child: Text(v)),
                      ],
                      onChanged: (v) => prefs['activity'] = v,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Activity target (minutes/day, optional)',
                      ),
                      validator: (s) {
                        if (s == null || s.trim().isEmpty) return null;
                        final n = int.tryParse(s.trim());
                        return n == null || n < 1 || n > 1440
                            ? 'Enter 1–1440 minutes.'
                            : null;
                      },
                    ),
                  ],
                  if (step == 3) ...[
                    const Text(
                      'Choose energy, macros, water and goal weight. Existing dated targets stay in place until you save changes.',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: goals,
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Configure nutrition and water goals'),
                    ),
                  ],
                  if (step == 4) ...[
                    const Icon(
                      Icons.check_circle_outline,
                      color: teal,
                      size: 72,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your profile is saved. Continue logging at your own pace. You can change preferences and goals at any time.',
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (error != null)
                    Semantics(liveRegion: true, child: Text(error!)),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            if (step == 4) {
                              Navigator.pop(context);
                              return;
                            }
                            if (!form.currentState!.validate()) return;
                            if (step == 3) {
                              finish();
                            } else {
                              setState(() => step++);
                            }
                          },
                    child: Text(
                      busy
                          ? 'Saving…'
                          : step == 4
                          ? 'Go to FLEX'
                          : step == 3
                          ? 'Finish setup'
                          : 'Continue',
                    ),
                  ),
                  if (step > 0 && step < 4)
                    TextButton(
                      onPressed: busy ? null : () => setState(() => step--),
                      child: const Text('Back'),
                    ),
                ],
              ),
            ),
    ),
  );
}

class ExportPage extends StatelessWidget {
  const ExportPage({super.key, required this.json});
  final String json;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Export local data')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'This export contains your local diary, drafts, tracking, goals, profile and collections. It excludes authentication credentials. Store it privately. It is a readable data export, not a database restore file.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copy JSON export'),
          onPressed: () async {
            try {
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Export copied.')));
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not copy. Select and copy the text below.',
                    ),
                  ),
                );
              }
            }
          },
        ),
        const SizedBox(height: 16),
        SelectableText(json),
      ],
    ),
  );
}
