# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Project

`anubis-mcp-server-mobile` is an MCP (Model Context Protocol) server intended to run
**on a smartphone**, exposing three capability areas to an MCP client:

- **app-use** — driving apps installed on the device
- **data analysis** — working over on-device data
- **calling** — placing/handling phone calls

## Current state

The repository is a greenfield scaffold: `README.md`, `LICENSE` (MIT), and a `.gitignore`.
There is **no source code, build system, dependency manifest, or test suite yet**.

Implications when working here:

- Do not assume a project layout, entry point, or command set exists — check first.
- The `.gitignore` is GitHub's standard Python template, so Python is the presumed
  language, but nothing is committed that confirms a runtime, package manager, or
  MCP SDK choice. Confirm with the user before picking one.
- When the first real code lands (package manifest, entry point, test runner),
  update this file with the actual build/test/run commands and the architecture
  as-built, and delete this section.

## Constraints to keep in mind

The mobile deployment target is the defining constraint of this project: the server
runs on-device rather than on a workstation or in the cloud. Anything that assumes a
desktop filesystem, a long-lived background process, or unrestricted network/OS access
is likely wrong for this target.
