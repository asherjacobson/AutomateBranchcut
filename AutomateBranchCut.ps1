$userInput = $args[0]
$timeStarted = Get-Date
echo "script started: $timeStarted"
$format = '\d{4}-BR\d{2}-[a-zA-Z]{2,20}'

$localPath = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Backup\Local'
$remotePath = '\\fileshare.navex-pe.com\pe\Database Snapshots\Baseline\DevDeploy\EPIM - Copy' 

$localBackups = Get-ChildItem -Path $localPath 
$remoteBackups = Get-ChildItem -Path $remotePath
 
# check for vpn connection to avoid partial execution of script? won't fail until "copy over" step and will error out when it checks for remote backups of same name
do {
    if ($null -eq $userInput) {
        $userInput = Read-Host -Prompt "Enter new database backup name. Format should be `n[Release Year]-BR[Counter]-[Trainstop Name]`n`nFor example, ""2022-BR01-Aster"". Check https://confluence.navexglobal.com/pages/viewpage.action?spaceKey=PE&title=Deployment+Train+Stops for the Release Year, and if your branchcut trainstop is the first one in Q1 of next year then the Counter should reset to 01 and you should increment the year (otherwise just increment Counter from the previous branchcut)"
    }

    Write-Host "`n"
    if ($userInput -notmatch "\A$format\Z") {
        Write-Host "Invalid format detected...`n"
        $userInput = $null
    }

    elseif ($localBackups | Where-Object -FilterScript { $_.Name -eq $userInput }) {
        # could allow them to continue w/ script which should overwrite existing backup, but that could create confusion
        Write-Host "$userInput already exists in local backups ($localPath). If you wish to overwrite it, simply delete it and re-run this script."
        exit
    }

    elseif ($remoteBackups | Where-Object -FilterScript { $_.Name -eq $userInput }) {
        Write-Host "$userInput already exists in remote backups ($remotePath). If you wish to overwrite it, simply delete it and re-run this script."
        exit
    }

    else {
        $backupName = $userInput
    }

} while ($null -eq $backupName)

# ----------------------------Updating command in BuildObjects-----------------------------

$buildObjectsPath = 'C:\git\epim\.DevDeploy\BuildObjects.ps1'

$command = Get-ChildItem $buildObjectsPath | Select-String 'New-DatabaseSet' 
$line = $command | % { $_.LineNumber }
$newCommand = $command | % { $_.Line -replace ($format, $backupName) }

$script = Get-Content -Path $buildObjectsPath
$script[$line - 1] = $newCommand
$script | Set-Content $buildObjectsPath

# ---------------------------Creating new backup----------------------------------------

$countBefore = $localBackups | Measure-Object | % { $_.count }
Write-Host "Database backups found locally prior to creating new one: $countBefore. Creating new database backups..."

Invoke-DevDeploy -ConfigFiles C:\git\epim\.DevDeploy\BuildObjects.ps1 -ScriptWhiteList 'Backup Databases'
 
$countAfter = Get-ChildItem -Path $localPath | Measure-Object | % { $_.count }
Write-Host "New backup count: $countAfter."

if ( $countAfter -ne $countBefore + 1 ) {
    Write-Host "New local backup count is incorrect. Maybe ""New-DatabaseSet"" command in BuildObjects.ps1 failed?" 
    exit
}

# -----------------------Copying backup over to shared drive------------------------------

$remoteBackups | sort-object -desc -Property {$_.LastWriteTime} | select-object -skip 3 | remove-item -recurse

move-item -Path "$localPath\$backupName" -Destination $remotePath

$timeEnded = Get-Date
echo "script ended: $timeEnded"

<# ---------------------------------------------------------------------------------------
 Questions:
 - How can I show a prettier prompt if I use a function to retrieve user params
 - How can I show a prettier error msg when using write-warning
 - is regex used good enuf
 - better to navigate to directories to reduce references to paths or to be more explicit?
 - should we give option to proceed after create back up attempt locally or should we decide based on outcome of that step
 - don't forget to chg remote path to remove - Copy once done
 - Ensure x time has elapsed since last backup was added to remote drive before allowing execution of script? otherwise you may remove recent db backups for new backups made only days apart from one another (and thus representing more or less the same code base) 

 
---------------------------------------------------------------------------------------- #>
