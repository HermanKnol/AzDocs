#region Helper functions

<#
.SYNOPSIS
    Add Access restriction to app service and/or function app
.DESCRIPTION
    Add Access restriction to app service and/or function app
#>
function Add-AccessRestriction
{
    [CmdletBinding(DefaultParameterSetName='cidr')]
    param (
        [Parameter(Mandatory)][string] [ValidateSet('functionapp', 'webapp')]$AppType,
        [Parameter(Mandatory)][string] $ResourceGroupName,
        [Parameter(Mandatory)][string] $ResourceName,
        [Parameter(Mandatory)][string] $AccessRestrictionRuleName,
        [Parameter()][string] $AccessRestrictionRuleDescription,
        [Parameter()][string] $DeploymentSlotName,
        [Parameter()][string] $AccessRestrictionAction = "Allow",
        [Parameter()][string] $Priority = 10,
        [Parameter(ParameterSetName = 'cidr', Mandatory)][ValidatePattern('^$|^(?:(?:\d{1,3}.){3}\d{1,3})(?:\/(?:\d{1,2}))?$', ErrorMessage = "The text '{0}' does not match with the CIDR notation, like '1.2.3.4/32'")][string] $CIDRToWhitelist,
        [Parameter(ParameterSetName = 'subnet', Mandatory)][string] $SubnetName,
        [Parameter(ParameterSetName = 'subnet', Mandatory)][string] $VnetName,
        [Parameter(ParameterSetName = 'subnet', Mandatory)][string] $VnetResourceGroupName,
        [Parameter()][bool] $ApplyToMainEntrypoint = $true,
        [Parameter()][bool] $ApplyToScmEntrypoint = $true
    )

    Write-Header -ScopedPSCmdlet $PSCmdlet

    $optionalParameters = @()
    if ($DeploymentSlotName)
    {
        $optionalParameters += "--slot", "$DeploymentSlotName"
    }

    ### CHECKING AND REMOVING EXISTING RULES
    # SCM entrypoint
    if ($ApplyToScmEntrypoint -and (Confirm-AccessRestriction -AppType $AppType -ResourceGroupName $ResourceGroupName -ResourceName $ResourceName -AccessRestrictionRuleName $AccessRestrictionRuleName -SecurityRestrictionObjectName "scmIpSecurityRestrictions" -DeploymentSlotName $DeploymentSlotName))
    {
        Invoke-Executable az $AppType config access-restriction remove --resource-group $ResourceGroupName --name $ResourceName --rule-name $AccessRestrictionRuleName --scm-site $true @optionalParameters
    }

    # Main entrypoint
    if ($ApplyToMainEntrypoint -and (Confirm-AccessRestriction -AppType $AppType -ResourceGroupName $ResourceGroupName -ResourceName $ResourceName -AccessRestrictionRuleName $AccessRestrictionRuleName -SecurityRestrictionObjectName "ipSecurityRestrictions" -DeploymentSlotName $DeploymentSlotName))
    {
        Invoke-Executable az $AppType config access-restriction remove --resource-group $ResourceGroupName --name $ResourceName --rule-name $AccessRestrictionRuleName --scm-site $false @optionalParameters
    }
    ### END CHECKING AND REMOVING EXISTING RULES
    
    ### ADDING NEW RULES
    if($AccessRestrictionRuleDescription)
    {
        $optionalParameters += "--description", "$AccessRestrictionRuleDescription"
    }

    switch ($PSCmdlet.ParameterSetName) {
        "cidr" {
            $optionalParameters += "--ip-address", "$CIDRToWhitelist"
        }
        "subnet" {
            # Fetch Subnet Resource ID
            $subnetResourceId = (Invoke-Executable az network vnet subnet show --resource-group $VnetResourceGroupName --name $SubnetName --vnet-name $VnetName | ConvertFrom-Json).id
            $scriptArguments += "--subnet", "$subnetResourceId"
        }
    }

    # SCM entrypoint
    if ($ApplyToScmEntrypoint)
    {
        Invoke-Executable az $AppType config access-restriction add --resource-group $ResourceGroupName --name $ResourceName --action $AccessRestrictionAction --priority $Priority --rule-name $AccessRestrictionRuleName --scm-site $true @optionalParameters
    }

    # Main entrypoint
    if ($ApplyToMainEntrypoint)
    {
        Invoke-Executable az $AppType config access-restriction add --resource-group $ResourceGroupName --name $ResourceName --action $AccessRestrictionAction --priority $Priority --rule-name $AccessRestrictionRuleName --scm-site $false @optionalParameters
    }
    ### END ADDING NEW RULES

    Write-Footer -ScopedPSCmdlet $PSCmdlet
}

<#
.SYNOPSIS
    Remove Access restriction from app service and/or function app
.DESCRIPTION
    Remove Access restriction from app service and/or function app
#>
function Remove-AccessRestriction
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string] [ValidateSet('functionapp', 'webapp')]$AppType,
        [Parameter(Mandatory)][string] $ResourceGroupName,
        [Parameter(Mandatory)][string] $ResourceName,
        [Parameter(ParameterSetName = 'rulename', Mandatory)][string] $AccessRestrictionRuleName,
        [Parameter(ParameterSetName = 'cidr', Mandatory)][string] $CIDRToRemove,
        [Parameter(ParameterSetName = 'subnet', Mandatory)][string] $SubnetResourceId,
        [Parameter()][string] $DeploymentSlotName,
        [Parameter()][bool] $ApplyToMainEntrypoint = $true,
        [Parameter()][bool] $ApplyToScmEntrypoint = $true
    )

    Write-Header -ScopedPSCmdlet $PSCmdlet

    $optionalParameters = @()
    if ($DeploymentSlotName)
    {
        $optionalParameters += "--slot", "$DeploymentSlotName"
    }
 
    if($AccessRestrictionRuleName)
    {
        $optionalParameters += "--rule-name", "$AccessRestrictionRuleName"
    }
    elseif ($SubnetResourceId)
    {
        $optionalParameters += "--subnet", "$SubnetResourceId"
    }
    elseif ($CIDRToRemove)
    {
        $optionalParameters += "--ip-address", "$CIDRToRemove"
    }
    else
    {
        throw "Couldnt find IP/Subnet/Accessrule information."
    }

    if($ApplyToScmEntrypoint)
    {
        Invoke-Executable az $AppType config access-restriction remove --resource-group $ResourceGroupName --name $ResourceName --scm-site $true @optionalParameters 
    }
    
    if($ApplyToMainEntrypoint)
    {
        Invoke-Executable az $AppType config access-restriction remove --resource-group $ResourceGroupName --name $ResourceName --scm-site $false @optionalParameters
    }

    Write-Footer -ScopedPSCmdlet $PSCmdlet
}

<#
.SYNOPSIS
    Check if Access restrictions exist on app service and/or function app
.DESCRIPTION
    Check if Access restrictions exist on app service and/or function app
#>

function Confirm-AccessRestriction
{  
    [OutputType([boolean])]
    param (
        [Parameter(Mandatory)][string] [ValidateSet('functionapp', 'webapp')] $AppType,
        [Parameter(Mandatory)][string] $ResourceGroupName,
        [Parameter(Mandatory)][string] $ResourceName,
        [Parameter(ParameterSetName = 'rulename', Mandatory)][string] $AccessRestrictionRuleName,
        [Parameter(ParameterSetName = 'cidr', Mandatory)][string] $CIDR,
        [Parameter(ParameterSetName = 'subnet', Mandatory)][string] $SubnetResourceId,
        [Parameter(Mandatory)][ValidateSet("ipSecurityRestrictions", "scmIpSecurityRestrictions")][string] $SecurityRestrictionObjectName,
        [Parameter()][string] $DeploymentSlotName
    )

    Write-Header -ScopedPSCmdlet $PSCmdlet

    $optionalParameters = @()
    if ($DeploymentSlotName)
    {
        $optionalParameters += "--slot", "$DeploymentSlotName"
    }

    $accessRestrictions = Invoke-Executable az $AppType config access-restriction show --resource-group $ResourceGroupName --name $ResourceName @optionalParameters | ConvertFrom-Json
    if ($accessRestrictions.$SecurityRestrictionObjectName.Name -contains $AccessRestrictionRuleName)
    {
        Write-Host "Access restriction for type $SecurityRestrictionObjectName already exists, continueing"
        Write-Output $true
    }
    else
    {
        Write-Host "Access restriction for type $SecurityRestrictionObjectName does not exist. Creating."
        Write-Output $false
    }

    Write-Footer -ScopedPSCmdlet $PSCmdlet
}

#endregion