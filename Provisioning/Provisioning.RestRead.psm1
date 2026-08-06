Set-StrictMode -Version Latest

function ConvertTo-UlcRestListResult {
    param([Parameter(Mandatory = $true)]$Value)

    [pscustomobject]@{
        Id = [guid]$Value.Id
        Title = [string]$Value.Title
        Description = [string]$Value.Description
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
    $response = Invoke-PnPSPRestMethod -Url $url -Method Get -Connection $Connection
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
    $response = Invoke-PnPSPRestMethod -Url $url -Method Get -Connection $Connection

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
            InternalName = [string]$field.InternalName
            Title = [string]$field.Title
            TypeAsString = [string]$field.TypeAsString
            Required = [bool]$field.Required
            Indexed = [bool]$field.Indexed
            EnforceUniqueValues = [bool]$field.EnforceUniqueValues
            Choices = $choices
        }
    }
}

Export-ModuleMember -Function Get-UlcRestList, Get-UlcRestFields
