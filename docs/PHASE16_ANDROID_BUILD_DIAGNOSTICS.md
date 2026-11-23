# Phase 16 Android build diagnostics

Windows reported 1557164 KiB free out of 8243508 KiB with the existing emulator online. Prior isolated builds failed inside Dart and the JVM under memory pressure. Avoid concurrent Gradle, Flutter and PostgreSQL verification. Use the existing Gradle distribution and workspace-local Gradle home.

The one-worker x86_64 build used an 850 MiB Gradle heap. The offline attempt stopped at uncached net.openid:appauth:0.11.1. The network-enabled retry resolved it and built in 4m 9s. AAPT verified the original package and the redirect receiver scheme. No APK was installed.
