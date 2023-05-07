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
            return $False
        }else{
            Write-Host "Updating repository $repositoryName"
            set-location $repositoryName
            git pull
            Write-Host "Updated repository $repositoryName"
            set-location '..'
        }
    }
    return $True
}

function Update-DistransStock {
    param (
        [Parameter(Mandatory)]$repositoryName,
        [Parameter(Mandatory)]$distransProductsUrl
    )

    set-location $repositoryName
    Get-ChildItem -Path "."
    |  ForEach-Object {
        $fileName = $_.Name
        $pattern = "(?<file_name>.+).csv"
        $matches = [Regex]::Matches($fileName, $Pattern)
        if ($matches) {
            $csvName = $matches[0].Groups["file_name"].Value
            Write-Host "Reading csv file $fileName"
            $products = Import-Csv -Path ".\$fileName"
            $dirtySupplierName = [regex]::split($repositoryName,'-')[0]
            $dirtySupplierNameSpace = [regex]::replace($dirtySupplierName,'_', " ")
            $TextInfo = (Get-Culture).TextInfo
            $supplierCleanName = $TextInfo.ToTitleCase($dirtySupplierNameSpace)
            $products | ForEach-Object {
                $productName = $_.name
                $price = $_.'unit price'
                $units = $_.units
                $postParams = @{name=$productName ;price=$price ;supplier_name=$supplierCleanName ;category=$csvName ;units=$units} | ConvertTo-Json
                Write-Host "Inserting stock for product in Distrans service"
                $postParams | Format-Table

                $headers = @{
                    "Content-Type" = "application/json"
                }

                Try {
                    $resp = Invoke-WebRequest -Uri $distransProductsUrl -Headers $headers -Method POST -Body $postParams -ErrorAction Stop
                    Write-Host $resp.Content
                    Write-Host "Added stock por product $productName"
                } Catch {
                    if($_.ErrorDetails.Message) {
                        # "----WebResponseError----"
                        Write-Host $_.ErrorDetails.Message;
                    } else {
                        #UsualException
                        $_
                    }
                }
                # if ( $resp.StatusCode -gt 201 ) { 
                #     Write-Host "Unable to insert product from file on Distrans service"
                # } 
            }
        }
    }

    set-location '..'
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
$distransProductsUrl = $h.Get_Item("DistransProductsUrl")

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


set-location $downloadPath
foreach ($entry in $json) { 
    $name = $entry.name 

    # Clone or pull all group's repositories
    $url = $entry.http_url_to_repo -replace "://", ("://{0}@" -f $gitcred)
    $exists = Update-StockRepository -repoUrl $url -repositoryName $name
    if ($exists) {
        Update-DistransStock -repositoryName $name -distransProductsUrl $distransProductsUrl
    }
}
