Set-StrictMode -Version Latest

$script:RestToken = $null
$script:RestSiteUrl = $null

function Get-UlcRestContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Connection
    )

    $connectionUrl = ([string]$Connection.Url).TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($connectionUrl)) {
        throw 'Die PnP-Verbindung enthält keine Site-URL.'
    }

    if (
        [string]::IsNullOrWhiteSpace($script:RestToken) -or
        $script:RestSiteUrl -ne $connectionUrl
    ) {
        $script:RestToken = Get-PnPAccessToken `
            -ResourceTypeName SharePoint `
            -Connection $Connection

        if ([string]::IsNullOrWhiteSpace($script:RestToken)) {
            throw 'Für SharePoint konnte kein Access Token abgerufen werden.'
        }

        $script:RestSiteUrl = $connectionUrl
    }

    [pscustomobject]@{
        SiteUrl = $script:RestSiteUrl
        Headers = @{
            Authorization = "Bearer $($script:RestToken)"
            Accept        = 'application/json;odata=nometadata'
        }
    }
}

function Invoke-UlcSharePointRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativeUrl,

        [Parameter(Mandatory = $true)]
        $Connection
    )

    $context = Get-UlcRestContext -Connection $Connection
    $uri = if ($RelativeUrl.StartsWith('/')) {
        "$($context.SiteUrl)$RelativeUrl"
    }
    else {
        "$($context.SiteUrl)/$RelativeUrl"
    }

    Invoke-RestMethod `
        -Uri $uri `
        -Headers $context.Headers `
        -Method Get `
        -TimeoutSec 30 `
        -ErrorAction Stop
}

function ConvertTo-UlcRestListResult {
    param([Parameter(Mandatory = $true)]$Value)

    [pscustomobject]@{
        Id               = [guid]$Value.Id
        Title            = [string]$Value.Title
        Description      = [string]$Value.Description
        EnableVersioning = [bool]$Value.EnableVersioning
    }
}

function Get-UlcRestList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identity,

        [Parameter(Mandatory = $true)]
        $Connection
    )

    $escapedIdentity = $Identity.Replace("'", "''")
    $url = "/_api/web/lists/getbytitle('$escapedIdentity')?`$select=Id,Title,Description,EnableVersioning"
    $response = Invoke-UlcSharePointRest -RelativeUrl $url -Connection $Connection
    ConvertTo-UlcRestListResult -Value $response
}

function Get-UlcRestFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$List,

        [Parameter(Mandatory = $true)]
        $Connection
    )

    $escapedList = $List.Replace("'", "''")
    $url = "/_api/web/lists/getbytitle('$escapedList')/fields?`$select=InternalName,Title,TypeAsString,Required,Indexed,EnforceUniqueValues,Choices"
    $response = Invoke-UlcSharePointRest -RelativeUrl $url -Connection $Connection

    foreach ($field in @($response.value)) {
        $choices = @()
        if ($null -ne $field.Choices) {
            if ($null -ne $field.Choices.results) {
                $choices = @($field.Choices.results)
            }
            else {
                $choices = @($field.Choices)
            }
        }

        [pscustomobject]@{
            InternalName       = [string]$field.InternalName
            Title              = [string]$field.Title
            TypeAsString       = [string]$field.TypeAsString
            Required           = [bool]$field.Required
            Indexed            = [bool]$field.Indexed
            EnforceUniqueValues = [bool]$field.EnforceUniqueValues
            Choices            = $choices
        }
    }
}

Export-ModuleMember -Function Get-UlcRestList, Get-UlcRestFields
