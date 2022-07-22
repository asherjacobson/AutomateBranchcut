function setup {
    $global:localPath = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Backup\Local'
    $global:remotePath = '\\fileshare.navex-pe.com\pe\Database Snapshots\Baseline\DevDeploy\EPIM' 
    
    if (-not (Test-Path "$remotePath")) {
        throw "Could not access RemoteSource: '$remotePath' Try to visit that path in file explorer and update your cached creds (directly in Windows Credential Manager) and make sure you have network access (VPN)"
    }
    
    Write-Host "Invoking RunDevDeploy to ensure we have the latest database versions before creating new backups..."

   # try { RunDevDeploy }
   # catch { 
   #     Write-Host "Error while running DevDeploy. Fix that and re-run this script."
   #     exit
   # }

    Write-Host "`n ----------------------------------------------------------------- `n RunDevDeploy Complete"

    $global:localBackups = Get-ChildItem -Path $localPath 
    $global:remoteBackups = Get-ChildItem -Path $remotePath

    $global:format = '\d{4}-BR\d{2}-[a-zA-Z]{2,20}'
    $global:backupName = $null
}

function RetrieveBackupName {
    do {
        $userInput = Read-Host -Prompt "`nEnter new database backup name. Format should be `n[Release Year]-BR[Counter]-[Trainstop Name]`n`nFor example, ""2022-BR01-Aster"". Check https://confluence.navexglobal.com/pages/viewpage.action?spaceKey=PE&title=Deployment+Train+Stops for the Release Year, and if your branchcut trainstop is the first one in Q1 of next year then the Counter should reset to 01 and you should increment the year (otherwise just increment Counter from the previous branchcut)"
 
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
    
    return $backupName
}

function CreateBranch {
        $parts = $backupName -split "-" 
    $global:sprint = $parts[2]
    cd "C:/git/epim"

    git checkout . # remove any pre-existing changes
    git checkout develop
    git pull

    if (git show-ref "refs/heads/$sprint-branchcut-update") {
        Write-Host "`nBranch ""$sprint-branchcut-update"" found locally. Deleting..."
        git branch -D "$sprint-branchcut-update"
    } else {
        Write-Host "`nBranch ""$sprint-branchcut-update"" not found locally."
    }

    Write-Host "Creating branch ""$sprint-branchcut-update"""
    git checkout -b "$sprint-branchcut-update"

$input = $null
do {
$input = Read-Host -Prompt "`nOpen Visual Studio, select reload all if a dialog box pops up, and ensure that VS is on the new branch. ""$sprint-branchcut-update"" should be shown in the bottom right corner of the UI. Do not close Visual Studio until this script has completed, or project files may not get updated correctly... Enter ""done"" once this is confirmed."
}
while ($input -ne "done")

}

function UpdateBuildObjects { 
    $buildObjectsPath = 'C:\git\epim\.DevDeploy\BuildObjects.ps1'
    
    $command = Get-ChildItem $buildObjectsPath | Select-String 'New-DatabaseSet' 
    $line = $command | % { $_.LineNumber }
    
    $newCommand = $command | % { $_.Line -replace ($format, $backupName) }
    
    $script = Get-Content -Path $buildObjectsPath
    $script[$line - 1] = $newCommand
    $script | Set-Content $buildObjectsPath
} 
 
function CreateBackups{
    $countBefore = $localBackups | Measure-Object | % { $_.count }
    Write-Host "Database backups found locally prior to creating new one: $countBefore. Creating new database backups..."
    
    Invoke-DevDeploy -ConfigFiles C:\git\epim\.DevDeploy\BuildObjects.ps1 -ScriptWhiteList 'Backup Databases'
    
    $countAfter = Get-ChildItem -Path $localPath | Measure-Object | % { $_.count }
    Write-Host "New backup count: $countAfter."
    
    if ( $countAfter -ne $countBefore + 1 ) {
        Write-Host "New local backup count is incorrect. Maybe ""New-DatabaseSet"" command in BuildObjects.ps1 failed?" 
        exit
    }
}
 
function RemoveOldBackups {
    $localBackups |  Where-Object { $_.LastWriteTime -lt (get-date).AddDays(-90) } | Remove-Item -Recurse
    $remoteBackups |  Where-Object { $_.LastWriteTime -lt (get-date).AddDays(-90) } | Remove-Item -Recurse
}

# function CopyBackupsOver {
#     Write-Host "Copying new database backups from local to remote folder, this may take a little while..."
# 
#     New-Item -Path $remotePath -Name $backupName -ItemType Directory
#     Get-ChildItem "$localPath\$backupName" | Get-ChildItem | % { Copy-Item $_.FullName -Destination "$remotePath\$backupName" }
# }


 function CleanUpDbUp{
    Write-Host "Checking for old DbUp scripts to remove..."
    $global:DBsUpdated = @()
    $DBs = "Central", "Core", "DCService", "FileStorage", "Local" | % { 

        $db = $_
        gci "C:\git\epim\Applications\DbUp\Navex.CaseManagement.Data.$_\$_ Database Scripts" | Where-Object { $_.Name -ne "000001 - Initial Script.sql" -and $_.LastWriteTime -lt (get-date).AddMinutes(-1) } | % {

        Write-Host "Deleting old script: $_"
        Remove-Item -Path $_.FullName

        if (-not ($DBsUpdated -contains $db)) { $DBsUpdated += $db}
    }
}

Write-Host "`nScripts have been removed from the following DbUp projects:"
$DBsUpdated | % { Write-Host "`n$_" }

$input = $null
do {
$input = Read-Host -Prompt "`nYou should now reload all (if prompted) and build the EthicsPoint solution in Visual Studio (or build each of those projects individually) so that the appropriate project files will be updated. Once you have done so, enter ""done"" and this branch will be pushed to GitHub."
}
while ($input -ne "done")

    git status
    git add .
    git commit -m "deleting DbUp scripts"
    git push --set-upstream origin "$sprint-branchcut-update"
 }

 Setup
 $backupName = retrieveBackupName
 CreateBranch
 UpdateBuildObjects
 CreateBackups
 RemoveoldBackups
 CopyBackupsOver
 CleanUpDbUp

Try { RunDevDeploy }
Catch {
    Write-Host "An error ocurred during the final run of DevDeploy which is designed to ensure the branchcut checklist automation script ran correctly. New db copies have likely been added to the remote folder and a branch containing the removal of DbUp scripts may still have been pushed to GitHub. Double check that everything worked as expected."
}


#  do:
# on other computer:
    # try script w/ docker off 
    # dbup portion w/ 90
# make projfile changes if above works correctly
# delete backup local-Copy folder in C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Backup, dbup, and EPIM-Copy on remote drive
# don't forget to delete all the branches made by testing this script, both remote and local