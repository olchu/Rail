# Rail

Rail is a glass sidebar for macOS. It slides out from the left edge of the screen and lists every window of every app, on every Space, as one vertical list in the style of Arc's tabs, with each browser tab as a row of its own. Windows and tabs group into projects, and a pinned row stays in its project after its window closes: one click opens the same page, folder, document, Telegram chat or Slack thread again, in the app it came from.

[Download the latest release](https://github.com/olchu/Rail/releases/latest) · requires macOS 26 or later · the interface is in Russian.

## Features

- The sidebar opens from the left edge of a screen that has no other screen beyond it. When the pointer touches the edge, a sliver of glass appears; after the pointer rests there for 0.18 seconds, the sidebar opens. It hides 0.3 seconds after the pointer leaves it and never takes keyboard focus from the app you are in.
- The list includes windows on other Spaces and minimized windows. A click switches to the window's Space, raises the window and selects its tab.
- Each browser tab is a separate row: Chrome and other Chromium browsers, Safari and Firefox. Rail counts any app that opens `https` links as a browser, so Firefox forks and Tor need no list. The tabs macOS adds to Finder and Terminal windows are rows too.
- A project collects windows by rules: an app, optionally narrowed to window titles that contain a word. A project has a color, can be renamed and collapsed, and its rules can be removed one by one. Windows outside any project stay grouped by app.
- A pinned window or tab keeps its row in the project after it closes and reopens on click (see [Pins](#pins)).
- Running apps with no windows sit at the bottom of the sidebar as icons. A click activates the app, and most apps open a new window.

## Install

### From a release

1. Download `Rail-<version>.dmg` from [Releases](https://github.com/olchu/Rail/releases/latest) and drag Rail to Applications.
2. Open Rail. The release is signed with a development certificate and is not notarized, so macOS blocks the first launch. Open **System Settings → Privacy & Security** and click **Open Anyway** next to the message about Rail.
3. Grant Accessibility access when Rail asks for it: **System Settings → Privacy & Security → Accessibility**, then turn Rail on.

Rail lives in the menu bar (the `sidebar.left` icon) and has no Dock icon. To start it at login, add it in **System Settings → General → Login Items**.

### From source

Building needs Xcode 26 or a Swift 6.2 toolchain on macOS 26.

```sh
git clone https://github.com/olchu/Rail.git
cd Rail
scripts/bundle.sh            # builds build/Rail.app
open build/Rail.app
```

`scripts/bundle.sh` signs the app with the identity named in its first argument, `Apple Development` by default. Sign with the same identity every time: macOS ties the Accessibility grant to the signature, and an ad hoc signature loses the grant on every rebuild.

`scripts/dmg.sh` builds the app and packs it into `build/Rail-<version>.dmg` with an Applications shortcut. With a `Developer ID Application` identity and a `notarytool` keychain profile it also notarizes and staples the image:

```sh
NOTARY_PROFILE=<profile> scripts/dmg.sh "Developer ID Application: <name> (<team>)"
```

## Usage

The menu bar icon has three items: show the sidebar, open the Accessibility settings, and quit.

Right-click a window row to manage projects:

| Row | Menu items |
|---|---|
| Window outside a project | Add to project (Добавить в проект) |
| Window in a project | Pin (Закрепить), add to project, remove from the project (Убрать из) |
| Pinned row | Edit (Изменить), unpin (Открепить) |
| Project header | Rename (Переименовать), color (Цвет), rules (Правила), delete the project (Удалить проект) |

**Add to project** asks for a project name and a word the window title must contain. An empty word puts every window of the app into the project. Typing a new name creates the project.

## Pins

A pin remembers the app, a title and an address. While the pinned window or tab is open, its row behaves like any window row and shows a pin mark. After it closes, the row stays, dimmed, and a click opens the address in the app the pin was made from. A pin without an address opens just the app.

Rail reads the address when you pin the row:

| App | Address the pin keeps |
|---|---|
| Browsers | The tab's URL, from the window's `AXDocument` (Chrome reports it there) or else from the `AXURL` of the page's web area |
| Apps that report a document for the window | The document's file, from `AXDocument` |
| Finder | The folder, worked out from the paths of the files shown in the window |
| Slack | The open thread, or the channel, as a `slack://` link |
| Telegram and other apps that do not report what a window shows | A link you type when pinning |

Only the selected tab of a browser window has its page in the accessibility tree. To read the URL of a background tab, Rail selects that tab for a moment and then selects the previous tab again.

The pin dialog opens when Rail finds no address, and from **Edit** on a pinned row. Its link field accepts:

| App | Accepted input | Opens as |
|---|---|---|
| Telegram | `@username`, `t.me/username`, `t.me/username/123` | `tg://resolve?domain=…` |
| Telegram | A phone number such as `+7 999 123-45-67` | `tg://resolve?phone=…` |
| Telegram | `t.me/+invite` | `tg://join?invite=…` |
| Slack | A message link from **Copy link** | `slack://channel?team=…&id=…&message=…&thread_ts=…` |
| Any | A URL, a custom scheme link, or a file path (`~/…`, `/…`) | As typed |

Slack opens only `slack://` links, and those need the workspace ID that a message link does not contain. Rail takes the ID from the address of Slack's page and stores it the first time it reads a Slack window. A pin saved with an `https` Slack link turns into a `slack://` link on the next refresh once the ID is known.

## Permissions and private APIs

Rail needs one permission, Accessibility. It reads window titles, tabs and addresses through the Accessibility API, and lists windows with `CGWindowListCopyWindowInfo`, which reports window numbers and owners without Screen Recording access.

The public Accessibility API sees only windows on the current Space and cannot switch to another one. For those, Rail loads private calls at runtime, the approach [AltTab](https://github.com/lwouis/alt-tab-macos) uses:

| Call | Framework | Use |
|---|---|---|
| `_AXUIElementGetWindow` | HIServices | Window number of an accessibility element |
| `_AXUIElementCreateWithRemoteToken` | HIServices | Finds windows on other Spaces |
| `GetProcessForPID` | HIServices | Process serial number for the SkyLight calls |
| `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo` | SkyLight | Brings a window on another Space to the front |
| `SLSCopySpacesForWindows`, `SLSMainConnectionID` | SkyLight | Tells background tabs of Finder and Terminal from windows on other Spaces |

If a later macOS drops one of these symbols, Rail falls back to windows on the current Space instead of failing to start. The private calls rule out the Mac App Store.

Rail makes no network requests. It stores projects, pins and the Slack workspace ID in its user defaults (`com.olchu.Rail`).

## Limitations

- The sidebar has no keyboard shortcut; it opens from the screen edge or the menu bar icon.
- Slack's full-screen window on another Space is missing from the list: the scan for windows on other Spaces does not find it. Slack pins still open.
- A pinned Slack thread always shows as closed, since Slack's window title names only the channel.
- Finder cannot report the folder of an empty folder in list or icon view, of Recents, or of search results; pinning such a window asks for the path.
- A Telegram chat without a username can be pinned only by the phone number of a contact.
- The interface is available in Russian only.

## License

[MIT](LICENSE)
