[CmdletBinding()]
param(
	[string]$ProjectPath = "",
	[string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
	$ProjectPath = Join-Path $PSScriptRoot "..\pinoy-party"
}

$projectRoot = (Resolve-Path -LiteralPath $ProjectPath).Path
$repoRoot = (& git -C $projectRoot rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) {
	throw "The project must be inside a Git worktree so resource paths can be checked case-sensitively."
}

$projectPrefix = (& git -C $projectRoot rev-parse --show-prefix).Trim().TrimEnd("/")
if ($LASTEXITCODE -ne 0) {
	throw "Could not determine the project's path within the Git worktree."
}
$trackedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
& git -C $repoRoot ls-files | ForEach-Object { [void] $trackedPaths.Add($_) }
if ($LASTEXITCODE -ne 0) {
	throw "Could not read Git-tracked paths."
}

# The bundled editor addon has optional sample resources that are not part of
# Pinoy Party's runtime. Validate the game project, not vendor-addon fixtures.
$addonRoot = (Join-Path $projectRoot "addons") + [IO.Path]::DirectorySeparatorChar
$sourceFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
	Where-Object {
		($_.Extension -in ".gd", ".tscn", ".godot") -and
		(-not $_.FullName.StartsWith($addonRoot, [StringComparison]::OrdinalIgnoreCase))
	}
$issues = [System.Collections.Generic.List[string]]::new()
$resourcePattern = 'res://[^\r\n"''\]\)\},]+'

foreach ($file in $sourceFiles) {
	$content = [IO.File]::ReadAllText($file.FullName)
	if ($content -match '(?m)^(<<<<<<<|=======|>>>>>>>)') {
		$issues.Add("Unresolved merge marker: $($file.FullName)")
	}

	# Resource-looking examples in comments are documentation, not runtime loads.
	$resourceContent = ($content -split "`r?`n" | Where-Object {
		$trimmed = $_.TrimStart()
		-not ($trimmed.StartsWith("#") -or $trimmed.StartsWith(";"))
	}) -join "`n"
	foreach ($match in [regex]::Matches($resourceContent, $resourcePattern)) {
		$resourcePath = $match.Value
		# Paths assembled with String.format() cannot be resolved statically
		# without duplicating game logic.
		if ($resourcePath.Contains("%")) {
			continue
		}
		$resourceRelativePath = $resourcePath.Substring(6)
		$gitPath = if ([string]::IsNullOrWhiteSpace($projectPrefix)) {
			$resourceRelativePath
		} else {
			"$projectPrefix/$resourceRelativePath"
		}
		if ($trackedPaths.Contains($gitPath)) {
			continue
		}

		$caseInsensitiveMatch = $trackedPaths | Where-Object {
			$_.Equals($gitPath, [StringComparison]::OrdinalIgnoreCase)
		} | Select-Object -First 1
		if ($null -ne $caseInsensitiveMatch) {
			$issues.Add("Case mismatch in $($file.FullName): $resourcePath (tracked as $caseInsensitiveMatch)")
		} else {
			$issues.Add("Missing tracked resource in $($file.FullName): $resourcePath")
		}
	}
}

if ($issues.Count -gt 0) {
	$issues | ForEach-Object { Write-Error $_ }
	throw "Project verification failed with $($issues.Count) issue(s)."
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
	$godotCommand = Get-Command godot, godot.exe -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($null -ne $godotCommand) {
		$GodotPath = $godotCommand.Source
	}
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
	Write-Warning "Static checks passed. Godot was not found on PATH; skipped headless project parsing."
	return
}

Write-Host "Running Godot headless project parse with $GodotPath"
& $GodotPath --headless --path $projectRoot --editor --quit
if ($LASTEXITCODE -ne 0) {
	throw "Godot headless project parsing failed with exit code $LASTEXITCODE."
}

Write-Host "Project verification passed."
