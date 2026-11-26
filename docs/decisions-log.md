# Decisions made while you were away

Each entry: what I decided, why, and how to change it if you disagree.

## Phase 3 — Diagnosis

1. **Simulated results are always labelled.** With demo data on, an "analysis" picks one of four fixed demo results based on the uploaded file, so the same image always gives the same result. Every result screen shows a **SIMULATED RESULT** banner, and the model name is marked "(placeholder)". The seeded demo analyses are flagged as simulated too.
   *Why:* the brief forbids presenting fake AI output as real.
   *Change:* `FixtureAnalysesRepository._demoResults` in `lib/dev/fixtures/fixture_repositories.dart`.
2. **Explainability is a placeholder.** The Heatmap and Overlay tabs show "Explainability not available yet", and the opacity slider is disabled until a real heatmap exists. The Original tab shows the uploaded image; seeded demo results have no image.
   *Why:* the brief says never to generate fake heatmaps.
3. **The grayscale check warns rather than blocks.** A colour or non-MRI-looking image shows a warning, and the doctor must confirm "Analyze anyway". Wrong format, over 10 MB, or unreadable images are blocked.
   *Why:* the image check is a rough rule of thumb; the doctor makes the final call.
4. **Review rules** (enforced in the review form and in the demo repository):
   - an override must pick a different class and give a reason of at least 10 characters
   - releasing to the patient requires a patient summary
   - an analysis can't be reviewed twice
   - a reviewed result can be released later from the result screen
5. **Patients see the doctor's decision first**, then the AI output labelled "AI-assisted analysis". Clinical notes and the override reason are never shown to patients.
6. **Releasing a result notifies the patient** (demo notification "Your MRI result has been reviewed").
7. **Upload is from the photo gallery / files only, with no camera option.** A phone photo of a screen would be a poor input for the model.
8. **Riverpod's automatic retry is turned off** (`main.dart`), so "server not connected" errors show immediately. It will be configured properly with the real API.
9. **"Confirm AI result" became "Confirm"** in the review toggle, because the long label wrapped onto two lines on phones. The review form now shows "Your decision · Dr. …" instead of a "Doctor reviewed" badge, since nothing is reviewed until it's submitted.

## Phase 4 — Report, counselling, appointments, messages

1. **The counselling chat uses predefined answers only.** Each question goes through safety rules first (`SafetyRules.classify`):
   - emergency → fixed "call your emergency number" reply
   - medication or dosing → "please ask your doctor or pharmacist" plus a *Message my doctor* button
   - "do I have…" questions → referral
   - your result → built only from the **released** result and the doctor's patient summary
   - everything else → points to an article

   A yellow **PROTOTYPE** notice stays on screen the whole time.
   *Change:* `lib/features/counselling/data/safety_rules.dart`, `lib/dev/fixtures/fixture_support_repositories.dart`. The team's LLM replaces the fixture repository later; the safety rules should stay in front of it on the backend.
2. **I wrote the 8 education articles** (`lib/dev/fixtures/counselling_content.dart`). They cite public bodies (WHO, NIA, Alzheimer's Association) as sources but are my summaries, **not reviewed by a clinician**. They need a supervisor or clinician review before any real use.
3. **PDF download is deferred to the backend.** The report is a Flutter screen with separate "AI-GENERATED" and "DOCTOR-REVIEWED" bands. "Download PDF" shows a message that the server will generate it. `pdfx` was **not** added yet, so there's one fewer dependency until there's a real PDF.
4. **The confidence-over-time chart is doctor-only.** Patients get the comparison table and a note that changes between AI results do not by themselves prove progression. The doctor's chart has the same caption.
5. **I added a Messages icon** next to the bell on both dashboards, because the design has no entry point for messaging. Messages go to the care team, and the screen says clearly that they don't go to the AI assistant.
6. **The patient History tab** now has two tabs, Results and Timeline. It used to be just the timeline.
7. **The patient dashboard's "Upload MRI" quick action** (design conflict 4) became **Reports**.
8. **Removed the temporary "Coming soon" screen**, since every tab now has real content.
9. **The chat scrolls to the newest message automatically.** This was found in testing, where answers appeared below the fold.
10. **The chat title is shortened to "Support"**, because "NeuroSense Support" was cut off next to the "Ask my doctor" button on a 390-px-wide phone.

## Phase 5 — Quality and testing

1. **Every screen is tested automatically** on a small Android phone (360 × 740 dp), at normal size and at 200 % text size, for both roles (43 screens). The sweep also runs Flutter's accessibility checks: 48 dp tap targets, labelled buttons, and text contrast. All pass.
2. **Overflow fixes found by the sweep.** Long labels now wrap instead of being cut off:
   - status/source badges
   - badge + date rows
   - patient card
   - appointment card
   - list-row trailing badges (limited to about 40 % of the width)
   - "Latest Analysis" card
   - upload drop zone (grows with text)
   - explainability placeholder (scrolls)
   - appointment reason dropdown
   - model-confidence block (caption now sits under the number)
3. **"Mark all read" in Notifications is now an icon button** (✓✓ with the tooltip "Mark all read"). The text button didn't fit next to the title at large text sizes.
4. **"Ask my doctor" in the chat** keeps its text label at normal sizes and switches to an icon with a tooltip when the user's text size is very large.
5. **Error messages are safe for users.** Only known errors show their message: server not connected, network/timeout, not found, conflict, validation and sign-in messages. Any other error shows "Something went wrong. Please try again.", so technical details never appear on screen (`lib/core/data/user_facing_error.dart`).
6. **Loading, empty and error states are tested**, including recovery: an error shows "Try again", and the list appears once the data loads.
7. **Visual comparison with App-UI.png.** Layout, colours, cards, gradient hero card, quick actions, bottom navs and lists follow the design. The intentional differences are all listed in `design-reference.md` §2:
   - model class labels
   - heatmap placeholder
   - initials instead of photos
   - JPG/PNG ≤ 10 MB
   - Reports instead of patient Upload
   - Inter font not yet bundled (system font is used)
8. **There is still no on-device run.** Android Studio is installed but its SDK setup wizard and licences need you; see "What you need to do" in the final report. Everything was checked with widget tests and the web build.

## Restyle to the mobile-sections design (after Phase 5)

The design reference is now `App-UI/NeuroSense-Mobile-Sections-for-PDF`: warm off-white background, Source Serif 4 titles, IBM Plex Sans text, IBM Plex Mono numbers, a deep navy and clinical blue palette, and dark navy hero cards. It replaces the blue/violet App-UI.png look.

1. **Fonts are bundled**, so nothing is fetched at runtime (`assets/fonts`, SIL Open Font License). Sans and Serif come from Google Fonts' variable files, converted to fixed weights with fontTools.
2. **Kept from the safety rules, even where the design differs:**
   - the four model labels stay ("Very Mild Demented", not "Very Mild Dementia")
   - there are no MRI drawings or heatmaps: the thumbnail shows a neutral brain icon, and explainability is still a placeholder
   - the SIMULATED and PROTOTYPE banners stay
   - the DEVELOPMENT ONLY demo banner stays
3. **Messages icon** stays in the dashboard header, next to the bell and the initials.
4. **The doctor's "New MRI analysis" button** opens the patient list, because a scan must belong to a patient.
5. **Notifications go straight to the detail screen**: the result, appointment, or analysis. They are opened with `push`, so Back always returns to Notifications. This fixes your report that an appointment notification had no back button. A new test checks that every non-tab screen has a back button.
6. **Chat and message banners use shorter wording at very large text sizes**, so the conversation still fits.
7. **Screenshots for design review:** `flutter test tool/screenshots_test.dart --update-goldens` writes all screens to `mobile/tool/screenshots/`.

## Polish pass — every design section (missing buttons and sections)

All 24 sections of the mobile design were compared with the app, and the missing pieces were added:

- **Patients:** "+" (explains that patients are registered by the clinic admin), a filter button, counts on the chips, and a "No analyses yet" badge.
- **Patient profile:**
  - "…" menu, and the latest result card with an "Open" link
  - analysis history with dates in mono type
  - Appointments section ("All" opens the appointments tab)
  - Doctor Notes with a working **Add note** (new doctor-only notes data)
  - Timeline preview ("View full timeline")
  - Personal Information with a working **Edit** for phone and emergency contact
- **Upload:** one screen now (preview merged in). It shows "Step 1 of 2", the assigned patient, a dashed upload area, the selected file with a validation checklist and a remove button, and **Analyze MRI**.
- **Analysis progress:**
  - a close (X) button and **Continue in background**
  - the demo analysis now finishes even after you leave, and notifies the doctor
  - step details, with the explainability step shown as skipped until the model is connected
- **Result:** "…" menu (explainability, report, compare, message patient), **Doctor Review** / **View Explainability** buttons, and the release button in green.
- **Explainability:** a colour-scale legend, a doctor-only technical-details panel and **Generate LIME explanation**. The **LIME screen** is new and doctor-only: it shows the legend, the planned parameters and region weights as "not available yet". No fake superpixels.
- **Review:** "1 · AI output" / "2 · Your reviewed decision", large Confirm/Override cards, labelled fields (Required / Clinicians only / Shown to patient), a green **Submit Review** and an audit-log note.
- **Compare:** previous and current side by side, a "How to read this comparison" card and, for patients, **Discuss with my doctor**.
- **Report:** a paper-style page with a header, ID grid, AI and doctor sections, disclaimer and page footer, plus a "…" menu, **Download PDF** and a send button that opens messages.
- **Appointments:** "+" for patients. Every upcoming card has buttons: patient **View / Cancel**, doctor **Confirm / Reschedule / Cancel**. These are shared with the details screen.
- **Counselling:** an "Explain my latest report" card (opens the chat and asks automatically), **All resources** (new searchable Resources screen), an **Ask NeuroSense** card and a safety box.
- **Chat:** a "Using only your released report" banner, an **Ask My Doctor** card after answers, follow-up questions and a footer note.
- **Ask My Doctor:** a doctor card, a message form with an optional **Linked: MRI analysis** (stored with the message), and "Previous messages" newest first. Doctors keep the chat layout.
- **Profile:** centred layout with a role pill and ID, two grouped cards with descriptions.
- **Security & Privacy:** a "Your Privacy" header, the list of protections, **Sign out of all devices** and the academic notice.
- **Doctor dashboard:** "View all" on Recent Activity. **Patient dashboard:** activity rows open History.

Still server-dependent, and each says so when tapped: PDF download and password change.

The resources subtitle says "pending clinical review", because the articles have not been reviewed by a clinician yet.

## Clinical UI refinement pass (supervisor feedback: "looks AI-generated")

The UI was over-designed rather than poor: cards everywhere, tinted icon squares on every row, pills next to pills, serif headings, statistics-first dashboards, and a "DEMO DATA" ribbon on every screen. This pass is a refinement: same architecture, data, safety rules and navigation.

- **Global:**
  - the demo corner ribbon is removed; demo status stays on Login, the role picker and as one caption in Profile
  - headings use IBM Plex Sans
  - card and button radii go from 20/14 to 12/10
  - `ListRowTile` uses a plain icon
  - new `RowGroup` (divider rows + section heading) replaces card-wrapped groups
  - `SourceBadge` becomes a quiet label, while `StatusBadge` stays a compact pill because it carries state
  - `InfoNote`, `DisclaimerBanner` and `TechPanel` lose their filled boxes
  - the SIMULATED and PROTOTYPE notices become slim amber strips, with the same wording
- **Doctor dashboard:**
  - ordered by attention: "Awaiting your review" (patients whose latest analysis is unreviewed, from the existing patients repository), New MRI analysis, Schedule (today, otherwise the next appointments), Recent activity
  - the four statistic cards became one summary line
- **Analysis result (doctor):**
  - patient, analysis date, AI-assisted analysis, then the doctor review state
  - one primary action (Doctor Review, then Release to patient, then View report), with the other actions as a list
  - the image viewer moved to Explainability
- **Explainability:**
  - without a model map: "Not available yet" text and the original image (if stored); no tabs, slider or colour legend
  - the Original/Heatmap/Overlay viewer and opacity slider remain in code and appear only when a real map is supplied
- **Patient home:** latest released result (the only card), next appointment, care team, then "Learn and prepare". The four-tile grid and recent activity were removed (History tab has both).
- **Counselling:**
  - "Education & Support" rows replace the navy hero card
  - in the chat, answers are plain text labelled "predefined answer", while safety and referral replies keep their tinted boxes
- **Lists:** patients, notifications, messages, appointments, history, reports, resources and the timeline use divider rows instead of stacked cards.

**Not changed:**
- the ML/model module
- model classes and labels
- the analysis job
- repositories and fixtures
- the counselling safety rules
- review/release rules and permissions

**Verification:** Windows Device Guard began blocking the local `dart.exe`, so analyze, tests and screenshots ran on GitHub Actions (`.github/workflows/ui-verify.yml`, branch `ui-refinement`).

## Backend and app connection (FastAPI + PostgreSQL)

The app can now run against a real server (`USE_FIXTURES=false`); demo mode still works for demos and tests. How to run it: `backend.md`. The API: `api.md`.

**Decisions that change earlier ones**
1. **Patients can upload a scan** (earlier: doctors only). The patient gets a confirmation only. The result is visible to them after the doctor reviews and releases it, and the server enforces that.
2. **PyTorch `.pt` replaces Keras `.h5`** for the served model.
3. **Images travel as base64 inside JSON** (earlier plan: multipart), at most 256 × 256 pixels and 1 MB.
4. **One doctor per patient** in this version (`patients.doctor_id`), instead of an assignments table.

**Decisions made while building**
- **Stub predictor until the model arrives.** Every stub result is stored and returned with `simulated: true`, and the app shows its SIMULATED notice from that flag. The app's model previously ignored the flag in JSON; that is fixed.
- **No model settings are assumed.** Input size, preprocessing, class order and output type come from `model_config.yaml`, filled in by the model owner. Without a complete file the server keeps the stub.
- **Analysis jobs use the database as the queue** with one worker thread, not FastAPI background tasks (those are lost on restart) and not a separate queue service (not needed at this size).
- **The review queue is read-only.** The earlier idea of stamping "delivered to doctor" when the inbox is fetched was dropped: a lost reply would have hidden work.
- **The server ignores identity sent by the app** (patient id for patients, sender and author names). The repository interfaces still take them, for the demo repositories.
- **Notifications carry what they are about, not app routes.** The app maps them to screens.
- **Counselling stays inside the app.** With the server, "my result" answers use the released result from the API.
- **Progress and explainability texts no longer name a model or layer.** They said "EfficientNetV2S", "224 × 224" and "top_activation", which would be invented once results come from the server.
- **Upload notice wording:** "Encrypted connection" was removed from the upload screen, because the development server uses plain HTTP on the local network.

**Not verified here**
- The app talking to the live server on a phone or emulator (Flutter cannot run on this PC; the API layer is tested against a fake server on GitHub Actions, and the server is tested on its own).
- A real model: no `.pt` file exists yet.

## Patient view and look (2026-11-14)
- **Patients are not shown the model confidence.** The server no longer sends `confidence` in the patient copy of an analysis or in the patient timeline, and the patient screens (home card, history, result, report, comparison, counselling answer) no longer show it. Doctors see it as before. Reason: a percentage is easy to misread as the chance of having a condition.
- **New look, "Calm Clinical".** Teal actions on a soft grey-green background, larger corner radii and pill buttons, set in the theme tokens (`mobile/lib/core/theme`). Screens, navigation and wording are otherwise unchanged. The font is still IBM Plex Sans.

## Security & Privacy wording (2026-11-23)
- **"Encrypted connection" replaced with "Local network connection".** The Security & Privacy screen said information travels over HTTPS, but the server runs on the local Wi-Fi over plain HTTP. The row now says so, asks for fictional data only and notes that a real deployment would use HTTPS. The app no longer claims HTTPS anywhere.

## Report PDF and scan images (2026-11-23)

- **"Download PDF" works.** The server builds the PDF (ReportLab) from the same data as the in-app report; the app downloads it and opens the phone's share sheet (Save to Files, Mail, AirDrop, Print). The server picks the version from the token, so the patient copy can never contain model confidence, class scores, the override reason or clinical notes, and patients get it only for released results. Demo data shows a "server isn't connected" message instead of inventing a PDF.
- **Compare and Report show the MRI slice.** Both screens drew a placeholder icon; they now load each analysis's stored image.

## Full MRI scans, newer model, review comments 6 and 7 (2026-11-23)

- **Newer model.** `single_rotating_best.pt` replaces the 2026-10-14 weights. The team confirmed the class order (AD, LMCI, EMCI, CN) and that preprocessing is the same as before. The old model is kept beside it.
- **Comment 6 (resize).** The server resizes with `INTER_AREA`, as training did; the config now says `area`. The remaining gaps for single images (the app's 256 px downscale, JPEG compression) are documented in `docs/backend.md`, and full scans avoid them.
- **Comment 7 (which slice).** The upload screens now say: one axial slice, face pointing up, from the middle of the brain with brain tissue filling the image, PNG if possible.
- **Full scans.** Doctors can upload a `.nii` / `.nii.gz` scan. The server follows the team's steps: extract axial slices, rotate 90° counter-clockwise, keep the slices the brain detector accepts, mask, leave out the last 15, classify each slice and average the scores (the team chose averaging). Grad-CAM is made for the slice most confident in the top class. Patients cannot upload full scans.
- **Brain detector on PyTorch.** The Keras detector runs with Keras 3 on the PyTorch backend so the server does not need TensorFlow.

## LIME dropped (2026-11-22)
- **The team decided not to build a LIME explanation.** Grad-CAM, made by the server for every real analysis, is the only explainability method. The "LIME explanation — not available yet" row on the Explainability screen, the doctor-only LIME placeholder screen and its route are removed.
- **Find server on this Wi-Fi** was added to the login screen's Server address box (see `docs/backend.md`).
