$ErrorActionPreference = 'Stop'

$url = "https://static.burgerkingencasa.es/bkhomewebsite/pt/stores_pt.json"

. (Join-Path $PSScriptRoot common.ps1)

$rootDir = Join-Path $PSScriptRoot ".." -Resolve

Write-Host "Updating gluten-free restaurant list"

Write-Host "Loading districts"

$districts = Get-Content "$rootDir/regions.json" | ConvertFrom-Json

Write-Host "Loading existing places"

$existingPlacesById = @{}
Get-ChildItem "$rootDir/places/burger-king/*.json" | % {
    $id = $_.Name.Replace(".json", "")
    Get-Content $_ | ConvertFrom-Json -Depth 10 | % {
        $existingPlacesById.Add($id, $_)
    }
}

Write-Host "Scraping the page"

$page = Invoke-WebRequest `
    -UseBasicParsing `
    -Uri $url `
    @HttpClientCommonParams

$places = ([System.Text.Encoding]::UTF8.GetString($page.Content) | ConvertFrom-Json).stores

Write-Host "Merging the data"

$data = $places | % {
    [string]$id = $_.bkcode
    
    $previous = $existingPlacesById[$id]
    $existingPlacesById.Remove($id)

    $city = $_.city
    $city = [regex]::Replace($city, "(\s(?:D[AEO]S?|\w{1,2})\s)", { param($m) $m.Groups[1].Value.ToLower() })
    $city = [regex]::Replace($city, "((?:^|[^\w])[A-ZÁÀÉÈÍÌÓÒÚÙ])(\w+)", { param($m) $m.Groups[1].Value + $m.Groups[2].Value.ToLower() })

    $place = [ordered]@{
        id = $id
        name = $_.address.Trim(',')
        gid = $previous.gid
        address =
            if ($previous.fixes.address -ne $null) {
                $previous.fixes.address
            } else {
                "$($_.address.Trim(','))","$($_.postalcode -replace ' ','') $city"
            }
        region = $previous.region
        position = if ($previous.fixes.position -ne $null) {
                $previous.fixes.position
            } else {
                [ordered]@{
                    lat = [double]$_.latitude
                    lng = [double]$_.longitude
                }
            }
    }
    if ($previous.fixes -ne $null) { $place.fixes = $previous.fixes }

    Write-Output $place        
}

$data `
    | ? { $_.region -eq $null } `
    | Write-Throttled 1000 `
    | % {
        Write-Host "Resolving district for $($_.name)"
        $_.region = Resolve-District $_.position.lat $_.position.lng $districts
    }

Write-Host "Updating the files"

$data | % {
    $id = $_["id"]
    $_.Remove("id")
    if ($_.gid -eq $null) {
        $_.Remove("gid")
    }
    $_ | ConvertTo-Json -Depth 10 | Set-Content "$rootDir/places/burger-king/$id.json"
}

if ($existingPlacesById.Count -ne 0) {
    Write-Host "Deleting $($existingPlacesById.Count) removed places"
    $existingPlacesById.Keys | % {
        Remove-Item "$rootDir/places/burger-king/$_.json"
    }
}

Write-Host "Done"
