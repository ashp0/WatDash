#!/bin/bash
# Compiles and runs the pure-logic checks natively (no app, no Xcode project).
#
# Only the UI-free parts are included: models, parsers, recurrence and the
# grade engine — the pieces whose failures are silent and date-dependent.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

swiftc -O -o "$OUT/checks" -parse-as-library \
  WatDash/Core/StringConvenience.swift \
  WatDash/Core/Dates.swift \
  WatDash/Core/DeterministicID.swift \
  WatDash/Models/*.swift \
  WatDash/Services/RecurrenceExpander.swift \
  WatDash/Services/GradeEngine.swift \
  WatDash/Services/StudyPrompt.swift \
  WatDash/Importers/*.swift \
  Tests/Checks.swift

"$OUT/checks"
