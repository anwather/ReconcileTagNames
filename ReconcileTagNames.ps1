Param (
    [switch]$UpdateTags,
    [Parameter(ParameterSetName = "Subscription")]
    [string]$SubscriptionId,
    [Parameter(ParameterSetName = "ManagementGroup")]
    [string]$ManagementGroupId,
    [hashtable]$TagFixes,
    [string[]]$TagCorrections
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


$query = @"
resources
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




