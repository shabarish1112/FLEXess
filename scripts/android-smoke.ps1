param(
    [Parameter(Mandatory)] [string]$Adb,
    [Parameter(Mandatory)] [string]$Apk,
    [string]$Serial = 'emulator-5554',
    [switch]$AlreadyOpen
)
$ErrorActionPreference = 'Stop'
$package = 'dev.independent.fitness_diary'
function Invoke-Adb {
    $response = & $Adb -s $Serial @args
    if ($LASTEXITCODE) { throw "ADB failed: $($args[0])" }
    $response
}
function Read-Screen {
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        Start-Sleep -Milliseconds 550
        $dump = Invoke-Adb shell uiautomator dump /sdcard/fitness-smoke.xml
        if ("$dump" -match 'dumped to') {
            [xml]$xml = (Invoke-Adb shell cat /sdcard/fitness-smoke.xml) -join ''
            return $xml
        }
    }
    throw 'UI hierarchy unavailable.'
}
function Find-Control([string]$value) {
    $xml = Read-Screen
    $nodes = @($xml.SelectNodes('//node') | Where-Object {
        ($_.text -split '\r?\n')[0] -eq $value -or ($_.'content-desc' -split '\r?\n')[0] -eq $value
    })
    if (!$nodes.Count) { throw "Expected control: $value" }
    $nodes[0]
}
function Select-Control([string]$value) {
    $node = Find-Control $value
    if ($node.bounds -notmatch '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') { throw "Missing bounds: $value" }
    Invoke-Adb shell input tap ([int](($Matches[1] / 2) + ($Matches[3] / 2))) ([int](($Matches[2] / 2) + ($Matches[4] / 2))) | Out-Null
}
if (!$AlreadyOpen) {
    Invoke-Adb install -r $Apk
Invoke-Adb shell am start -W -n "$package/.MainActivity"
}
Select-Control 'Open diary'
if ((Read-Screen).OuterXml.Contains('Sample rolled oats')) { throw 'Existing oats entry found; use a fresh development install.' }
Select-Control 'Add food to breakfast'
Select-Control 'Sample rolled oats'
Select-Control 'Add to diary'
Find-Control 'Sample rolled oats' | Out-Null
Invoke-Adb shell am force-stop $package
Invoke-Adb shell am start -W -n "$package/.MainActivity"
Select-Control 'Open diary'
Find-Control 'Sample rolled oats' | Out-Null
Select-Control 'Delete Sample rolled oats'
Select-Control 'Delete'
if ((Read-Screen).OuterXml.Contains('Sample rolled oats')) { throw 'Synthetic entry still visible after deletion.' }
'PASS: Android add, process restart and delete'
