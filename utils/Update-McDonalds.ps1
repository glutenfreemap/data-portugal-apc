# nuget restore -PackagesDirectory packages

$ErrorActionPreference = 'Stop'

$url = "https://www.mcdonalds.pt/restaurantes"

. (Join-Path $PSScriptRoot common.ps1)

$rootDir = Join-Path $PSScriptRoot ".." -Resolve

Add-Type -AssemblyName "$PSScriptRoot/packages/HtmlAgilityPack.1.11.46/lib/netstandard2.0/HtmlAgilityPack.dll"

Write-Host "Loading districts"

$districts = Get-Content "$rootDir/regions.json" | ConvertFrom-Json

Write-Host "Loading existing places"

$existingPlacesById = @{}
Get-ChildItem "$rootDir/places/mcdonalds/*.json" | % {
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

$doc = New-Object HtmlAgilityPack.HtmlDocument
$doc.LoadHtml($page.Content)
$places = $doc.DocumentNode.SelectNodes("//section[contains(@class, ' restaurantMapList__listing ')]//a[@class='contentList__item']")

Write-Host "Merging the data"

$data = $places `
    | % {
        $id = $_.Attributes["href"].Value -replace '/restaurantes/',''

        $previous = $existingPlacesById[$id]
        $existingPlacesById.Remove($id)

        $article = $_.SelectSingleNode("article")

        $place = [ordered]@{
            id = $id
            name = [System.Web.HttpUtility]::HtmlDecode($article.SelectSingleNode("p[@class='listedItem__description']/text()").Text.Trim())
            gid = $previous.gid
            address =
                if ($previous.fixes.address -ne $null) {
                    $previous.fixes.address
                } else {
                    $previous.address
                }
            region = $previous.region
            position = [ordered]@{
                lat = [double]$article.Attributes["data-lat"].Value
                lng = [double]$article.Attributes["data-lng"].Value
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

$data `
    | ? { $_.address -eq $null } `
    | Write-Throttled 1000 `
    | % {
        Write-Host "Getting address for $($_.name)"
        $page = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri "$url/$($_.id)" `
            @HttpClientCommonParams

        $doc = New-Object HtmlAgilityPack.HtmlDocument
        $doc.LoadHtml($page.Content)
        $address = $doc.DocumentNode.SelectNodes("//div[@class='info']/p[not(@class='phone')]/text()") `
            | % { [System.Web.HttpUtility]::HtmlDecode($_.Text.Trim()) } `
            | Get-UniqueUnsorted

        $_.address = $address
    }

Write-Host "Updating the files"

$data | % {
    $id = $_["id"]
    $_.Remove("id")
    if ($_.gid -eq $null) {
        $_.Remove("gid")
    }
    $_ | ConvertTo-Json -Depth 10 | Set-Content "$rootDir/places/mcdonalds/$id.json"
}

if ($existingPlacesById.Count -ne 0) {
    Write-Host "Deleting $($existingPlacesById.Count) removed places"
    $existingPlacesById.Keys | % {
        Remove-Item "$rootDir/places/mcdonalds/$_.json"
    }
}

Write-Host "Done"
