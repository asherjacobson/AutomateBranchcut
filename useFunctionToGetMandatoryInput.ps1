
if ($null -eq $newBackupName) {
    function retrieveBackupName {
        param(
            [Parameter(Mandatory)]
            [string]$userInput 
        ) 
        $global:newBackupName = $userInput
    }

    do {
        try {
            retrieveBackupName
        }
        catch {
            Write-Warning $Error[0] 
        }
    }
    until ($newBackupName)
}
