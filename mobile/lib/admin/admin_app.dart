import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/firebase_identity.dart';
import '../core/firebase_sign_in.dart';
import '../core/service_api.dart';
import '../ui/design_system.dart';

const adminRoutes = [
  '/overview',
  '/users',
  '/catalog',
  '/analytics',
  '/operations',
  '/settings',
];
const adminLabels = [
  'Overview',
  'Users',
  'Food catalog',
  'Analytics',
  'Operations',
  'Settings',
];
const adminIcons = [
  Icons.space_dashboard_outlined,
  Icons.people_outline,
  Icons.restaurant_outlined,
  Icons.insights_outlined,
  Icons.monitor_heart_outlined,
  Icons.settings_outlined,
];

class FlexAdmin extends StatefulWidget {
  const FlexAdmin({super.key});
  @override
  State<FlexAdmin> createState() => _FlexAdminState();
}

class _FlexAdminState extends State<FlexAdmin> {
  ThemeMode theme = ThemeMode.system;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FLEX Admin',
    theme: flexTheme(Brightness.light),
    darkTheme: flexTheme(Brightness.dark),
    themeMode: theme,
    initialRoute: '/overview',
    onGenerateRoute: (settings) {
      final index = adminRoutes.indexOf(settings.name ?? '');
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => AdminAccess(
          section: index < 0 ? 0 : index,
          onTheme: () => setState(
            () => theme = theme == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark,
          ),
        ),
      );
    },
  );
}

class AdminAccess extends StatefulWidget {
  const AdminAccess({super.key, required this.section, required this.onTheme});
  final int section;
  final VoidCallback onTheme;
  @override
  State<AdminAccess> createState() => _AdminAccessState();
}

class _AdminAccessState extends State<AdminAccess> {
  StreamSubscription<User?>? authSubscription;
  int authGeneration = 0;
  ServiceApi? api;
  Map<String, dynamic>? identity;
  String? error;
  bool loading = false;
  static const endpoint = String.fromEnvironment('FLEX_API_URL');
  @override
  void initState() {
    super.initState();
    if (FirebaseIdentity.ready && endpoint.isNotEmpty) {
      api = ServiceApi(
        endpoint,
        () async => FirebaseIdentity.auth.currentUser?.getIdToken(),
      );
      authSubscription = FirebaseIdentity.auth.authStateChanges().listen((
        user,
      ) {
        authGeneration++;
        if (mounted) {
          setState(() {
            identity = null;
            loading = false;
          });
        }
        if (user != null) unawaited(check());
      });
    }
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    api?.close();
    super.dispose();
  }

  Future<void> check() async {
    if (loading) return;
    final generation = authGeneration;
    final uid = FirebaseIdentity.auth.currentUser?.uid;
    if (uid == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await api!.call('/v1/admin/me');
      if (mounted &&
          generation == authGeneration &&
          FirebaseIdentity.auth.currentUser?.uid == uid) {
        setState(() => identity = result);
      }
    } catch (e) {
      if (mounted && generation == authGeneration) {
        setState(
          () => error = e is ServiceError
              ? e.code
              : 'Cannot reach the administration service.',
        );
      }
    } finally {
      if (mounted && generation == authGeneration) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> signOut() async {
    authGeneration++;
    setState(() => identity = null);
    await FirebaseIdentity.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (identity != null) {
      return AdminShell(
        api: api!,
        identity: identity!,
        section: widget.section,
        onTheme: widget.onTheme,
        onSignOut: signOut,
      );
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.hexagon_outlined, color: violet, size: 46),
                const SizedBox(height: 24),
                Text(
                  'FLEX Admin',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Nutrition platform operations',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (api == null)
                  const Text(
                    'Administration is not configured in this build. A verified Firebase configuration and HTTPS backend are required.',
                  )
                else
                  FirebaseSignIn(onAuthenticated: check),
                if (loading) const LinearProgressIndicator(),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(liveRegion: true, child: Text(error!)),
                  TextButton(
                    onPressed: loading ? null : check,
                    child: const Text('Retry access check'),
                  ),
                ],
                if (FirebaseIdentity.ready &&
                    FirebaseIdentity.auth.currentUser != null)
                  TextButton(onPressed: signOut, child: const Text('Sign out')),
                const SizedBox(height: 24),
                const Text(
                  'Staff access is assigned by a trusted operator. Consumer accounts do not receive administrative access.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.api,
    required this.identity,
    required this.section,
    required this.onTheme,
    required this.onSignOut,
  });
  final ServiceApi api;
  final Map<String, dynamic> identity;
  final int section;
  final VoidCallback onTheme;
  final Future<void> Function() onSignOut;
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  bool expanded = true;
  int days = 30, offset = 0;
  final search = TextEditingController();
  final searchFocus = FocusNode();
  Timer? debounce;
  late Future<Map<String, dynamic>> result;
  bool get canWrite =>
      ['admin', 'super_admin'].contains(widget.identity['role']);
  @override
  void initState() {
    super.initState();
    result = fetch();
  }

  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    debounce?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> fetch() => widget.api.call(
    switch (widget.section) {
      1 => '/v1/admin/users',
      2 => '/v1/admin/catalog',
      4 when canWrite => '/v1/admin/audit',
      5 => '/v1/admin/me',
      _ => '/v1/admin/overview',
    },
    query: switch (widget.section) {
      1 || 2 => {'q': search.text.trim(), 'offset': '$offset', 'limit': '25'},
      4 when canWrite => {'offset': '$offset', 'limit': '25'},
      5 => null,
      _ => {'days': '$days'},
    },
  );
  void reload() => setState(() => result = fetch());
  Future<void> globalSearch() async {
    final selected = await showSearch<Map<String, dynamic>?>(
      context: context,
      delegate: _AdminSearch(widget.api),
    );
    if (!mounted || selected == null) return;
    if (selected['kind'] == 'user') {
      await userDetails(selected['row'] as Map<String, dynamic>);
    } else if (canWrite) {
      await foodEditor(selected['row'] as Map<String, dynamic>);
    } else {
      final row = selected['row'] as Map<String, dynamic>;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(row['name'] as String),
          content: Text(
            '${row['category']} · ${row['energy_kcal']} kcal per 100 g',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  void navigate(int index) =>
      Navigator.of(context).pushReplacementNamed(adminRoutes[index]);
  Future<void> messageAction(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ServiceError
                  ? e.code
                  : 'The operation did not complete. Retry.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
          unawaited(globalSearch()),
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): reload,
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1000;
        final sidebar = NavigationRail(
          extended: expanded && desktop,
          selectedIndex: widget.section,
          labelType: expanded && desktop
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.all,
          onDestinationSelected: navigate,
          leading: IconButton(
            tooltip: 'Collapse navigation',
            onPressed: () => setState(() => expanded = !expanded),
            icon: const Icon(Icons.hexagon_outlined, color: violet),
          ),
          destinations: List.generate(
            6,
            (i) => NavigationRailDestination(
              icon: Icon(adminIcons[i]),
              label: Text(adminLabels[i]),
            ),
          ),
        );
        return Scaffold(
          appBar: AppBar(
            title: const Text('FLEX / Admin'),
            actions: [
              IconButton(
                tooltip: 'Global search (Ctrl+K)',
                onPressed: globalSearch,
                icon: const Icon(Icons.search),
              ),
              if (canWrite)
                IconButton(
                  tooltip: 'Recent administrative activity',
                  onPressed: () => navigate(4),
                  icon: const Icon(Icons.notifications_none),
                ),
              IconButton(
                tooltip: 'Switch theme',
                onPressed: widget.onTheme,
                icon: const Icon(Icons.contrast),
              ),
              PopupMenuButton<String>(
                tooltip: 'Staff account',
                onSelected: (_) => messageAction(widget.onSignOut),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text('${widget.identity['role']}'),
                  ),
                  const PopupMenuItem(value: 'logout', child: Text('Sign out')),
                ],
              ),
            ],
          ),
          drawer: desktop
              ? null
              : Drawer(
                  child: SafeArea(
                    child: ListView(
                      children: [
                        const ListTile(title: Text('FLEX Admin')),
                        for (var i = 0; i < 6; i++)
                          ListTile(
                            selected: i == widget.section,
                            leading: Icon(adminIcons[i]),
                            title: Text(adminLabels[i]),
                            onTap: () {
                              Navigator.pop(context);
                              navigate(i);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
          body: Row(
            children: [
              if (desktop) sidebar,
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(desktop ? 32 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Workspace / ${adminLabels[widget.section]}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 20,
                        runSpacing: 12,
                        children: [
                          Text(
                            adminLabels[widget.section],
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if ([0, 3].contains(widget.section))
                                DropdownButton<int>(
                                  value: days,
                                  items: [7, 30, 90]
                                      .map(
                                        (d) => DropdownMenuItem(
                                          value: d,
                                          child: Text('Last $d days'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (d) {
                                    days = d!;
                                    reload();
                                  },
                                ),
                              IconButton(
                                tooltip: 'Refresh (Ctrl+R)',
                                onPressed: reload,
                                icon: const Icon(Icons.refresh),
                              ),
                              if (widget.section == 2 && canWrite)
                                IconButton(
                                  tooltip: 'Import foods from JSON',
                                  onPressed: importFoods,
                                  icon: const Icon(Icons.upload_file),
                                ),
                              if (widget.section == 2 && canWrite)
                                FilledButton.icon(
                                  onPressed: () => foodEditor(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add food'),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if ([1, 2].contains(widget.section))
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: TextField(
                            controller: search,
                            focusNode: searchFocus,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              labelText: widget.section == 1
                                  ? 'Filter account ID'
                                  : 'Filter food name',
                            ),
                            onChanged: (_) {
                              debounce?.cancel();
                              debounce = Timer(
                                const Duration(milliseconds: 350),
                                () {
                                  offset = 0;
                                  reload();
                                },
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: FutureBuilder<Map<String, dynamic>>(
                          future: result,
                          builder: (context, state) {
                            if (state.connectionState != ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  semanticsLabel: 'Loading administration data',
                                ),
                              );
                            }
                            if (state.hasError) {
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        state.error is ServiceError
                                            ? (state.error as ServiceError).code
                                            : 'Service unavailable.',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: reload,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              );
                            }
                            final data = state.data!;
                            return SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if ([0, 3].contains(widget.section))
                                    overview(data),
                                  if ([1, 2].contains(widget.section))
                                    directory(data),
                                  if (widget.section == 4) operations(data),
                                  if (widget.section == 5) settings(data),
                                  const SizedBox(height: 20),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(
                                            text: const JsonEncoder.withIndent(
                                              '  ',
                                            ).convert(data),
                                          ),
                                        );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Current report page copied as JSON.',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.copy),
                                      label: const Text(
                                        'Copy this report page as JSON',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget overview(Map<String, dynamic> data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final item in [
            ('Registered accounts', 'users', Icons.people_outline),
            (
              'Enabled accounts',
              'enabled_accounts',
              Icons.verified_user_outlined,
            ),
            (
              'New registrations',
              'new_registrations',
              Icons.person_add_outlined,
            ),
            ('Managed foods', 'catalog_foods', Icons.restaurant_outlined),
          ])
            SizedBox(
              width: 244,
              child: MetricCard(
                title: item.$1,
                value: '${data[item.$2]}',
                icon: item.$3,
              ),
            ),
        ],
      ),
      const SizedBox(height: 24),
      panel('Registration growth', [
        if ((data['growth'] as List).isEmpty)
          const Text('No measured registrations in this range.'),
        ValueBars(
          values: (data['growth'] as List)
              .map(
                (r) => ('${r['day']}', (r['registrations'] as num).toDouble()),
              )
              .toList(),
          unit: 'accounts',
        ),
        Text(
          '${data['legacy_registration_unknown']} older accounts have no recorded registration date.',
        ),
      ]),
      const SizedBox(height: 20),
      panel('Tracking activity', [
        for (final entry in (data['activity'] as Map).entries)
          ListTile(
            title: Text('${entry.key}'),
            trailing: Text('${entry.value} current records'),
          ),
        if ((data['activity'] as Map).isEmpty)
          const Text('No current records updated in this range.'),
      ]),
      const SizedBox(height: 20),
      panel('Metric definitions', [
        for (final entry in (data['definitions'] as Map).entries)
          ListTile(
            title: Text('${entry.key}'),
            subtitle: Text('${entry.value}'),
          ),
        const Text(
          'Retention, platform usage, API error trends and background jobs: unavailable. Event instrumentation is required.',
        ),
      ]),
    ],
  );

  Widget panel(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Widget directory(Map<String, dynamic> data) {
    final users = widget.section == 1;
    final rows = (data['items'] as List).cast<Map<String, dynamic>>();
    return panel(
      users ? 'Account directory' : 'Managed food catalog · per 100 g',
      [
        if (rows.isEmpty)
          Text(
            users
                ? 'No matching accounts.'
                : 'No managed foods. The bundled USDA consumer catalog is preserved separately.',
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              for (final label
                  in users
                      ? ['Account', 'Status', 'Role', 'Registered', 'Actions']
                      : [
                          'Food',
                          'Category',
                          'kcal / 100 g',
                          'Quality',
                          'Actions',
                        ])
                DataColumn(label: Text(label)),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: users
                      ? [
                          DataCell(SelectableText(row['id'] as String)),
                          DataCell(
                            Text(
                              row['active'] == true ? 'Enabled' : 'Suspended',
                            ),
                          ),
                          DataCell(Text(row['role'] as String)),
                          DataCell(
                            Text(
                              row['registered_at']
                                      ?.toString()
                                      .split('T')
                                      .first ??
                                  'Unknown',
                            ),
                          ),
                          DataCell(
                            TextButton(
                              onPressed: () => userDetails(row),
                              child: const Text('Inspect'),
                            ),
                          ),
                        ]
                      : [
                          DataCell(Text(row['name'] as String)),
                          DataCell(Text(row['category'] as String)),
                          DataCell(Text('${row['energy_kcal']}')),
                          DataCell(
                            Text(
                              row['possible_duplicate'] == true
                                  ? 'Possible duplicate'
                                  : row['verified'] == true
                                  ? 'Verified'
                                  : 'Draft',
                            ),
                          ),
                          DataCell(
                            Row(
                              children: [
                                TextButton(
                                  onPressed: canWrite
                                      ? () => foodEditor(row)
                                      : null,
                                  child: const Text('Edit'),
                                ),
                                IconButton(
                                  tooltip: 'Delete food',
                                  onPressed: canWrite
                                      ? () => deleteFood(row)
                                      : null,
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ],
                ),
            ],
          ),
        ),
        Row(
          children: [
            Text('${data['total']} total'),
            const Spacer(),
            IconButton(
              tooltip: 'Previous page',
              onPressed: offset == 0
                  ? null
                  : () {
                      offset = max(0, offset - 25);
                      reload();
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Page ${offset ~/ 25 + 1}'),
            IconButton(
              tooltip: 'Next page',
              onPressed: offset + 25 >= (data['total'] as int)
                  ? null
                  : () {
                      offset += 25;
                      reload();
                    },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> userDetails(Map<String, dynamic> row) async {
    final reason = TextEditingController();
    final change = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account inspection'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(row['id'] as String),
                Text(
                  'Identity issuers: ${(row['issuers'] as List).join(', ')}',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Personal diary, weight, exercise and water values are excluded.',
                ),
                if (canWrite &&
                    row['role'] == 'user' &&
                    row['id'] != widget.identity['id'])
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(
                      labelText: 'Reason (8–240 characters)',
                    ),
                    maxLength: 240,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          if (canWrite &&
              row['role'] == 'user' &&
              row['id'] != widget.identity['id'])
            FilledButton(
              onPressed: () {
                if (reason.text.trim().length >= 8) {
                  Navigator.pop(context, true);
                }
              },
              child: Text(
                row['active'] == true ? 'Suspend account' : 'Enable account',
              ),
            ),
        ],
      ),
    );
    if (change == true) {
      await messageAction(() async {
        await widget.api.call(
          '/v1/admin/users/${row['id']}/status',
          body: {'active': row['active'] != true, 'reason': reason.text.trim()},
        );
      });
    }
    reason.dispose();
  }

  Future<void> foodEditor([Map<String, dynamic>? row]) async {
    final keys = [
      'name',
      'category',
      'serving_grams',
      'energy_kcal',
      'protein_mg',
      'carbs_mg',
      'fat_mg',
    ];
    final fields = {
      for (final key in keys)
        key: TextEditingController(text: row?[key]?.toString() ?? ''),
    };
    var verified = row?['verified'] == true;
    final form = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(row == null ? 'Create food' : 'Edit food'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Nutrients are per 100 g. Protein, carbs and fat use milligrams.',
                    ),
                    for (final key in keys)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          controller: fields[key],
                          decoration: InputDecoration(
                            labelText: key.replaceAll('_', ' '),
                          ),
                          keyboardType: ['name', 'category'].contains(key)
                              ? TextInputType.text
                              : TextInputType.number,
                          validator: (value) {
                            if (['name', 'category'].contains(key)) {
                              return value == null || value.trim().isEmpty
                                  ? 'Required'
                                  : null;
                            }
                            final number = int.tryParse(value ?? '');
                            return number == null ||
                                    number < (key == 'serving_grams' ? 1 : 0) ||
                                    number >
                                        (key == 'energy_kcal' ? 10000 : 100000)
                                ? 'Enter a valid whole number'
                                : null;
                          },
                        ),
                      ),
                    SwitchListTile(
                      title: const Text('Verified by administrator'),
                      value: verified,
                      onChanged: (v) => update(() => verified = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Save food'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      final id =
          row?['id'] ??
          '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
      await messageAction(() async {
        await widget.api.call(
          '/v1/admin/catalog/$id',
          body: {
            for (final key in keys)
              key: ['name', 'category'].contains(key)
                  ? fields[key]!.text.trim()
                  : int.parse(fields[key]!.text),
            'verified': verified,
            'revision': row?['revision'] ?? 0,
          },
        );
      });
    }
    for (final field in fields.values) {
      field.dispose();
    }
  }

  Future<void> importFoods() async {
    final input = TextEditingController();
    final form = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import up to 50 foods'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: form,
            child: TextFormField(
              controller: input,
              minLines: 6,
              maxLines: 12,
              maxLength: 100000,
              decoration: const InputDecoration(
                labelText: 'JSON array of new foods (revision: 0)',
              ),
              validator: (value) {
                try {
                  final parsed = jsonDecode(value ?? '');
                  if (parsed is! List || parsed.isEmpty || parsed.length > 50) {
                    return 'Enter 1–50 foods as a JSON array.';
                  }
                } catch (_) {
                  return 'Enter valid JSON.';
                }
                return null;
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Validate and import'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await messageAction(() async {
        final response = await widget.api.call(
          '/v1/admin/catalog/import',
          body: {'items': jsonDecode(input.text)},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${response['imported']} foods imported.')),
          );
        }
      });
    }
    input.dispose();
  }

  Future<void> deleteFood(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete managed food?'),
        content: Text(
          '${row['name']}\nExisting consumer diary snapshots are retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete food'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await messageAction(() async {
        await widget.api.call(
          '/v1/admin/catalog/${row['id']}/delete',
          body: {
            'revision': row['revision'],
            'reason': 'Catalog review: administrator confirmed deletion',
          },
        );
      });
    }
  }

  Widget operations(Map<String, dynamic> data) => panel('Operational audit', [
    const Text(
      'The authenticated API responded. Performance, error history, failed-sync monitoring and background-job telemetry are not instrumented.',
    ),
    if (!canWrite)
      const Text('Audit history requires an Admin or Super Admin role.'),
    if (canWrite)
      for (final row in data['items'] as List)
        ListTile(
          title: Text('${row['action']}'),
          subtitle: Text(
            '${row['created_at']} · ${row['actor_id']}\n${row['reason']}',
          ),
        ),
    if (canWrite && (data['items'] as List).isEmpty)
      const Text('No administrative events yet.'),
  ]);

  Widget settings(Map<String, dynamic> data) => panel('Access and security', [
    SelectableText('Account: ${data['id']}'),
    Text('Role: ${data['role']}'),
    const SizedBox(height: 16),
    const Text(
      'Roles are assigned through the trusted backend operator command. Google and phone sign-in never grant staff access.',
    ),
    const Text(
      'Sensitive changes require authentication within the past five minutes. Sign out and authenticate again when requested.',
    ),
    const Text(
      'No service credentials or database tools are available in this interface.',
    ),
  ]);
}

class _AdminSearch extends SearchDelegate<Map<String, dynamic>?> {
  _AdminSearch(this.api) : super(searchFieldLabel: 'Find food or account ID');
  final ServiceApi api;
  String? loadedQuery;
  Future<List<Map<String, dynamic>>>? loadedResult;
  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(
      tooltip: 'Retry search',
      onPressed: () {
        loadedQuery = null;
        showResults(context);
      },
      icon: const Icon(Icons.refresh),
    ),
    IconButton(
      tooltip: 'Clear search',
      onPressed: () => query = '',
      icon: const Icon(Icons.clear),
    ),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    tooltip: 'Close search',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );
  @override
  Widget buildSuggestions(BuildContext context) => const Center(
    child: Text('Enter a food name or backend account UUID, then press Enter.'),
  );
  Future<List<Map<String, dynamic>>> find() async {
    final text = query.trim();
    if (text.isEmpty || text.length > 100) return [];
    final results = await Future.wait([
      api.call('/v1/admin/catalog', query: {'q': text, 'limit': '25'}),
      if (RegExp(r'^[a-fA-F0-9-]{1,36}$').hasMatch(text))
        api.call(
          '/v1/admin/users',
          query: {'q': text.toLowerCase(), 'limit': '25'},
        ),
    ]);
    return [
      for (var i = 0; i < results.length; i++)
        for (final row in results[i]['items'] as List)
          {'kind': i == 0 ? 'food' : 'user', 'row': row},
    ];
  }

  @override
  Widget buildResults(BuildContext context) {
    if (loadedQuery != query) {
      loadedQuery = query;
      loadedResult = find();
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: loadedResult,
      builder: (context, state) {
        if (state.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.hasError) {
          return Center(
            child: Text(
              state.error is ServiceError
                  ? (state.error as ServiceError).code
                  : 'Search unavailable. Use Retry search.',
            ),
          );
        }
        final rows = state.data!;
        if (rows.isEmpty) {
          return const Center(child: Text('No matching foods or account IDs.'));
        }
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final item = rows[index],
                row = rows[index]['row'] as Map<String, dynamic>;
            final user = item['kind'] == 'user';
            return ListTile(
              leading: Icon(
                user ? Icons.person_outline : Icons.restaurant_outlined,
              ),
              title: Text('${row[user ? 'id' : 'name']}'),
              subtitle: Text(
                user
                    ? 'Account · ${row['role']}'
                    : 'Managed food · ${row['category']}',
              ),
              onTap: () => close(context, item),
            );
          },
        );
      },
    );
  }
}
