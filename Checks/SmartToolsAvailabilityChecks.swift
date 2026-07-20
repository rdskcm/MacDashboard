// Checks/SmartToolsAvailabilityChecks.swift
// Block N8: pure-logic coverage for ReportCollector.smartToolsAvailability's 4-way
// input mapping (smartctl present/absent x brew present/absent). This file is real
// check code (NOT a symlink — see README.md), split out of main.swift because Swift
// executable targets only allow ONE file with top-level (script-mode) statements —
// main.swift already owns that slot — so this file instead defines a plain function
// that main.swift calls. `check()`/`total`/`failures` are the top-level helpers
// declared in main.swift; they're visible here because both files compile into the
// same MacDashboardChecks module.

import Foundation

func runSmartToolsAvailabilityChecks() {
    check(ReportCollector.smartToolsAvailability(smartctl: "/opt/homebrew/bin/smartctl",
                                                  brew: "/opt/homebrew/bin/brew") == .installed,
          "smartToolsAvailability: smartctl present, brew present ⇒ .installed")
    check(ReportCollector.smartToolsAvailability(smartctl: "/opt/homebrew/bin/smartctl",
                                                  brew: nil) == .installed,
          "smartToolsAvailability: smartctl present, brew absent ⇒ .installed (smartctl wins)")
    check(ReportCollector.smartToolsAvailability(smartctl: nil,
                                                  brew: "/opt/homebrew/bin/brew") == .installable,
          "smartToolsAvailability: smartctl absent, brew present ⇒ .installable")
    check(ReportCollector.smartToolsAvailability(smartctl: nil, brew: nil) == .needsHomebrew,
          "smartToolsAvailability: smartctl absent, brew absent ⇒ .needsHomebrew")
}
