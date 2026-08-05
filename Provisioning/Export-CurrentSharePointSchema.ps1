param(
    [Parameter(Mandatory = $true)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [string]$OutputDirectory = "./generated/sharepoint-schema"
)

$ErrorActionPreference = "Stop"

Import-Module PnP.PowerShell -ErrorAction Stop

$resolvedOutput = [System.IO.Path]::GetFullPath(
    (Join-Path (Get-Location) $OutputDirectory)
)

New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null

Connect-PnPOnline `
    -Url $SiteUrl `
    -Interactive `
    -ClientId $ClientId

$lists = Get-PnPList |
    Where-Object {
        -not $_.Hidden -and
        $_.BaseTemplate -notin @(544, 851)
    } |
    Sort-Object Title

$schema = [ordered]@{
    exportedAt = (Get-Date).ToUniversalTime().ToString("o")
    siteUrl    = $SiteUrl
    lists      = @()
}

$fieldRows = [System.Collections.Generic.List[object]]::new()
$viewRows  = [System.Collections.Generic.List[object]]::new()
$listRows  = [System.Collections.Generic.List[object]]::new()

foreach ($list in $lists) {
    Write-Host "Exportiere Liste: $($list.Title)"

    $fields = Get-PnPField -List $list |
        Where-Object {
            -not $_.Hidden -or
            $_.InternalName -in @(
                "ID",
                "Created",
                "Modified",
                "Author",
                "Editor"
            )
        } |
        Sort-Object InternalName

    $views = Get-PnPView -List $list | Sort-Object Title

    $contentTypes = Get-PnPContentType -List $list |
        Sort-Object Name

    $fieldDefinitions = foreach ($field in $fields) {
        $lookupListTitle = $null

        if (
            $field.TypeAsString -in @(
                "Lookup",
                "LookupMulti"
            ) -and
            $field.LookupList
        ) {
            try {
                $lookupList = Get-PnPList -Identity $field.LookupList
                $lookupListTitle = $lookupList.Title
            }
            catch {
                $lookupListTitle = $field.LookupList
            }
        }

        $definition = [ordered]@{
            title              = $field.Title
            internalName       = $field.InternalName
            id                 = $field.Id.ToString()
            type               = $field.TypeAsString
            required           = $field.Required
            readOnly           = $field.ReadOnlyField
            hidden             = $field.Hidden
            indexed            = $field.Indexed
            enforceUnique      = $field.EnforceUniqueValues
            defaultValue       = $field.DefaultValue
            group              = $field.Group
            description        = $field.Description
            choices            = @($field.Choices)
            lookupList         = $lookupListTitle
            lookupField        = $field.LookupField
            allowMultiple      = $field.AllowMultipleValues
            schemaXml          = $field.SchemaXml
        }

        $fieldRows.Add([pscustomobject]@{
            ListTitle       = $list.Title
            ListUrl         = $list.RootFolder.ServerRelativeUrl
            FieldTitle      = $field.Title
            InternalName    = $field.InternalName
            Type            = $field.TypeAsString
            Required        = $field.Required
            Indexed         = $field.Indexed
            Unique          = $field.EnforceUniqueValues
            LookupList      = $lookupListTitle
            LookupField     = $field.LookupField
            Choices         = (@($field.Choices) -join " | ")
            Description     = $field.Description
        })

        $definition
    }

    $viewDefinitions = foreach ($view in $views) {
        $viewFields = @($view.ViewFields)

        $viewRows.Add([pscustomobject]@{
            ListTitle    = $list.Title
            ViewTitle    = $view.Title
            DefaultView  = $view.DefaultView
            RowLimit     = $view.RowLimit
            Paged        = $view.Paged
            Fields       = ($viewFields -join " | ")
            Query        = $view.ViewQuery
        })

        [ordered]@{
            title       = $view.Title
            id          = $view.Id.ToString()
            defaultView = $view.DefaultView
            rowLimit    = $view.RowLimit
            paged       = $view.Paged
            fields      = $viewFields
            query       = $view.ViewQuery
        }
    }

    $contentTypeDefinitions = foreach ($contentType in $contentTypes) {
        [ordered]@{
            name = $contentType.Name
            id   = $contentType.StringId
        }
    }

    $listRows.Add([pscustomobject]@{
        Title                  = $list.Title
        Id                     = $list.Id
        Url                    = $list.RootFolder.ServerRelativeUrl
        BaseTemplate           = $list.BaseTemplate
        ItemCount              = $list.ItemCount
        EnableVersioning       = $list.EnableVersioning
        EnableMinorVersions    = $list.EnableMinorVersions
        ForceCheckout          = $list.ForceCheckout
        ContentTypesEnabled    = $list.ContentTypesEnabled
        HasUniquePermissions   = $list.HasUniqueRoleAssignments
    })

    $schema.lists += [ordered]@{
        title                = $list.Title
        id                   = $list.Id.ToString()
        url                  = $list.RootFolder.ServerRelativeUrl
        description          = $list.Description
        baseTemplate         = $list.BaseTemplate
        itemCount            = $list.ItemCount
        enableVersioning     = $list.EnableVersioning
        enableMinorVersions  = $list.EnableMinorVersions
        forceCheckout        = $list.ForceCheckout
        contentTypesEnabled  = $list.ContentTypesEnabled
        hasUniquePermissions = $list.HasUniqueRoleAssignments
        fields               = @($fieldDefinitions)
        views                = @($viewDefinitions)
        contentTypes         = @($contentTypeDefinitions)
    }
}

$jsonPath = Join-Path $resolvedOutput "sharepoint-schema.json"
$listCsv  = Join-Path $resolvedOutput "lists.csv"
$fieldCsv = Join-Path $resolvedOutput "fields.csv"
$viewCsv  = Join-Path $resolvedOutput "views.csv"

$schema |
    ConvertTo-Json -Depth 20 |
    Set-Content -Path $jsonPath -Encoding UTF8

$listRows |
    Export-Csv -Path $listCsv -NoTypeInformation -Encoding UTF8

$fieldRows |
    Export-Csv -Path $fieldCsv -NoTypeInformation -Encoding UTF8

$viewRows |
    Export-Csv -Path $viewCsv -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Schemaexport abgeschlossen:"
Write-Host "  $jsonPath"
Write-Host "  $listCsv"
Write-Host "  $fieldCsv"
Write-Host "  $viewCsv"
