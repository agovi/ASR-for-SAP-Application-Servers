## ASR initial setup for SAP Application Servers, ASCS, SAPRouters, etc

### Requirements:

* Azure Subscription
* https://shell.azure.com
* PowerShell 7.1 or newer - if you are running it from Visual Code
* PowerShell modules Az - if you are running it from Visual Code

### More about this script
* Leverage ASR-Infra-Setup.ps1 to setup Recovery Vault Infrastructure - One time activity
* This script "ASR-MultiVM-SAP.ps1" has got three functions such as
  * enable
  * test
  * cleanup
* You can run "ASR-MultiVM-SAP.ps1" in one of the three modes, start with enable, test and cleanup. 
* These two PS scripts require number of parameters, part of input file. See Input Parameter section for more details.
* All VMs must reside within same RG.
* Script capture source VM OS/Data Disks, NIC accelerated settings, AvSet and sets up both test and recovery settings accordingly.
* Script also creates a Recovery Plan.
* Re-Running of the script typically skips already protected VMs but you can include new set of VMs that can be protected. Each rerun will update NIC & Recovery plan. 
* VM SKU, OS, Data Disks and AvSet settings are created part of initial run for each VM and rerun does not update after initial run.
* This script can be leveraged to enable ASR on individual SAP system application servers
* This script can be modified to include PPG, AvZones & other features.


### Reference documentation 

[Powershell module for Azure Recovery Services](https://docs.microsoft.com/en-us/powershell/module/az.recoveryservices/new-azrecoveryservicesasrrecoveryplan?view=azps-5.6.0)

[ASR Powershell automation](https://docs.microsoft.com/en-us/azure/site-recovery/azure-to-azure-powershell)

### Preparing Input file

If Recovery Vault Infrastructure is already created then you can leverage [Azure Resource Explorer](https://resources.azure.com/) to locate all required parameters by drill-down to Recovery Services section. 

Fill-out csv file named "asr_input_parameters.csv 

### Input parameter details 
```
Parameter Name              Description 

SubscriptionName            Subscription Name 
region                      Primary Region 
drregion                    DR Region
rv_name                     Recovery Vault Name
rv_rg                       Resource Group of Recovery Vault 
fabric_name                 Primary Region Fabric Name
dr_fabric_name              DR Region Fabric Name 
prot_name                   Primary Region Protection Container Name 
dr_prot_name                DR Region Protection Container Name
a2a_policy                  A2A Replication Policy Name 
a2a_pri_to_dr               A2A Mapping Name 
primary_sa_rg               Primary Region Cache storage account resource group name
primary_sa_acc              Primary Region Cache storage account 
vnet                        Primary Region vnet name 
vnet_rg                     Primary Region vnet resource group name 
drvnet                      DR Region vnet name 
drvnet_test                 DR Region test vnet name 
drsubnet_test               DR Region test subnet name 
drsubnet_primary            DR Region subnet name 
drvnet_rg                   DR vnet resource group name
vmlist                      List of SAP PAS, AAS, ASCS VMs
vm_rg_name                  Resource Group name for the VMs 

```
### Sample Output 

```
ASR-MultiVM-SAP.ps1 .\asr_input_parameters.csv

Importing file content : ..\asr_input_parameters.csv
Source VM Resource Group Name : sapapp2
Following VM will be considered for ASR :
sapapp1
sapapp2
Following recovery plan name will be created or used : sapapp2-recovery-plan
Selecting Subscription : XXX

Name                                     Account                SubscriptionName      Environment           TenantId
----                                     -------                ----------------      -----------           --------
XXX                                       XXX                          XXX              AzureCloud            XXX 
Checking if DR Resource Group : sapapp2-asr exists or create
Resource group sapapp2-asr already exist
Recovery VM Resource Group Name : sapapp2-asr
Recovery Vault Name : rvname-v1
Primary Fabric Name : fabric-v1
Recovery Fabric Name : drfabric-v1
Primary Protection Container Name : container-v1
Recovery Protection Container Name : drcontainer-v1
Mapping between the Primary and Recovery Protection Containers : a2apolicy-v1
Recovery vnet name  : /subscriptions/xxx/resourceGroups/infra-eastus-rg/providers/Microsoft.Network/virtualNetworks/sapvnet-wus2
Primary vnet name  : /subscriptions/xxx/resourceGroups/azsap/providers/Microsoft.Network/virtualNetworks/azsapspoke
Enter one of the options:  enable, test, cleanup, exit to continue: enable
Enabling VM replication, creating or updating Recovery Plan and updating individual VM NIC configuration
Enabling Replication for VM sapapp1
Checking and Creating AvSet based on source VM configuration
Check Recovery Vault -> Site Recovery jobs section for VM sapapp1
ASR Job Status : InProgress
Enabling Replication for VM sapapp2
Checking and Creating AvSet based on source VM 
ASR Job Status : InProgress
Checking for VM Protection progress and takes 15-20 minutes to see % completion progress
Enabling Protection could take minutes to few hours and depends on data volume
Date                ; VM Name        ;  Protection Current State  ;   % Completion
ASR Protected VM:  sapapp1
ASR Protected VM:  sapapp2
Checking if Recovery Plan exists
Deleting existing recovery plan Group and creating the Group again with updated Protected Items
Recovery Plan update job status : Succeeded
Updating NIC for sapapp1
NIC setting update job status : Succeeded for sapapp1
Updating NIC for sapapp2
NIC setting update job status : Succeeded for sapapp2
Check Site Recovery jobs section if all jobs successfully completed
Manually verify Compute and Network Settings in Azure Portal if Configured with Isolated subnet for Test Failover section , before doing DR Test
Login to Azure portal and verify recovery plan and VM network settings are created as expected

```

### SAP on Azure - HA/DR High Level Architecture

![HADR](images/SAP_HADR_Architecture.jpg)