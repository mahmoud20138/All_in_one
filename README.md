# Individual AI Agent Extensions Installer

This repository provides a Windows one-shot installer for the **100 individual skills, plugins, and MCP extension repositories** in the accompanying catalog. The installer deliberately keeps every repository and every `SKILL.md` separate; it does not create or install a merged master skill.

## Quick start

Download or clone this repository on Windows, then double-click `install-all-individual.bat`. The launcher now displays an interactive menu with **Top 10**, **Top 25**, **Top 50**, **All 100**, and **Quit** choices. You can also pass a ranked scope directly from Command Prompt:

```bat
install-all-individual.bat top10
install-all-individual.bat top25
install-all-individual.bat top50
install-all-individual.bat all
```

The launcher invokes PowerShell with a temporary execution-policy bypass and runs the installer for all standard targets. It processes every one of the 100 catalog rows individually, clones or updates each repository into `%LOCALAPPDATA%\ai-agent-individual-extensions\repos`, installs each valid skill separately, stages plugins and MCP repositories, attempts safe runtime repairs with official `winget` package IDs, and installs repository dependencies separately when supported. It produces a final per-repository state for all 100 rows and exits with an error if any repository clone fails or any catalog skill cannot be installed, unless `-AllowPartial` is explicitly supplied.

The installer targets the following global skill locations:

| Host | Skill location |
|---|---|
| Claude Code | `%USERPROFILE%\.claude\skills` |
| Codex | `%USERPROFILE%\.agents\skills` |
| OpenCode | `%USERPROFILE%\.config\opencode\skills` |
| Hermes | `%HERMES_SKILLS_DIR%`, or an existing Hermes skills directory |

The individual repository sources remain under `%LOCALAPPDATA%\ai-agent-individual-extensions\repos`, which is outside `%USERPROFILE%\Downloads`. The installer refuses to use Downloads or any subfolder of Downloads as a clone workspace. You may provide another dedicated non-Downloads location with `-Workspace C:\AI\extensions`; it is marked with `.ai-agent-individual-extensions-workspace`.

To inspect Downloads without changing it, run `install-all-individual.ps1 -InstallSet top10 -ScanDownloads`. To remove only a workspace previously created and marked by this installer, run `install-all-individual.ps1 -CleanWorkspace`. Cleanup refuses to delete any path without the installer marker and never deletes unrelated Downloads files.

The installer does not silently register MCP servers, create credentials, publish content, or enable external write permissions. Therefore, a plugin or MCP row is considered **processed and staged**, not fully activated, until its host-specific registration, runtime, transport, and credentials have been verified. The final report labels these rows `plugin-staged-host-registration-pending` or `mcp-staged-host-registration-pending` instead of falsely claiming they are ready.

## Requirement handling

Before processing the catalog, the installer checks for Git, Python, Node.js/npm, Go, and Rust/Cargo when required. If `winget` is available and automatic repair is enabled, it attempts official package IDs for missing Git, Python, Node.js, Go, and Rust/Cargo. Docker and credentials are reported but are not silently installed or fabricated.

With the default launcher, repository dependencies are installed separately. Node repositories use `npm ci --ignore-scripts` when a lockfile exists and otherwise use `npm install --ignore-scripts`. Python repositories use a repository-local `.venv`; Go repositories use `go mod download`; Rust repositories use `cargo fetch`. No Python packages are installed globally.

## Reports

Every run creates a timestamped report directory under `%LOCALAPPDATA%\ai-agent-individual-extensions\reports`, including clone and skill status, detected requirements, an MCP registry, plugin source records, and an installation log. A final readiness pass can be completed by pasting [`INSTALL_ALL_INDIVIDUAL_PROMPT.md`](INSTALL_ALL_INDIVIDUAL_PROMPT.md) into Claude, Codex, OpenCode, or Hermes.

## Safety boundaries

Repository files, README content, issues, scripts, downloaded artifacts, and external documentation are treated as untrusted input. The installer does not execute repository lifecycle scripts during the initial Node install, does not invent or print secrets, does not register MCP servers automatically, and does not overwrite an existing skill without an explicit `-Force` argument. The completion prompt instructs the agent to preserve individual repositories, use host-specific configuration, report missing credentials, and request approval before external side effects.

## Command options

The PowerShell installer supports `-InstallSet top10|top25|top50|all`, `-Targets all|auto|claude|codex|opencode|hermes`, `-Workspace` for a dedicated non-Downloads clone root, `-ScanDownloads` for a non-destructive scan, `-CleanWorkspace` for marker-protected cleanup, `-NoRepair` to report missing runtimes without attempting `winget`, `-InstallRepoDeps` to install repository-local dependencies, `-Force` to replace existing same-name skills, and `-AllowPartial` to opt out of strict clone/skill failure handling. The batch launcher passes `-Targets all -InstallSet <selected-scope> -InstallRepoDeps` by default and keeps strict completion enabled. If no scope is supplied, the interactive menu sets `<selected-scope>` before PowerShell starts.

## Source catalog

`individual_extensions_catalog.csv` is a clean ranked snapshot of 100 unique GitHub repositories selected for their role as installable agent skills, plugins, reusable extension packs, or MCP servers for Claude, Codex, OpenCode, and compatible Hermes hosts. The catalog preserves repository URLs, extension type, target host information, adoption metrics, activity, language, license, and topics.
