#!/usr/bin/osascript
-- Inspect by default. Pass --allow to press the upper button of the verified
-- Xcode Service MCP dialog. Xcode 27's SwiftUI buttons have no AX names; their
-- order was verified against the visible "Allow for 24 Hours" / "Don't Allow" pair.
-- Usage: xbridge-allow [--allow /absolute/project/root]

on run argv
  set shouldAllow to false
  set expectedPath to ""
  if (count of argv) is not 0 then
    if (count of argv) is not 2 then error "usage: xbridge-allow [--allow /absolute/project/root]"
    if item 1 of argv is not "--allow" then error "usage: xbridge-allow [--allow /absolute/project/root]"
    set expectedPath to item 2 of argv
    if expectedPath does not start with "/" then error "Expected an absolute project root; nothing clicked"
    set shouldAllow to true
  end if

  tell application "System Events"
    if not (exists process "Xcode Service") then error "Xcode Service is not running"
    tell process "Xcode Service"
      set matches to {}
      repeat with w in windows
        if subrole of w is "AXDialog" then
          if my matchesAccessPrompt(w, expectedPath) then set end of matches to w
        end if
      end repeat
      if (count of matches) is not 1 then
        if shouldAllow then error "Refusing to click: expected exactly one matching Xcode Service access dialog; found " & (count of matches)
        return "Matching Xcode Service access dialogs: " & (count of matches) & ". Nothing clicked."
      end if

      set targetDialog to item 1 of matches
      set hostingView to first UI element of targetDialog whose subrole is "AXHostingView"
      set buttonList to every UI element of hostingView whose role is "AXButton"
      set upperButton to item 1 of buttonList
      set lowerButton to item 2 of buttonList
      set upperPosition to position of upperButton
      set lowerPosition to position of lowerButton
      if (item 2 of upperPosition) is not less than (item 2 of lowerPosition) then error "Unexpected button order; nothing clicked"
      if (item 1 of upperPosition) is not (item 1 of lowerPosition) then error "Unexpected button alignment; nothing clicked"
      if not (enabled of upperButton) then error "Upper button is disabled; nothing clicked"
      if not my matchesAccessPrompt(targetDialog, expectedPath) then error "Dialog changed during inspection; nothing clicked"

      set headline to value of first static text of hostingView as text
      if not shouldAllow then return "Ready: Xcode Service > AXDialog > AXHostingView > upper AXButton (" & upperPosition & "). Headline: " & headline & ". Nothing clicked."
      click upperButton
      return "Clicked upper button (Allow for 24 Hours) on verified Xcode Service dialog: " & headline
    end tell
  end tell
end run

on matchesAccessPrompt(w, expectedPath)
  tell application "System Events"
    if subrole of w is not "AXDialog" then return false
    if (count UI elements of w) is not 1 then return false
    set hostingView to first UI element of w
    if subrole of hostingView is not "AXHostingView" then return false
    if (count UI elements of hostingView) is not 6 then return false
    if (count static texts of hostingView) is not 3 then return false
    if (count (every UI element of hostingView whose role is "AXButton")) is not 2 then return false
    set headline to value of first static text of hostingView as text
    set explanation to value of second static text of hostingView as text
    set projectPath to value of third static text of hostingView as text
    return (headline starts with "Allow an unknown agent (xbridge) to access ") and (headline ends with "?") and (explanation is "Allowing access gives the agent permission to open and work in any Xcode projects at the path:") and (projectPath starts with "/") and ((expectedPath is "") or (projectPath is expectedPath))
  end tell
end matchesAccessPrompt
