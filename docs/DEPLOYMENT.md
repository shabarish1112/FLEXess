# FLEX development release

Live browser: https://flex-nutrition-diary.vercel.app

Editable design: https://www.figma.com/design/leE6qFHI8f29Y5LKxJSrak

Version: `1.1.0-dev+2`. This is the guest browser edition, not an accepted production cloud service.

## Hosting evidence

- Team: RED (`red-7f6a`), `team_CDUYqxL6RfbcM6dU6PxKielO`.
- Project: `flex-nutrition-diary`, `prj_X8R0beZCfPhFqMYXdeqKXGYqkeBc`.
- Deployment: `dpl_DouDkJ6pdiuWSJckKhBCJYhxRQUd`, READY, production hosting target.
- Uploaded: 33 compiled static files plus `mobile/vercel.json`. No credentials, personal records, repository source or screenshots were deployed.
- Production guest site is public. Preview deployment protection and private source visibility remain enabled.
- Use the canonical URL consistently: SQLite/IndexedDB storage is separate for every origin, including alternate deployment URLs.

## Rebuild

Run from `mobile` with the compatible Flutter SDK:

```powershell
flutter pub get
dart run sqflite_common_ffi_web:setup
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
```

Deploy the contents of `mobile/build/web` with `mobile/vercel.json` at the hosting root, targeting the existing project/team above. The initial deployment used the authenticated Vercel connector's content-addressed upload API. Git auto-deployment has not been connected. The existing GitHub workflow now builds a browser artifact, but a hosted workflow run has not been verified.

Keep native cloud flags off until the existing Auth0/HTTPS/database acceptance gates pass. No backend services, paid database, custom domain or production Android signing credentials were provisioned.

## Android test artifact

`mobile/build/releases/FLEX-1.1.0-dev-x86_64-isolated-debug.apk` is for the x86_64 emulator test package `dev.independent.fitness_diary.isolatedtest`. AAPT verified version `1.1.0-dev`, code `2`. SHA-256: `EB0F31E047CA91AC0021F10DBB4ECC797FC31814FB79EDE9CD269F39AF410122`.

The isolated package installed successfully, preserving the original FLEX package and data. Native runtime verification was blocked by the emulator's “System UI isn't responding” dialog. This artifact is debug-signed and is not a Play Store or physical ARM release.

## Data limits

Guest browser data stays in the current browser/site storage and is not backed up or shared with Android. Clearing site data removes it. The export screen provides readable/copyable JSON, not a full SQLite restoration path. Loading/reloading the browser shell offline is not supported. See FEATURE_COMPLETENESS.md for cloud and integration availability.
