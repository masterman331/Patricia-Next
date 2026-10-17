# Interactive UCI probe using async OutputDataReceived (Peek() lies on pipes).
# ! -File mode flattens arrays, so CMDs arrives as ONE string; split on ';'.
param([string]$CMDs = "", [int]$Millis = 5000)
$script:cmdList = @()
if ($CMDs -ne "") { $script:cmdList = $CMDs.Split(';') }
Write-Host "harness starting, $($script:cmdList.Count) commands"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path (Get-Location) "patricia.exe"
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
$syncRoot = New-Object System.Object
$script:lines = New-Object System.Collections.ArrayList

$handler = {
  param($sender, $e)
  if ($e.Data) {
    $data = $e.Data
    if ($data -notlike "option name*") {
      [void]([System.Threading.Monitor]::Enter($syncRoot))
      try { [void]$script:lines.Add($data) } finally {
        [void]([System.Threading.Monitor]::Exit($syncRoot))
      }
    }
  }
}
$p.add_OutputDataReceived($handler)
$p.add_ErrorDataReceived($handler)

if ($p.Start()) {
  Start-Sleep -Milliseconds 100
  if ($p.HasExited) {
    Write-Host "engine exited immediately, code=$($p.ExitCode)"
  }
} else {
  Write-Host "failed to start engine"
}
Write-Host "stage: started=$($p.HasExited -eq $false)"
if ($p.HasExited) { exit 1 }
$p.BeginOutputReadLine()
$p.BeginErrorReadLine()
Write-Host "stage: async readers attached"

try {
  foreach ($c in $script:cmdList) {
    Write-Host "stage: sending [$c]"
    $p.StandardInput.WriteLine($c.Trim())
    Start-Sleep -Milliseconds 200
  }
  Write-Host "stage: all commands sent"
} catch {
  Write-Host "send failed: $_"
}

Write-Host "stage: main sleep"
Start-Sleep -Milliseconds $Millis
Write-Host "stage: sleep done, exited=$($p.HasExited)"
if (-not $p.HasExited) {
  try {
    $p.StandardInput.WriteLine("quit")
  } catch {}
  Start-Sleep -Milliseconds 1500
  if (-not $p.HasExited) { try { $p.Kill() } catch {} }
}

# print everything we collected
Write-Host "---- captured ----"
[System.Threading.Monitor]::Enter($syncRoot)
try {
  $script:lines | ForEach-Object { Write-Host $_ }
} finally {
  [void]([System.Threading.Monitor]::Exit($syncRoot))
}
