param(
    [string] $LogRoot = (Join-Path $PSScriptRoot '..\..\lab\.local'),
    [string] $OutputPath = $PSScriptRoot
)

$LabLocal = $LogRoot
$out = $OutputPath
New-Item -ItemType Directory -Force $out | Out-Null
$rx = '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d,\d{3}) .*?\| (.*)$'
$all = foreach ($log in Get-ChildItem $LabLocal -Recurse -Filter ansible.log | Where-Object FullName -Match 'runs') {
    $run = $log.Directory.Name; $lab = $log.Directory.Parent.Parent.Name
    $stamped = foreach ($line in [IO.File]::ReadLines($log.FullName)) {
        if ($line -match $rx) { [pscustomobject]@{ T = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss,fff', $null); Text = $Matches[2] } }
    }
    $recap = [bool]($stamped | Where-Object Text -Match '^PLAY RECAP')
    $idx = @(0..($stamped.Count - 1) | Where-Object { $stamped[$_].Text -match '^TASK \[(.*?)\] \**$' })
    for ($k = 0; $k -lt $idx.Count; $k++) {
        $i = $idx[$k]
        $end = if ($k + 1 -lt $idx.Count) { $stamped[$idx[$k + 1]].T } else { $stamped[-1].T }
        $name = [regex]::Match($stamped[$i].Text, '^TASK \[(.*?)\] \**$').Groups[1].Value -replace '^[^:]+ : ', ''
        $vid = if ($name -match '^(V-\d+)(\.\w+)? \|') { $Matches[1] } else { '' }
        [pscustomobject]@{ Lab = $lab; Run = $run; Complete = $recap; Vid = $vid; Task = $name; Seconds = [math]::Round(($end - $stamped[$i].T).TotalSeconds, 3) }
    }
}
$all | Export-Csv (Join-Path $out 'tasks.csv') -NoTypeInformation
$all | Where-Object { $_.Vid } | Group-Object Lab, Run, Vid | ForEach-Object {
    $f = $_.Group[0]
    [pscustomobject]@{ Lab = $f.Lab; Run = $f.Run; Complete = $f.Complete; Vid = $f.Vid; Tasks = $_.Count; Seconds = [math]::Round(($_.Group | Measure-Object Seconds -Sum).Sum, 3); Sample = $f.Task }
} | Export-Csv (Join-Path $out 'rules.csv') -NoTypeInformation
"tasks: $($all.Count)"
