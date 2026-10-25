# Sets one key in the Default Domain Policy's security template, on a domain controller. A
# generated task runs this as its script. Read-then-write: a template that already holds the value
# is left alone, so the GPO's version only moves when something changed. See docs/adr/0028.
# SupportsShouldProcess makes win_powershell run the script under check mode, rather than skip it
# and report a change.
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)] [string] $Section,
    [Parameter(Mandatory)] [string] $Key,
    [Parameter(Mandatory)] [string] $Value
)

$ErrorActionPreference = 'Stop'
# The Default Domain Policy's GUID is the same in every domain; its display name can be changed.
$guid = '{31B2F340-016D-11D2-945F-00C04FB984F9}'
$domain = Get-ADDomain
$sysvol = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters').SysVol
$policy = Join-Path $sysvol "$($domain.DNSRoot)\Policies\$guid"
$template = Join-Path $policy 'MACHINE\Microsoft\Windows NT\SecEdit\GptTmpl.inf'

$lines = [System.Collections.Generic.List[string]] @(Get-Content -LiteralPath $template)
$header = '[{0}]' -f $Section
$start = $lines.IndexOf($header)
$line = '{0} = {1}' -f $Key, $Value

if ($start -lt 0) {
    $lines.Add($header)
    $lines.Add($line)
}
else {
    $end = $start + 1
    while ($end -lt $lines.Count -and -not $lines[$end].StartsWith('[')) { $end++ }
    $at = -1
    for ($i = $start + 1; $i -lt $end; $i++) { if ($lines[$i] -match ('^{0}\s*=' -f [regex]::Escape($Key))) { $at = $i; break } }

    if ($at -ge 0 -and ($lines[$at] -replace '^[^=]*=\s*') -eq $Value) {
        $Ansible.Changed = $false
        return
    }
    if ($at -ge 0) { $lines[$at] = $line } else { $lines.Insert($end, $line) }
}

$Ansible.Changed = $true
if ($Ansible.CheckMode) { return }

Set-Content -LiteralPath $template -Value $lines -Encoding Unicode

# A client applies a GPO only when its version moves: the computer half is the low 16 bits, and the
# same number lives on the AD object and in GPT.INI.
$adPath = 'CN={0},CN=Policies,CN=System,{1}' -f $guid, $domain.DistinguishedName
$version = [int] (Get-ADObject -Identity $adPath -Properties versionNumber).versionNumber + 1
Set-ADObject -Identity $adPath -Replace @{ versionNumber = $version }
$ini = Join-Path $policy 'GPT.INI'
(Get-Content -LiteralPath $ini) -replace '^Version=\d+', "Version=$version" | Set-Content -LiteralPath $ini
