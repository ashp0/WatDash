# WatDash

A native macOS dashboard for a University of Waterloo term: every class,
deadline, quiz and office hour in one place, a grade engine that tracks the
**80% cumulative average** a sixth course needs, and study pages made by Claude
Code from your own course folders. Almost nothing is typed by hand.

Companion to [WatAlarm](../WatAlarm) (iOS alarms before class). Same
conventions: generated Xcode project, a hand-rolled RFC 5545 parser, and pure
logic verified by plain `swiftc` checks.

---

## What's in it

| Screen | What it does |
|---|---|
| **Today** | A grid of cards you add, remove and drag into order: now & next, today, upcoming deadlines, overload tracker, highest-impact work, two-week load chart, course grades, import, study, next-exam countdown, seat watch, inbox. A setup checklist appears until the term is fully set up. |
| **Schedule** | Week grid with a live "now" line, overlap-aware columns, click-to-inspect popovers ("skip this one" for a cancelled lecture), double-click to add. Agenda mode for the next four weeks. |
| **Deadlines** | Overdue / this week / next week / later / TBA, with done checkboxes, marks, and on every quiz, midterm and exam a **Seat** button (your room and seat on Odyssey) and a study-prompt button. |
| **Grades** | Projected term average with a likely range, chance of clearing the target, the uniform score needed on everything left, a what-if slider, and per-item leverage ("+0.60 on your average per 10 marks"). |
| **Course** | Grading-scheme editor (weights, item counts, drop-lowest, exam flags, "final replaces midterm", "must pass the exams"), score table with per-item what-if sliders and exemptions, meetings, files, notes page map. |
| **Study** | Builds a ready-to-paste **Claude Code prompt** for a study page: assessment, sections, notes page ranges, course rules. No API key: Claude Code runs it on your subscription using the `quiz-prep` skill in the classes folder. |
| **Import** | Eight import tiles plus a list of every source with health, refresh and remove. |

Plus: a **menu bar** panel (now/next, rest of today, due this week, margin to
80, a capture field), **⌃⌥Space quick capture** from any app, **desktop
widgets**, **Shortcuts/Siri/Spotlight actions**, deadline **notifications**,
and optional **Apple Calendar** sync.

## Getting your term in

Every import is remembered as a *source*. Re-importing updates in place (ids
are stable), and removing a source removes exactly what it added. Marks are
never deleted by an import.

| Source | Gives you | Notes |
|---|---|---|
| **Course folders** | Assessments with dates, coverage, rooms and posted marks, grading scheme, weekly office hours, notes page map, study pages, notes PDF, reading week, the course's help rules and accent colour | Reads each `<Course>/CLAUDE.md` under `~/Documents/University of Waterloo Classes` (format below). A saved outline in the folder adds class times for the sections you pick. |
| **Quest schedule** | Your actual class meetings | Copy Quest → Enroll → My Class Schedule → List View and paste; or use that page's *Download Schedule* `.ics`. |
| **Calendar file / feed** | Anything iCalendar | Feeds refresh on a timer. LEARN's Calendar → Subscribe feed and public Google office-hour calendars both work. A UW Flow schedule export (uwflow.com → Schedule → export) gives every lecture, tutorial and test slot; open the `.ics` with WatDash. |
| **Course outline** | Every section's times plus the assessment table | Save the outline.uwaterloo.ca page as HTML. |
| **Apple Calendar** | Calendars already on the Mac (Google, Outlook, iCloud) | Re-read whenever they change. |
| **Waterloo Open Data** | Class times for your sections, important dates, final exam slots, seat counts, campus events | Free key from openapi.data.uwaterloo.ca, kept in the Keychain. |
| **UW holidays** | Stat holidays that cancel classes | Anonymous feed; no key. |
| **Quick capture** | One line of plain English | `CS 135 OH Tue 2-3pm MC 4065 weekly until Dec 4`, `math137 quiz 4 oct 19`, `A4 due fri 11:59pm`. Unsure parses wait in the inbox. |

### The course-folder `CLAUDE.md`

The same file briefs Claude and fills the dashboard. What WatDash reads:

- `# MATH 137: Calculus 1 for Honours Mathematics (Fall 2026)`: code, title, term. "(self-study)" in the heading marks a course that never counts.
- Under `## Assessments…`, grading bullets: `- Quizzes, 20%, best 9 of 10: …`, `- Midterm 2, 20%: …`. Sentences like "Assignments are due Wednesdays at 4:05 PM" set default times.
- Any table with *Assessment* and *Date* columns: one assessment per row. Optional columns: *Covers* / *Sections* (coverage), *Room* (room and seat), *Mark* (`15/19`, `91.67%`, or `Submitted`), *Status* (`Submitted`, `Written`, `Done`). A posted mark only fills an empty score; marks typed in the app win.
- `## Office hours`: one quick-capture line per weekly slot, e.g. `- Tue 11:30am-12:30pm MC 5473, Troy Vasiga, weekly until Dec 8`.
- "Reading week is Oct 10–18.", `## Study pages` links, a "blue accent" colour, and the notes PDF under `## Files`.

An item named after a component maps to it ("Midterm 2" → *Midterm 2*, "Skills challenge 1" → *Skills challenges*); otherwise the kind picks one ("Quiz 3" → *Quizzes*).

Timetable test slots (UW Flow and Quest `TST`) are hidden where the course's own quiz or exam already sits, and a quiz written in the tutorial slot replaces that tutorial, since the seat on Odyssey is usually somewhere else.

Holidays and reading week cancel **class meetings** and office hours only.
Deadlines during reading week still stand.

## The grade engine

The Faculty of Math rule (CS advising FAQ): students with a **cumulative
average of at least 80%** can take six courses; below that you can petition.
So the engine works in Waterloo averages, not GPA:

- unit-weighted mean of **whole-number** course grades (rounding modelled)
- CR/NCR and self-study courses excluded
- drop-lowest applied only once there are more marks than kept slots
- "final replaces midterm" and "must pass the exams" rules
- exemptions shift weight to the rest of the component

For each course it reports **banked** (zeros on everything left), **ceiling**
(100s), **current**, **projected** and the **uniform score needed**. Projection
fills unwritten work with your own component average; exams are projected
`examGap` points lower (default 8), a prior that is replaced by the gap
learned from your own marks once there are exam results. The spread and the
chance of clearing the target come from a per-slot variance (exams wider than
coursework), which is rough and meant as a range rather than a promise.

In your first term the cumulative average *is* this term's average, so the
overload tracker is the number that decides Winter.

## Architecture

```
Sources ──► Importers (pure parsers) ──► AppStore (one JSON file) ──► Projections
            ICSParser, QuestSchedule-     canonical store:            SnapshotWriter → widgets
            Parser, OutlineParser,        courses, events,            NotificationScheduler
            CourseFolderParser,           assessments, sources,       CalendarSync (EventKit)
            QuickCaptureParser            settings                    views, menu bar, intents
                                               │
                                     RecurrenceExpander, GradeEngine (pure)
```

```
Shared/            compiled into the app AND the widget extension
                   (snapshot model, palette, App Group id)
WatDash/
  App/             app entry, delegate, App Intents, debug snapshotter
  Core/            logging, deterministic ids, keychain, Waterloo time
  Models/          Course, DashEvent, Assessment, GradeScheme, DataSource, AppData
  Importers/       the parsers — no UI, no store, no clock
  Services/        store-facing work: imports, EventKit, notifications, hotkey,
                   smart capture, Open Data, study prompts, grade engine
  Store/           AppStore
  Views/           SwiftUI
WatDashWidgets/    Up Next, Deadlines, Overload Tracker, Today
Tests/Checks.swift assertions on parsers, recurrence, grades and study prompts
Tools/             project generator, checks runner, icon generator, installer
```

Design decisions worth knowing:

- **One store, many projections.** Every mutation goes through
  `AppStore.commit`, which saves (debounced) and refreshes the widget
  snapshot, notifications and the Apple Calendar export. Nothing is ever
  "the calendar" — calendars are rebuildable views.
- **Deterministic ids everywhere** (as in WatAlarm). Exported Calendar events
  carry `watdash://occurrence/<digest>` of what they are; reconciliation is a
  set difference; WatDash only ever touches events it created.
- **Writes that change nothing are dropped.** Observation fires on every
  write, and SwiftUI bindings (the menu bar's `isInserted`, toggles) re-set
  identical values; without the guard in `AppStore.settings` that loops.
- **The on-device model only normalizes language.** With Apple Intelligence
  on, messy captures go through `FoundationModels` guided generation into
  fields copied *as written*; dates are always computed by the deterministic
  parser, which is tested.
- **The widget never reads the store.** The app writes a small snapshot into
  the App Group container; the widget builds timeline entries at every class
  boundary and every 15 minutes, so "Up next" advances without the app.

## Building

Requires Xcode 27 / the macOS 26+ SDK.

```bash
python3 Tools/generate_project.py   # after adding or removing files
./Tools/run_checks.sh               # pure-logic checks, no Xcode project needed
./Tools/install.sh                  # Release build → /Applications, then launches it
```

### Signing

Manual signing with your **Apple Development** identity and **no provisioning
profile**, which macOS allows for everything WatDash uses: App Sandbox (widget
only), an App Group named `<TEAM>.com.ashwinpaudel.WatDash` (team-prefixed
groups need no registration on macOS), calendar access and network access.
That means a free personal team works, and unlike an iOS build there's **no
7-day expiry**. Use `--team` to build under a different team.

### Debug helpers

```bash
WatDash.app/Contents/MacOS/WatDash -WatDashDemo                      # sample term in its own data file
WatDash.app/Contents/MacOS/WatDash -WatDashStore scratch             # any scratch data file
WatDash.app/Contents/MacOS/WatDash -WatDashStore scratch -WatDashScanFolders
WatDash.app/Contents/MacOS/WatDash -WatDashDemo -WatDashSnapshot /tmp/shots   # PNG of every screen, then quit
```

Data lives in `~/Library/Application Support/WatDash/watdash.json`, with a
rolling daily backup next to it. API keys live in the login Keychain.
