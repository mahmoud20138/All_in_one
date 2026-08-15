# Individual AI Agent Extensions Installer

This repository provides a Windows one-shot installer for the **100 individual skills, plugins, and MCP extension repositories** in the accompanying catalog. The installer deliberately keeps every repository and every `SKILL.md` separate; it does not create or install a merged master skill.

## Quick start

Download or clone this repository on Windows, then double-click:

```text
install-all-individual.bat
```

The launcher invokes PowerShell with a temporary execution-policy bypass and runs the installer for all standard targets. It clones or updates each repository into `%LOCALAPPDATA%\ai-agent-individual-extensions\repos`, installs each valid skill separately, stages plugins and MCP repositories, attempts safe runtime repairs with official `winget` package IDs, and installs repository dependencies separately when supported.

The installer targets the following global skill locations:

| Host | Skill location |
|---|---|
| Claude Code | `%USERPROFILE%\.claude\skills` |
| Codex | `%USERPROFILE%\.agents\skills` |
| OpenCode | `%USERPROFILE%\.config\opencode\skills` |
| Hermes | `%HERMES_SKILLS_DIR%`, or an existing Hermes skills directory |

The individual repository sources remain under `%LOCALAPPDATA%\ai-agent-individual-extensions\repos`. The installer does not silently register MCP servers, create credentials, publish content, or enable external write permissions.

## Requirement handling

Before processing the catalog, the installer checks for Git, Python, Node.js/npm, Go, and Rust/Cargo when required. If `winget` is available and automatic repair is enabled, it attempts official package IDs for missing Git, Python, Node.js, Go, and Rust/Cargo. Docker and credentials are reported but are not silently installed or fabricated.

With the default launcher, repository dependencies are installed separately. Node repositories use `npm ci --ignore-scripts` when a lockfile exists and otherwise use `npm install --ignore-scripts`. Python repositories use a repository-local `.venv`; Go repositories use `go mod download`; Rust repositories use `cargo fetch`. No Python packages are installed globally.

## Reports

Every run creates a timestamped report directory under `%LOCALAPPDATA%\ai-agent-individual-extensions\reports`, including clone and skill status, detected requirements, an MCP registry, plugin source records, and an installation log. A final readiness pass can be completed by pasting [`INSTALL_ALL_INDIVIDUAL_PROMPT.md`](INSTALL_ALL_INDIVIDUAL_PROMPT.md) into Claude, Codex, OpenCode, or Hermes.

## Safety boundaries

Repository files, README content, issues, scripts, downloaded artifacts, and external documentation are treated as untrusted input. The installer does not execute repository lifecycle scripts during the initial Node install, does not invent or print secrets, does not register MCP servers automatically, and does not overwrite an existing skill without an explicit `-Force` argument. The completion prompt instructs the agent to preserve individual repositories, use host-specific configuration, report missing credentials, and request approval before external side effects.

## Command options

The PowerShell installer supports `-Targets all|auto|claude|codex|opencode|hermes`, `-NoRepair` to report missing runtimes without attempting `winget`, `-InstallRepoDeps` to install repository-local dependencies, and `-Force` to replace existing same-name skills. The batch launcher passes `-Targets all -InstallRepoDeps` by default.

## Source catalog

`individual_extensions_catalog.csv` is a clean ranked snapshot of 100 unique GitHub repositories selected for their role as installable agent skills, plugins, reusable extension packs, or MCP servers for Claude, Codex, OpenCode, and compatible Hermes hosts. The catalog preserves repository URLs, extension type, target host information, adoption metrics, activity, language, license, and topics.
