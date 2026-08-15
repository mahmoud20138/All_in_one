[CmdletBinding()]
param(
    [ValidateSet('all','claude','codex','opencode','hermes','auto')]
    [string]$Targets = 'all',
    [switch]$NoRepair,
    [switch]$InstallRepoDeps,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Catalog = Join-Path $Root 'individual_extensions_catalog.csv'
$Stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$Base = if ($env:AI_AGENT_EXTENSIONS_DIR) { $env:AI_AGENT_EXTENSIONS_DIR } else { Join-Path $env:LOCALAPPDATA 'ai-agent-individual-extensions' }
$RepoDir = Join-Path $Base 'repos'
$BackupDir = Join-Path $Base "backups\$Stamp"
$ReportDir = Join-Path $Base 'reports'
$LogPath = Join-Path $ReportDir "install-$Stamp.log"
$StatusPath = Join-Path $ReportDir "install-status-$Stamp.csv"
$ReqPath = Join-Path $ReportDir "requirements-$Stamp.csv"
$McpPath = Join-Path $ReportDir "mcp-registry-$Stamp.json"
$PluginPath = Join-Path $ReportDir "plugin-sources-$Stamp.json"

New-Item -ItemType Directory -Force -Path $RepoDir,$ReportDir | Out-Null
function Log([string]$Message) {
    $line = "$(Get-Date -Format s) $Message"
    Add-Content -Path $LogPath -Value $line
    Write-Host $line
}
function CommandExists([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Try-Winget([string]$Id, [string]$Label) {
    if (-not (CommandExists 'winget')) { Log "MISSING: winget; cannot automatically add $Label."; return $false }
    Log "REPAIR: attempting winget install for $Label ($Id)."
    & winget install --id $Id -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | ForEach-Object { Add-Content -Path $LogPath -Value $_ }
    $checkCommand = 'python'
    if ($Label -eq 'Git') { $checkCommand = 'git' }
    elseif ($Label -eq 'Node.js') { $checkCommand = 'node' }
    if (($LASTEXITCODE -eq 0) -or (CommandExists $checkCommand)) { Log "READY: $Label"; return $true }
    Log "UNRESOLVED: $Label installation did not complete; restart the shell and rerun."; return $false
}

$Prereqs = @()
if (-not (CommandExists 'git')) {
    if ($NoRepair) { Log 'MISSING: Git (required to clone repositories).' } else { Try-Winget 'Git.Git' 'Git' | Out-Null }
}
if (-not (CommandExists 'git')) { Log 'STOP: Git is still unavailable; repository cloning cannot proceed.'; exit 2 }
if (-not (CommandExists 'python')) {
    if ($NoRepair) { Log 'MISSING: Python (needed by some MCP/skill repositories).' } else { Try-Winget 'Python.Python.3.12' 'Python' | Out-Null }
}
if (-not (CommandExists 'node')) {
    if ($NoRepair) { Log 'MISSING: Node.js (needed by TypeScript/JavaScript MCP/plugin repositories).' } else { Try-Winget 'OpenJS.NodeJS.LTS' 'Node.js' | Out-Null }
}
if (-not (CommandExists 'npm') -and (CommandExists 'node')) { Log 'MISSING: npm; Node.js installation may need a shell restart.' }

if (-not (Test-Path $Catalog)) { Log "STOP: Catalog not found: $Catalog"; exit 3 }
$Rows = @(Import-Csv $Catalog | Where-Object { $_.repo -and $_.rank -and ([int]$_.rank -le 100) } | Sort-Object { [int]$_.rank })
if ($Rows.Count -ne 100) { Log "STOP: Expected 100 catalog rows, found $($Rows.Count)."; exit 4 }
$needsGo = @($Rows | Where-Object { $_.primary_language -match '(?i)^Go$' }).Count -gt 0
$needsRust = @($Rows | Where-Object { $_.primary_language -match '(?i)Rust' }).Count -gt 0
if ($needsGo -and -not (CommandExists 'go')) {
    if ($NoRepair) { Log 'MISSING: Go runtime required by one or more catalog repositories.' } else { Try-Winget 'GoLang.Go' 'Go' | Out-Null }
}
if ($needsRust -and -not (CommandExists 'cargo')) {
    if ($NoRepair) { Log 'MISSING: Rust/Cargo required by one or more catalog repositories.' } else { Try-Winget 'Rustlang.Rustup' 'Rust/Cargo' | Out-Null }
}
$SeenRepos = @{}
foreach ($Row in $Rows) {
    if ($SeenRepos.ContainsKey($Row.repo)) { Log "STOP: Duplicate repository in catalog: $($Row.repo)"; exit 5 }
    $SeenRepos[$Row.repo] = $true
}

function Add-Target([string]$Name, [string]$Path) {
    if (-not ($script:TargetList | Where-Object { $_.Name -eq $Name })) { $script:TargetList += [pscustomobject]@{ Name=$Name; Path=$Path } }
}
$TargetList = @()
$ClaudeDir = Join-Path $HOME '.claude\skills'
$CodexDir = Join-Path $HOME '.agents\skills'
$OpenCodeDir = Join-Path $HOME '.config\opencode\skills'
$HermesDir = if ($env:HERMES_SKILLS_DIR) { $env:HERMES_SKILLS_DIR } else { Join-Path $HOME '.hermes\skills' }
if ($Targets -eq 'all') {
    Add-Target 'Claude' $ClaudeDir; Add-Target 'Codex' $CodexDir; Add-Target 'OpenCode' $OpenCodeDir
    if ($env:HERMES_SKILLS_DIR -or (Test-Path (Split-Path $HermesDir -Parent))) { Add-Target 'Hermes' $HermesDir }
} elseif ($Targets -eq 'auto') {
    if ((Test-Path (Join-Path $HOME '.claude')) -or (CommandExists 'claude')) { Add-Target 'Claude' $ClaudeDir }
    if ((Test-Path (Join-Path $HOME '.agents')) -or (CommandExists 'codex')) { Add-Target 'Codex' $CodexDir }
    if ((Test-Path (Join-Path $HOME '.config\opencode')) -or (CommandExists 'opencode')) { Add-Target 'OpenCode' $OpenCodeDir }
    if ($env:HERMES_SKILLS_DIR -or (Test-Path (Split-Path $HermesDir -Parent))) { Add-Target 'Hermes' $HermesDir }
} else {
    if ($Targets -eq 'claude') { Add-Target 'Claude' $ClaudeDir }
    if ($Targets -eq 'codex') { Add-Target 'Codex' $CodexDir }
    if ($Targets -eq 'opencode') { Add-Target 'OpenCode' $OpenCodeDir }
    if ($Targets -eq 'hermes') { Add-Target 'Hermes' $HermesDir }
}
if ($TargetList.Count -eq 0) { Log 'STOP: No host targets selected.'; exit 6 }
foreach ($Target in $TargetList) { New-Item -ItemType Directory -Force -Path $Target.Path | Out-Null }

$Statuses = @()
$Requirements = @()
$McpRegistry = @()
$PluginSources = @()
function SafeName([string]$Text) {
    $name = $Text.ToLowerInvariant() -replace '[^a-z0-9]+','-'
    $name = $name.Trim('-') -replace '-+','-'
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'extension' }
    if ($name.Length -gt 54) { $name = $name.Substring(0,54).TrimEnd('-') }
    return $name
}
function Add-Status($Row, [string]$Stage, [string]$State, [string]$Detail) {
    $script:Statuses += [pscustomobject]@{ rank=$Row.rank; repo=$Row.repo; type=$Row.extension_type; stage=$Stage; state=$State; detail=$Detail; url=$Row.url }
}
function Add-Requirement($Row, [string]$Requirement, [string]$State, [string]$Action) {
    $script:Requirements += [pscustomobject]@{ rank=$Row.rank; repo=$Row.repo; type=$Row.extension_type; requirement=$Requirement; state=$State; action=$Action; url=$Row.url }
}
function Clone-Repo($Row) {
    $repoName = $Row.repo.Replace('/','__')
    $path = Join-Path $RepoDir $repoName
    if (Test-Path (Join-Path $path '.git')) {
        Log "UPDATE: $($Row.repo)"
        & git -C $path fetch --depth 1 origin 2>&1 | ForEach-Object { Add-Content $LogPath $_ }
        & git -C $path reset --hard origin/HEAD 2>&1 | ForEach-Object { Add-Content $LogPath $_ }
        if ($LASTEXITCODE -eq 0) { return $path }
        Log "WARN: update failed; retaining existing clone for $($Row.repo)."; return $path
    }
    if (Test-Path $path) { Log "ERROR: non-git path blocks clone: $path"; return $null }
    Log "CLONE: $($Row.repo)"
    & git clone --depth 1 --no-tags $Row.url $path 2>&1 | ForEach-Object { Add-Content $LogPath $_ }
    if ($LASTEXITCODE -eq 0) { return $path }
    Log "ERROR: clone failed: $($Row.repo)"; return $null
}
function Read-SkillMeta([string]$SkillFile) {
    $text = Get-Content -Raw -LiteralPath $SkillFile
    $nameMatch = [regex]::Match($text, '(?m)^name:\s*(.+?)\s*$')
    $descMatch = [regex]::Match($text, '(?m)^description:\s*(.+?)\s*$')
    if (-not $nameMatch.Success -or -not $descMatch.Success) { return $null }
    return [pscustomobject]@{ Text=$text; Name=$nameMatch.Groups[1].Value.Trim(); Description=$descMatch.Groups[1].Value.Trim() }
}
function Install-Skill([string]$SkillRoot, $Row) {
    $skillFile = Join-Path $SkillRoot 'SKILL.md'
    $meta = Read-SkillMeta $skillFile
    if ($null -eq $meta) { return 0 }
    $repoName = SafeName ($Row.repo.Replace('/','-'))
    $originalName = SafeName $meta.Name
    $installName = SafeName "$repoName-$originalName"
    if ($installName.Length -gt 64) { $installName = $installName.Substring(0,64).TrimEnd('-') }
    foreach ($Target in $TargetList) {
        $destination = Join-Path $Target.Path $installName
        if (Test-Path $destination) {
            if (-not $Force) { Add-Status $Row 'skill' 'collision' "$Target.Name: $installName already exists; use -Force to replace."; continue }
            $destBackup = Join-Path $BackupDir "$($Target.Name)\$installName"
            New-Item -ItemType Directory -Force -Path (Split-Path $destBackup -Parent) | Out-Null
            Move-Item -Force $destination $destBackup
        }
        New-Item -ItemType Directory -Force -Path $destination | Out-Null
        Copy-Item -Path (Join-Path $SkillRoot '*') -Destination $destination -Recurse -Force
        $copiedFile = Join-Path $destination 'SKILL.md'
        $copiedText = Get-Content -Raw -LiteralPath $copiedFile
        $copiedText = [regex]::Replace($copiedText, '(?m)^name:\s*.+?\s*$', "name: $installName", 1)
        Set-Content -LiteralPath $copiedFile -Value $copiedText -Encoding utf8
        Add-Status $Row 'skill' 'installed' "$Target.Name: $installName"
    }
    return 1
}

foreach ($Row in $Rows) {
    $repoPath = Clone-Repo $Row
    if ($null -eq $repoPath) { Add-Status $Row 'clone' 'failed' 'Repository could not be cloned.'; continue }
    Add-Status $Row 'clone' 'ready' $repoPath
    $skillCount = 0
    $skillFiles = @(Get-ChildItem -LiteralPath $repoPath -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|\.venv|venv|dist|build)\\' })
    foreach ($SkillFile in $skillFiles) { $skillCount += Install-Skill $SkillFile.DirectoryName $Row }
    if ($skillCount -eq 0 -and $Row.extension_type -like 'Agent skill*') { Add-Status $Row 'skill' 'not-found' 'No valid SKILL.md with name and description found.' }
    if ($Row.extension_type -like 'MCP*' -or $Row.extension_type -like 'Plugin*') {
        $packageFiles = @('package.json','pyproject.toml','requirements.txt','go.mod','Cargo.toml','Dockerfile','.env.example') | Where-Object { Test-Path (Join-Path $repoPath $_) }
        $requirements = @()
        if (Test-Path (Join-Path $repoPath 'package.json')) { $requirements += 'Node.js/npm' }
        if ((Test-Path (Join-Path $repoPath 'pyproject.toml')) -or (Test-Path (Join-Path $repoPath 'requirements.txt'))) { $requirements += 'Python/pip' }
        if (Test-Path (Join-Path $repoPath 'go.mod')) { $requirements += 'Go' }
        if (Test-Path (Join-Path $repoPath 'Cargo.toml')) { $requirements += 'Rust/Cargo' }
        if (Test-Path (Join-Path $repoPath 'Dockerfile')) { $requirements += 'Docker' }
        if (Test-Path (Join-Path $repoPath '.env.example')) { $requirements += 'Environment variables/API credentials' }
        foreach ($req in $requirements) {
            $cmd = switch -Wildcard ($req) { 'Node*' { 'npm install --ignore-scripts' } 'Python*' { 'python -m venv .venv; pip install -r requirements.txt' }             'Go*' { 'go mod download' } 'Rust*' { 'cargo fetch' } 'Docker' { 'docker build .' } default { 'Review .env.example and configure secrets manually' } }
            $ready = switch -Wildcard ($req) { 'Node*' { CommandExists 'node' -and CommandExists 'npm' } 'Python*' { CommandExists 'python' } 'Go*' { CommandExists 'go' } 'Rust*' { CommandExists 'cargo' } 'Docker' { CommandExists 'docker' } default { $false } }
            Add-Requirement $Row $req ($(if ($ready) { 'available' } else { 'missing' })) $cmd
        }
        $record = [pscustomobject]@{ rank=$Row.rank; repo=$Row.repo; url=$Row.url; local_path=$repoPath; detected_files=$packageFiles; requirements=$requirements }
        if ($Row.extension_type -like 'MCP*') { $McpRegistry += $record } else { $PluginSources += $record }
        Add-Status $Row 'extension' 'staged' "Individual source staged; host registration remains host-specific."
        if ($InstallRepoDeps) {
            if ((Test-Path (Join-Path $repoPath 'package-lock.json')) -and (CommandExists 'npm')) {
                Push-Location $repoPath; Log "DEPS: npm ci --ignore-scripts for $($Row.repo)"; & npm ci --ignore-scripts 2>&1 | Add-Content $LogPath; Pop-Location
                Add-Status $Row 'dependencies' ($(if ($LASTEXITCODE -eq 0) { 'installed' } else { 'failed' })) 'npm ci --ignore-scripts'
            } elseif ((Test-Path (Join-Path $repoPath 'package.json')) -and (CommandExists 'npm')) {
                Push-Location $repoPath; Log "DEPS: npm install --ignore-scripts for $($Row.repo)"; & npm install --ignore-scripts 2>&1 | Add-Content $LogPath; Pop-Location
                Add-Status $Row 'dependencies' ($(if ($LASTEXITCODE -eq 0) { 'installed' } else { 'failed' })) 'npm install --ignore-scripts'
            }
            if ((Test-Path (Join-Path $repoPath 'requirements.txt')) -and (CommandExists 'python')) {
                $venv = Join-Path $repoPath '.venv'
                Log "DEPS: creating repository-local Python venv for $($Row.repo)"
                & python -m venv $venv 2>&1 | Add-Content $LogPath
                $venvPython = Join-Path $venv 'Scripts\python.exe'
                if (Test-Path $venvPython) {
                    & $venvPython -m pip install --disable-pip-version-check -r (Join-Path $repoPath 'requirements.txt') 2>&1 | Add-Content $LogPath
                    Add-Status $Row 'dependencies' ($(if ($LASTEXITCODE -eq 0) { 'installed' } else { 'failed' })) 'repository-local venv + pip requirements.txt'
                } else { Add-Status $Row 'dependencies' 'failed' 'Python venv creation failed' }
            }
            if ((Test-Path (Join-Path $repoPath 'go.mod')) -and (CommandExists 'go')) {
                Push-Location $repoPath; & go mod download 2>&1 | Add-Content $LogPath; Pop-Location
                Add-Status $Row 'dependencies' ($(if ($LASTEXITCODE -eq 0) { 'installed' } else { 'failed' })) 'go mod download'
            }
            if ((Test-Path (Join-Path $repoPath 'Cargo.toml')) -and (CommandExists 'cargo')) {
                Push-Location $repoPath; & cargo fetch 2>&1 | Add-Content $LogPath; Pop-Location
                Add-Status $Row 'dependencies' ($(if ($LASTEXITCODE -eq 0) { 'installed' } else { 'failed' })) 'cargo fetch'
            }
        }
    }
}

$Statuses | Export-Csv -NoTypeInformation -Encoding utf8 $StatusPath
$Requirements | Export-Csv -NoTypeInformation -Encoding utf8 $ReqPath
$McpRegistry | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $McpPath
$PluginSources | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $PluginPath
Log "DONE: individual extension installation/staging finished."
Log "STATUS: $StatusPath"
Log "REQUIREMENTS: $ReqPath"
Log "MCP REGISTRY: $McpPath"
Log "PLUGIN SOURCES: $PluginPath"
Write-Host "`nComplete. This run kept all repositories and skills separate; nothing was merged."
Write-Host "Review the requirements report before installing repository-specific dependencies or configuring credentials."
