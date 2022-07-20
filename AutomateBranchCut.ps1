# explicitly dot-source for robocopy wrapper
. ("C:\Users\Asher\Documents\WindowsPowerShell\Modules\DevDeploy\0.0.25\scripts\FolderCtl.ps1")

$localPath = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Backup\Local'
$remotePath = '\\fileshare.navex-pe.com\pe\Database Snapshots\Baseline\DevDeploy\EPIM' 
 
if (-not (Test-Path "$remotePath")) {
    throw "Could not access RemoteSource: '$remotePath' Try to visit that path in file explorer and update your cached creds (directly in Windows Credential Manager) and make sure you have network access (VPN)"
}
 
$localBackups = Get-ChildItem -Path $localPath 
$remoteBackups = Get-ChildItem -Path $remotePath
  
$format = '\d{4}-BR\d{2}-[a-zA-Z]{2,20}'
$backupName = $null

do {
    $userInput = Read-Host -Prompt "Enter new database backup name. Format should be `n[Release Year]-BR[Counter]-[Trainstop Name]`n`nFor example, ""2022-BR01-Aster"". Check https://confluence.navexglobal.com/pages/viewpage.action?spaceKey=PE&title=Deployment+Train+Stops for the Release Year, and if your branchcut trainstop is the first one in Q1 of next year then the Counter should reset to 01 and you should increment the year (otherwise just increment Counter from the previous branchcut)"
 
    Write-Host "`n"
    if ($userInput -notmatch $format) {
        Write-Host "Invalid format detected...`n"
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

# ----------------------------Updating command in BuildObjects
 
$buildObjectsPath = 'C:\git\epim\.DevDeploy\BuildObjects.ps1'
 
$command = Get-ChildItem $buildObjectsPath | Select-String 'New-DatabaseSet' 
$line = $command | % { $_.LineNumber }
 
$newCommand = $command | % { $_.Line -replace ($format, $backupName) }
 
$script = Get-Content -Path $buildObjectsPath
$script[$line - 1] = $newCommand
$script | Set-Content $buildObjectsPath
 
# ---------------------------Creating new backup----------------------------------
 
$countBefore = $localBackups | Measure-Object | % { $_.count }
Write-Host "Database backups found locally prior to creating new one: $countBefore. Creating new database backups..."
 
Invoke-DevDeploy -ConfigFiles C:\git\epim\.DevDeploy\BuildObjects.ps1 -ScriptWhiteList 'Backup Databases'
  
$countAfter = Get-ChildItem -Path $localPath | Measure-Object | % { $_.count }
Write-Host "New backup count: $countAfter."
 
if ( $countAfter -ne $countBefore + 1 ) {
    Write-Host "New local backup count is incorrect. Maybe ""New-DatabaseSet"" command in BuildObjects.ps1 failed?" 
    exit
}
 
# ------------------------ Remove old backups ----------------------------------

$localBackups |  Where-Object { $_.LastWriteTime -lt (get-date).AddDays(-90) } | Remove-Item -Recurse

$remoteBackups |  Where-Object { $_.LastWriteTime -lt (get-date).AddDays(-90) } | Remove-Item -Recurse


# ------------------Copying backup over to shared drive--------------------------
 
# $newBackups = $localBackups | Where-Object { $_.Name -eq $backupName } | gci | gci | % { echo $_.Name }
# $subFolderName = gci $localPath/$backupName | % { $_.Name }
# echo "date directory is $subFolderName"
# $newLocalBakFiles = gci $localpath/$backupName/$subFolderName 
# $now = Get-date -format "yyyy.MM.dd-hh.mm.ss"
# 
# $newRemoteFolder = New-Item -Path $remotePath -Name $backupname -itemtype "directory"
# $newRemoteSubFolder = New-Item -Path $remotePath\$backupname -Name $now -itemtype "directory"
# 
# $targetPath = $newRemoteSubFolder | % { $_.FullName }
# echo "target path: $targetPath"
# echo "bakfiles = $newLocalBakFiles"

# Invoke-RoboCopy -ActivityName "Copying new backup from $localPath to $remotePath..." -SourcePath $localPath\$backupName -DestinationPath $remotePath\ -FilesToCopy  $newLocalBakFiles -UseRestartableMode
# $DevDeploy\0.0.25\scripts\DatabaseCtl.Map.ps1:43:        Copy-DatabaseSnapshots -RemoteSource "$remoteBakFolder" -LocalDestination $localBakFolder -Names ($dbSet.Databases.Name | 
#ForEach-Object{"$_.bak"})

move-item -Path "$localPath\$backupName" -Destination $remotePath


 <# -------------------------------------------------------------------------------
  Questions:
  - How can I show a prettier prompt if I use a function to retrieve user params
  - How can I show a prettier error msg when using write-warning
  - is regex used good enuf
  - better to navigate to directories to reduce references to paths or to be more explicit?
  - should we give option to proceed after create back up attempt locally or should we decide based on outcome of that step
  - don't forget to chg remote path to remove - Copy once done
  - Ensure x time has elapsed since last backup was added to remote drive before allowing execution of script? otherwise you may remove recent db backups for new backups made only days apart from one another (and thus representing more or less the same code base) 
 is there a good way to get our sprint name from Jira API?

 Changes I made to process:
 instead of keeping last 3 db copies on share drive, script keeps all db copies moved there in last 90 days, to guard against someone running this script more times than we expect and overwriting past-sprint copies with further duplicates of the same sprint
  do: delete backup local-Copy folder in C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Backup, dbup, and EPIM-Copy on remote drive
 don't forget to delete all the branches made by testing this script, both remote and local
  
 ------------------------------------------------------------------------------- #>
 



 function CleanUpDbUp{

    $parts = $backupName -split "-" 
    $sprint = $parts[2]
    cd "C:/git/epim"

    git checkout . # remove any pre-existing changes
    git checkout develop
    git pull

    if (git show-ref "refs/heads/$sprint-branchcut-update") {
        Write-Host "Branch ""$sprint-branchcut-update"" found locally. Deleting..."
        git branch -D "$sprint-branchcut-update"
    } else {
        Write-Host "Branch ""$sprint-branchcut-update"" not found locally."
    }

    Write-Host "Creating branch ""$sprint-branchcut-update"""
    git checkout -b "$sprint-branchcut-update"

    Write-Host "Checking for old DbUp scripts to remove..."

    $DBs = "Central", "Core", "DCService", "FileStorage", "Local" | % { 
        gci "C:\git\epim\Applications\DbUp\Navex.CaseManagement.Data.$_\$_ Database Scripts" | Where-Object { $_.Name -ne "000001 - Initial Script.sql" -and $_.LastWriteTime -lt (get-date).AddDays(-90) } | % {
        Write-Host "Deleting old script: $_"
        Remove-Item -Path $_.FullName
    }
}

    git status
    git add .
    git commit -m "deleting DbUp scripts"
    git push --set-upstream origin "$sprint-branchcut-update"
    cd "c:/personal/automatebranchcut"
 }

 CleanUpDbUp