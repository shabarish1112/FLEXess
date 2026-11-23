import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/diary_store.dart';
import 'diary/domain.dart';

class CustomFoodPage extends StatefulWidget {
  const CustomFoodPage({super.key, required this.store});
  final DiaryStore store;
  @override
  State<CustomFoodPage> createState() => _CustomFoodPageState();
}

class _CustomFoodPageState extends State<CustomFoodPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final inputs = {for (final n in Nutrient.values) n: TextEditingController()};
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    for (final c in inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? parsed(String raw) {
    if (!RegExp(r'^\d{1,4}(?:\.\d{1,3})?$').hasMatch(raw.trim())) return null;
    final value = double.tryParse(raw.trim());
    return value == null || !value.isFinite || value > 1000
        ? null
        : (value * 1000).round();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    final food = Food(
      'custom-${DateTime.now().microsecondsSinceEpoch}',
      name.text.trim(),
      {
        for (final n in Nutrient.values)
          n: inputs[n]!.text.trim().isEmpty ? null : parsed(inputs[n]!.text),
      },
      const [Serving('100 g', 100), Serving('1 g', 1)],
      source: 'Custom food',
      version: 'user-entered-v1',
    );
    try {
      await widget.store.importCatalog([foodRecord(food)]);
      if (mounted) Navigator.pop(context, food);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not save this food. Your input is still here.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Create custom food')),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Your food, clearly labeled',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Text(
              'Enter nutrition per 100 g from your own source. These values are user-entered and unverified. Leave unknown nutrients blank.',
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: name,
              enabled: !busy,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Food name'),
              validator: (s) =>
                  s == null || s.trim().isEmpty ? 'Enter a food name.' : null,
            ),
            for (final n in Nutrient.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextFormField(
                  controller: inputs[n],
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '${n.label} (${n.unit} per 100 g)',
                    hintText: 'Unknown if blank',
                  ),
                  validator: (s) =>
                      s == null || s.trim().isEmpty || parsed(s) != null
                      ? null
                      : 'Enter 0–1000, up to three decimal places.',
                ),
              ),
            if (error != null) Semantics(liveRegion: true, child: Text(error!)),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Saving…' : 'Save custom food'),
            ),
          ],
        ),
      ),
    ),
  );
}
