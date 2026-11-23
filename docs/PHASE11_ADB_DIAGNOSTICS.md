# Phase 11 ADB diagnostics

- Platform-Tools 37.0.1, ADB 1.0.41. Restricted shell failed to connect to the Windows daemon on TCP 5037. With Windows ADB access, devices, shell echo FLEX, sys.boot_completed (1), dumpsys activity and a standalone hierarchy dump all exited 0. No daemon or emulator restart was needed for connectivity.
- The Phase 10 script only reported its first argument (shell). The exact historical subcommand cannot be recovered. The first Phase 11 run captured valid XML but could not find Open diary. A separate window check identified Application Not Responding: com.android.systemui. Wait was selected by verified UI bounds. FLEX later regained window focus.
- The revised script resolves ADB, discovers a single online emulator or accepts an explicit serial, sends literal process arguments, applies a 20-second per-command deadline, reports stderr and exit status, and retries hierarchy reads only. It verifies FLEX package ownership in parsed XML and uses a unique device-side path that is removed at exit.
- Run in PowerShell 7. Pass -Adb with an absolute Platform-Tools path if adb cannot be found automatically. Do not use adb kill-server or reset the emulator as first-line diagnostics.

## Follow-up observations

When FLEX regained focus, a compressed UIAutomator dump showed 26 FLEX nodes and Open diary. The next run opened Diary and the Breakfast food search. The search label is an XML hint, and the previous selector read only text and content-desc. After including hint, the next run reached the editable field. The expected query bananas appeared as baanaanas in a focused UI field. The runner now uses a shorter query and verifies exact field text before selecting a result. The Windows dependency paths were inspected. Flutter 3.47.0, Dart 3.13.0, Python 3.14.6, PostgreSQL 18.4 and Android emulator API 37 were observed.
After restart UIAutomator returned null root with exit 0. An uncompressed capture recovered. The runner now starts each retry with a fresh path state and alternates compressed and uncompressed captures.
