# IPSFixtures

Synthetic iPhone crash-log files for `IPhoneCrashLogTests` (IPHONE-CRASHLOG-ACTIONS). A separate root because
`Tests/Fixtures` admits only `ParsedCommand` directories (see its README).

All files are synthetic; the shapes come from the masked headers of IPHONE-SPIKE Q5. Each `.ips` is a JSON first line,
a newline, then `{"synthetic":true}`. Never commit a real phone header unless it is scrubbed: `incident_id` and
`slice_uuid` become the zero UUID, app names become `SomeApp`, any `uniqueID` field is removed.

Local step L1 may add one scrubbed real 309 header as `<name>-ios<major.minor>.ips`.
