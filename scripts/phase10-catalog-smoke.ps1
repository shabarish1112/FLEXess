#Requires -Version 7.0
param([string]$Adb,[string]$Serial,[switch]$CommitTestEntry,[switch]$Install,[switch]$Relaunch,[switch]$FromDiary,[switch]$Isolated,[ValidateSet("Draft","Entry")][string]$Resume)
$ErrorActionPreference='Stop'
$package='dev.independent.fitness_diary'
if ($Isolated) { $package += '.isolatedtest' }
if ($Resume -and (!$Isolated -or !$CommitTestEntry)) { throw 'Resume requires the isolated test package and commit flag.' }
$activity = "$package/dev.independent.fitness_diary.MainActivity"
if ($Isolated -and $Install) { throw 'Install the verified isolated APK separately before running the smoke.' }
if (!$Adb) {
  $command = Get-Command adb -ErrorAction SilentlyContinue
  if ($command) { $Adb = $command.Source }
  elseif ($env:ANDROID_HOME) { $Adb = Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe' }
}
if (!$Adb -or !(Test-Path -LiteralPath $Adb -PathType Leaf)) { throw 'Pass -Adb with the Platform-Tools adb.exe path.' }
function Invoke-Adb {
  $commandArgs = @($args)
  $start = [System.Diagnostics.ProcessStartInfo]::new($Adb)
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $start.CreateNoWindow = $true
  if ($Serial) { $start.ArgumentList.Add('-s'); $start.ArgumentList.Add($Serial) }
  foreach ($argument in $commandArgs) { $start.ArgumentList.Add([string]$argument) }
  Write-Host ('ADB ' + ($commandArgs -join ' '))
  $process = [System.Diagnostics.Process]::Start($start)
  try {
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (!$process.WaitForExit(20000)) {
      $process.Kill()
      throw "ADB timed out: $($commandArgs -join ' ')"
    }
    if ($process.ExitCode) {
      throw "ADB exit $($process.ExitCode): $($commandArgs -join ' '): $($stderr.Result.Trim())"
    }
    if ($stderr.Result.Trim()) { Write-Host $stderr.Result.Trim() }
    $stdout.Result.Trim()
  } finally { $process.Dispose() }
}
if (!$Serial) {
  $devices = @(Invoke-Adb devices | Select-String '(?m)^(emulator-\d+)\s+device\s*$' -AllMatches |
      ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value })
  if ($devices.Count -ne 1) { throw 'Expected one online emulator. Pass -Serial explicitly.' }
  $Serial = $devices[0]
}
$remote = '/data/local/tmp/flex-smoke-' + [guid]::NewGuid().ToString('N') + '.xml'
function Read-Ui([string]$expected) {
  $last = 'No matching FLEX controls'
  foreach ($attempt in 1..5) {
    Start-Sleep -Milliseconds 650
    try {
      Invoke-Adb shell rm -f $remote | Out-Null
      $dump = if ($attempt % 2) { Invoke-Adb shell uiautomator dump --compressed $remote }
              else { Invoke-Adb shell uiautomator dump $remote }
      if ($dump -notmatch 'dumped to') { throw "Hierarchy dump did not complete: $dump" }
      [xml]$xml = Invoke-Adb shell cat $remote
      $nodes = @($xml.SelectNodes('//node') | Where-Object package -eq $package)
      if ($nodes | Where-Object {$_.hint -like "*$expected*" -or $_.text -like "*$expected*" -or $_.'content-desc' -like "*$expected*"}) {
        return $xml
      }
    } catch { $last = $_.Exception.Message }
    $focus = Invoke-Adb shell dumpsys window
    if ($focus -match 'mCurrentFocus=[^\r\n]*Application Not Responding: com\.android\.systemui') {
      throw 'Android System UI owns the unresponsive dialog. No FLEX control was tapped.'
    }
  }
  throw "Expected FLEX control '$expected'. Last diagnostic: $last"
}
function Tap-Node($node) {
  if(!$node -or $node.bounds -notmatch '\[(\d+),(\d+)\]\[(\d+),(\d+)\]'){throw 'Missing control bounds'}
  Invoke-Adb shell input tap ([int](($Matches[1]/2)+($Matches[3]/2))) ([int](($Matches[2]/2)+($Matches[4]/2)))
}
function Click([string]$label) {
  $xml=Read-Ui $label
  $node=$xml.SelectNodes('//node')|Where { $_.package -eq $package -and (($_.text -split '\r?\n')[0] -eq $label -or ($_.'content-desc' -split '\r?\n')[0] -eq $label)}|Select -First 1
  if(!$node){throw "Missing control: $label"}
  Tap-Node $node
}
function Assert-DailyEnergy($hierarchy, [string]$label) {
  $energyNodes = @($hierarchy.SelectNodes('//node') | Where-Object {
    $_.package -eq $package -and (($_.text -split '\r?\n')[0] -eq $label -or ($_.'content-desc' -split '\r?\n')[0] -eq $label)
  })
  if ($energyNodes.Count -eq 0) { throw "Expected daily energy $label." }
}
try {
if ($Install) { Invoke-Adb install -r (Join-Path $PSScriptRoot '../mobile/build/app/outputs/apk/debug/app-debug.apk') }
if ($Relaunch -or $Install) {
  Invoke-Adb shell am force-stop $package
  Invoke-Adb shell am start -n $activity
}
if (!$FromDiary) { Click 'Open diary' }
$before=Read-Ui 'Food diary'
if ($Resume -eq 'Entry') { Assert-DailyEnergy $before '194 kcal' }
elseif ($Isolated) { Assert-DailyEnergy $before '0 kcal' }
$name='Bananas, ripe and slightly ripe, raw'
if ($Resume -eq 'Entry') {
  $matching = @($before.SelectNodes('//node') | Where-Object {
    $_.package -eq $package -and $_.'content-desc' -eq "Delete $name"
  })
  if ($matching.Count -ne 1) { throw 'Expected one isolated test entry after restart.' }
} else {
if ($Resume -eq 'Draft') {
  $drafts = @($before.SelectNodes('//node') | Where-Object {
    $_.package -eq $package -and
      ($_.'content-desc' -split '\r?\n')[0] -eq "Resume draft: $name"
  })
  if ($drafts.Count -ne 1 -or $before.OuterXml.Contains("Delete $name")) {
    throw 'Expected one isolated test draft and no matching diary row.'
  }
  Click "Resume draft: $name"
  $null = Read-Ui '194 kcal'
  Write-Host 'PASS: draft and serving quantity survived restart without a diary entry'
} else {
if($before.OuterXml.Contains($name)){throw 'Matching record/draft already exists. No data created.'}
Click 'Add food to breakfast'
$search=Read-Ui 'Search foods'
$field = $search.SelectNodes('//node') | Where-Object {
  $_.package -eq $package -and $_.class -eq 'android.widget.EditText' -and $_.hint -eq 'Search foods'
} | Select-Object -First 1
Tap-Node $field
foreach ($attempt in 1..3) {
  if ($attempt -gt 1) {
    $previous = [string]$entered.text
    if ($previous -notmatch '^[a-z]{0,24}$') { throw 'Unexpected search text. No automatic clearing.' }
    if ($previous.Length) {
      Invoke-Adb shell input keyevent 123 | Out-Null
      $erase = @(1..$previous.Length | ForEach-Object { '67' })
      Invoke-Adb shell input keyevent @erase | Out-Null
    }
  }
  Invoke-Adb shell input keyevent KEYCODE_B KEYCODE_A KEYCODE_N | Out-Null
  $entered = (Read-Ui 'Search foods').SelectNodes('//node') | Where-Object {
    $_.package -eq $package -and $_.hint -eq 'Search foods'
  } | Select-Object -First 1
  if ($entered.text -eq 'ban') { break }
}
if ($entered.text -ne 'ban') { throw 'FLEX did not receive the exact search query after three attempts.' }
Click $name
$detail=Read-Ui 'USDA FoodData Central'
if(!$detail.OuterXml.Contains('2026-10-29')){throw 'USDA release attribution missing'}
$input=$detail.SelectNodes('//node')|Where class -eq 'android.widget.EditText'|Select -First 1
Tap-Node $input
Invoke-Adb shell input keyevent 123 67
Invoke-Adb shell input text 2
Invoke-Adb shell input keyevent 4
$preview=Read-Ui '194 kcal'
if(!$preview.OuterXml.Contains('Serving preview')){throw 'Serving preview not visible'}
if (!$CommitTestEntry) {
  Click 'Discard draft'
  $null = Read-Ui 'Search foods'
  'PASS: USDA search, attribution, doubled serving preview and draft discard'
  return
}
if ($Isolated) {
  Click 'Save draft'
  Click 'Back'
  $null = Read-Ui "Resume draft: $name"
  Invoke-Adb shell am force-stop $package
  Invoke-Adb shell am start -n $activity
  Click 'Open diary'
  $stillDraft = Read-Ui "Resume draft: $name"
  Assert-DailyEnergy $stillDraft '0 kcal'
  if ($stillDraft.OuterXml.Contains("Delete $name")) {
    throw 'Uncommitted draft appeared as a logged record.'
  }
  Click "Resume draft: $name"
  $null = Read-Ui '194 kcal'
  Write-Host 'PASS: draft and serving quantity survived restart without a diary entry'
}
}
Click 'Add to diary'
$logged=Read-Ui "Delete $name"
if(@($logged.SelectNodes('//node')|Where {$_.'content-desc' -eq "Delete $name"}).Count -ne 1){throw 'Expected exactly one logged record'}
Invoke-Adb shell am force-stop $package
Invoke-Adb shell am start -n $activity
Click 'Open diary'
$null=Read-Ui "Delete $name"
}
if ($Isolated) {
  Assert-DailyEnergy (Read-Ui 'Food diary') '194 kcal'
  Click $name
  $edit = Read-Ui 'Edit entry'
  $quantity = $edit.SelectNodes('//node') | Where-Object {
    $_.package -eq $package -and $_.class -eq 'android.widget.EditText'
  } | Select-Object -First 1
  Tap-Node $quantity
  Invoke-Adb shell input keyevent 123 67
  Invoke-Adb shell input text 3
  Invoke-Adb shell input keyevent 4
  $null = Read-Ui '291 kcal'
  Click 'Save changes'
  Assert-DailyEnergy (Read-Ui 'Food diary') '291 kcal'
  Write-Host 'PASS: changed the persisted entry from 194 to 291 kcal'
}
Click "Delete $name"
Click 'Delete'
$after=Read-Ui 'Food diary'
if($after.OuterXml.Contains($name)){throw 'Created record still visible after cleanup'}
if ($Isolated) { Assert-DailyEnergy $after '0 kcal' }
'PASS: offline USDA search, attribution, doubled preview, one log, restart persistence, cleanup'

} finally { Invoke-Adb shell rm -f $remote | Out-Null }
