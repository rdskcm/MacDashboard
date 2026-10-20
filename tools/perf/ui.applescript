-- usage: osascript ui.applescript <pid> <kind> [value]
-- Ported from the hunt's ui.applescript + settings-open.applescript. Every kind addresses the process by
-- unix id, never by name. AX actions run only BEFORE xctrace attaches (an AX walk loads the main thread).
--   id <AXIdentifier>[|alt...]   press the first button / radio button whose AXIdentifier equals a value
--   title <text>[|alt...]        press the first button / radio button whose title or AXDescription equals a
--                                value (pass both languages: "Таблица|Table")
--   frame <AXIdentifier>         do not press; "x y w h" (integers, global top-left points) of the first element
--                                of any class with that identifier, else "NOT FOUND"
--   exists <AXIdentifier>        do not press; "present" | "absent" for an element of any class with that identifier
--   settings                     press the app-menu item "Settings…" / "Настройки…"
--   pin                          set window 1 to position {0, 29}, size {1000, 733} (D13)
--   dump                         do not press; "windows: <n>", "window 1 @ x,y wxh", then one line "<id> <class> @ x,y wxh" per element of window 1 with a non-empty AXIdentifier
-- Prints "pressed" | "present" | "absent" | "x y w h" | "pinned" | "OK" | "NOT FOUND".
on splitAlts(theVal)
	set AppleScript's text item delimiters to "|"
	set alts to text items of theVal
	set AppleScript's text item delimiters to ""
	return alts
end splitAlts

on run argv
	set thePID to (item 1 of argv) as integer
	set theKind to item 2 of argv
	set theVal to ""
	if (count of argv) > 2 then set theVal to item 3 of argv
	set alts to my splitAlts(theVal)
	tell application "System Events"
		tell (first process whose unix id is thePID)
			if theKind is "pin" then
				set position of window 1 to {0, 29}
				set size of window 1 to {1000, 733}
				return "pinned"
			end if
			if theKind is "settings" then
				set appMenu to menu 1 of menu bar item 2 of menu bar 1
				repeat with mi in menu items of appMenu
					set miName to ""
					try
						set miName to name of mi
					end try
					if miName starts with "Settings" or miName starts with "Настройки" then
						perform action "AXPress" of mi
						return "OK"
					end if
				end repeat
				return "NOT FOUND"
			end if
			if theKind is "dump" then
				set out to "windows: " & ((count of windows) as text)
				try
					set wp to position of window 1
					set wsz to size of window 1
					set out to out & linefeed & "window 1 @ " & ((item 1 of wp) as integer as text) & "," & ((item 2 of wp) as integer as text) & " " & ((item 1 of wsz) as integer as text) & "x" & ((item 2 of wsz) as integer as text)
					set allElements to entire contents of window 1
					repeat with el in allElements
						set elID to ""
						try
							set elID to (value of attribute "AXIdentifier" of el)
						end try
						if elID is missing value then set elID to ""
						if elID is not "" then
							set cls to "?"
							try
								set cls to (class of el) as text
							end try
							set geo to "?"
							try
								set p to position of el
								set s to size of el
								set geo to ((item 1 of p) as integer as text) & "," & ((item 2 of p) as integer as text) & " " & ((item 1 of s) as integer as text) & "x" & ((item 2 of s) as integer as text)
							end try
							set out to out & linefeed & elID & " " & cls & " @ " & geo
						end if
					end repeat
				on error errMsg
					set out to out & linefeed & "error: " & errMsg
				end try
				return out
			end if
			if theKind is "frame" or theKind is "exists" then
				set allElements to entire contents of window 1
				repeat with el in allElements
					try
						set elID to ""
						try
							set elID to (value of attribute "AXIdentifier" of el)
						end try
						if alts contains elID then
							if theKind is "exists" then return "present"
							set p to position of el
							set s to size of el
							return ((item 1 of p) as integer as text) & " " & ((item 2 of p) as integer as text) & " " & ((item 1 of s) as integer as text) & " " & ((item 2 of s) as integer as text)
						end if
					end try
				end repeat
				if theKind is "exists" then return "absent"
				return "NOT FOUND"
			end if
			set allElements to entire contents of window 1
			repeat with el in allElements
				try
					set c to (class of el)
					if c is button or c is radio button then
						set hit to false
						if theKind is "id" then
							set elID to ""
							try
								set elID to (value of attribute "AXIdentifier" of el)
							end try
							if alts contains elID then set hit to true
						else
							set t to ""
							try
								set t to (title of el)
							end try
							set d to ""
							try
								set d to (value of attribute "AXDescription" of el)
							end try
							if t is missing value then set t to ""
							if d is missing value then set d to ""
							repeat with a in alts
								set av to a as text
								if theKind is "title" then
									if t is av or d is av then set hit to true
								end if
							end repeat
						end if
						if hit then
							perform action "AXPress" of el
							return "pressed"
						end if
					end if
				end try
			end repeat
		end tell
	end tell
	return "NOT FOUND"
end run
