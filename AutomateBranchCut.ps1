$newBackupName = $args[0]
MOVE script to repo 
Write-Host $newBackupName
    function retrieveBackupName {
        param(
            [Parameter(Mandatory, HelpMessage = "Enter db name")]
            [string]$New-Database-Backup-Name
        ) 
        $newBackupName = $userInput
    }
}
<# -----------------------------------------------------------------
if ($null -eq $newBackupName) {
$newBackupName = Read-Host -Prompt "Please enter a name for the new database backup to be created:"

}
 $localBackupPath = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Backup\Local'
 $localBackupCountBeforeNewBackup = Get-ChildItem -Path $localBackupPath | Measure-Object | %{$_.count}
 
 
 Write-Host "Database backups found locally prior to creating new one: $localBackupCountBeforeNewBackup. Creating new database backups..."
 Invoke-DevDeploy -ConfigFiles C:\git\epim\.DevDeploy\BuildObjects.ps1 -ScriptWhiteList 'Backup Databases'
 
 
 $localBackupCountAfterNewBackup = Get-ChildItem -Path $localBackupPath | Measure-Object | %{$_.count}
 Write-Host "New backup count: $localBackupCountAfterNewBackup."
 
 
 if ( $localBackupCountAfterNewBackup -eq $localBackupCountBeforeNewBackup + 1 )
 {
     Write-Host "New local database backup created successfully."
 }
 else {
     Write-Host "New local backup count is incorrect. Confirm creation of new backups worked properly..."
     exit
 }


$devDeployBuildObjPath = 'C:\git\epim\.DevDeploy\BuildObjects.ps1'
$newDatabaseSet_Command = Get-ChildItem $devDeployBuildObjPath | Select-String 'New-DatabaseSet' | %{$_.ToString()}
$stringIndexOfKeyword = $newDatabaseSet_Command.IndexOf('Version')
$versionNameOffsetFromKeyword = 9 # distance between Version keyword and version name in New-DatabaseSet command
$releaseVersion = $newDatabaseSet_Command.Substring($stringIndexOfKeyword + $versionNameOffsetFromKeyword) 



 # count number of back up files before and after above command and log error if count hasn't changed?
 
 $NewestBackup = 
---------------------------------------------------------------- #>