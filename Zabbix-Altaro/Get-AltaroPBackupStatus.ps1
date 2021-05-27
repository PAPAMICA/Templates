<#
    .SYNOPSIS
    This script is used for obtaining the status of backups that have taken place in
    Altaro VM Backup.

    .DESCRIPTION
    This script utilises the logs that Altaro VM Backup outputs into Event Viewer in
    order to determine the condition of onsite and offsite backup jobs.

    .PARAMETER ComputerName
    The hostname that should be reported to Zabbix, in case the hostname you set up in
    Zabbix isn't exactly the same as this computer's name.

    .PARAMETER BackupType
    The type of backup to check. (Choices: Offsite,
                                           Onsite)

    .PARAMETER ZabbixIP
    The IP address of the Zabbix server/proxy to send the value to.

    
    .EXAMPLE
    Get-AltaroBackupStatus.ps1 -ComputerName = "CLIENT - HOST1" -BackupType Offsite -ZabbixIP 10.0.0.240

    .NOTES
    Author: Rory Fewell
    GitHub: https://github.com/rozniak
    Website: https://oddmatics.uk
    
    Edited by Mickael Asseline (03/04/2021)
    GitHub : https://github.com/PAPAMICA
    Website : https://mickaelasseline.com
#>

Param (
    [Parameter(Position=0, Mandatory=$TRUE)]
    [String]
    $ComputerName,
    [Parameter(Position=1, Mandatory=$TRUE)]
    [String]
    $BackupType,
    [Parameter(Position=2, Mandatory=$TRUE)]
    [ValidatePattern("^(\d+\.){3}\d+$")]
    [String]
    $ZabbixIP
)

# VARIABLES
$ZabbixFolder = "C:\Program Files\Zabbix Agent"

# FUNCTION DEFINITIONS
#
Function Send-ZabbixValue
{
    Param (
        [Parameter(Position=0, Mandatory=$TRUE)]
        [System.Byte]
        $ResultCode,
        [Parameter(Position=1, Mandatory=$TRUE)]
        [ValidatePattern("^(\d+\.){3}\d+$")]
        [String]
        $ZabbixHost,
        [Parameter(Position=2, Mandatory=$TRUE)]
        [String]
        $ZabbixHostname
    )

    $arch = [System.IntPtr]::Size * 8;
    
    & ($ZabbixFolder + "\zabbix_sender.exe") ("-z", $ZabbixHost, "-p", "10051", "-s", $ZabbixHostname, "-k", ("altaroP.backupstatus[" + $BackupType.ToLower() + "]"), "-o", $ResultCode);
    
    Exit
}

# CONSTANTS
#
$cutoffDateTime = [System.DateTime]::UtcNow.AddDays(-2);
$keywordOffsite = "Offsite copy result";
$keywordOnsite = "Backup result";

# MAIN SCRIPT STARTS
#
$altaroEvents = Get-EventLog -Source "Altaro Physical Server Backup" -LogName Application -Newest 10;
$checkOffsite = $FALSE;
$resultCode = 3; # Unknown

Write-Output $altaroEvents

switch ($BackupType.ToLower())
{
    "offsite" {
        $checkOffsite = $TRUE;
    }

    "onsite" {
        $checkOffsite = $FALSE;
    }

    default {
        throw [System.ArgumentException] "Unknown backup type specified.";
    }
}

# Search for first instance of onsite and offsite backup reports
#
$eventOffsite = $NULL;
$eventOnsite  = $NULL;
$foundOffsite = $FALSE;
$foundOnsite  = $FALSE;

for ($i = 0; $i -lt $altaroEvents.Length; $i++)
{
    $message   = $altaroEvents[$i].Message.Split([Environment]::NewLine)[0];
    # Check for offsite
    #
    if (-Not $foundOffsite -And $message.StartsWith($keywordOffsite))
    {
        $eventOffsite = $altaroEvents[$i];
        $foundOffsite = $TRUE;
        continue;
    }

    # Check for onsite
    #
    if (-Not $foundOnsite -And $message.StartsWith($keywordOnsite))
    {
        $eventOnsite = $altaroEvents[$i];
        $foundOnsite = $TRUE;

        continue;
    }
}

# Always check onsite first
#
switch ($eventOnsite.EntryType)
{
    "Error" {
        Send-ZabbixValue -ResultCode 1 -ZabbixHost $ZabbixIP -ZabbixHostname $ComputerName; # Failure
    }

    "Information" {
        $resultCode = 0; # Success
        Send-ZabbixValue -ResultCode 0 -ZabbixHost $ZabbixIP -ZabbixHostname $ComputerName; # Success
    }
    
    default {
        Send-ZabbixValue -ResultCode 3 -ZabbixHost $ZabbixIP -ZabbixHostname $ComputerName; # Unknown
    }
}

# Ensure onsite was within the threshold
#
if ($eventOnsite.TimeGenerated -le $cutoffDateTime)
{
    Send-ZabbixValue -ResultCode 2 -ZabbixHost $ZabbixIP -ZabbixHostname $ComputerName; # Out of date
}

# See if we need to check offsite
#
if (-Not $checkOffsite)
{
    Send-ZabbixValue -ResultCode $resultCode -ZabbixHost $ZabbixIP -ZabbixHostname $ComputerName;
}

switch ($eventOffsite.EntryType)
{
    "Error" {
        Send-ZabbixValue -ResultCode 1 -ZabbixHost $ZabbixIP -ZabbixHostname $ComputerName; # Failure
    }

    "Information" {
        $resultCode = 0; # Success
        Send-ZabbixValue -ResultCode 0 -ZabbixHost $ZabbixIP -ZabbixHostname $ComputerName; # Success
    }

    default {
        Send-ZabbixValue -ResultCode 3 -ZabbixHost $ZabbixIP -ZabbixHostname $ComputerName; # Unknown
    }
}

# Ensure offiste was within the threshold
#
if ($eventOffsite.TimeGenerated -le $cutoffDateTime)
{
    Send-ZabbixValue -ResultCode 2 -ZabbixHost $ZabbixIP -ZabbixHostname $ComputerName; # Out of date
}
else
{
    Send-ZabbixValue -ResultCode 0 -ZabbixHost $ZabbixIP -ZabbixHostname $ComputerName; # Success
}