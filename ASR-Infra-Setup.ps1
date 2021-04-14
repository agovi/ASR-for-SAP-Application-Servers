param(
    [Parameter(Mandatory = $true)][string]$ConfigFilePath = ""
)

# Importing File content
Write-Host -ForegroundColor Green ("Importing file content : " + $ConfigFilePath) 
$param_file = Import-CSV $ConfigFilePath            # CSV file with all below parameters supplied as input file

# Setting up Parameters
$SubscriptionName = $param_file.SubscriptionName    # Subscription Name
$region = $param_file.region                        # Primary Region 
$drregion = $param_file.drregion                    # DR Region 
$rv_name = $param_file.rv_name                      # Recovery Vault Name
$rv_rg = $param_file.rv_rg                          # Resource Group of Recovery Vault 
$fabric_name = $param_file.fabric_name              # Primary Region Fabric Name
$dr_fabric_name = $param_file.dr_fabric_name        # DR Region Fabric Name
$prot_name = $param_file.prot_name                  # Primary Region Protection Container Name
$dr_prot_name = $param_file.dr_prot_name            # DR Region Protection Container Name
$a2a_policy = $param_file.a2a_policy                # A2A Replication Policy Name
$a2a_pri_to_dr = $param_file.a2a_pri_to_dr          # A2A Mapping Name

$primary_sa_rg = $param_file.primary_sa_rg          # Primary Region Cache storage account resource group name
$primary_sa_acc = $param_file.primary_sa_acc        # Primary Region Cache storage account

$vnet = $param_file.vnet                            # Primary Region vnet name
$vnet_rg = $param_file.vnet_rg                      # Primary Region vnet resource group name
$drvnet = $param_file.drvnet                        # DR Region vnet name
$drvnet_test = $param_file.drvnet_test              # DR Region test vnet name
$drsubnet_test = $param_file.drsubnet_test          # DR Region test subnet name
$drsubnet_primary = $param_file.drsubnet_primary    # DR Region subnet name
$drvnet_rg = $param_file.drvnet_rg                  # DR vnet resource group name



# select subscription
$Subscription = Get-AzSubscription -SubscriptionName $SubscriptionName -WarningAction SilentlyContinue
if (-Not $Subscription) {
    Write-Host -ForegroundColor Red -BackgroundColor White "Sorry, it seems you are not connected to Azure or don't have access to the subscription. Please use Connect-AzAccount to connect."
    exit
}

Write-Host -ForegroundColor Green -BackgroundColor black ("Selecting Subscription : " + $SubscriptionName)
Select-AzSubscription -Subscription $SubscriptionName -Force -WarningAction SilentlyContinue

######## Create a Recovery Services vault
#Create a resource group for the recovery services vault in the recovery Azure region

Write-Host -ForegroundColor Yellow (("Checking if DR Resource Group : ") + $rv_rg + (" exists or create" ))

$RecoveryRG = AzResourceGroup -Name $rv_rg -ErrorAction SilentlyContinue
if (-Not $RecoveryRG) {
    Write-Host -ForegroundColor green -BackgroundColor black ("Creating resource group " + $rv_rg )
    $RecoveryRG = New-AzResourceGroup -Name $rv_rg -Location $drregion
}
else {
    Write-Host -ForegroundColor green -BackgroundColor black ("Resource group " + $rv_rg + " already exist")
}

#Create a new Recovery services vault in the recovery region
$vault = New-AzRecoveryServicesVault -Name $rv_name -ResourceGroupName $rv_rg -Location $drregion 
$host.ui.RawUI.ForegroundColor = “Green"
Write-Output ("Create Recovery Vault - " + $rv_name)

######## Set the vault context
Set-AzRecoveryServicesAsrVaultContext -Vault $vault

#Create Primary ASR fabric
$TempASRJob = New-AzRecoveryServicesAsrFabric -Azure -Location $region  -Name $fabric_name

# Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        #If the job hasn't completed, sleep for 10 seconds before checking the job status again
        sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
$host.ui.RawUI.ForegroundColor = “Green"
Write-Output ("Create ASR fabric in Primary Region - ASR Job status : " + $TempASRJob.State)

$PrimaryFabric = Get-AzRecoveryServicesAsrFabric -Name $fabric_name

#Create Recovery ASR fabric
$TempASRJob = New-AzRecoveryServicesAsrFabric -Azure -Location $drregion  -Name $dr_fabric_name

# Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output ("Create ASR fabric in DR Region - ASR Job status : " + $TempASRJob.State)

$RecoveryFabric = Get-AzRecoveryServicesAsrFabric -Name $dr_fabric_name

#Create a Protection container in the primary Azure region (within the Primary fabric)
$TempASRJob = New-AzRecoveryServicesAsrProtectionContainer -InputObject $PrimaryFabric -Name $prot_name

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

$host.ui.RawUI.ForegroundColor = “Green"
Write-Output ("Create Protection Container in the Primary Region - ASR Job status: " + $TempASRJob.State)

$PrimaryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $PrimaryFabric -Name $prot_name

#Create a Protection container in the recovery Azure region (within the Recovery fabric)
$TempASRJob = New-AzRecoveryServicesAsrProtectionContainer -InputObject $RecoveryFabric -Name $dr_prot_name

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}
$host.ui.RawUI.ForegroundColor = “Green"
Write-Output ("Create Protection Container in the DR Region - ASR Job status: " + $TempASRJob.State)

$DRProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $RecoveryFabric -Name $dr_prot_name

#Create replication policy
$TempASRJob = New-AzRecoveryServicesAsrPolicy -AzureToAzure -Name $a2a_policy -RecoveryPointRetentionInHours 24 -ApplicationConsistentSnapshotFrequencyInHours 4

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output ( "Create Replication Policy - ASR Job status : "+ $TempASRJob.State)

$ReplicationPolicy = Get-AzRecoveryServicesAsrPolicy -Name $a2a_policy

#Create Protection container mapping between the Primary and Recovery Protection Containers with the Replication policy
$TempASRJob = New-AzRecoveryServicesAsrProtectionContainerMapping -Name $a2a_pri_to_dr -Policy $ReplicationPolicy -PrimaryProtectionContainer $PrimaryProtContainer -RecoveryProtectionContainer $DRProtContainer

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
$host.ui.RawUI.ForegroundColor = “Green"
Write-Output ("Create Protection container mapping between the Primary and Recovery with Replication policy - ASR Job status : " + $TempASRJob.State)

$A2AMapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $PrimaryProtContainer -Name $a2a_pri_to_dr

###########  Create cache storage account and target storage account
#Create Cache storage account for replication logs in the primary region
$PrimaryStorageAccount = New-AzStorageAccount -Name $primary_sa_acc -ResourceGroupName $rv_rg -Location $region -SkuName Standard_LRS -Kind Storage

#Recovery Network in the recovery region

$RecoveryVnet = Get-AzVirtualNetwork -Name $drvnet -ResourceGroupName $drvnet_rg
$RecoveryNetwork = $RecoveryVnet.Id

Write-Host ("Recovery vnet " + $RecoveryNetwork )

#Retrieve the virtual network that the virtual machine is connected to

  # Extract the resource ID of the Azure virtual network the nic is connected to from the subnet ID
  $PrimaryNetwork = Get-AzVirtualNetwork -Name $vnet -ResourceGroupName $vnet_rg
  $PrimaryNetworkID = $PrimaryNetwork.Id
  Write-Host ("Primary vnet " + $RecoveryNetwork )

##############  Create network mapping between the primary virtual network and the recovery virtual network:

  #Create an ASR network mapping between the primary Azure virtual network and the recovery Azure virtual network
  $TempASRJob = New-AzRecoveryServicesAsrNetworkMapping -AzureToAzure -Name "A2ANWMapping" -PrimaryFabric $PrimaryFabric -PrimaryAzureNetworkId $PrimaryNetworkID -RecoveryFabric $RecoveryFabric -RecoveryAzureNetworkId $RecoveryNetwork

  #Track Job status to check for completion
  while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
          sleep 10;
          $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
  }

  #Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
  $host.ui.RawUI.ForegroundColor = “Green"
  Write-Output ("ASR network mapping between the primary Azure virtual network and the recovery Azure virtual network - ASR Job status : " + $TempASRJob.State)
