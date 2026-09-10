param(
    [string]$Repository = 'DipperHide/shogi-studio',
    [ValidateSet('public', 'private')][string]$Visibility = 'public',
    [string]$ReportDirectory = ''
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $taskRoot
& gh auth status
if ($LASTEXITCODE -ne 0) { throw 'GitHub authentication has expired. Run gh auth login -h github.com --scopes workflow first; no password or token should be put in this repository.' }
if ($Repository -notmatch '^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$') { throw 'Expected owner/repository.' }
$taskVersion = [regex]::Match((Get-Content godot/project.godot -Raw), 'config/version="([^"]+)"').Groups[1].Value
$taskTag = "v$taskVersion"
$taskReportDirectory = if ($ReportDirectory) { $ReportDirectory } else { "review/app/chessis$($taskVersion.Split('.')[1])" }
$taskRelease = Get-Content -LiteralPath (Join-Path $taskReportDirectory 'release.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskRelease.version -ne $taskVersion) { throw 'Release manifest version mismatch.' }
foreach ($taskArtifact in $taskRelease.artifacts) {
    $taskHash = (Get-FileHash -LiteralPath $taskArtifact.path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($taskHash -ne $taskArtifact.sha256) { throw "Artifact checksum mismatch: $($taskArtifact.path)" }
}
foreach ($taskReadme in @('README.md', 'README.en.md', 'README.ja.md')) {
    if (-not (Test-Path -LiteralPath $taskReadme)) { throw "Missing $taskReadme" }
}
$taskFeed = Get-Content -LiteralPath godot/config/tournaments.json -Raw | ConvertFrom-Json
if ($Visibility -eq 'public' -and $taskFeed.index_url -ne "https://raw.githubusercontent.com/$Repository/main/godot/assets/data/tournament-index.json") {
    throw 'Catalog endpoint differs from the repository. Update the endpoint and rebuild before publishing.'
}
$taskDirty = & git status --porcelain --untracked-files=no
if ($taskDirty) { throw 'Commit the reviewed release source before publishing.' }
$taskHead = & git rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Create the release source commit before publishing.' }
$taskExisting = & gh repo view $Repository --json nameWithOwner,visibility,defaultBranchRef 2>$null
if ($LASTEXITCODE -ne 0) {
    & gh repo create $Repository "--$Visibility" --description 'Free shogi for Android and Windows: local analysis, animated replay, lessons and tournament records.'
    if ($LASTEXITCODE -ne 0) { throw 'Repository creation failed.' }
}
$taskRemote = & git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0) {
    & git remote add origin "https://github.com/$Repository.git"
    if ($LASTEXITCODE -ne 0) { throw 'Could not add origin.' }
} elseif ($taskRemote -notin @("https://github.com/$Repository.git", "https://github.com/$Repository", "git@github.com:$Repository.git")) {
    throw 'Existing origin points to a different repository; it was not changed.'
}
# A normal push refuses unrelated or newer remote history; never force-push.
& git -c 'credential.helper=' -c 'credential.helper=!gh auth git-credential' push -u origin HEAD:main
if ($LASTEXITCODE -ne 0) { throw 'Source push failed; remote history was not overwritten.' }
& gh repo edit $Repository --default-branch main
if ($LASTEXITCODE -ne 0) { throw 'Unable to set the catalog default branch.' }
$taskExistingTag = & git rev-parse --verify "refs/tags/$taskTag" 2>$null
if ($LASTEXITCODE -eq 0 -and $taskExistingTag -ne $taskHead) { throw 'An existing release tag points to a different commit.' }
if ($LASTEXITCODE -ne 0) { & git tag $taskTag $taskHead }
& git -c 'credential.helper=' -c 'credential.helper=!gh auth git-credential' push origin "refs/tags/$taskTag"
if ($LASTEXITCODE -ne 0) { throw 'Release tag push failed.' }
$taskAssets = @($taskRelease.artifacts | ForEach-Object { $_.path })
$taskAssets += "builds/SHA256SUMS-$taskVersion.txt"
& gh release view $taskTag --repo $Repository *> $null
if ($LASTEXITCODE -ne 0) {
    & gh release create $taskTag --repo $Repository --verify-tag --title "Shogi Studio $taskVersion" --notes-file "docs/releases/$taskTag.md" @taskAssets
} else {
    & gh release upload $taskTag --repo $Repository @taskAssets
}
if ($LASTEXITCODE -ne 0) { throw 'Release upload failed. Existing assets were not overwritten.' }
& gh release view $taskTag --repo $Repository --json url,tagName,assets
