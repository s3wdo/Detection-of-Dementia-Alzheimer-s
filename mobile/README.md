# NeuroSense mobile app (Flutter)

The patient, doctor and administrator app for NeuroSense. It talks to the FastAPI server in [`../backend`](../backend) and runs on the team's iPhones through SideStore. **Academic project, not a certified medical device.**

## Run

Requires Flutter 3.47 (the version used in CI).

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<server-ip>:8000/api/v1   # against a running server
flutter run --dart-define=USE_FIXTURES=true                             # fictional demo data, no server
```

Without `API_BASE_URL` the app points to `http://10.0.2.2:8000/api/v1`, which is the host machine as seen from the Android emulator. The server address can also be changed on the login screen, and **Find server on this Wi-Fi** looks for a NeuroSense server on the phone's local network.

Demo mode (`USE_FIXTURES=true`) uses fictional data from `lib/dev/` and adds a development-only demo login. Never enable it in a real release.

## Builds

| Target | How |
|:--|:--|
| iPhone (SideStore) | Actions, then **iOS demo build (.ipa)**, then **Run workflow**. Download the `NeuroSense-ipa` artifact and open `NeuroSense.ipa` in SideStore. Free Apple ID installs last 7 days. |
| Android | Actions, then **Android build (.apk)**, then **Run workflow** |
| Web | `flutter build web --release --dart-define=USE_FIXTURES=false`; the server can serve the result from `backend/web` |

## Check

```bash
flutter analyze
flutter test
```

123 tests cover the API layer, session handling, the upload checks, every screen and the main flows. `test/phase5/screen_sweep_test.dart` opens every screen on a 360 dp phone at normal and 200% text size and checks Flutter's accessibility guidelines (tap-target size, labels, contrast). Details of any failure go to `build/sweep_details.txt`.

`tool/screenshots_test.dart` renders every main screen to PNG for design review. It is not part of the normal test run:

```bash
flutter test tool/screenshots_test.dart --update-goldens   # output: tool/screenshots/ (git-ignored)
```

## Structure

```
lib/
  core/        configuration, theme, router, session and token storage, networking (Dio), shared widgets
  features/    admin, auth, dashboard, patients, diagnosis, explainability, reviews, timeline,
               reports, counselling, appointments, messages, notifications, profile
  dev/         demo users and fixture repositories (only used when USE_FIXTURES=true)
test/          unit, widget and flow tests
tool/          screenshot renderer for design review
```

Each feature has `data/models`, a repository interface in `data/`, its Riverpod providers and its `screens/`. The implementation behind each repository (API or demo fixtures) is chosen in `lib/core/data/repository_providers.dart`, so screens never depend on where the data comes from.

## Safety rules in the app

- The four classes are the model's: CN, EMCI, LMCI and AD.
- AI output, doctor-reviewed results and results released to the patient look different and are labelled as such.
- Patients see only results their doctor has reviewed and released, without the model's probabilities or the doctor's notes. The server enforces this; the app does not rely on hiding data.
- Doctors see every class probability and the Grad-CAM map before they confirm or override a result.
- The counselling section offers reviewed education content and predefined answers, with safety rules that send risky questions (emergencies, medication, diagnosis) to fixed, safe replies. It does not use a language model.

See [`../docs/design-reference.md`](../docs/design-reference.md) for the design mapping and [`../docs/decisions-log.md`](../docs/decisions-log.md) for decisions and their reasons.
