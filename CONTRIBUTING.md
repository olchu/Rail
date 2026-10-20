# Contributing to Rail

Bug reports, ideas and pull requests are welcome. Rail reads other apps through the Accessibility API, and most bugs depend on the app, its version and the macOS version, so a report needs those three to be reproducible.

## Build and run

Rail is a Swift package with one executable target and no dependencies. It needs macOS 26 and Xcode 26 or a Swift 6.2 toolchain.

```sh
swift build                  # debug build, to check that it compiles
scripts/bundle.sh            # signed build/Rail.app, the way to run it
open build/Rail.app
```

Run Rail from the bundle rather than from `swift build`: the Accessibility grant belongs to a signed app. `scripts/bundle.sh` signs with `Apple Development` unless its first argument names another identity; keep the identity the same between builds, or macOS asks for Accessibility access again.

`RAIL_PREVIEW=1 build/Rail.app/Contents/MacOS/Rail` opens the sidebar at launch and keeps it open, which helps with work on the interface.

## Code layout

| File | Contents |
|---|---|
| `AppDelegate.swift`, `main.swift` | Launch, menu bar item |
| `EdgeMonitor.swift` | Pointer at the screen edge |
| `SidebarController.swift` | The panel, showing and hiding, menu actions |
| `SidebarView.swift`, `ProjectCard.swift`, `WindowRow.swift` | The SwiftUI interface |
| `GlassBackground.swift`, `Palette.swift` | Glass material, project colors |
| `WindowStore.swift` | Windows and tabs of every app, the sidebar layout, opening pins |
| `ProjectStore.swift` | Projects, rules and pins, saved in user defaults |
| `Tabs.swift` | Browser and system tabs, page addresses |
| `Finder.swift`, `Slack.swift` | What a Finder or Slack window shows |
| `PrivateAPI.swift` | Private HIServices and SkyLight calls for other Spaces |
| `Accessibility.swift` | Permission check, AX helpers |
| `Dialogs.swift` | Add to project, rename, pin dialogs |

`IDEA.md` holds the product notes and the roadmap, in Russian.

## Conventions

- Match the surrounding code: its naming, its comment density, and comments that explain why rather than what.
- Interface strings are in Russian.
- A commit message is one subject line, prefixed with `Rail: `, for example `Rail: Slack threads in pins`.
- A change that reads another app through the Accessibility API names in the pull request the app versions it was tested with.
