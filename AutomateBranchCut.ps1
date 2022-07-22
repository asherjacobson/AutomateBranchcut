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

 function CopyBackupsOver {
     Write-Host "Copying new database backups from local to remote folder, this may take a little while..."
 
     New-Item -Path $remotePath -Name $backupName -ItemType Directory
     Get-ChildItem "$localPath\$backupName" | Get-ChildItem | % { Copy-Item $_.FullName -Destination "$remotePath\$backupName" }
 }

 Setup
 $backupName = retrieveBackupName
 CreateBranch
 UpdateBuildObjects
 CreateBackups
 RemoveoldBackups
 CopyBackupsOver

Write-Host "You are on ""$sprint-branchcut-update"" branch. You should now delete any DbUp scripts more than 90 days old, build Visual Studio, ensure you see the changes reflected in the project file, and then push the branch."

# Try { RunDevDeploy }
# Catch {
#     Write-Host "An error ocurred during the final run of DevDeploy which is designed to ensure the branchcut checklist automation script ran correctly. New db copies have likely been added to the remote folder and a branch containing the removal of DbUp scripts may still have been pushed to GitHub. Double check that everything worked as expected."
# }