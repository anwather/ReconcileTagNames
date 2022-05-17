## Reconcile Tag Names

Used to alter tags across an environment to correct incorrect tag names/spelling/case differences.

e.g. Cost Centre / Cost Center / CostCenter / Costcenter

## Usage

```
PS C:\>ReconcileTagNames.ps1 -Subscription "cf0f9db2-7009-41d4-a360-f7e5ed552c13" `
        -TagFixes @{"Cost Center"="CostCentre";"Cost Centre"="CostCentre","CostCentre"="CostCentre"} `
        -TagCorrections "CostCentre"
```
Scans the subscription for tags which match the keys of the ```TagFixes``` hashtable. For each incorrect tag it will display the operations to be performed e.g. add/remove and the id of the resource and the tag value. Does not actually perform any changes.

```
PS C:\>ReconcileTagNames.ps1 -Subscription "cf0f9db2-7009-41d4-a360-f7e5ed552c13" `
        -TagFixes @{"Cost Center"="CostCentre";"Cost Centre"="CostCentre","CostCentre"="CostCentre"} `
        -TagCorrections "CostCentre" `
        -UpdateTags
```
As above but will update the tag names and values across the subscription scope. 

```
PS C:\>ReconcileTagNames.ps1 -Subscription "cf0f9db2-7009-41d4-a360-f7e5ed552c13" `
        -TagFixes @{"Cost Center"="CostCentre";"Cost Centre"="CostCentre","CostCentre"="CostCentre";"appname"="Application";"Application"="Application"} `
        -TagCorrections "CostCentre","Application" `
        -UpdateTags
```
As above but will also fix the ```Application``` tag casing and change and tag with a name of ```appname``` to ```Application```. Note the corrected tag must appear in the ```TagCorrections``` parameter.

```
PS C:\>ReconcileTagNames.ps1 -ManagementGroupId "my-root-management-group" `
        -TagFixes @{"Cost Center"="CostCentre";"Cost Centre"="CostCentre","CostCentre"="CostCentre";"appname"="Application";"Application"="Application"} `
        -TagCorrections "CostCentre","Application" `
        -UpdateTags
```
Same as above but the target will be the management group defined in the parameter. 


        