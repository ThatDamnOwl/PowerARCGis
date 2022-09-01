## Module variables and getters/setters

$ARCGISAPIRoot = "arcgis/rest"
$ARCGISServer = "server"
$ARCGISProtocol = "https"
$ARCGISAPIURI = "$($ARCGISProtocol)://$($ARCGISServer)/$($ARCGISAPIRoot)"
$ModuleFolder = (Get-Module PowerARCGIS -ListAvailable).path -replace "PowerARCGIS\.psm1"

function Set-ArcGISAPIRoot
{
    param
    (
        [string]
        $NewAPIRoot
    )
    set-variable -scope 1 -name ARCGISAPIRoot -value $NewAPIRoot
    set-variable -scope 1 -name ARCGISAPIURI -value "$($ARCGISProtocol)://$($ARCGISServer)/$($ARCGISAPIRoot)"
}

function Set-ARCGISServer
{
    param
    (
        [string]
        $NewServer
    )
    set-variable -scope 1 -name ARCGISServer -value $NewServer
    set-variable -scope 1 -name ARCGISAPIURI -value "$($ARCGISProtocol)://$($ARCGISServer)/$($ARCGISAPIRoot)"
}

function Set-ARCGISProtocol
{
    param
    (
        [string]
        $NewProtocol
    )
    set-variable -scope 1 -name ARCGISProtocol -value $NewProtocol
    set-variable -scope 1 -name ARCGISAPIURI -value "$($ARCGISProtocol)://$($ARCGISServer)/$($ARCGISAPIRoot)"
}

function get-ARCGISAPIRoot
{
    return $ARCGISAPIRoot
}

function get-ARCGISServer
{
    return $ARCGISServer
}

function get-ARCGISProtocol
{
    return $ARCGISProtocol
}

## Basic functions

Function Invoke-ARCGISVariableSave 
{
    $AllVariables = Get-Variable -scope 1 | where {$_.name -match "ARCGIS"}
    $VariableStore = @{}
    foreach ($Variable in $AllVariables)
    {
        if ($Variable.value.GetType().name -eq "PSCredential")
        {
            $VariableStore += @{
                                   "username" = $Variable.value.username
                                   "securepass" = ($Variable.value.Password | ConvertFrom-SecureString)
                               }
        }
        else {
            $VariableStore += @{$Variable.name = $Variable.Value}
        }
    }

    $VariableStore.GetEnumerator() | export-csv "$ModuleFolder\$($ENV:Username)-Variables.csv"
}

Function Invoke-ARCGISVariableLoad
{
    $VariablePath = "$ModuleFolder\$($ENV:Username)-Variables.csv"
    if (test-path $VariablePath)
    {
        $VariableStore = import-csv $VariablePath

        foreach ($Variable in $VariableStore)
        {
            if ($Variable.name -match "(username|securepass)")
            {
                if ($Variable.name -eq "username")
                {
                    Write-Debug "Importing ARCGISCredential"
                    $EncString = ($VariableStore | where {$_.name -eq "securepass"}).Value | ConvertTo-SecureString
                    $Credential = New-Object System.Management.Automation.PsCredential($Variable.Value, $EncString)
                    set-variable -scope 1 -name ARCGISCredential -value $Credential
                }
            }
            else
            {
                Write-Debug "Importing $($Variable.name)"
                set-variable -scope 1 -name $Variable.Name -value $Variable.Value
            }
        }
    }

}

## API Specific functions

Function Convert-ARCGISLatLngtoWebMerc 
{
    param 
    (
        [double]
        $Lat,
        [double]
        $Lng
    )

    $Shift = 20037508.34

    $WebMercLng = 6378137.0 * [double]($Lng * 0.017453292519943295)
    $WebMercLat = $Lat * 0.017453292519943295
    $WebMercLat = (1.0 + [System.Math]::sin($WebMercLat)) / (1.0 - [System.Math]::sin($WebMercLat))
    $WebMercLat = [System.Math]::Log($WebMercLat)
    $WebMercLat = 3189068.5 * $WebMercLat
    @{"y" = $WebMercLat; "x" = $WebMercLng}
}

Function Invoke-ARCGISFeatureServiceLayerQuery
{
    param
    (
        $ServiceName,
        $LayerNumber,
        $Conditions
    )

    $BaseURI = "$APIURI/services/Hosted/$ServiceName/FeatureServer/$LayerNumber/Query"
    #Write-host $Conditions
    $BaseURI = Add-QueryConditions $BaseURI $Conditions
    #Write-host $BaseURI
    Invoke-RestMethod -uri $BaseURI -method get
}

Function Add-ARCGISQueryConditions
{
    param
    (
        $BaseURI,
        $Conditions
    )
    $BaseURI += "?"

    for ($X = 0; $X -lt $Conditions.Count; $X++)
    {
        $ConditionKey = ($Conditions.keys -split "`n")[$X]
        #Write-host $ConditionKey
        $ConditionValue = $Conditions[$ConditionKey]
        $BaseURI += "$($ConditionKey)=$([System.Web.HttpUtility]::URLEncode($ConditionValue))&"
    }

    if ($BaseURI[$BaseURI.length - 1] -ne "&")
    {
        $BaseURI += "&"
    }

    $BaseURI += "f=json"

    $BaseURI
}

function Get-ARCGISFeatureServiceLayerFeatures
{
    param
    (
        $ServiceName,
        $LayerNumber,
        $Conditions,
        [switch]
        $all
    )
    if ($all)
    {
        $Conditions = @{"where" = "1=1"; "returnIdsOnly" = "true"}
    }

    if ($Conditions.keys -notcontains "returnIdsOnly")
    {
        $Conditions += @{"returnIdsOnly" = "true"}
    }

    $ObjectIDs = (Invoke-FeatureServiceLayerQuery $ServiceName $LayerNumber $Conditions).ObjectIDs
    $Features = @()
    foreach ($ObjectID in $ObjectIDs)
    {
        $Features += Get-FeatureServiceLayerFeature $ServiceName $LayerNumber $ObjectID
    }
    return $Features
}

Function Get-ARCGISFeatureServiceLayerFeature
{
    param
    (
        $ServiceName,
        $LayerNumber,
        $ObjectID
    )

    $BaseURI = "$APIURI/services/Hosted/$ServiceName/FeatureServer/$LayerNumber/$ObjectID/"

    $BaseURI = Add-ARCGISQueryConditions $BaseURI

    (Invoke-RestMethod -uri $BaseURI -method get).Feature
}

Function Invoke-ARCGISFeatureServiceLayerFeatureUpdate
{
    param
    (
        $ServiceName,
        $LayerNumber,
        $UpdateJson
    )
    if ($UpdateJson[0] -eq "{")
    {
        $UpdateJson = "[$UpdateJson]"
    }

    if ($UpdateJson -notcontains "features=")
    {
        $UpdateJson = "features=$UpdateJson"
    }

    $BaseURI = "$APIURI/services/Hosted/$ServiceName/FeatureServer/$LayerNumber/updateFeatures?f=json"
    Write-Verbose "Posting to $BaseURI"
    Write-Debug $UpdateJson
    $Return = Invoke-RestMethod -uri $BaseURI -body $UpdateJson -method post

    if ($Return -match """success"": true")
    {
        return 0
    }
    else {
        return $Return
    }
}

Function Add-ARCGISFeatureServiceLayerFeature
{
    param
    (
        $ServiceName,
        $LayerNumber,
        $AddJson
    )

    if ($AddJson[0] -eq "{")
    {
        $AddJson = "[$AddJson]"
    }

    if ($AddJson -notcontains "features=")
    {
        $AddJson = "features=$AddJson"
    }

    $BaseURI = "$APIURI/services/Hosted/$ServiceName/FeatureServer/$LayerNumber/addFeatures?f=json"
    Write-Verbose "Posting to $BaseURI"
    Write-Debug $AddJson
    $Return = Invoke-RestMethod -uri $BaseURI -body $AddJson -method post

    if ($Return -match """success"": true")
    {
        return 0
    }
    else {
        return $Return
    }
}



