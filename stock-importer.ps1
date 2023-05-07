#!/usr/bin/pwsh

function Update-StockRepository {
    param (
        [Parameter(Mandatory)]
        $repoUrl,
        [Parameter(Mandatory)]$repositoryName
    )

    if (-Not (Test-Path $repositoryName)) {
        Write-Host "Cloning repository $repositoryName"
        git clone $repoUrl
        Write-Host "Cloned repository $repositoryName"
    }
    else {
        if (-Not (Test-Path "$repositoryName/.git")) {
            Write-Host "$repositoryName is not a valid git repository"
        }else{
            Write-Host "Updating repository $repositoryName"
            set-location $repositoryName
            git pull
            Write-Host "Updated repository $repositoryName"
            set-location '..'
        }
    }
}

# Read configuration file
Get-Content "configuration.config" | foreach-object -begin {$h=@{}} -process { 
    $k = [regex]::split($_,'='); 
    if(($k[0].CompareTo("") -ne 0) -and ($k[0].StartsWith("[") -ne $True)) { 
        $h.Add($k[0], $k[1]) 
    } 
}

$url = $h.Get_Item("Url")
$gitlabUsername = $h.Get_Item("GitlabUsername")
$gitlabToken = $h.Get_Item("GitlabPAT")
$downloadPath = $h.Get_Item("DownloadPath")
$groupId = $h.Get_Item("GroupId")

if (-Not (Test-Path $downloadPath)) {
    Write-Host "Download path $downloadPath do not exists"
    return
}

$headers = @{
    "Authorization" = ("Bearer {0}" -f $gitlabToken)
    "Accept" = "application/json"
}

Add-Type -AssemblyName System.Web
$gitcred = ("{0}:{1}" -f  [System.Web.HttpUtility]::UrlEncode($gitlabUsername),$gitlabToken)

$groupProjectsUri = ("{0}/api/v4/groups/{1}/projects" -f $url, $groupId)
$resp = Invoke-WebRequest -Headers $headers -Uri $groupProjectsUri
$json = convertFrom-JSON $resp.Content

# Clone or pull all group's repositories
set-location $downloadPath
foreach ($entry in $json) { 
    $name = $entry.name 

    $url = $entry.http_url_to_repo -replace "://", ("://{0}@" -f $gitcred)
    Update-StockRepository -repoUrl $url -repositoryName $name
}
