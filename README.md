# T3 Bar

A companion menu bar app for [T3 Code](https://github.com/pingdotgg/t3code) that shows how much of your AI
provider rate limits you have used, and whether you are on pace to run out before the window resets.

It shows every provider T3 Code tracks usage for: Claude, Codex, Antigravity, a second Codex account, the accounts
of a CLIProxyAPI hub. It reads the usage T3 Code already keeps, so with T3 Code installed there is nothing to log
in to or set up, and without it there is nothing to show.

<img src="docs/screenshots/popover.png" alt="The menu bar reading and the popover with Claude and ChatGPT, annotated: usage so far, projected usage at reset, how much of the window has passed, and how long you would be locked out" width="750">

> **A personal project.** I built T3 Bar for myself, and it is opinionated to match how I work: the
> providers I use, the windows I care about, the defaults I like. It is public in case it is useful to
> someone else.

## What you see

- **Menu bar reading** with the 5-hour window usage, for example `42%`, in the menu bar's own text colour
  like the clock beside it. With two providers there, their readings are stacked, Claude above Codex, each
  behind its provider's logo, so the item stays as narrow as one reading. Whether you are on pace to run out
  shows in the tooltip and the popover.
- **Left click** opens a popover with every limit window of every provider: 5-hour, weekly, and weekly per
  model.
  Each bar is green below 70%, yellow from 70%, red from 90%. A translucent segment behind the bar
  shows the projected usage at reset, and a thin cursor marks how much of the window's time has
  passed: a fill past the cursor means usage is running ahead of time. A line underneath says how
  long you will be locked out (`Locked out for ~1h 20m`, or `~2d 19h` for a day or more, in red) or
  that the window `Lasts to reset`.
- **Right click**, or Refresh in the popover, re-reads T3 Code's latest readings at once; a light runs round
  the pill and the icon turns while it runs, and the icon shows a checkmark once the data is in. The app also
  re-reads every 5 minutes and after the Mac wakes.
- Hover the pill for a tooltip with the reset countdown and, when you are on pace to run out, the lockout.

## How the forecast works

A rate-limit window opens at 0% on its first request, so usage is 0 at `resetsAt - windowLength`.
That anchor plus every reading taken during the window gives a least-squares line; extending it to
the reset time yields the projected usage. Readings are stored per window under
`~/Library/Application Support/T3 Bar/` so the estimate survives restarts. The 5-hour window is
5 hours long, the weekly windows are 7 days.

## Settings

Settings… in the popover (or ⌘, while it is open) opens Settings: launch at login, how often to re-read T3 Code's readings
(1 to 15 minutes, default 5) and an optional shortcut that opens the popover from
any app (none by default). Each provider has one choice: which of its windows the pill shows, "Popover only", which keeps it
out of the menu bar, or "Off", which also stops fetching it. The menu bar fits two providers, so once two are there no
other can be placed there until one makes room. T3 Code's built-in Claude and Codex start out in the menu bar,
any other provider "Popover only". Every Codex account gets the OpenAI logo, and a provider without a logo is
marked in the pill with its initial. With no provider in the menu bar the item
shows a gauge icon, so the popover stays within reach. A Hyper key (all of ⌃⌥⇧⌘, e.g. Caps Lock remapped by Karabiner-Elements or Raycast)
shows as ✦. The shortcut needs ⌃ or ⌘ unless it is a function key, because macOS 15 ignores global shortcuts
built from ⌥ and ⇧ alone. Changes apply at once and are kept in the
app's user defaults (`defaults read com.torz.t3bar`).

## How the data is fetched

T3 Code keeps a status file per provider instance in `~/.t3/caches/<instance>.json` (or under `T3CODE_HOME`),
with the rate-limit windows it last saw. It fills them from its own probes, every 5 minutes while it runs, and
from its sessions. T3 Bar only reads those files: it holds no tokens and calls no provider. A provider appears as
soon as T3 Code reports usage for it, and each reading is dated by when T3 Code took it, so when T3 Code is closed
the popover's "Updated … ago" shows how old the numbers are. The files are T3 Code's internal cache, not a
published API, so a file T3 Bar cannot read counts as no reading.

A [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) hub connected in T3 Code
([how](https://github.com/pingdotgg/t3code/blob/main/docs/user/usage.md#connect-a-cliproxyapi-hub)) shows too, one
provider per account in its pool, named by the account's email and starting out "Popover only". T3 Code polls the
hub itself but keeps those readings in memory, so T3 Bar subscribes to the running T3 Code server's config stream
for them. It mints its own token for that with T3 Code's bundled CLI (`t3 auth session issue --scope
orchestration:read --ttl 1d --label "T3 Bar"`), keeps it in memory only, and mints a new one when T3 Code refuses
it; the session shows as "T3 Bar" in `t3 auth session list`. Hub accounts update as soon as T3 Code reports them,
and keep their last readings while T3 Code is closed. The stream is T3 Code's internal RPC, not a published API,
so a T3 Code update can change it; T3 Bar then shows no hub accounts and keeps trying.

## Requirements

- macOS 14 or newer
- Xcode 16 or newer (Swift 6 toolchain)
- T3 Code, signed in to the providers you want to see

## Install or update

```
make install   # or scripts/install.sh
```

The same command does both jobs. It pulls the latest code (fast-forward only, so it stops instead of merging
into a checkout that has diverged), builds a release bundle, quits any running copy, puts the new one in
`/Applications` (`~/Applications` if that is not writable) and launches it. Settings and forecast history
are kept, because they live outside the bundle.

## Build and run

```
make build   # swift build
make test    # swift test
make app     # bundle dist/T3 Bar.app
make run     # build and launch the app bundle
```

## Project layout

```
Sources/T3BarCore   Foundation-only library: model, T3 Code reading, forecasting, text, badge and bar
                    geometry. Everything here is unit-tested without AppKit.
Sources/T3Bar       The menu bar app: status item, badge rendering, popover, polling controller.
Tests/T3BarCoreTests
Support/Info.plist  Bundle metadata (LSUIElement, so no Dock icon).
tickets/            The design notes each part was built from, in dependency order.
```

## Adding a provider

There is nothing to add here: a provider shows up once T3 Code reports usage for it. Windows of 5 hours and of a
week get forecasts. To give it a logo instead of its initial, add its T3 Code driver to `ProviderMark`.
