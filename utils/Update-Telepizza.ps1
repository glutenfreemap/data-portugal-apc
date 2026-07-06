# nuget restore -PackagesDirectory packages

Param(
    [string] $Url = "https://www.telepizza.pt/pizzas-sem-gluten.html",
    [switch] $AddMissingPlaces
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot common.ps1)

$rootDir = Join-Path $PSScriptRoot ".." -Resolve

Add-Type -AssemblyName "$PSScriptRoot/packages/HtmlAgilityPack.1.11.46/lib/netstandard2.0/HtmlAgilityPack.dll"

Write-Host "Loading districts"

$districts = Get-Content "$rootDir/regions.json" | ConvertFrom-Json

Write-Host "Loading existing places"

$existingPlacesById = @{}
Get-ChildItem "$rootDir/places/telepizza/*.json" | % {
    $id = $_.Name.Replace(".json", "")
    Get-Content $_ | ConvertFrom-Json -Depth 10 | % {
        $existingPlacesById.Add($id, $_)
    }
}

Write-Host "Scraping the page"

$page = Invoke-WebRequest `
    -UseBasicParsing `
    -Uri $Url `
    @HttpClientCommonParams

$doc = New-Object HtmlAgilityPack.HtmlDocument
$doc.LoadHtml($page.Content)

$manualFixes = @{
    "FORTE DA CASA" = "219530251"
}

$placesByPhoneNumber = @{}
$doc.DocumentNode.SelectNodes("//ul[@class='infotable']/li") `
    | % {
        $phoneNumber = $_.SelectSingleNode("p/text()").Text.Trim() -replace " ",""
        $name = [System.Web.HttpUtility]::HtmlDecode(($_.SelectSingleNode("p/strong/text()|p/b/text()").Text.Trim()))

        if ($manualFixes.ContainsKey($name)) {
            $phoneNumber = $manualFixes[$name]
        }

        if ($placesByPhoneNumber.ContainsKey($phoneNumber)) {
            Write-Error "Found a duplicate phone number $phoneNumber for places '$name' and '$($placesByPhoneNumber[$phoneNumber])'"
            exit 1
        }

        $placesByPhoneNumber.Add($phoneNumber, $name)
    }


Write-Host "Merging the data"

$data = $placesByPhoneNumber.GetEnumerator() `
    | % {
        $id = $_.Key
        $name = $_.Value | % { [String]::Join(" ", ([System.Text.RegularExpressions.Regex]::Split($_, "\s+") | % { "$($_[0].ToString().ToUpper())$($_.Substring(1).ToLower())" })) }

        $previous = $existingPlacesById[$id]
        $existingPlacesById.Remove($id)

        if ($previous -ne $null) {
            $place = [ordered]@{
                id = $id
                name = $name
                gid = $previous.gid
                address = $previous.address
                region = $previous.region
                position = [ordered]@{
                    lat = $previous.position.lat
                    lng = $previous.position.lng
                }
            }
        } elseif($AddMissingPlaces) {
            $place = [ordered]@{
                id = $id
                name = "$name - $id"
                address = @("")
                region = $districts[0].id
                position = [ordered]@{
                    lat = 39.608
                    lng = -8.267
                }
            }
        } else {
            Write-Error "There are missing places"
            exit 1
        }

        Write-Output $place
    }

Write-Host "Updating the files"

$data | % {
    $id = $_["id"]
    $_.Remove("id")
    if ($_.gid -eq $null) {
        $_.Remove("gid")
    }
    $_ | ConvertTo-Json -Depth 10 | Set-Content "$rootDir/places/telepizza/$id.json"
}

if ($existingPlacesById.Count -ne 0) {
    Write-Host "Deleting $($existingPlacesById.Count) removed places"
    $existingPlacesById.Keys | % {
        Remove-Item "$rootDir/places/telepizza/$_.json"
    }
}

Write-Host "Done"
