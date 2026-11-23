param([Parameter(Mandatory)][string]$Adb,[string]$Serial='emulator-5554')
$ErrorActionPreference='Stop'
$package='dev.independent.fitness_diary'
function adb { & $Adb -s $Serial @args; if($LASTEXITCODE){throw "ADB failed: $($args[0])"} }
function screen($label){
 foreach($attempt in 1..10){
  Start-Sleep -Milliseconds 700
  $dump=adb shell uiautomator dump /sdcard/flex-draft-smoke.xml 2>&1
  if("$dump" -notmatch 'dumped to'){continue}
  $raw=(adb shell cat /sdcard/flex-draft-smoke.xml)-join ''
  if($raw -match "package=`"$package`"" -and $raw.Contains($label)){return [xml]$raw}
 }
 throw "Expected FLEX screen containing $label"
}
function click($label){
 $x=screen $label
 $n=$x.SelectNodes('//node')|Where {($_.text -split '\r?\n')[0] -eq $label -or ($_.'content-desc' -split '\r?\n')[0] -eq $label}|Select-Object -First 1
 if(!$n -or $n.bounds -notmatch '\[(\d+),(\d+)\]\[(\d+),(\d+)\]'){throw "Missing control $label"}
 adb shell input tap ([int](($Matches[1]/2)+($Matches[3]/2))) ([int](($Matches[2]/2)+($Matches[4]/2)))
}
function launch { adb shell am start -n "$package/.MainActivity" }
adb install -r 'mobile/build/app/outputs/apk/debug/app-debug.apk'
launch
click 'Open diary'
$before=screen 'Food diary'
if($before.OuterXml.Contains('Sample sliced mango')){throw 'Existing mango entry or draft, stopping without changes.'}
click 'Add food to breakfast'
click 'Sample sliced mango'
click 'Save draft'
adb shell input keyevent 4
$draft=screen 'Resume draft: Sample sliced mango'
if($draft.OuterXml.Contains('Delete Sample sliced mango')){throw 'Draft became a committed entry'}
adb shell am force-stop $package
launch
click 'Open diary'
click 'Resume draft: Sample sliced mango'
click 'Add to diary'
$committed=screen 'Delete Sample sliced mango'
if($committed.OuterXml.Contains('Resume draft: Sample sliced mango')){throw 'Draft retained after commit'}
if(@($committed.SelectNodes('//node')|Where {$_.'content-desc' -eq 'Delete Sample sliced mango'}).Count -ne 1){throw 'Expected exactly one committed entry'}
click 'Delete Sample sliced mango'
click 'Delete'
$after=screen 'Food diary'
if($after.OuterXml.Contains('Sample sliced mango')){throw 'Synthetic entry still present'}
'PASS: in-place upgrade, save draft, restart, resume, commit once, cleanup'
