# Settings window

One page, 500 points wide, with no sidebar, search or sheets. Its height fits the content; on a screen too short for it, the page scrolls inside a window that leaves 80 points of the visible screen free. The window can't be resized. It is rebuilt each time it opens and released when it closes, and it doesn't remember its position: it opens centred on the preferred screen.

## Layout

- **Header**: the app icon, the app name, and "Switch between windows with ⌘⇥", naming shortcut 1's hold and next-window keys as stored. With neither key set, the version takes its place. The traffic lights float over the transparent title bar above it.
- **Shortcut**: Hold (`holdShortcut`, can't be cleared), Select next window (`nextWindowShortcut`), Select previous window (`previousWindowShortcut`).
- **Windows** (shortcut 1 only): minimized, hidden and fullscreen windows, apps with no open window, Spaces, screens (`showMinimizedWindows`, `showHiddenWindows`, `showFullscreenWindows`, `showWindowlessApps`, `spacesToShow`, `screensToShow`). Fullscreen windows offer Show and Hide only, as before.
- **Appearance**: Theme (`appearanceTheme`, listed System, Light, Dark) and the delay before the switcher appears (`windowDisplayDelay`, 0–900 ms in 50 ms steps, with the value shown next to the slider).
- **General**: Start at login (`startAtLogin`), Menubar icon (`menubarIconShown`).
- **Footer**: the version, a GitHub link to the fork's repository, and Quit.

Each section is a small uppercase title over a rounded card. Rows hold a label on the leading side and the control on the trailing side, with hairlines between them. The layout mirrors for right-to-left languages.

## Behaviour

- A popup stores its case's index in the preference's enum, whatever order it lists the cases in, so the switcher reads the value exactly as it did with the old Settings.
- A control writes only when its value differs from the stored one, then goes through `Preferences.set`, so the change applies live through `PreferencesEvents`.
- A control follows its preference when it changes elsewhere: the menubar icon dragged off the menubar turns its switch off, and a conflict dialog that unassigns a shortcut clears its recorder.
- The recorders keep the old validation: `CustomRecorderControlTestable.isShortcutAcceptable` decides, the conflict and macOS-reserved dialogs open as sheets on Settings, and the next-window recorder can't take the hold's modifiers.
- Every other preference keeps its stored value and has no control: the other shortcuts, the gesture, exceptions, per-shortcut appearance overrides, animations, cursor following, arrow and vim keys, the shortcuts used while the switcher is open, the language.
