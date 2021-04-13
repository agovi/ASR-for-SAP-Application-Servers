# asr4sap
# ASR for SAP Application Servers, ASCS, etc


**requirements:**

* Azure Subscription
* https://shell.azure.com
* PowerShell 7.1 or newer
* PowerShell modules Az

### What the script does

This script can be leveraged to setup ASR for SAP Application Servers, ASCS type VMs
Script can also be used to perform DR test and cleanup 
This PS script require number of parameters and input file can be used for inputting VM list and VM resource group. 
All VMs must reside within same RG
Script capture source VM OS/Data Disks, NIC accelerated settings, AvSet and sets up both test and recovery settings accordingly
Script also creates Recovery Plan
Re-Running of the script typically skips already protected VMs


### Reference documentation 

ASR PS https://docs.microsoft.com/en-us/azure/site-recovery/azure-to-azure-powershell
PS https://docs.microsoft.com/en-us/powershell/module/az.recoveryservices/new-azrecoveryservicesasrrecoveryplan?view=azps-5.6.0





