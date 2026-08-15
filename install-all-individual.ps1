[CmdletBinding()]
param(
    [ValidateSet('all','claude','codex','opencode','hermes','auto')]
    [string]$Targets = 'all',
    [ValidateSet('top10','top25','top50','all')]
    [string]$InstallSet = 'all',
    [string]$Workspace = '',
    [switch]$CleanWorkspace,
    [switch]$CleanDownloads,
    [switch]$ScanDownloads,
    [switch]$NoRepair,
    [switch]$InstallRepoDeps,
    [switch]$Force,
    [switch]$AllowPartial
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Catalog = Join-Path $Root 'individual_extensions_catalog.csv'
$Stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$Base = if ($Workspace) { $Workspace } elseif ($env:AI_AGENT_EXTENSIONS_DIR) { $env:AI_AGENT_EXTENSIONS_DIR } else { Join-Path $env:LOCALAPPDATA 'ai-agent-individual-extensions' }
$Downloads = Join-Path $HOME 'Downloads'
function CanonicalPath([string]$Path) { return [System.IO.Path]::GetFullPath($Path).TrimEnd('\\') }
$baseCanonical = CanonicalPath $Base
$downloadsCanonical = CanonicalPath $Downloads
if (($baseCanonical -eq $downloadsCanonical) -or $baseCanonical.StartsWith($downloadsCanonical + '\\', [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Error "Refusing to use Downloads or a subfolder of Downloads as the clone workspace. Choose a dedicated path outside Downloads."
    exit 7
}
$RepoDir = Join-Path $Base 'repos'
$BackupDir = Join-Path $Base "backups\\$Stamp"
$ReportDir = Join-Path $Base 'reports'
$LogPath = Join-Path $ReportDir "install-$Stamp.log"
$StatusPath = Join-Path $ReportDir "install-status-$Stamp.csv"
$ReqPath = Join-Path $ReportDir "requirements-$Stamp.csv"
$McpPath = Join-Path $ReportDir "mcp-registry-$Stamp.json"
$PluginPath = Join-Path $ReportDir "plugin-sources-$Stamp.json"
$FinalPath = Join-Path $ReportDir "install-final-$Stamp.csv"
$DownloadsScanPath = Join-Path $ReportDir "downloads-scan-$Stamp.csv"
$WorkspaceMarker = Join-Path $Base '.ai-agent-individual-extensions-workspace'
if ($CleanWorkspace) {
    if (-not (Test-Path $WorkspaceMarker)) { Write-Error "Refusing to delete a workspace without the installer marker: $Base"; exit 8 }
    Remove-Item -LiteralPath $Base -Recurse -Force
    Write-Host "Removed installer-created workspace: $Base"
    exit 0
}
New-Item -ItemType Directory -Force -Path $RepoDir,$ReportDir | Out-Null
Set-Content -LiteralPath $WorkspaceMarker -Value "created_by=individual-extension-installer`ncreated_at=$Stamp`nroot=$Base`nclones_outside_downloads=true" -Encoding utf8
if ($ScanDownloads) {
    $downloadRows = @()
    if (Test-Path $Downloads) {
        Get-ChildItem -LiteralPath $Downloads -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if (Test-Path (Join-Path $_.FullName '.git')) {
                $downloadRows += [pscustomobject]@{ path=$_.FullName; state='existing-git-directory'; action='not touched by installer'; note='Review manually; installer never clones into Downloads.' }
            }
        }
    }
    if ($downloadRows.Count -eq 0) { $downloadRows += [pscustomobject]@{ path=$Downloads; state='clean-for-installer'; action='none'; note='No top-level Git clone detected; installer does not use Downloads.' } }
    $downloadRows | Export-Csv -NoTypeInformation -Encoding utf8 $DownloadsScanPath
}

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
$RequestedCount = switch ($InstallSet) { 'top10' { 10 } 'top25' { 25 } 'top50' { 50 } default { 100 } }
$Rows = @($Rows | Where-Object { [int]$_.rank -le $RequestedCount })
$ScopeLabel = if ($RequestedCount -eq 100) { 'all-100' } else { "top-$RequestedCount" }
Log "INSTALL SET: $ScopeLabel; processing $($Rows.Count) ranked repositories."
if ($CleanDownloads) {
    $cleanupRows = @()
    foreach ($Row in $Rows) {
        $candidate = Join-Path $Downloads $Row.repo.Replace('/','__')
        if (Test-Path (Join-Path $candidate '.git')) {
            $origin = (& git -C $candidate remote get-url origin 2>$null | Select-Object -First 1)
            if ($origin -and ($origin.TrimEnd('/') -eq $Row.url.TrimEnd('/'))) {
                Remove-Item -LiteralPath $candidate -Recurse -Force
                $cleanupRows += [pscustomobject]@{ path=$candidate; state='removed'; repo=$Row.repo; reason='catalog URL matched installer clone naming' }
                Log "CLEAN DOWNLOADS: removed known installer clone $candidate"
            } else {
                $cleanupRows += [pscustomobject]@{ path=$candidate; state='skipped'; repo=$Row.repo; reason='origin URL did not match catalog; not touched' }
            }
        }
    }
    $cleanupPath = Join-Path $ReportDir "downloads-cleanup-$Stamp.csv"
    if ($cleanupRows.Count -eq 0) { $cleanupRows += [pscustomobject]@{ path=$Downloads; state='clean-for-known-clones'; repo=''; reason='no matching catalog clone was removed' } }
    $cleanupRows | Export-Csv -NoTypeInformation -Encoding utf8 $cleanupPath
    Log "DOWNLOADS CLEANUP: $cleanupPath"
}
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
        Log "ERROR: update failed for $($Row.repo); strict mode will mark this repository failed."; return $null
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

$Final = @()
foreach ($Row in $Rows) {
    $cloneStatus = @($Statuses | Where-Object { ([int]$_.rank -eq [int]$Row.rank) -and $_.stage -eq 'clone' } | Select-Object -Last 1)
    $cloneState = if ($cloneStatus.Count -gt 0) { $cloneStatus[0].state } else { 'missing' }
    $rowSkillStatuses = @($Statuses | Where-Object { ([int]$_.rank -eq [int]$Row.rank) -and $_.stage -eq 'skill' })
    $installedSkillStatuses = @($rowSkillStatuses | Where-Object { $_.state -eq 'installed' })
    $dependencyRows = @($Requirements | Where-Object { [int]$_.rank -eq [int]$Row.rank })
    $dependencyStatusRows = @($Statuses | Where-Object { ([int]$_.rank -eq [int]$Row.rank) -and $_.stage -eq 'dependencies' })
    $dependencyState = 'not-detected'
    if (@($dependencyRows | Where-Object { $_.state -eq 'missing' }).Count -gt 0) { $dependencyState = 'missing' }
    elseif (@($dependencyStatusRows | Where-Object { $_.state -eq 'failed' }).Count -gt 0) { $dependencyState = 'failed' }
    elseif ($dependencyRows.Count -gt 0) { $dependencyState = 'available-or-installed' }
    $isSkill = $Row.extension_type -like 'Agent skill*'
    $artifactState = if ($isSkill) { if ($installedSkillStatuses.Count -gt 0) { 'installed' } else { 'not-found' } } else { 'staged' }
    $finalState = if ($cloneState -ne 'ready') { 'clone-failed' } elseif ($isSkill -and $artifactState -ne 'installed') { 'skill-not-installed' } elseif ($Row.extension_type -like 'MCP*') { 'mcp-staged-host-registration-pending' } elseif ($Row.extension_type -like 'Plugin*') { 'plugin-staged-host-registration-pending' } else { 'processed' }
    $readyForUse = if ($isSkill) { ($finalState -eq 'processed') } else { $false }
    $unresolved = @()
    if ($cloneState -ne 'ready') { $unresolved += 'Repository clone/update failed' }
    if ($isSkill -and $artifactState -ne 'installed') { $unresolved += 'No valid SKILL.md was installed' }
    if (-not $isSkill) { $unresolved += 'Host registration and runtime-specific activation were not attempted automatically' }
    if ($dependencyState -eq 'missing') { $unresolved += 'One or more runtime or credential requirements are missing' }
    if ($dependencyState -eq 'failed') { $unresolved += 'One or more dependency installation commands failed' }
    $Final += [pscustomobject]@{
        scope=$ScopeLabel; rank=$Row.rank; repo=$Row.repo; type=$Row.extension_type; url=$Row.url; clone_state=$cloneState; artifact_state=$artifactState;
        dependency_state=$dependencyState; final_state=$finalState; ready_for_use=$readyForUse;
        unresolved=($unresolved -join ' | '); local_repo_path=(Join-Path $RepoDir $Row.repo.Replace('/','__'))
    }
}
$expectedRanks = 1..$RequestedCount
$actualRanks = @($Final | ForEach-Object { [int]$_.rank } | Sort-Object -Unique)
$missingRanks = @($expectedRanks | Where-Object { $_ -notin $actualRanks })
$hardFailures = @($Final | Where-Object { $_.final_state -in @('clone-failed','skill-not-installed') })
$Final | Export-Csv -NoTypeInformation -Encoding utf8 $FinalPath
$Statuses | Export-Csv -NoTypeInformation -Encoding utf8 $StatusPath
$Requirements | Export-Csv -NoTypeInformation -Encoding utf8 $ReqPath
$McpRegistry | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $McpPath
$PluginSources | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $PluginPath
Log "DONE: processed $($Final.Count) of $RequestedCount selected catalog repositories ($ScopeLabel)."
Log "FINAL REPORT: $FinalPath"
Log "STATUS: $StatusPath"
Log "REQUIREMENTS: $ReqPath"
Log "MCP REGISTRY: $McpPath"
Log "PLUGIN SOURCES: $PluginPath"
if ($ScanDownloads) { Log "DOWNLOADS SCAN: $DownloadsScanPath" }
Log "SUMMARY: skills installed=$(@($Final | Where-Object { $_.artifact_state -eq 'installed' }).Count); plugins staged=$(@($Final | Where-Object { $_.final_state -like 'plugin-*' }).Count); MCP staged=$(@($Final | Where-Object { $_.final_state -like 'mcp-*' }).Count); hard failures=$($hardFailures.Count); missing catalog ranks=$($missingRanks.Count)"
Write-Host "`nAll $RequestedCount selected catalog rows ($ScopeLabel) were processed as individual repositories; nothing was merged."
Write-Host "Plugin/MCP entries are staged separately and remain pending host-specific registration and credentials."
if (($missingRanks.Count -gt 0 -or $hardFailures.Count -gt 0) -and -not $AllowPartial) {
    Log "FAIL: strict completion check failed. Use the final report to repair issues, or rerun with -AllowPartial only if partial processing is intentional."
    exit 20
}
