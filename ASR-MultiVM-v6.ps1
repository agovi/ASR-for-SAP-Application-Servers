# This script can be leveraged to setup ASR for SAP Application Servers, ASCS type VMs
# Script can also be used to perform DR test and cleanup 
# This PS script require number of parameters and input file can be used for inputting VM list and VM resource group. 
# All VMs must reside within same RG
# Script capture source VM OS/Data Disks, NIC accelerated settings, AvSet and sets up both test and recovery settings accordingly
# Script also creates Recovery Plan 
# Re-Running of the script typically skips already protected VMs
# Azure PS documentation can be found on below link
# ASR PS https://docs.microsoft.com/en-us/azure/site-recovery/azure-to-azure-powershell
# PS https://docs.microsoft.com/en-us/powershell/module/az.recoveryservices/new-azrecoveryservicesasrrecoveryplan?view=azps-5.6.0

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


# Setting up Parameters - VM list, VM RG and Recovery Plan
$vm_rg = $param_file.vm_rg_name 
$vm_rg_name = $vm_rg.trim()

$vmlist1 = @()
$vmlist1 = $param_file.vmlist -split ","
$rp_tmp = $vm_rg_name -split "-"
$recovery_plan = $rp_tmp[0] + "-recovery-plan"

write-host -ForegroundColor green -BackgroundColor black ("Source VM Resource Group Name : " + $vm_rg_name )
write-host -ForegroundColor green -BackgroundColor black "Following VM will be considered for ASR : "
$vmlist = @()
foreach ($temp in $vmlist1) {
    if ($temp -eq "") {
        continue
    }

    $vmlist += $temp.trim()
    $temp1 = $temp.trim()
    write-host $temp1

}
Write-Host -ForegroundColor green -BackgroundColor black ("Following recovery plan name will be created or used : " + $recovery_plan)

# select subscription
$Subscription = Get-AzSubscription -SubscriptionName $SubscriptionName -WarningAction SilentlyContinue
if (-Not $Subscription) {
    Write-Host -ForegroundColor Red -BackgroundColor White "Sorry, it seems you are not connected to Azure or don't have access to the subscription. Please use Connect-AzAccount to connect."
    exit
}

Write-Host -ForegroundColor Green -BackgroundColor black ("Selecting Subscription : " + $SubscriptionName)
Select-AzSubscription -Subscription $SubscriptionName -Force -WarningAction SilentlyContinue

#Create a resource group for the recovery services vault in the recovery Azure region
$DRResourceGroup = $vm_rg_name + "-asr"
Write-Host -ForegroundColor green -BackgroundColor black ("Checking if DR Resource Group : " + $DRResourceGroup + " exists or create" )

$RecoveryRG = AzResourceGroup -Name $DRResourceGroup -ErrorAction SilentlyContinue
if (-Not $RecoveryRG) {
    Write-Host -ForegroundColor green -BackgroundColor black ("Creating resource group " + $DRResourceGroup )
    $RecoveryRG = New-AzResourceGroup -Name $DRResourceGroup -Location $drregion
}
else {
    Write-Host -ForegroundColor Yellow -BackgroundColor black ("Resource group " + $DRResourceGroup + " already exist")
}
Write-Host -ForegroundColor green -BackgroundColor black ("Recovery VM Resource Group Name : " + $DRResourceGroup )

######## Set the vault context
#Setting the vault context.
$vault = Get-AzRecoveryServicesVault  -Name $rv_name -ResourceGroupName $rv_rg
$rv_set = Set-AzRecoveryServicesAsrVaultContext -Vault $vault

if (-Not $rv_set) {
    Write-Host -ForegroundColor Red -BackgroundColor White ("Check the Recovery Vault Name " + $rv_name)
    exit
}

Write-Host -ForegroundColor Green -BackgroundColor black ("Recovery Vault Name : " + $vault.Name)

#Get Primary & DR ASR fabric name
$PrimaryFabric = Get-AzRecoveryServicesAsrFabric -Name $fabric_name
$RecoveryFabric = Get-AzRecoveryServicesAsrFabric -Name $dr_fabric_name

if (-Not $PrimaryFabric) {
    Write-Host -ForegroundColor Red -BackgroundColor Yellow ("Check the Primary Fabric Name " + $fabric_name)
    exit
}

if (-Not $RecoveryFabric) {
    Write-Host -ForegroundColor Red -BackgroundColor Yellow ("Check the Recovery Fabric Name " + $dr_fabric_name)
    exit
}

Write-Host -ForegroundColor Green -BackgroundColor black ("Primary Fabric Name : " + $PrimaryFabric.Name)
Write-Host -ForegroundColor Green -BackgroundColor black ("Recovery Fabric Name : " + $RecoveryFabric.Name)

######## Get a Site Recovery protection container in the primary & dr fabric
$PrimaryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $PrimaryFabric -Name $prot_name
$DRProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $RecoveryFabric -Name $dr_prot_name

if (-Not $PrimaryProtContainer) {
    Write-Host -ForegroundColor Red -BackgroundColor Yellow ("Check the Primary Protection Container Name " + $prot_name)
    exit
}

if (-Not $DRProtContainer) {
    Write-Host -ForegroundColor Red -BackgroundColor Yellow ("Check the DR Protection Container Name " + $dr_prot_name)
    exit
}

Write-Host -ForegroundColor Green  -BackgroundColor black ("Primary Protection Container Name : " + $PrimaryProtContainer.FriendlyName)
Write-Host -ForegroundColor Green  -BackgroundColor black ("Recovery Protection Container Name : " + $DRProtContainer.FriendlyName)


#Get replication policy
$ReplicationPolicy = Get-AzRecoveryServicesAsrPolicy -Name $a2a_policy

if (-Not $ReplicationPolicy) {
    Write-Host -ForegroundColor Red -BackgroundColor Yellow ("Check the A2A Replication Policy Name " + $a2a_policy)
    exit
}

#Get Protection container mapping between the Primary and Recovery Protection Containers with the Replication policy
$A2AMapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $PrimaryProtContainer -Name $a2a_pri_to_dr

if (-Not $A2AMapping) {
    Write-Host -ForegroundColor Red -BackgroundColor Yellow ("Check the A2A Mapping Name " + $a2a_pri_to_dr)
    exit
}

Write-Host -ForegroundColor Green -BackgroundColor black ("Mapping between the Primary and Recovery Protection Containers : " + $A2AMapping.PolicyFriendlyName)

#Get a storage cache account 
$PrimaryStorageAccount = Get-AzStorageAccount -Name $primary_sa_acc -ResourceGroupName $primary_sa_rg

if (-Not $PrimaryStorageAccount) {
    Write-Host -ForegroundColor Red -BackgroundColor Yellow (("Check the cache storage account/rg ") + $primary_sa_acc )
    exit
}

#Recovery Network in the recovery region
$RecoveryVnet = Get-AzVirtualNetwork -Name $drvnet -ResourceGroupName $drvnet_rg
$RecoveryNetwork = $RecoveryVnet.Id

if (-Not $RecoveryVnet) {
    Write-Host -ForegroundColor Red ("Recovery vnet name is missing: " + $RecoveryNetwork)
    exit
}
Write-Host -ForegroundColor Green -BackgroundColor black ("Recovery vnet name  : " + $RecoveryNetwork)

# Recovery Network in the recovery region
$PrimaryVnet = Get-AzVirtualNetwork -Name $vnet -ResourceGroupName $vnet_rg
$PrimaryNetwork = $PrimaryVnet.Id

if (-Not $PrimaryNetwork) {
    Write-Host -ForegroundColor Red ("Primary vnet name is missing: " + $PrimaryNetwork)
    exit
}
Write-Host -ForegroundColor Green -BackgroundColor black ("Primary vnet name  : " + $PrimaryNetwork)

function enable-replication {

    # Get details of the virtual machine
    foreach ($vmtmp in $vmlist) {
        $VM = Get-AzVM -ResourceGroupName $vm_rg_name -Name $vmtmp
        Write-Host -ForegroundColor Yellow -BackgroundColor black ("Enabling Replication for VM " + $vmtmp)

        #Getting source OsDisk
        $OSdiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id

        $OSDiskReplicationConfig = New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -ManagedDisk -LogStorageAccountId $PrimaryStorageAccount.Id `
            -DiskId $OSdiskId -RecoveryResourceGroupId  $RecoveryRG.ResourceId  -RecoveryReplicaDiskAccountType  "Premium_LRS" `
            -RecoveryTargetDiskAccountType "Premium_LRS"

        # Getting list of source Data disk
        $diskconfigs = @()
        $diskconfigs += $OSDiskReplicationConfig
        foreach ($DataDisk in $vm.StorageProfile.DataDisks) {
            $datadiskId = $DataDisk.ManagedDisk.Id
            $DataDisk1ReplicationConfig = New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -ManagedDisk -LogStorageAccountId $PrimaryStorageAccount.Id `
                -DiskId $datadiskId -RecoveryResourceGroupId $RecoveryRG.ResourceId -RecoveryReplicaDiskAccountType "Premium_LRS" `
                -RecoveryTargetDiskAccountType "Premium_LRS"
            $diskconfigs += $DataDisk1ReplicationConfig
        }
        # Getting source avset and based on that it sets up the target avset setting
        write-host -ForegroundColor Yellow -BackgroundColor black ("Checking and Creating AvSet based on source VM configuration")
        $avset = $VM.AvailabilitySetReference.Id
        #        Clear-Variable -name aslid
        if ($avset -ne $null) {
            $avset1 = $avset -split "/"
            $RecoveryAvSet = ($avset1[-1] + "-asr")
            $aslid = ""
            $RecAvset = Get-AzAvailabilitySet -ResourceGroupName $DRResourceGroup -Name $RecoveryAvSet -ErrorAction SilentlyContinue
            if (-Not $RecAvset) {
                Write-Host -ForegroundColor green -BackgroundColor black ("Creating recovery avset " + $RecoveryAvSet )
                $as1 = New-AzAvailabilitySet -ResourceGroupName $DRResourceGroup -Name $RecoveryAvSet -Location $drregion -sku "Aligned" -PlatformUpdateDomainCount 5 -PlatformFaultDomainCount 2
                $aslid = $as1.Id
            }
            else {
                $aslid = $RecAvset.Id
                Write-Host -ForegroundColor green -BackgroundColor black ("Recovery AvSet " + $RecoveryAvSet + " already exist")
            }
            
            #Start replication by creating replication protected item. Using a GUID for the name of the replication protected item to ensure uniqueness of name.
            # this block used if avset exists on source VM
            $TempASRJob = New-AzRecoveryServicesAsrReplicationProtectedItem -AzureToAzure -AzureVmId $VM.Id -Name (New-Guid).Guid `
                -ProtectionContainerMapping $A2AMapping -AzureToAzureDiskReplicationConfiguration $diskconfigs `
                -RecoveryResourceGroupId $RecoveryRG.ResourceId -RecoveryAvailabilitySetId $aslid 
            Write-Host -ForegroundColor Yellow -BackgroundColor black ("Check Recovery Vault -> Site Recovery jobs section for VM " + $vmtmp)
            Write-Host -ForegroundColor Yellow -BackgroundColor black ("ASR Job Status : " + $TempASRJob.state)
  
        }
        else {
            #Start replication by creating replication protected item. Using a GUID for the name of the replication protected item to ensure uniqueness of name.
            # this block used if no avset on source VM
            $TempASRJob = New-AzRecoveryServicesAsrReplicationProtectedItem -AzureToAzure -AzureVmId $VM.Id -Name (New-Guid).Guid `
                -ProtectionContainerMapping $A2AMapping -AzureToAzureDiskReplicationConfiguration $diskconfigs `
                -RecoveryResourceGroupId $RecoveryRG.ResourceId 
            Write-Host -ForegroundColor Yellow -BackgroundColor black ("Check Recovery Vault -> Site Recovery jobs section for VM ") -NoNewline; Write-Host -ForegroundColor White ($vmtmp)
            Write-Host -ForegroundColor Yellow -BackgroundColor black ("ASR Job Status : " + $TempASRJob.state)
        }
    }

    # Introducing 10 seconds delay for above jobs to start
    sleep 30

    Write-Host -ForegroundColor White -BackgroundColor black "Checking for VM Protection progress and takes 15-20 minutes to see % completion progress"
    Write-Host -ForegroundColor White -BackgroundColor black "Enabling Protection could take minutes to few hours and depends on data volume"
    Write-Host -ForegroundColor Yellow -BackgroundColor black ("Date                ; VM Name        ;  Protection Current State  ;   % Completion " )
    $alldone = "false"
    while ($alldone -ne "true") {
        $icount = 0
        foreach ($vmtmp in $vmlist) {
            $t1 = Get-AzRecoveryServicesAsrReplicationProtectedItem -FriendlyName $vmtmp -ProtectionContainer $PrimaryProtContainer
            $progress = $t1[0].ProviderSpecificDetails.MonitoringPercentageCompletion
            $test_date = Get-Date

            if ($t1.ProtectionState -eq "EnablingFailed") {
                Write-Host -ForegroundColor Red ("Enabling Failed and check ASR Job in Azure Portal for the details")
                exit
            }
            elseif ($t1.ProtectionState -ne "Protected") {
                Write-Host -ForegroundColor Yellow -BackgroundColor black ("" + $test_date + " ; " + $vmtmp + " ;  " + $t1.ProtectionStateDescription + " ; " + $progress )
                sleep 30; 
            }
            if ( $t1.ProtectionState -eq "Protected" ) {
                $icount += 1
                write-host -ForegroundColor green -BackgroundColor black ("ASR Protected VM:  " + $vmtmp )
            }  
        }
        if ($icount -eq $vmlist.Length) {
            $alldone = "true"
        }
    }

    # Create the array of Protected Item
    $ReplicationProtectedItem = @()
    foreach ($vmtmp in $vmlist) {
        $ReplicationProtectedItem += Get-AzRecoveryServicesAsrReplicationProtectedItem -FriendlyName $vmtmp -ProtectionContainer $PrimaryProtContainer
    }


    # Creating or Updating Recovery Plan
    Write-Host -ForegroundColor Yellow -BackgroundColor black "Checking if Recovery Plan exists"
    $RP1 = Get-AzRecoveryServicesAsrRecoveryPlan -Name $recovery_plan -ErrorAction Ignore
    if (-Not (Get-AzRecoveryServicesAsrRecoveryPlan -Name $recovery_plan -ErrorAction Ignore)) {
        Write-Host -ForegroundColor Yellow -BackgroundColor black ("Creating Recovery Plan " + $recovery_plan )
        $TempASRJob = New-AzRecoveryServicesAsrRecoveryPlan -Name $recovery_plan -PrimaryFabric $PrimaryFabric -RecoveryFabric $RecoveryFabric -ReplicationProtectedItem $ReplicationProtectedItem
        #Track Job status to check for completion
        while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")) {
            sleep 10;
            $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
        }
        #Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
        # $host.ui.RawUI.ForegroundColor = “Yellow"
        Write-Output ("Recovery Plan create job status : " + $TempASRJob.State)
    }
    else {
        Write-Host -ForegroundColor Yellow -BackgroundColor black "Deleting existing recovery plan Group and creating the Group again with updated Protected Items"
        $RP = Get-AzRecoveryServicesAsrRecoveryPlan -Name $recovery_plan
        # setting empty string to existing group and adding protected item based on new list
        $emptyList = New-Object System.Collections.Generic.List[Microsoft.Azure.Commands.RecoveryServices.SiteRecovery.ASRReplicationProtectedItem]
        $RP.Groups[2].ReplicationProtectedItems = $emptyList
        $RP_Edit = Edit-AzRecoveryServicesAsrRecoveryPlan -AddProtectedItem $ReplicationProtectedItem -Group $RP.Groups[2] -RecoveryPlan $RP
        $TempASRJob = Update-AzRecoveryServicesAsrRecoveryPlan -RecoveryPlan $RP

        #Track Job status to check for completion
        while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")) {
            sleep 10;
            $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
        }
        #Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
        Write-Output ("Recovery Plan update job status : " + $TempASRJob.State)
    }

    # Updating vnet and subnet of DR test & recovery network
    foreach ($i in $ReplicationProtectedItem) {
        $AsrNicGuid = $i.NicDetailsList.NicId
        $vmnic = Get-AzVM -Name $i.FriendlyName -ResourceGroupName $vm_rg_name
        $getnic = Get-AzNetworkInterface -ResourceId $vmnic.NetworkProfile.NetworkInterfaces.Id
        $accsetting = $getnic.EnableAcceleratedNetworking
        Write-Host -ForegroundColor Yellow -BackgroundColor black ("Updating NIC for " + $i.FriendlyName )
        if ( $accsetting -eq "True") {
            $nicconfig = New-AzRecoveryServicesAsrVMNicConfig -NicId $AsrNicGuid -ReplicationProtectedItem $i -RecoveryVMNetworkId $RecoveryNetwork `
                -RecoveryVMSubnetName $drsubnet_primary -RecoveryNicStaticIPAddress "" -TfoVMNetworkId $RecoveryNetwork `
                -TfoVMSubnetName $drsubnet_test -TfoNicStaticIPAddress "" `
                -EnableAcceleratedNetworkingOnRecovery -EnableAcceleratedNetworkingOnTfo 
            $TempASRJob = Set-AzRecoveryServicesAsrReplicationProtectedItem -ReplicationProtectedItem $i -ASRVMNicConfiguration $nicconfig 

            #Track Job status to check for completion
            while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")) {
                sleep 10;
                $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
            }

            #Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
            Write-Output ("NIC setting update job status : " + $TempASRJob.State + " for " + $i.FriendlyName)
        }
        else {
            $nicconfig = New-AzRecoveryServicesAsrVMNicConfig -NicId $AsrNicGuid -ReplicationProtectedItem $i -RecoveryVMNetworkId $RecoveryNetwork `
                -RecoveryVMSubnetName $drsubnet_primary -RecoveryNicStaticIPAddress "" -TfoVMNetworkId $RecoveryNetwork `
                -TfoVMSubnetName $drsubnet_test -TfoNicStaticIPAddress "" 
            $TempASRJob = Set-AzRecoveryServicesAsrReplicationProtectedItem -ReplicationProtectedItem $i -ASRVMNicConfiguration $nicconfig 
            #Track Job status to check for completion
            while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")) {
                sleep 10;
                $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
            }
            #Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
            Write-Output ("NIC setting update job status : " + $TempASRJob.State + " for " + $i.FriendlyName)
        }
    }
    Write-Host -ForegroundColor Yellow -BackgroundColor black ("Check Site Recovery jobs section if all jobs successfully completed" )
    Write-Host -ForegroundColor Red -BackgroundColor Yellow ("Manually verify Compute and Network Settings in Azure Portal if Configured with Isolated subnet for Test Failover section , before doing DR Test" )
}
function dr-test { 
   
    # Create the array of Protected Item
    $ReplicationProtectedItem = @()
    foreach ($vmtmp in $vmlist) {
        $ReplicationProtectedItem += Get-AzRecoveryServicesAsrReplicationProtectedItem -FriendlyName $vmtmp -ProtectionContainer $PrimaryProtContainer
    }

    # Display Recovery Plan, VM & NIC settings that will be deployed part of DR test
    Write-Host -ForegroundColor White -BackgroundColor black ("Following VM, vnet and subnet will be used for DR Test that are part of Recovery Plan : ") -NoNewline; Write-Host -ForegroundColor Yellow ($recovery_plan)
    foreach ($prot in $ReplicationProtectedItem) {
        write-host -ForegroundColor White -BackgroundColor black ("Test VM Name : ") -NoNewline; Write-Host -ForegroundColor Yellow ($prot.RecoveryAzureVMName + "-test")
        $tvnet = $prot.NicDetailsList.TfoVMNetworkId -split "/" 
        write-host -ForegroundColor White -BackgroundColor black ("vnet : ")  -NoNewline; Write-Host -ForegroundColor Yellow ($tvnet[-1])
        write-host -ForegroundColor White -BackgroundColor black ("subnet : ") -NoNewline; Write-Host -ForegroundColor Yellow $prot.NicDetailsList.TfoVMSubnetName 
        Write-host " "
    }
    
    # Final confirmation and then DR test triggered 
    $drtest = Read-Host -Prompt "Manually verify Compute and Network Settings in Azure Portal if it points to Isolated subnet for Failover Network, before entering continue or exit" 
    if ($drtest -eq 'continue' ) {
        Write-Host -ForegroundColor green -BackgroundColor black ("DR test is in progress" )
        Write-Host -ForegroundColor Yellow -BackgroundColor black ("Login to azure portal and check if VMs are being deployed inside Isolated Subnet")
        $RP1 = Get-AzRecoveryServicesAsrRecoveryPlan -Name $recovery_plan
        $TempASRJob = Start-AzRecoveryServicesAsrTestFailoverJob -AzureVMNetworkId $RecoveryNetwork -Direction PrimaryToRecovery -RecoveryPlan $RP1
        #Track Job status to check for completion
        while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")) {
            $test_date = Get-Date
            $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
            Write-Host (" ASR test jobs status : " + $TempASRJob.state + " - " + $test_date )
            sleep 20;
        }
        if ($TempASRJob.State -eq "Failed") {
            Write-host -ForegroundColor Red  -BackgroundColor Yellow ("ASR test job failed. Check portal for more information")
            exit
        }
        Write-Host -ForegroundColor Yellow -BackgroundColor black ("Verify one more time if VMs are deployed inside Isolated Subnet before continue with DR test activities" )
    }
    else {
        exit
    }
}

function dr-test-cleanup {
    # Test Failover Cleanup
    $RP = Get-AzRecoveryServicesAsrRecoveryPlan -Name $recovery_plan
    Write-Host -ForegroundColor Yellow -BackgroundColor black ("DR test resources cleanup in progress for Recovery Plan : " + $recovery_plan )
    $test_date = Get-Date
    $Job_TFOCleanup = Start-AzRecoveryServicesAsrTestFailoverCleanupJob -RecoveryPlan $RP -Comment ("Testing Done on " + $test_date)
    while (($Job_TFOCleanup.State -eq "InProgress") -or ($Job_TFOCleanup.State -eq "NotStarted")) {
        sleep 30;
        $test_date1 = Get-Date
        $Job_TFOCleanup = Get-AzRecoveryServicesAsrJob -Job $Job_TFOCleanup
        Write-Host (" ASR cleanup job state and description : " + $Job_TFOCleanup.state + " ; " + $Job_TFOCleanup.StateDescription + " - " + $test_date1)
        Write-Host -ForegroundColor green -BackgroundColor black ("Check ASR job section for job status and VM deletion progress" )
    }
    if ($Job_TFOCleanup.State -eq "Failed") {
        Write-host -ForegroundColor Red -BackgroundColor Yellow ("ASR cleanup job failed. Check portal for more information")
        exit
    }

}

# Main code block 

$setup = Read-Host -Prompt "Enter one of the options:  enable, test, cleanup, exit to continue"
if ($setup -eq 'enable' ) {
    Write-Host -ForegroundColor green -BackgroundColor black ("Enabling VM replication, creating or updating Recovery Plan and updating individual VM NIC configuration" ) 
    enable-replication
    Write-Host -ForegroundColor Yellow -BackgroundColor black ("Login to Azure portal and verify recovery plan and VM network settings are created as expected")
}
elseif ($setup -eq 'test') { 
    dr-test
}
elseif ($setup -eq 'cleanup') {
    dr-test-cleanup
}
else {
    exit
}
