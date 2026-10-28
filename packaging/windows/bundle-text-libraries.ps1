# Bundle the runtime-loaded text libraries and their transitive MinGW DLL imports.
param(
  [Parameter(Mandatory)][string]$Prefix,
  [Parameter(Mandatory)][string]$Destination
)

$ErrorActionPreference = 'Stop'
$bin = Join-Path $Prefix 'bin'
$objdump = Join-Path $bin 'objdump.exe'
New-Item -ItemType Directory -Force $Destination | Out-Null
foreach ($name in @('libharfbuzz-0.dll', 'libfribidi-0.dll')) {
  Copy-Item (Join-Path $bin $name) $Destination
}
$pending = [System.Collections.Generic.Queue[string]]::new()
Get-ChildItem "$Destination/*.exe", "$Destination/*.dll" | ForEach-Object {
  $pending.Enqueue($_.FullName)
}
$visited = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
while ($pending.Count -gt 0) {
  $path = $pending.Dequeue()
  if (-not $visited.Add($path)) { continue }
  $imports = & $objdump -p $path
  if ($LASTEXITCODE -ne 0) { throw "Cannot inspect DLL imports for $path" }
  foreach ($line in $imports) {
    if ($line -match '^\s*DLL Name:\s+(\S+)\s*$') {
      $name = $Matches[1]
      $bundled = Join-Path $Destination $name
      $source = Join-Path $bin $name
      if (Test-Path $bundled) {
        $pending.Enqueue((Get-Item $bundled).FullName)
      } elseif (Test-Path $source) {
        Copy-Item $source $bundled
        $pending.Enqueue((Get-Item $bundled).FullName)
      } elseif ($name -notmatch '^(api-ms-|ext-ms-)' -and
                -not (Test-Path (Join-Path "$env:SystemRoot/System32" $name))) {
        throw "Missing dependency $name imported by $path"
      }
    }
  }
}
Copy-Item -Recurse (Join-Path $Prefix 'share/licenses') "$Destination/text-library-licenses"
