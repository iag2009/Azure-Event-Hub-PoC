# Azure Event Hub PoC

![alt tag](https://raw.githubusercontent.com/shaneochotny/Azure-Synapse-Analytics-PoC\/main/Images/Synapse-Analytics-PoC-Architecture.gif)

# Description

Create an Event Hub environment based on best practices to achieve a successful proof of concept. 

# How to Run

### "Easy Button" Deployment
The following commands should be executed from the Azure Cloud Shell at https://shell.azure.com using bash:
```
@Azure:~$ git clone https://github.com/iag2009/Azure-Event-Hub-PoC
@Azure:~$ cd Azure-Event-Hub-PoC
@Azure:~$ bash deployEventHub.sh
```

### Advanced Deployment: Terraform
You can manually configure the Terraform parameters and update default settings such as the Azure region, database name, credentials, and private endpoint integration. The following commands should be executed from the Azure Cloud Shell at https://shell.azure.com using bash:
```
@Azure:~$ git clone https://github.com/iag2009/Azure-Event-Hub-PoC
@Azure:~$ cd Azure-Event-Hub-PoC
@Azure:~$ code Terraform/terraform.tfvars
@Azure:~$ terraform -chdir=Terraform init
@Azure:~$ terraform -chdir=Terraform plan
@Azure:~$ terraform -chdir=Terraform apply
@Azure:~$ bash deployEventHub.sh 
```

# What's Deployed

### Azure Event Hub Namespace
- <b>eventhub-test-120723</b> - container that provides logical separation and management of multiple Event Hubs in Azure subscription.

### Azure Event Hub
- <b>apphub</b> - a managed event streaming service in the Microsoft Azure cloud.

# What's Configured
- Enable Result Set Caching
- Create a pipeline to auto pause/resume the Dedicated SQL Pool
- Feature flag to enable/disable Private Endpoints
- Serverless SQL Demo Data Database
- Proper service and user permissions for Azure Synapse Analytics Workspace and Azure Data Lake Storage Gen2
- Parquet Auto Ingestion pipeline to optimize data ingestion using best practices

# To Do
- Example script for configuring Row Level Security
- Example script for configuring Dynamic Data Masking
