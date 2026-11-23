import 'package:flutter/material.dart';

const violet = Color(0xff6d5ef8);
const teal = Color(0xff18b7a0);
const amber = Color(0xfff4b860);
const darkCanvas = Color(0xff10121b);
const darkSurface = Color(0xff1a1d29);
const lightCanvas = Color(0xfff7f8fc);

ThemeData flexTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(seedColor: violet, brightness: brightness)
      .copyWith(
        primary: violet,
        onPrimary: Colors.white,
        secondary: teal,
        onSecondary: darkCanvas,
        tertiary: amber,
        onTertiary: darkCanvas,
        surface: dark ? darkSurface : Colors.white,
        onSurface: dark ? const Color(0xfff1f2fa) : darkCanvas,
        onSurfaceVariant: dark
            ? const Color(0xffb4bad0)
            : const Color(0xff555d74),
        error: dark ? const Color(0xffffb4ab) : const Color(0xffb3261e),
      );
  final border = dark ? const Color(0xff34384c) : const Color(0xffdfe2ee);
  return ThemeData(
    colorScheme: colors,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: dark ? darkCanvas : lightCanvas,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? darkCanvas : lightCanvas,
      foregroundColor: colors.onSurface,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: violet, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: dark
            ? const Color(0xffb3abff)
            : const Color(0xff5846c8),
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark
            ? const Color(0xffb3abff)
            : const Color(0xff5846c8),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: violet.withValues(alpha: 0.18),
      elevation: 0,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      indicatorColor: violet.withValues(alpha: 0.18),
    ),
    dividerTheme: DividerThemeData(color: border, space: 24),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5),
    ),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.detail,
    this.onTap,
    this.color = teal,
  });
  final String title, value;
  final String? detail;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right, size: 20),
              ],
            ),
            const SizedBox(height: 16),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            if (detail != null)
              Text(
                detail!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class GoalRing extends StatelessWidget {
  const GoalRing({
    super.key,
    required this.value,
    required this.label,
    required this.detail,
  });
  final double? value;
  final String label, detail;
  @override
  Widget build(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) > 20
      ? Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.headlineMedium),
            Text(detail, textAlign: TextAlign.center),
          ],
        )
      : Semantics(
          label: '$label, $detail',
          child: ExcludeSemantics(
            child: SizedBox(
              width: 184,
              height: 184,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: value?.clamp(0, 1) ?? 0),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                      builder: (context, progress, _) =>
                          CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 10,
                            strokeCap: StrokeCap.round,
                            backgroundColor: violet.withValues(alpha: 0.15),
                            color: violet,
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          detail,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
}

class ValueBars extends StatelessWidget {
  const ValueBars({
    super.key,
    required this.values,
    required this.unit,
    this.color = violet,
  });
  final List<(String, double?)> values;
  final String unit;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final max = values.fold(
      1.0,
      (m, v) => v.$2 != null && v.$2! > m ? v.$2! : m,
    );
    return Column(
      children: [
        for (final item in values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.$1} · ${item.$2 == null ? 'Unknown' : '${item.$2!.toStringAsFixed(1)} $unit'}',
                ),
                const SizedBox(height: 6),
                Tooltip(
                  message:
                      '${item.$1}: ${item.$2?.toStringAsFixed(1) ?? 'Unknown'} $unit',
                  triggerMode: TooltipTriggerMode.tap,
                  child: ExcludeSemantics(
                    child: LinearProgressIndicator(
                      value: item.$2 == null ? 0 : item.$2! / max,
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                      minHeight: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class LoadingCards extends StatelessWidget {
  const LoadingCards({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading your records',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 24),
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Card(child: SizedBox(height: 100)),
          ),
      ],
    ),
  );
}
