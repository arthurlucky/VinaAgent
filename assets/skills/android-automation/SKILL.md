---
name: android-automation
description: Safely drive the Android device with the automation tools. Use when the user asks to open an app, tap, type, scroll, toggle a setting, or run a multi-step phone task.
---

# Android Automation

## Before acting

1. Read the current screen state (screenshot or UI tree) before the first action.
2. Restate the goal in one line and list the taps you plan to make.
3. Ask for confirmation before anything that sends a message, spends money,
   changes an account, or deletes data.

## Loop

1. Inspect the screen.
2. Choose the smallest next action: `open_app`, `tap`, `type_text`, `swipe`,
   `press_back`.
3. After each action, verify the screen changed as expected before continuing.
4. Stop after 15 actions and report progress instead of looping.

## Safety rules

- Never enter passwords, OTPs, or payment details read from a screenshot.
- Never accept permissions, terms, or subscriptions on the user's behalf
  without explicit approval.
- If an unexpected dialog appears, stop and ask.
- Prefer deep links (`open_app` with a URI) over blind coordinate taps.
- When a step fails twice, stop and explain what blocked you.
