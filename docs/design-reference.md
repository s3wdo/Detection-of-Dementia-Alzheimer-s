# NeuroSense — Design reference (App-UI.png → Flutter)

**Source of truth for the look:** `junior\App-UI.png` (15 phone screens). No Figma file exists, so
colours, sizes and spacing below are **estimated from the image** (about 170 px per phone) and may be
tuned later. Screens the board doesn't include are built in the same style, using the earlier
concept board only for layout ideas.

## 1. Screen mapping

| # | App-UI screen | Role | Flutter screen | File | Phase | Status |
|---|---|---|---|---|---|---|
| 15 | End screen (dark, wave) | shared | `SplashScreen` (launch) | `features/auth/screens/splash_screen.dart` | 1 | Done |
| 1 | Splash / Login | shared | `WelcomeScreen` + `LoginScreen` | `features/auth/screens/` | 1 | Done |
| 2 | Role selection | shared | `DevRolePickerScreen` (**dev only**) | `features/auth/screens/dev_role_picker_screen.dart` | 1 | Done |
| — | (not in design) Forgot password | shared | `ForgotPasswordScreen` | `features/auth/screens/forgot_password_screen.dart` | 1 | Done |
| 14 | Profile & Settings | shared | `ProfileScreen` + settings pages | `features/profile/screens/` | 2 | Done (preferences kept in memory until backend) |
| 11 | Doctor dashboard | doctor | `DoctorDashboardScreen` | `features/dashboard/screens/` | 2 | Done |
| 3 | Patient dashboard | patient | `PatientDashboardScreen` | `features/dashboard/screens/` | 2 | Done (released results only) |
| 9 | Patient timeline | both | `TimelineScreen` | `features/timeline/screens/` | 2 | Done (source filter; patient view = released only) |
| 13 | Notifications | both | `NotificationsScreen` | `features/notifications/screens/` | 2 | Done (All/Unread, mark read) |
| 4 | Upload MRI | doctor | `MriUploadScreen`, `MriPreviewScreen` | `features/diagnosis/screens/` | 3 | Done (JPG/PNG ≤10 MB, grayscale warning) |
| 5 | Analysis in progress | doctor | `AnalysisProgressScreen` | `features/diagnosis/screens/` | 3 | Done (simulated job) |
| 6 | Result + explainability | doctor | `DiagnosisResultScreen`, `ExplainabilityScreen` | `features/diagnosis/`, `features/explainability/` | 3 | Done (heatmap = placeholder) |
| 7 | Doctor review | doctor | `DiagnosisReviewScreen` | `features/reviews/screens/` | 3 | Done |
| 8 | Report | both | `ReportScreen` | `features/reports/screens/` | 4 | Done (PDF comes from backend later) |
| 10 | Counselling | patient | `CounsellingHomeScreen`, `CounsellingChatScreen`, `ResourceDetailScreen` | `features/counselling/screens/` | 4 | Done (predefined answers, no LLM) |
| 12 | Appointments | both | `AppointmentsScreen`, details, request | `features/appointments/screens/` | 4 | Done |

**Not in the design (built in the same style):**
- Doctor (all done): patient list + search/filters, patient profile, history & comparison (with chart), appointment details, messages inbox + thread.
- Patient (all done): latest result, result history (History tab), result details, resource library + details, appointment request, messages, reports list.

## 2. Design conflicts and how they're resolved
1. **Labels.** "Alzheimer's Disease" and "MCI" are not model outputs. The app only shows *Non Demented, Very Mild Demented, Mild Demented, Moderate Demented.*
2. **Heatmaps.** The design's coloured heatmap is replaced by a clearly labelled placeholder until the real model produces one. No fake heatmaps. The welcome screen uses a logo illustration instead of the MRI-with-heatmap artwork.
3. **Counselling answer.** The design's "signs consistent with early Alzheimer's" is replaced with the approved safe wording.
4. **Patient "Upload MRI".** Only doctors upload scans, so this patient quick action is replaced (Reports / Messages).
5. **Upload limits.** JPG/PNG up to 10 MB (the design says DICOM, 50 MB). DICOM is a later stretch goal.
6. **Wording.**
   - "Confidence" becomes **"Model confidence"**.
   - The tagline "AI-Powered … Healthier Tomorrow" becomes "AI-Assisted MRI Analysis", with "Supporting informed healthcare decisions."
   - "Early Detection. Better Outcomes." is removed, because it is an outcome claim.
7. **Photos of people.** Replaced with initials avatars, since there are no licensed photos.
8. **Doctor review.** The "Share with patient" toggle becomes **Release to patient**. Confirm/override, final label, reason, clinical notes and patient summary are added in Phase 3.
9. **Create account.** There's no self-signup; it explains that accounts are created by the clinic, per the approved security model.

## 3. Design tokens (`lib/core/theme/`)

| Token | Value | Note |
|---|---|---|
| primary | `#2F5BEA` | buttons, active tab, links |
| primaryTint | `#EAF0FF` | icon tiles, selected nav |
| violet | `#6A4CF5` | gradient end, logo |
| heroGradient | `#3557E8 → #6A4CF5` | latest-analysis card, progress ring (Phases 2–3) |
| navy | `#0F1B3D` | headings |
| body | `#3B4660` | body text |
| muted | `#5B6580` | darkened from the design (~`#6B7590`) to reach 4.5:1 contrast |
| background | `#F5F8FF` | screen background |
| border | `#E3E8F4` | card and input borders |
| launch | `#0B1736` | dark splash |
| AI / Doctor / Admin | violet `#5B3FD9` / teal `#0B7A5E` / slate `#4A5568` | information-source badges |
| status | success `#157A52`, pending `#9A5B00`, error `#C62F2F` | dark text on a light tint |

- **Type:** 28 / 22 / 18 / 16 / 14 / 12. The `Inter` family is referenced but **not bundled yet**, so the platform font is used until the font files are added.
- **Spacing:** 4 / 8 / 12 / 16 / 20 / 24 / 32; screen padding 20.
- **Radii:** card 16, button 12, input 12, tile 14, pill.
- **Touch targets:** at least 48 dp.

## 4. Temporary assets (replace when the real ones arrive)
- **Logo:** drawn in code by `NeuroLogo` (`core/widgets/neuro_logo.dart`), approximating the design's gradient brain icon.
- **Splash wave:** drawn by `WavePainter`.
- **Font:** the platform default until Inter (or the team's actual font) is bundled.

## 5. Visual check against App-UI.png (Phase 5)
Checked in the web build (390 × 844 phone frame) and the widget-test sweep (360 × 740, 1× and 2× text).
- Matches the design: blue/white palette, card style, blue→violet hero card, quick-action tiles, the four-tab bottom navs for both roles, list rows with icon tiles, the segmented Upcoming/Past and All/Unread controls, and the dark launch screen.
- Intentional differences: see §2. In addition:
  - the chat title is "Support" (the full name was cut off on phones)
  - "Mark all read" is an icon button
  - the patient dashboard shows a disclaimer under the hero card
- Still approximate: the font (Inter not bundled yet), the logo (temporary drawing) and the end-screen wave (painted).


## Typography and visual language (clinical refinement pass)
Supersedes the font notes above.
- **IBM Plex Sans** for all UI text, headings included: display 26, title 22, screen title 22, headline 18, body 16, small 14, caption 13.
- **IBM Plex Mono** only for MRNs, IDs, percentages and model name/version.
- **Source Serif 4** stays bundled for the welcome-screen wordmark only.
- **Cards** are used only where one object is grouped (the patient's latest result, the report page). Lists and settings use divider rows with spaced-capital section headings (`RowGroup`).
- **Colour carries state:** blue for the primary action, green for doctor decisions and release, amber for pending and simulated/prototype notices, violet only for the "AI model output" label.
