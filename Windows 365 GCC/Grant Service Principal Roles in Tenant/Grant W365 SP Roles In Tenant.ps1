param ($subscriptionid, $selectedRg, $selectedVnetRg, $selectedVnet)
#New-MgRoleManagementDirectoryRoleAssignment

#---------------Login to your Azure government cloud tenant -----------------------------------------
try
{
    # If using Azure Cloud Powershell, comment out below command.
    Connect-AzAccount -Environment AzureUSGovernment -ErrorAction Stop
} 
catch [System.Management.Automation.CommandNotFoundException] 
{
    Write-Output "Please ensure az module installed first. You can run 'Install-Module -Name Az -Scope CurrentUser -AllowClobber  -Repository PSGallery -Force' to install the module"
    Write-Output "For more details, you can refer: https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-7.2.0#installation"
    return
}
catch
{
    Write-Output $PSItem.ToString()
    return
}

#--------------- Check if Windows 365 application has been provisioned into the Azure government cloud tenant, if not, consent it into the tenant.-----------------------
$Windows365AppId = "0af06dc6-e4b5-4f28-818e-e78e62d137a5"
$ServicePrincipal= Get-AzADServicePrincipal -ApplicationId $Windows365AppId -ErrorAction Stop
if([String]::IsNullOrEmpty($ServicePrincipal.Id))
{
    try
    {
        # Consent Windows 365 application into this Azure government cloud tenant.
        New-AzADServicePrincipal -ApplicationId $Windows365AppId -ErrorAction Stop
        $ServicePrincipal = Get-AzADServicePrincipal -ApplicationId $Windows365AppId -ErrorAction Stop
        Write-Output "`r`nConsent Windows 365 application into your tenant. Object Id: $($ServicePrincipal.Id)"
    }
    catch
    {
        Write-Output "Failed to consent Windows 365 application into your tenant,error: $PSItem"
        If($PSItem.ToString().contains("Insufficient privileges to complete the operation"))
        {
            Write-Output "Contact your Azure Active Directory admin to create a service principal for app id $Windows365AppId"
        }
    }
 }
 Write-Output "`r`nWindows 365 application has been provisioned into your Azure government cloud successfully. The Windows 365 service principal id:$($ServicePrincipal.Id)."


 #-------------- Select subscripion, resource group, virtual network, and add role assignments to Windows 365 service principal so that it can access your resources----------------
 # Define function to check if Role has been assigned to our service principal in the scope, if no, add the role.
function CheckAndAddRoleAssignmentToServicePrincipal() {
    param (
        [string] $RoleName,
        [string] $Scope,
        [string] $ServicePrincipalId
    )

    try
    {
       #Check RoleAssignment
       $azureRole = Get-AzRoleDefinition -Name $RoleName -ErrorAction Stop
       $restResponse = Invoke-AzRestMethod -Path "$Scope/providers/Microsoft.Authorization/roleAssignments?`$filter=atScope() and assignedTo('$ServicePrincipalId')&api-version=2020-03-01-preview" -Method GET -ErrorAction Stop
       $IsAssigned = $restResponse.Content.contains($azureRole.Id)
       if($IsAssigned -eq $true)
       {
            Write-Output "$RoleName has already been assigned to $Scope."
       }
       else
       {

           $result = New-AzRoleAssignment `
           -ObjectId $ServicePrincipalId `
            -RoleDefinitionName $RoleName `
            -Scope $Scope `
            -ErrorAction Stop
           Write-Output "$RoleName was assigned to $Scope successfully."
       }
    }
    catch
    {
        Write-Output $PSItem.ToString()
        If($PSItem.ToString().contains("Forbidden"))
        {
            Write-Output "Add role $RoleName to $Scope failed, please make sure the sign in user has owner or user access admin role in the subscription"
        }
    }
}
    # Check if role exists, if not exist, add the role to our service principal in the target scope
    CheckAndAddRoleAssignmentToServicePrincipal -RoleName "Reader" -Scope "/subscriptions/$SubscriptionId" -ServicePrincipalId $ServicePrincipal.Id
    CheckAndAddRoleAssignmentToServicePrincipal -RoleName "Network contributor" -Scope "/subscriptions/$subscriptionid/resourcegroups/$selectedRg" -ServicePrincipalId $ServicePrincipal.Id
    CheckAndAddRoleAssignmentToServicePrincipal -RoleName "Network contributor" -Scope "/subscriptions/$subscriptionid/resourcegroups/$selectedVnetRg/providers/Microsoft.Network/virtualNetworks/$selectedvnet" -ServicePrincipalId $ServicePrincipal.Id

    
