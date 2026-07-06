$ErrorActionPreference = 'Stop'

$url = "https://www.pansandcompany.pt/onde-estamos/"

. (Join-Path $PSScriptRoot common.ps1)

$rootDir = Join-Path $PSScriptRoot ".." -Resolve


$districts = Get-Content "$rootDir/regions.json" | ConvertFrom-Json

Write-Host "Loading existing places"

$existingPlacesById = @{}
Get-ChildItem "$rootDir/places/pans-and-company/*.json" | % {
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

$matched = $page.Content -match "(?s-imnx:var settings\s*=\s*(\{.*?\});)"
if (-not $matched) {
    throw "Failed to parse the page"
}

$settings = $Matches[1] | ConvertFrom-Json
$places = $settings.pins.pins `
    | Select-Object id, title, latlng, @{label="tipXml";expression={[xml]"<x>$($_.tooltipContent -replace '&','&amp;' -replace '<br>',"`n" -replace '<br />',"`n")</x>"}} `
    | Select-Object id, title, latlng, @{label="address";expression={$_.tipXml.x.div.p.FirstChild.NextSibling.Value.Trim("`n").Replace("`n`n", "`n")}}

Write-Host "Merging the data"

$data = $places `
    | % {
        [string]$id = $_.id
        $previous = $existingPlacesById[$id]
        $existingPlacesById.Remove($id)

        $place = [ordered]@{
            id = $id
            name = $_.title -replace "PANS & COMPANY - ",""
            gid = $previous.gid
            address =
                if ($previous.fixes.address -ne $null) {
                    $previous.fixes.address
                } else {
                    $_.address.Split("`n")
                }
            region = $previous.region
            position = [ordered]@{
                lat = [double]$_.latlng[0]
                lng = [double]$_.latlng[1]
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
    $_ | ConvertTo-Json -Depth 10 | Set-Content "$rootDir/places/pans-and-company/$id.json"
}

if ($existingPlacesById.Count -ne 0) {
    Write-Host "Deleting $($existingPlacesById.Count) removed places"
    $existingPlacesById.Keys | % {
        Remove-Item "$rootDir/places/pans-and-company/$_.json"
    }
}

Write-Host "Done"
