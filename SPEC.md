# Applets for Quickshell: applet format, version 0

This document is the contract between applets, the `qsa` CLI and the
`qs.Applets` QML module that hosts them, either embedded in a Quickshell config
or in the standalone runtime. Anything not described here is an implementation
detail.

## Layout

Applets live in `$APPLETS_HOME`, by default `$XDG_CONFIG_HOME/applets`
(`~/.config/applets`). Each applet is one folder:

```
~/.config/applets/
├── theme.json            optional, see "Theme tokens"
└── tz/
    ├── applet.toml       manifest
    └── main.py           entry
```

Folders starting with `.` are ignored. Per-applet data lives in
`$XDG_DATA_HOME/applets/<name>/` (default `~/.local/share/applets/<name>/`) and
is created automatically.

## Manifest: `applet.toml`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | folder name | Lowercase letters, digits and dashes. Must equal the folder name. |
| `entry` | string | required | File inside the folder. `.qml` makes a QML applet; anything else is a script applet and must be executable. Optional when `bar` names a `.qml` file (a bar-only applet). |
| `title` | string | `name` | Shown in the header and window title. |
| `description` | string | `""` | One line, shown by `qsa install`. |
| `icon` | string | `""` | A short glyph for the bar chip, for example `"◷"`. |
| `bar` | bool or string | `false` | `true` shows a chip in each `AppletBar`; a `.qml` file path shows that file there instead. See "Bar". |
| `surface` | string | `"popup"` | `popup`, `floating` or `desktop`. See "Surfaces". |
| `position` | string | `"top-right"` | Desktop surface anchor: `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right`. |
| `layer` | string | `"below"` | Desktop surface: `below` keeps the widget under windows, `above` puts it over them. |
| `screen` | string | `""` | Output name (for example `DP-1`). Empty means the focused output on Hyprland, otherwise the first one. |
| `width` | int | `420` | Content width in pixels. |
| `height` | int | `0` | Content height. `0` sizes script applets to their content (up to 640) and QML applets to 300. |
| `key` | string | `""` | Suggested shortcut, for example `"SUPER + CTRL + T"`. `qsa binds` turns it into compositor configuration; applets do not grab keys themselves. |
| `config` | table | `{}` | Free-form settings passed to the applet. |
| `interval` | int | `0` | Script only. Seconds between refreshes while active (shown, or always when in a bar). `0` refreshes only on show, at start for bar applets, and after actions. |
| `timeout` | int | `20` | Script only. Seconds before a refresh, action or input run is stopped. |
| `stream` | bool | `false` | Script only. Keep the script running while active; every stdout line is a new state. |
| `input` | bool | `false` | Script only. Show a text field; Enter submits it. |
| `placeholder` | string | `""` | Script only. Placeholder for the text field. |

Unknown keys are ignored, so newer manifests keep loading in older versions.

## Script applets

### Invocation

The entry is executed directly (no shell), with the applet folder as its
working directory:

| Call | When |
|---|---|
| `entry` | Refresh: on show, every `interval` while active, and after an action that printed nothing. A `stream` applet runs while active. |
| `entry action <id>` | An item with `"run": "<id>"` was chosen. |
| `entry input <text>` | The text field was submitted. |

Environment:

| Variable | Value |
|---|---|
| `APPLET_NAME` | Applet name. |
| `APPLET_DIR` | Absolute path of the applet folder. |
| `APPLET_DATA` | Writable data folder for this applet. |
| `APPLET_CONFIG` | The manifest's `[config]` table as JSON. |
| `APPLET_EVENT` | `refresh`, `action` or `input`. |

A script applet is active while its window is shown, and always when it has
`bar` set. A non-zero exit status keeps the previous state and shows the last
line of stderr as the error.

### Output

A run prints one JSON object. Pretty-printed output is accepted; when stdout
has several lines that do not parse as a whole, the last line is used. In
`stream` mode, each line is a complete object.

```json
{
  "text": "3",
  "icon": "⎇",
  "class": "warning",
  "title": "Unsaved work",
  "tooltip": "3 repositories have changes",
  "body": "Plain text shown under the header.",
  "placeholder": "Overrides the manifest placeholder",
  "notify": "Sends a desktop notification with this text",
  "error": "Shown in the footer instead of the update time",
  "items": [
    {
      "text": "dotfiles",
      "detail": "4 changed",
      "icon": "●",
      "class": "warning",
      "run": "commit-dotfiles",
      "copy": "/home/me/dotfiles",
      "open": "/home/me/dotfiles",
      "close": false
    }
  ]
}
```

Every field is optional.

- `text`, `tooltip` and `class` follow Waybar's custom-module format, so
  `qsa run <name>` works as a Waybar module with `"return-type": "json"`.
  `text` appears in the window header and the bar chip; `tooltip` is only
  used by Waybar.
- `icon` overrides the manifest `icon` in the bar chip.
- `class` (on the state or an item) is one of `accent`, `muted`, `success`,
  `warning`, `error`. Other values render as normal text.
- An item can have any combination of `run`, `copy` and `open`:
  - `run` calls `entry action <id>`.
  - `copy` puts the string on the clipboard.
  - `open` passes the string to `xdg-open`.
- After `copy` or `open`, popups and floating windows close unless
  `"close": false`. When the window stays open, a copy shows "Copied" in its
  footer.
- If an action or input run prints an object, that becomes the new state.
  If it prints nothing, a refresh follows.
- All text is plain text, never markup.

## QML applets

A QML entry, and a `bar` QML file, has a root item that declares the injected
API:

```qml
import QtQuick
import qs.Applets

Item {
    required property var applet
}
```

The `qs.Applets` module provides `AppletTheme` (a singleton with the tokens below
plus `tone(class)`), `AppletText`, `AppletButton` and `AppletField`. Other
files in the applet folder can be imported relatively.

`applet` has:

| Member | Meaning |
|---|---|
| `name`, `title`, `icon`, `dir`, `dataDir` | Strings from the manifest; `dir` and `dataDir` are absolute paths. |
| `config` | The `[config]` table. |
| `theme` | Same object as `AppletTheme`. |
| `shown` | Whether the applet's window is visible. |
| `store.get(key, fallback)` / `store.set(key, value)` | JSON values persisted in `dataDir/store.json`. Bindings using `get` update on `set` and on external edits. `set(key, undefined)` deletes. |
| `show()`, `close()`, `toggle()` | Open, hide or toggle the applet's window. |
| `notify(title, body)` | Desktop notification. |
| `copy(text)` | Put text on the clipboard. |
| `open(target)` | `xdg-open` a URL or path. |
| `run(argv, callback)` | Run a program without a shell; `callback(stdout, exitCode, stderr)`. |
| `state`, `error` | A script applet's current output and error, for a custom bar item of a script applet. |
| `refresh()`, `action(id)`, `submit(text)` | Script applets: run the entry as described in "Invocation". |

Popups and floating windows destroy their item when hidden, so keep state that
must survive in `store`.

## Surfaces

- `popup`: centered overlay on one output, or attached to the bar chip that
  opened it (below it, or above on a bottom bar). Escape or a click outside
  closes it. Takes keyboard focus while open.
- `floating`: a regular window. The compositor decides whether it floats or
  tiles; closing it hides the applet.
- `desktop`: a widget shown from start, under windows (above the wallpaper)
  or, with `layer = "above"`, over them. Keyboard focus is given on click.

## Bar

`AppletBar` (see "Embedding") shows every applet with `bar` set, in name
order, or the applets named in its `names` property, in that order. Use `names`
to split applets between several places in a bar; an `AppletBar` without
`names` shows all of them.

- `bar = true` shows a chip: the icon (state `icon`, else manifest `icon`) and
  the script output's `text`, colored by `class`. As in Waybar, an empty `text`
  hides the chip; a missing `text` shows only the icon. A failed script with no
  text shows a warning sign. Clicking toggles the applet's window, attached to
  the chip for `popup` applets.
- `bar = "Bar.qml"` places that QML file in the bar instead, with the same
  `applet` object as QML applets. It sizes itself through `width`/`height`.
  One instance is created per bar.

## Theme tokens

The tokens are: `background`, `surface`, `surfaceAlt`, `border`, `foreground`,
`foregroundDim`, `muted`, `accent`, `warning`, `error`, `success` (colors),
`opacity` (card background, 0–1), `rounding`, `borderSize`, `fontFamily` and
`fontSize`.

Each token is looked up in this order:

1. `AppletsHost.theme`: any QML object or JS object with properties of those
   names, usually the shell's own theme singleton. Bindings follow its changes.
2. `$APPLETS_HOME/theme.json`, reloaded when it changes. Useful for the
   standalone runtime.
3. Built-in neutral defaults.

```json
{
  "background": "#16161a", "surface": "#1e1e24", "surfaceAlt": "#2a2a32",
  "border": "#3a3a44", "foreground": "#e6e6eb", "foregroundDim": "#a6a6b0",
  "muted": "#70707c", "accent": "#8ab4f8", "warning": "#e7c787",
  "error": "#e07070", "success": "#8fbf8f",
  "opacity": 1, "rounding": 8, "borderSize": 1,
  "fontFamily": "Inter", "fontSize": 12
}
```

`opacity` values below 1 rely on the compositor blending layer surfaces.

## Embedding

`qsa setup <config>` links the module into a Quickshell config as
`<config>/Applets`, which makes `import qs.Applets` work there and in applet
files. A shell then adds:

```qml
import qs.Applets

ShellRoot {
    AppletsHost {
        id: applets
        theme: Theme          // optional
    }

    // in each bar
    AppletBar { host: applets }
}
```

Use one `AppletsHost` per shell. Its properties are `theme` and `cli`, the
path of the `qsa` CLI; when empty, the CLI is found through the module link.
The host starts `qsa watch`, which reports applets and their changes.
`AppletBar` has `host` and `names`.

The standalone runtime (`runtime/shell.qml`, started by `qsa daemon`) is
just a `ShellRoot` with an `AppletsHost`, so it has no bar.

## IPC

The host registers the Quickshell IPC target `applets`. The CLI talks to the
instance in `$APPLETS_SHELL` (a config path) if set, else a running standalone
runtime, else the default Quickshell config.

| Function | CLI |
|---|---|
| `toggle(name)`, `open(name)`, `close(name)` | `qsa toggle\|show\|hide <name>` |
| `action(name, id)` | `qsa send <name> --action <id>` |
| `submit(name, text)` | `qsa send <name> --input <text>` |
| `list()` | `qs ipc call applets list` |

Toggling a bar-only applet fails because it has no window.

## Security

Applets are ordinary programs that run with your user account, without a
sandbox. `qsa install` lists an applet's files and asks before installing,
and `qsa new --ai` / `qsa edit --ai` show the generated files or diff
before anything runs or is installed. Read them before you accept.
