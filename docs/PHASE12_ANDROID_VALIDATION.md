# Phase 12 Android validation

Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0 and Android Studio JBR 25. The first retry failed before dependency resolution with EOFException reading the global daemon registry. Invoking the already installed distribution with project-local GRADLE_USER_HOME and the shared dependency cache in read-only mode resolved that error. No shared cache was deleted. No HTTPS proxy was configured for the shell. The offline standard x86_64 debug build succeeded, and the binary is saved under mobile/build/phase12/flex-debug.apk.

ADB found one booted emulator. The existing FLEX package was left installed and was not upgraded. The optional flexIsolatedDebug Gradle property appends .isolatedtest only for a debug test package. The first isolated build hit a verified JVM native memory allocation failure during host memory pressure. A second emulator instance was not started.

The sequential one-worker retry with a 1280 MiB Java heap reached compileFlutterBuildDebug. Dart reported exhausted heap and failed to create a worker thread, and the JVM reported another native memory allocation failure. The isolated APK did not install. This is a confirmed host-resource failure. Phase 12 device behavior remains unverified, while the prior Phase 11 USDA preview and single-entry restart and cleanup evidence remains valid for that build.
