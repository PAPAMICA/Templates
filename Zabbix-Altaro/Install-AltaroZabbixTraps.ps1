<#
    .SYNOPSIS
    This script is used for installing the PowerShell scripts used for providing Zabbix
    traps into the task scheduler on the local machine.

    .DESCRIPTION
    This script first queries for the IP of the Zabbix Server or Proxy that is then
    embedded as part of the parameters used in the scheduled task actions. The tasks are
    scheduled to run hourly into order to provide data to Zabbix via traps.

    .PARAMETER ZabbixIP
    The IP address of the Zabbix server/proxy to send the value to.

    .PARAMETER ComputerName
    The hostname that should be reported to Zabbix, in case the hostname you set up in
    Zabbix isn't exactly the same as this computer's name.
    
    .EXAMPLE
    Install-AltaroZabbixTraps.ps1 -ZabbixIP 10.0.0.240

    .NOTES
    Author: Mickael Asseline
    GitHub: https://github.com/PAPAMICA
    Website: https://labo-tech.fr
#>

Param (
    [Parameter(Position=0, Mandatory=$TRUE)]
    [ValidatePattern("^(\d+\.){3}\d+$")]
    [String]
    $ZabbixIP,
    [Parameter(Position=1, Mandatory=$FALSE)]
    [ValidatePattern(".+")]
    [String]
    $ComputerName = $env:COMPUTERNAME
)

$globalTrigger   = New-ScheduledTaskTrigger -Daily -At 8am
$systemPrincipal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Set up Altaro VM Backup status tasks
#
$backupTypes = (
    "Offsite",
    "Onsite"
)

foreach ($backupType in $backupTypes)
{
    $monitorAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ('-NoProfile -NoLogo -File "' + $env:ProgramFiles + '\Zabbix Agent\ALTAROREPORTS\Get-AltaroBackupStatus.ps1" -BackupType ' + $backupType + ' -ZabbixIP ' + $ZabbixIP + ' -ComputerName ' + $ComputerName)

    $monitorTask = Register-ScheduledTask -TaskName ("Report Altaro VM Backup State for " + $backupType  + " backups (Zabbix Trap)") -Trigger $globalTrigger -Action $monitorAction -Principal $systemPrincipal

    $monitorTask.Triggers[0].Repetition.Interval = "PT1H"
    $monitorTask | Set-ScheduledTask
}