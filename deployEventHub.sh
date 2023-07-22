#!/bin/bash
#
# This script is in two parts; Event Hub Environment Deployment and Post-Deployment Configuration.
#
#   Part 1: Event Hub Environment Deployment
#
#       This is simply validation that the Terraform deployment was completed before executing the post-deployment 
#       configuration.
#
#   Part 2: Post-Deployment Configuration
#
#       These are post-deployment configurations done at the data plan level which is beyond the scope of what Terraform
#       are capable of managing or would normally manage. Database settings are made, sample data is ingested, and 
#       pipelines are created for the PoC.
#
#   This script should be executed via the Azure Cloud Shell via:
#
#       @Azure:~/Azure-Event Hub-Analytics-PoC$ bash deployEventHub.sh
#
# Todo:
#    - Bicep deployment


#
# Part 1: Event Hub Environment Deployment
#

# Make sure this configuration script hasn't been executed already
if [ -f "deployEvent Hub.complete" ]; then
    echo "ERROR: It appears this configuration has already been completed." | tee -a deployEvent Hub.log
    exit 1;
fi

# Try and determine if we're executing from within the Azure Cloud Shell
if [ ! "${AZUREPS_HOST_ENVIRONMENT}" = "cloud-shell/1.0" ]; then
    echo "ERROR: It doesn't appear like your executing this from the Azure Cloud Shell. Please use the Azure Cloud Shell at https://shell.azure.com" | tee -a deployEvent Hub.log
    exit 1;
fi

aadToken=$(az account get-access-token --resource=https://eventhubs.azure.net/ --query accessToken --output tsv 2>&1)
if echo "$aadToken" | grep -q "ERROR"; then
    echo "ERROR: You don't appear to be logged in to Azure CLI. Please login to the Azure CLI using 'az login'" | tee -a deployEventHub.log
    exit 1;
fi

# The token has been successfully received, now you can use it to access the Event Hubs
echo "Successfully logged in to Azure CLI and obtained an access token for Azure Event Hubs."

# Get environment details
azureSubscriptionName=$(az account show --query name --output tsv 2>&1)
azureSubscriptionID=$(az account show --query id --output tsv 2>&1)
azureUsername=$(az account show --query user.name --output tsv 2>&1)
# azureUsernameObjectId=$(az ad user show --id $azureUsername --query objectId --output tsv 2>&1)

# Update a few Terraform variables if they aren't configured by the user
# sed -i "s/REPLACE_Event Hub_AZURE_AD_ADMIN_UPN/${azureUsername}/g" Terraform/terraform.tfvars

        deploymentType="terraform"
        echo "Deploying Event Hub environment. This will take several minutes..." | tee -a deployEventHub.log

        # Terraform init and validation
        echo "Executing 'terraform -chdir=Terraform init'"
        terraformInit=$(terraform -chdir=Terraform init 2>&1)
        if ! echo "$terraformInit" | grep -q "Terraform has been successfully initialized!"; then
            echo "ERROR: Failed to perform 'terraform -chdir=Terraform init'" | tee -a deployEvent Hub.log
            exit 1;
        fi

        # Terraform plan and validation
        echo "Executing 'terraform -chdir=Terraform plan'"
        terraformPlan=$(terraform -chdir=Terraform plan)
        if echo "$terraformPlan" | grep -q "Error:"; then
            echo "ERROR: Failed to perform 'terraform -chdir=Terraform plan'" | tee -a deployEvent Hub.log
            exit 1;
        fi

        # Terraform apply and validation
        echo "Executing 'terraform -chdir=Terraform apply'"
        terraformApply=$(terraform -chdir=Terraform apply -auto-approve)
        if echo "$terraformApply" | grep -q "Apply complete!"; then
            deploymentType="terraform"
        else
            echo "ERROR: Failed to perform 'terraform -chdir=Terraform apply'" | tee -a deployEvent Hub.log
            exit 1;
        fi

#
# Part 2: Post-Deployment Configuration
#

# Get the output variables from the Terraform deployment
if [ "$deploymentType" == "terraform" ]; then
    resourceGroup=$(terraform output -state=Terraform/terraform.tfstate -raw Event Hub_analytics_workspace_resource_group 2>&1)
    Event HubAnalyticsWorkspaceName=$(terraform output -state=Terraform/terraform.tfstate -raw Event Hub_analytics_workspace_name 2>&1)
    Event HubAnalyticsSQLPoolName=$(terraform output -state=Terraform/terraform.tfstate -raw Event Hub_sql_pool_name 2>&1)
    Event HubAnalyticsSQLAdmin=$(terraform output -state=Terraform/terraform.tfstate -raw Event Hub_sql_administrator_login 2>&1)
    Event HubAnalyticsSQLAdminPassword=$(terraform output -state=Terraform/terraform.tfstate -raw Event Hub_sql_administrator_login_password 2>&1)
    datalakeName=$(terraform output -state=Terraform/terraform.tfstate -raw datalake_name 2>&1)
    datalakeKey=$(terraform output -state=Terraform/terraform.tfstate -raw datalake_key 2>&1)
    privateEndpointsEnabled=$(terraform output -state=Terraform/terraform.tfstate -raw private_endpoints_enabled 2>&1)
fi

echo "Deployment Type: ${deploymentType}" | tee -a deployEvent Hub.log
echo "Azure Subscription: ${azureSubscriptionName}" | tee -a deployEvent Hub.log
echo "Azure Subscription ID: ${azureSubscriptionID}" | tee -a deployEvent Hub.log
echo "Azure AD Username: ${azureUsername}" | tee -a deployEvent Hub.log
echo "Event Hub Analytics Workspace Resource Group: ${resourceGroup}" | tee -a deployEvent Hub.log
echo "Event Hub Analytics Workspace: ${Event HubAnalyticsWorkspaceName}" | tee -a deployEvent Hub.log
echo "Event Hub Analytics SQL Admin: ${Event HubAnalyticsSQLAdmin}" | tee -a deployEvent Hub.log
echo "Data Lake Name: ${datalakeName}" | tee -a deployEvent Hub.log

# If Private Endpoints are enabled, temporarily disable the firewalls so we can copy files and perform additional configuration
if [ "$privateEndpointsEnabled" == "true" ]; then
    az storage account update --name ${datalakeName} --resource-group ${resourceGroup} --default-action Allow >> deployEvent Hub.log 2>&1
    az Event Hub workspace firewall-rule create --name AllowAll --resource-group ${resourceGroup} --workspace-name ${Event HubAnalyticsWorkspaceName} --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255 >> deployEvent Hub.log 2>&1
    az Event Hub workspace firewall-rule create --name AllowAllWindowsAzureIps --resource-group ${resourceGroup} --workspace-name ${Event HubAnalyticsWorkspaceName} --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 >> deployEvent Hub.log 2>&1
fi

# Enable Result Set Cache
echo "Enabling Result Set Caching..." | tee -a deployEvent Hub.log
sqlcmd -U ${Event HubAnalyticsSQLAdmin} -P ${Event HubAnalyticsSQLAdminPassword} -S tcp:${Event HubAnalyticsWorkspaceName}.sql.azureEvent Hub.net -d master -I -Q "ALTER DATABASE ${Event HubAnalyticsSQLPoolName} SET RESULT_SET_CACHING ON;" >> deployEvent Hub.log 2>&1

# Enable the Query Store
echo "Enabling the Query Store..." | tee -a deployEvent Hub.log
sqlcmd -U ${Event HubAnalyticsSQLAdmin} -P ${Event HubAnalyticsSQLAdminPassword} -S tcp:${Event HubAnalyticsWorkspaceName}.sql.azureEvent Hub.net -d ${Event HubAnalyticsSQLPoolName} -I -Q "ALTER DATABASE ${Event HubAnalyticsSQLPoolName} SET QUERY_STORE = ON;" >> deployEvent Hub.log 2>&1

echo "Creating the Auto Pause and Resume pipeline..." | tee -a deployEvent Hub.log

# Copy the Auto_Pause_and_Resume Pipeline template and update the variables
cp artifacts/Auto_Pause_and_Resume.json.tmpl artifacts/Auto_Pause_and_Resume.json 2>&1
sed -i "s/REPLACE_SUBSCRIPTION/${azureSubscriptionID}/g" artifacts/Auto_Pause_and_Resume.json
sed -i "s/REPLACE_RESOURCE_GROUP/${resourceGroup}/g" artifacts/Auto_Pause_and_Resume.json
sed -i "s/REPLACE_Event Hub_ANALYTICS_WORKSPACE_NAME/${Event HubAnalyticsWorkspaceName}/g" artifacts/Auto_Pause_and_Resume.json
sed -i "s/REPLACE_Event Hub_ANALYTICS_SQL_POOL_NAME/${Event HubAnalyticsSQLPoolName}/g" artifacts/Auto_Pause_and_Resume.json

# Create the Auto_Pause_and_Resume Pipeline in the Event Hub Analytics Workspace
az Event Hub pipeline create --only-show-errors -o none --workspace-name ${Event HubAnalyticsWorkspaceName} --name "Auto Pause and Resume" --file @artifacts/Auto_Pause_and_Resume.json

# Create the Pause/Resume triggers in the Event Hub Analytics Workspace
az Event Hub trigger create --only-show-errors -o none --workspace-name ${Event HubAnalyticsWorkspaceName} --name Pause --file @artifacts/triggerPause.json
az Event Hub trigger create --only-show-errors -o none --workspace-name ${Event HubAnalyticsWorkspaceName} --name Resume --file @artifacts/triggerResume.json

echo "Creating the Parquet Auto Ingestion pipeline..." | tee -a deployEvent Hub.log

# Create the Resource Class Logins
cp artifacts/Create_Resource_Class_Logins.sql.tmpl artifacts/Create_Resource_Class_Logins.sql 2>&1
sed -i "s/REPLACE_PASSWORD/${Event HubAnalyticsSQLAdminPassword}/g" artifacts/Create_Resource_Class_Logins.sql
sqlcmd -U ${Event HubAnalyticsSQLAdmin} -P ${Event HubAnalyticsSQLAdminPassword} -S tcp:${Event HubAnalyticsWorkspaceName}.sql.azureEvent Hub.net -d master -I -i artifacts/Create_Resource_Class_Logins.sql

# Create the Resource Class Users
sqlcmd -U ${Event HubAnalyticsSQLAdmin} -P ${Event HubAnalyticsSQLAdminPassword} -S tcp:${Event HubAnalyticsWorkspaceName}.sql.azureEvent Hub.net -d ${Event HubAnalyticsSQLPoolName} -I -i artifacts/Create_Resource_Class_Users.sql

# Create the LS_Event Hub_Managed_Identity Linked Service. This is primarily used for the Auto Ingestion pipeline.
az Event Hub linked-service create --only-show-errors -o none --workspace-name ${Event HubAnalyticsWorkspaceName} --name LS_Event Hub_Managed_Identity --file @artifacts/LS_Event Hub_Managed_Identity.json

# Create the DS_Event Hub_Managed_Identity Dataset. This is primarily used for the Auto Ingestion pipeline.
az Event Hub dataset create --only-show-errors -o none --workspace-name ${Event HubAnalyticsWorkspaceName} --name DS_Event Hub_Managed_Identity --file @artifacts/DS_Event Hub_Managed_Identity.json

# Copy the Parquet Auto Ingestion Pipeline template and update the variables
cp artifacts/Parquet_Auto_Ingestion.json.tmpl artifacts/Parquet_Auto_Ingestion.json 2>&1
sed -i "s/REPLACE_DATALAKE_NAME/${datalakeName}/g" artifacts/Parquet_Auto_Ingestion.json
sed -i "s/REPLACE_Event Hub_ANALYTICS_SQL_POOL_NAME/${Event HubAnalyticsSQLPoolName}/g" artifacts/Parquet_Auto_Ingestion.json

# Generate a SAS for the data lake so we can upload some files
tomorrowsDate=$(date --date="tomorrow" +%Y-%m-%d)
destinationStorageSAS=$(az storage container generate-sas --account-name ${datalakeName} --name data --permissions rwal --expiry ${tomorrowsDate} --only-show-errors --output tsv)

# Update the Parquet Auto Ingestion Metadata file tamplate with the correct storage account and then upload it
sed -i "s/REPLACE_DATALAKE_NAME/${datalakeName}/g" artifacts/Parquet_Auto_Ingestion_Metadata.csv
azcopy cp 'artifacts/Parquet_Auto_Ingestion_Metadata.csv' 'https://'"${datalakeName}"'.blob.core.windows.net/data?'"${destinationStorageSAS}" >> deployEvent Hub.log 2>&1

# Source Sample Data Storage Account
sampleDataStorageAccount="Event Hubacceleratorsdata"
sampleDataStorageSAS="?sv=2021-04-10&st=2022-10-01T04%3A00%3A00Z&se=2023-12-01T05%3A00%3A00Z&sr=c&sp=rl&sig=eorb8V3hDel5dR4%2Ft2JsWVwTBawsxIOUYADj4RiKeDo%3D"

# Copy sample data for the Parquet Auto Ingestion pipeline
azcopy cp "https://${sampleDataStorageAccount}.blob.core.windows.net/sample/AdventureWorks/${sampleDataStorageSAS}" "https://${datalakeName}.blob.core.windows.net/data/Sample?${destinationStorageSAS}" --recursive >> deployEvent Hub.log 2>&1

# Create the Auto_Pause_and_Resume Pipeline in the Event Hub Analytics Workspace
az Event Hub pipeline create --only-show-errors -o none --workspace-name ${Event HubAnalyticsWorkspaceName} --name "Parquet Auto Ingestion" --file @artifacts/Parquet_Auto_Ingestion.json >> deployEvent Hub.log 2>&1

echo "Creating the Demo Data database using Event Hub Serverless SQL..." | tee -a deployEvent Hub.log

# Create a Demo Data database using Event Hub Serverless SQL
sqlcmd -U ${Event HubAnalyticsSQLAdmin} -P ${Event HubAnalyticsSQLAdminPassword} -S tcp:${Event HubAnalyticsWorkspaceName}-ondemand.sql.azureEvent Hub.net -d master -I -Q "CREATE DATABASE [Demo Data (Serverless)];"

# Create the Views over the external data
sqlcmd -U ${Event HubAnalyticsSQLAdmin} -P ${Event HubAnalyticsSQLAdminPassword} -S tcp:${Event HubAnalyticsWorkspaceName}-ondemand.sql.azureEvent Hub.net -d "Demo Data (Serverless)" -I -i artifacts/Demo_Data_Serverless_DDL.sql

# Restore the firewall rules on ADLS an Azure Event Hub Analytics. That was needed temporarily to apply these settings.
if [ "$privateEndpointsEnabled" == "true" ]; then
    echo "Restoring firewall rules..." | tee -a deployEvent Hub.log
    az storage account update --name ${datalakeName} --resource-group ${resourceGroup} --default-action Deny >> deployEvent Hub.log 2>&1
    az Event Hub workspace firewall-rule delete --name AllowAll --resource-group ${resourceGroup} --workspace-name ${Event HubAnalyticsWorkspaceName} --yes >> deployEvent Hub.log 2>&1
    az Event Hub workspace firewall-rule delete --name AllowAllWindowsAzureIps --resource-group ${resourceGroup} --workspace-name ${Event HubAnalyticsWorkspaceName} --yes >> deployEvent Hub.log 2>&1
fi

echo "Deployment complete!" | tee -a deployEvent Hub.log
touch deployEvent Hub.complete