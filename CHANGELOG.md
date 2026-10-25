# Changelog

Every change a user of dockerpen would notice, newest first. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org/): while dockerpen is `0.x`, a minor release may
change what the previous one did.

## [Unreleased]

### Changed

- dockerpen is now one native file instead of a Node package: the program is Lua, the
  interface is drawn by your terminal in its own font and theme (a page of the pencere kit, no
  web view), and there is nothing to install but the file and Docker. It is made for macOS on
  Apple silicon and for Linux on `arm64` and `x86_64`, and is taken from the releases of this
  repository, not from npm.
- It runs the `docker` command instead of talking to the engine's socket, so it reaches the
  engine the way `docker` does for you: the current Docker context, `DOCKER_HOST`, a rootless
  Docker, OrbStack, Colima, Rancher Desktop and Podman's `docker` all work with nothing to set
  up. It needs `docker` on the `PATH`, and says so when it is not there, and says when there is
  no engine to talk to and carries on by itself when there is again.
- Nothing runs while nothing is shown: one `docker events` runs while the interface is up, one
  `docker stats` only while the containers are on show, a container's log only while its log is,
  and none of them while a shell has the pane.
- A log is a window of rows, so a container's log of a hundred thousand lines scrolls and is
  searched as easily as one of a hundred. The charts are the last thirty readings.
- A project's row stands for all of its containers: `s`, `r` and `p`, and the button on the row,
  act on them together.

### Added

- **One line installs it.** `curl -fsSL https://raw.githubusercontent.com/bateri/dockerpen/main/install.sh | sh`
  puts the newest release in `~/.local/bin` after checking it against the release's `SHA256SUMS`
  (`DOCKERPEN_VERSION` takes a version, `DOCKERPEN_INSTALL` another directory). A file `curl`
  fetches is not quarantined by macOS, as a browser's download is.
- Each file of a release carries an attestation of the workflow that built it
  (`gh attestation verify <file> --repo bateri/dockerpen`).

- `dockerpen --text` prints the containers as text, whatever the terminal is, and `--help` and
  `--version` say what they say.
- `z` takes back the last stop from the keyboard, as the button on the toast does.
- `⇧→` and `⇧←` read the lines of a log further to the right and back, and `0` returns them to
  their start.
- The log of a container that was stopped and started again goes on from the line it ended
  with, without the lines before it a second time.

### Fixed

- The interface is drawn as the first dockerpen drew it, again, where the native page had drifted
  from it: sizes, spacing, colours and weights of the list, the rail, the status line, the
  container's detail and log, the other lists, System, Activity, the dialogs, the help and the
  palette. Text that the first dockerpen wrapped wraps again (the engine's numbers in the rail,
  empty screens, dialogs, toasts, the help) instead of running past its box, and a toolbar that
  has no room cuts at its edge. Each list's field says what it filters ("Filter images"), also
  while you type in it (the terminal's field shows the page's words), and so do the palette's, the
  log's, the environment's and the pull dialog's. Wrapped text breaks where your terminal's font
  says, not by a guess at the width of a character.
- A password inside a URL in a container's environment (`postgres://user:secret@…`) is hidden
  again until it is revealed.

### Removed

- The MCP server: `show_docker` and the tools a model could call (`list_containers`,
  `container_logs`, `disk_usage`) are not in this one.
- The command palette, and opening a published port in the browser: a page of the kit has one
  text field to give and cannot ask its terminal to open a link.
- Dragging the edge of the detail to resize it, and the pulse and the spinner a row had while a
  container ran or was changing state: a row says it in a word (`stopping…`), and its colour.

## [0.2.1] - 2026-10-22

### Fixed

- The icons, checkboxes and layers button in the first column of the image, volume and network
  lists sit on the middle of their row, where a container's dot sits in its list, instead of on
  the text's baseline and further left.

## [0.2.0] - 2026-10-22

### Added

- dockerpen's icon, its mark of three stacked containers, beside its name above the view in a
  terminal that draws program icons (bateri), and beside the server in MCP clients that show
  them. It comes for a dark ground and a light one, as PNGs inside the program, since a terminal
  draws only the icons it is given and fetches none.

### Changed

- The rail starts with the sections: the mark, the name and the user and machine at its top are
  gone, since the terminal says them above the view (its strip in bateri names the program, with
  its icon, and the machine it runs on), as an MCP Apps host names the app it shows.
- A selected row of the image, volume and network lists is outlined whole, as in the container
  list, instead of marked by a bar at its left.

### Fixed

- The first row of a list no longer touches the line under the list's header when it is hovered
  or selected: every list keeps the same gap there, and keeps it while rows scroll under the
  header.
- A row chosen with the keys in the image, volume and network lists is no longer left under
  their header when the list scrolls to show it.

## [0.1.1] - 2026-10-22

### Fixed

- ⌃C no longer leaves the pane on the alternate screen when dockerpen runs under something that
  passes the interrupt on, as `npx dockerpen` and `npm start` do: the second interrupt could end
  it between saying goodbye to the terminal and giving the screen back. It takes
  `@pencere/sdk` 0.1.1, which keeps listening until the terminal is given back.

## [0.1.0] - 2026-10-22

### Added

- Containers grouped by compose project, with their state, health, CPU, memory, published
  ports and uptime; filters for running, stopped and those with issues; start, stop, restart,
  pause, kill and remove for one container, a project or several marked ones, and a stop that
  can be undone.
- The detail of a container: live CPU, memory and network charts, why it stopped, health
  checks, ports, networks, mounts and labels; its logs with the program's colours, search and
  follow; its environment with secret-looking values hidden; its processes; the engine's
  whole answer.
- A shell in a container (`e`) and its logs as they come (`F`) in the terminal itself: the
  interface steps aside and comes back where it was.
- Images with their layers, pull and update; volumes with their size; networks; the disk
  Docker takes and a clean-up that says what it frees; the engine's events, and a toast when a
  container dies, runs out of memory or turns unhealthy.
- Everything by keyboard and by mouse alike, a command palette (`:`), and colours and font
  from the terminal's theme, down to an 80×24 pane.
- As an MCP server: `show_docker` shows the interface in any MCP Apps host, and a model can
  list containers, read logs and look at the disk; what changes something is the person's.
- Speaks version 1 of the pencere wire, through `@pencere/sdk` 0.1.
