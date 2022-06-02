<#
.SYNOPSIS
    Alter tag names and scopes while retaining values
.DESCRIPTION
    Modify tag names at a scope while retaining the original values. This can help when tags have incorrect casing or spelling and a uniform scheme is required. 
.NOTES
    Requires the Az.ResourceGraph module to be installed. 
.LINK
    https://github.com/anwather/ReconcileTagNames/blob/main/README.md
.EXAMPLE
    PS>.\ReconcileTagNames.ps1 -SubscriptionId "b01dbd36-a874-467a-99d4-0ee2cecaa474" -TagFixes @{"Cost Center"="CostCentre";"Cost Centre"="CostCentre";"CostCentre"="CostCentre"}

    Displays changes to be made to tags at the subscription scope. The hashtable for the TagFixes parameter contains each incorrect spelling 
    as the key and the corrected value as the value. Ensure that there is a single entry with the same key and value which will correct tags with incorrect casing.
.EXAMPLE
    PS>.\ReconcileTagNames.ps1 -SubscriptionId "b01dbd36-a874-467a-99d4-0ee2cecaa474" -TagFixes @{"Cost Center"="CostCentre";"Cost Centre"="CostCentre";"CostCentre"="CostCentre"} -UpdateTags

    Updates tags at the subscription scope. The hashtable for the TagFixes parameter contains each incorrect spelling 
    as the key and the corrected value as the value. Ensure that there is a single entry with the same key and value which will correct tags with incorrect casing.
.EXAMPLE
    PS>.\ReconcileTagNames.ps1 -ManagementGroupId "caf-bd" -TagFixes @{"Cost Center"="CostCentre";"Cost Centre"="CostCentre";"CostCentre"="CostCentre"} -UpdateTags

    Updates tags at the management group scope. The hashtable for the TagFixes parameter contains each incorrect spelling 
    as the key and the corrected value as the value. Ensure that there is a single entry with the same key and value which will correct tags with incorrect casing.
.PARAMETER TagFixes
    A hashtable of keys which represent the incorrect tag names. The value for each key should be the correct tag value. There should be a key with the same name/value used to 
    correct incorrect casing. 

    E.G. 

    $tagFixes = @{
        "businesscost" = "costcentre"
        "Cost Center" = "costcentre"
        "costCenntre" = "costcentre"
        "CostCenter"  = "costcentre"
        "costcentre"  = "costcentre"
        "application" = "appname"
        "Application Name" = "appname"
        "appname" = "appname"
    }

    The script will look through the tags returned from resources - if a tag is found which matches one of the keys the tag will be replaced. Note the costcentre = costcentre value
    in there to correct incorrect casing on tags. 
.PARAMETER UpdateTags
    Adding this switch parameter in will update the tags. Omitting it will simply show the changes to be made. 
#>

Param (
    [switch]$UpdateTags,
    [Parameter(ParameterSetName = "Subscription", Mandatory = $true)]
    [string]$SubscriptionId,
    [Parameter(ParameterSetName = "ManagementGroup", Mandatory = $true)]
    [string]$ManagementGroupId,
    [hashtable]$TagFixes
)

function ConvertPSObjectToHashtable {
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    process {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @(
                foreach ($object in $InputObject) { ConvertPSObjectToHashtable $object }
            )

            Write-Output -NoEnumerate $collection
        }
        elseif ($InputObject -is [psobject]) {
            $hash = @{}

            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = ConvertPSObjectToHashtable $property.Value
            }

            $hash
        }
        else {
            $InputObject
        }
    }
}

$tagCorrections = $TagFixes.Values | Select-Object -Unique

$query = @"
resources
| where not(isnull(tags))
| where tags != '{}'
| project id,tags
| union 
resourcecontainers
| where not(isnull(tags))
| where tags != '{}'
| project id,tags
"@

$objects = @()

if ($PSBoundParameters.ContainsKey('SubscriptionId')) {
    $parameters = @{
        Subscription = $SubscriptionId
    }
}
elseif ($PSBoundParameters.ContainsKey('ManagementGroupId')) {
    $parameters = @{
        ManagementGroup = $ManagementGroupId
    }
}

do {
    if ($null -eq $SkipToken) {
        $results = Search-AzGraph -Query $query -First 1000 @parameters
        foreach ($res in $results) {
            $objects += $res
        }
        if ($results.SkipToken) {
            $SkipToken = $results.SkipToken
        }
    }
    else {
        $results = Search-AzGraph -Query $query -First 1000 -SkipToken $SkipToken @parameters
        foreach ($res in $results) {
            $objects += $res
        }
        if ($results.SkipToken) {
            $SkipToken = $results.SkipToken
        }
        else {
            $SkipToken = $null
        }
    }
}
until ($null -eq $SkipToken)

$actions = @()

foreach ($id in $objects) {
    foreach ($tag in (ConvertPSObjectToHashtable $id.tags).GetEnumerator()) {
        if ($tagFixes[$tag.Name]) {
            $v = $tagFixes[$tag.Name]
            if ((ConvertPSObjectToHashtable $id.tags).Keys -contains $v) {
                if (!($tag.Name -cmatch $v) -and ($tag.Name -match $v) -and ($tag.Name -in $tagCorrections)) {
                    Write-Output "Removing existing incorrect cased tag"
                    $obj = [PsCustomObject]@{
                        id      = $id.ResourceId
                        action  = "Remove"
                        tagName = $tag.Name
                    }
                    $actions += $obj
                    Write-Output "Adding new tag"
                    $obj = [PsCustomObject]@{
                        id       = $id.ResourceId
                        action   = "Add"
                        tagName  = $v
                        tagValue = (ConvertPSObjectToHashtable $id.tags)[$tag.Name]
                    }
                    $actions += $obj 
                }
                elseif (!($tag.Name -in $tagCorrections)) {
                    Write-Output "Correct Tag already exists"
                    $obj = [PsCustomObject]@{
                        id      = $id.ResourceId
                        action  = "Remove"
                        tagName = $tag.Name
                    }
                    $actions += $obj
                }

            }
            else {
                Write-Output "Removing existing tag"
                $obj = [PsCustomObject]@{
                    id      = $id.ResourceId
                    action  = "Remove"
                    tagName = $tag.Name
                }
                $actions += $obj
                Write-Output "Adding new tag"
                $obj = [PsCustomObject]@{
                    id       = $id.ResourceId
                    action   = "Add"
                    tagName  = $v
                    tagValue = (ConvertPSObjectToHashtable $id.tags)[$tag.Name]
                }
                $actions += $obj
            }
        }
    }
}

$actions

if ($UpdateTags) {
    foreach ($action in $actions) {
        switch ($action.action) {
            "Remove" { Update-AzTag -ResourceId $action.id -Tag @{$action.tagName = $null } -Operation Delete }
            "Add" { Update-AzTag -ResourceId $action.id -Tag @{$action.tagName = $action.tagValue } -Operation Merge }
        }
    }
}




