# Changelog

Every change a user of dockerpen would notice, newest first. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org/): while dockerpen is `0.x`, a minor release may
change what the previous one did.

## [Unreleased]

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
