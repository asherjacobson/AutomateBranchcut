# -------------------------Validating new database backup name------------------------------

$backupName = $args[0]
$format = '\d{4}-BR\d{2}-[a-zA-Z]{2,20}'
clear

while ($backupName -notmatch "\A$format\Z") {
    $userInput = Read-Host -Prompt "Enter new database backup name. Format should be [Release Year]-BR[Counter]-[Trainstop Name].  For example, ""2022-BR01-Aster"". Check https://confluence.navexglobal.com/pages/viewpage.action?spaceKey=PE&title=Deployment+Train+Stops for the Release Year, and if your branchcut trainstop is the first one in Q1 of next year then the Counter should reset to 01 and you should increment the year (otherwise just increment Counter from the previous branchcut)"

    if ($userInput -notmatch "\A$format\Z") {
        Write-Host "`r`nInvalid format detected...`r`n"
    }
    else {
        $global:backupName = $userInput
    }
}

# ----------------------------Updating command in BuildObjects-----------------------------

$path = 'C:\git\epim\.DevDeploy\BuildObjects.ps1'

$command = Get-ChildItem $path | Select-String 'New-DatabaseSet' 
$line = $command | %{$_.LineNumber}
$newCommand = $command | %{$_.Line -replace ($format, $backupName)}

$script = Get-Content -Path $path
$script[$line - 1] = $newCommand
$script | Set-Content $path

# ---------------------------Creating new backup----------------------------------------

 $path = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Backup\Local'

 $backups = Get-ChildItem -Path $path 
$countBefore = $backups | Measure-Object | %{$_.count}
 
 Write-Host "Database backups found locally prior to creating new one: $countBefore. Creating new database backups..."
 Invoke-DevDeploy -ConfigFiles C:\git\epim\.DevDeploy\BuildObjects.ps1 -ScriptWhiteList 'Backup Databases'
 
 # --------------------------Confirming local backup creation---------------------------
$countAfter = $backups | Measure-Object | %{$_.count}
 Write-Host "New backup count: $countAfter."

 $newBackup = $backups | Where-Object %{$_.LastWriteTime -gt (get-date).AddMinutes(-30)}
 
$remotePath = '\\fileshare.navex-pe.com\pe\Database Snapshots\Baseline\DevDeploy\EPIM' 
 $remoteBackups = Get-ChildItem -Path -$remotePath
 
 $questionProceed = $true
 
 if ( $countAfter -eq $countBefore + 1 )
 {
     Write-Host "New local database backup created successfully."
    $questionProceed = $false
 }
 elseif ($countAfter -eq $countBefore -and $newBackup.Name -eq $backupName)
 {
    Write-Host "A backup of name [$backupName] already existed locally ($path) and was overwritten. Maybe this script was already run with that backup name."

    if($remoteBackups | Where-Object %{$_.Name -eq $backupName})
    {
        $date = $remoteBackups | Where-Object %{$_.Name -eq $backupName} | %{$_.LastWriteTime}
        Write-Host "A backup of this name also exists on the shared drive ($remotePath), and was last modified $date. Proceeding with this script will overwrite that remote backup."
    }
    else {
        Write-Host "A backup of this name does not exist in $remotePath."
    }
 } else {
     Write-Host "New local backup count is incorrect. Maybe ""New-DatabaseSet"" command in BuildObjects.ps1 failed? Proceeding will allow for the completion of the other steps in the branchcut process, but you will want to ensure that the above issue is resolved and that a new database backup can be created."
 }

 $proceed = Read-Host -Prompt "Do you wish to proceed?"

 if ($proceed -eq $false)
 {
    Write-Host "Script Aborted."
    exit
 }

 # -----------------------Remove DBs over 3 releases old----------------------------------
$remoteBackups | sort-object -desc | select-object -skip 3 | remove-item -recurse

 # -----------------------Copying backup over to shared drive------------------------------

 <# ---------------------------------------------------------------------------------------
 Questions:
 How can I show a prettier prompt if I use a function to retrieve user params
 How can I show a prettier error msg when using write-warning
 is regex used good enuf
 better to navigate to directories to reduce references to paths or to be more explicit?
 
---------------------------------------------------------------------------------------- #>
