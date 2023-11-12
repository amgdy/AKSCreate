#!/bin/bash

COLOR_GREEN="\033[0;32m"
COLOR_RED="\033[31m"
COLOR_RESET="\033[0m"
SYSTEMNODE_NAME=systempool01
WORKERPOOL_NAME=workerpool01
echo -e "$COLOR_GREEN Hi!, This script will help you create Azure Kubernetes Services $COLOR_RESET"
echo -e "$COLOR_GREEN These are the prerequisistes needed: $COLOR_RESET"
echo -e "$COLOR_GREEN - Global Admin Permission on ADD $COLOR_RESET"
echo -e "$COLOR_GREEN - Subscription Owner $COLOR_RESET"
echo -e "$COLOR_GREEN Subnet created to Land AKS $COLOR_RESET"
echo -e "$COLOR_GREEN ----------------------------------- $COLOR_RESET"
echo -e "$COLOR_GREEN Please enter the name of the cluster:  $COLOR_RESET"
read -r CLUSTER_NAME
echo export CLUSTER_NAME=$CLUSTER_NAME >>./var.txt
echo -e "$COLOR_GREEN Please enter the cluster location: (Example: westeurope or uaenorth) $COLOR_RESET"
read -r CLUSTER_LOCATION
echo export CLUSTER_LOCATION=$CLUSTER_LOCATION >>./var.txt
echo -e "$COLOR_GREEN Please enter the Resource-Group for the VNET:  $COLOR_RESET"
read -r VNET_RRSOURCE_GROUP
echo export VNET_RRSOURCE_GROUP=$VNET_RRSOURCE_GROUP >>./var.txt
echo -e "$COLOR_GREEN Please enter the vnet name:  $COLOR_RESET"
read -r VNET_NAME
echo export vnetname=$VNET_NAME >>./var.txt
echo -e "$COLOR_GREEN Please enter the Subnet name:  $COLOR_RESET"
read -r SUBNET_NAME
echo export SUBNET_NAME=$SUBNET_NAME >>./var.txt

echo -e "$COLOR_GREEN Do you have the subnet ALREADY Created ? [y/n] $COLOR_RESET"
read -r SUBNET_ALREADY_CREATED
if [ $SUBNET_ALREADY_CREATED == 'y' ]; then
  echo -e "$COLOR_GREEN Getting exisiting subnet... $COLOR_RESET"
  VNET_ID=$(az network vnet show --resource-group ${VNET_RRSOURCE_GROUP} --name $VNET_NAME --query id -o tsv)
  echo export VNET_ID=$VNET_ID >>./var.txt
  SUBNET_ID=$(az network vnet subnet show --resource-group ${VNET_RRSOURCE_GROUP} --vnet-name $VNET_NAME --name $SUBNET_NAME --query id -o tsv)
  echo export SUBNET_ID=$SUBNET_ID >>./var.txt
else

  echo -e "$COLOR_GREEN Ok! What is the address-prefix for the subnet? (Example: 10.179.128.0/21) $COLOR_RESET"
  read -r SUBNET_ADDRESS_PREFIX
  echo -e "$COLOR_GREEN Creating subnet for AKS cluster... $COLOR_RESET"
  VNET_ID=$(az network vnet show --resource-group ${VNET_RRSOURCE_GROUP} --name $VNET_NAME --query id -o tsv)
  echo export VNET_ID=$VNET_ID >>./var.txt
  SUBNET_ID=$(az network vnet subnet create -n aks-subnet -g ${VNET_RRSOURCE_GROUP} --vnet-name $VNET_NAME --address-prefix $SUBNET_ADDRESS_PREFIX --query "id" -o tsv)
  echo export SUBNET_ID=$SUBNET_ID >>./var.txt
  echo -e "$COLOR_GREEN Subnet $SUBNET_ID has been created!... $COLOR_RESET"
fi

echo -e "$COLOR_GREEN Should we use Kubenet (Otherwise will use Azure CNI)? [y/n] $COLOR_RESET"
read -r USE_KUBENET

if [ $USE_KUBENET == 'y' ]; then
  CLUSTER_NETWORK=kubenet
else
  CLUSTER_NETWORK=azure
fi

echo export CLUSTER_NETWORK=$CLUSTER_NETWORK >>./var.txt

echo -e "$COLOR_GREEN Geting tenant ID... $COLOR_RESET"
TENANT_ID=$(az account show --query tenantId -o tsv)

echo -e "$COLOR_GREEN do you have a predefined Admin Group ? [y/n] $COLOR_RESET"
read -r AAD_GROUP_ALREADY_CREATED
if [ $AAD_GROUP_ALREADY_CREATED == 'y' ]; then
  echo -e "$COLOR_GREEN What is the name of the predefined AD Group? $COLOR_RESET"
  read -r AAD_GROUP_NAME
  echo export AAD_GROUP_NAME=$AAD_GROUP_NAME >>./var.txt
  AAD_GROUP_ID=$(az ad group show -g $AAD_GROUP_NAME --query id -o tsv)
  echo export AAD_GROUP_ID=$AAD_GROUP_ID >>./var.txt
else
  echo -e "$COLOR_GREEN What is the name of the new AD Group? $COLOR_RESET"
  read -r AAD_GROUP_NEW_NAME
  echo export AAD_GROUP_NEW_NAME=$AAD_GROUP_NEW_NAME >>./var.txt
  echo -e "$COLOR_GREEN Creating AD Group.."
  AAD_GROUP_ID=$(az ad group create \
    --display-name $AAD_GROUP_NEW_NAME \
    --mail-nickname $AAD_GROUP_NEW_NAME \
    --query id -o tsv)
  echo -e "$COLOR_GREEN AD Group $AAD_GROUP_NEW_NAME has been created ! $COLOR_RESET"
  echo export AAD_GROUP_ID=$AAD_GROUP_ID >>./var.txt
fi

echo -e "$COLOR_GREEN Now let's configure System and User node pools for the cluster:  $COLOR_RESET"
echo -e "$COLOR_GREEN System node pools serve the primary purpose of hosting critical *system pods* such as CoreDNS, konnectivity, metrics-server... $COLOR_RESET"
echo -e "$COLOR_GREEN What is the count of System node pools? (2 or higher is recommended) $COLOR_RESET"
read -r SYSTEM_NODE_COUNT
echo export SYSTEM_NODE_COUNT=$SYSTEM_NODE_COUNT >>./var.txt
echo -e "$COLOR_GREEN System node pools count will be $SYSTEM_NODE_COUNT $COLOR_RESET"

echo -e "$COLOR_GREEN What is the system node pools VM Size? (example: Standard_DS4_v2) $COLOR_RESET"
read -r SYSTEM_NODE_SIZE
echo export SYSTEM_NODE_SIZE=$SYSTEM_NODE_SIZE >>./var.txt
echo -e "$COLOR_GREEN System node pools VM Size will be $SYSTEM_NODE_SIZE $COLOR_RESET"

echo -e "$COLOR_GREEN User node pools serve the primary purpose of hosting your application pods. $COLOR_RESET"

echo -e "$COLOR_GREEN What is the user node pools count? (3 or higher *odd number* is recommended) $COLOR_RESET"
read -r USER_NODE_COUNT
echo export USER_NODE_COUNT=$USER_NODE_COUNT >>./var.txt
echo -e "$COLOR_GREEN User node pools count will be $USER_NODE_COUNT.  $COLOR_RESET"

echo -e "$COLOR_GREEN What is the user node pools VM Size? (example: Standard_D8s_v3) $COLOR_RESET"
read -r USER_NODE_SIZE
echo export USER_NODE_SIZE=$USER_NODE_SIZE >>./var.txt
echo -e "$COLOR_GREEN User node pools VM Size will be $USER_NODE_SIZE  $COLOR_RESET"

echo -e "$COLOR_GREEN Current Support Kubernetes version for AKS $COLOR_RESET"
az aks get-versions --location $CLUSTER_LOCATION --output table

echo -e "$COLOR_GREEN Specify kubernetes version for the cluster: (Example: 1.27.3) $COLOR_RESET"
read -r K8S_VERSION
echo export K8S_VERSION=$K8S_VERSION >>./var.txt

echo -e "$COLOR_GREEN What is the Resource Group for the Cluster? $COLOR_RESET"
read -r CLUSTER_RESOURCE_GRPUP
echo export CLUSTER_RESOURCE_GRPUP=$CLUSTER_RESOURCE_GRPUP >>./var.txt
# Assign subnet contributor permissions
#az role assignment create --assignee $SP_ID --scope $SUBNET_ID --role Contributor

echo -e "$COLOR_GREEN What is the name of your Managed Identity to create ? (We will this as User-Assigned Managed Identity for the cluster) $COLOR_RESET"
read -r MANAGED_IDENTITY_NAME
echo export MANAGED_IDENTITY_NAME=$MANAGED_IDENTITY_NAME >>./var.txt
MANAGED_IDENTITY_ID=$(az identity create --name $MANAGED_IDENTITY_NAME --resource-group $CLUSTER_RESOURCE_GRPUP --query "id" | tr -d '"')
echo export MANAGED_IDENTITY_ID=$MANAGED_IDENTITY_ID >>./var.txt

echo -e "$COLOR_GREEN Should we use AzureLinux? (Otherwise will use Ubuntu)? [y/n] $COLOR_RESET"
read -r USE_AZURELINUX
echo export USE_AZURELINUX=$USE_AZURELINUX >>./var.txt

if [ $USE_AZURELINUX == 'y' ]; then
  OS_SKU=AzureLinux
else
  OS_SKU=Ubuntu
fi

echo export OS_SKU=$OS_SKU >>./var.txt

echo -e "$COLOR_GREEN Would this cluster host Windows Nodes ? [y/n] $COLOR_RESET"
read -r WINDOWS_NODE
echo export WINDOWS_NODE=$WINDOWS_NODE >>./var.txt

if [ $WINDOWS_NODE == 'y' ]; then

  echo -e "$COLOR_GREEN Please provide username for Windows Nodes? $COLOR_RESET"
  read -r WINDOWS_NODE_USERNAME

  echo -e "$COLOR_GREEN Please provide Password for Windows Nodes? $COLOR_RESET"
  read -r WINDOWS_NODE_PASSWORD

  echo export WINDOWS_NODE_USERNAME=$WINDOWS_NODE_USERNAME >>./var.txt
  echo export WINDOWS_NODE_PASSWORD=$WINDOWS_NODE_PASSWORD >>./var.txt
  echo -e "$COLOR_GREEN Creating Windows-based Cluster..."
  az aks create \
    --resource-group $CLUSTER_RESOURCE_GRPUP \
    --name $CLUSTER_NAME \
    --location $CLUSTER_LOCATION \
    --generate-ssh-keys \
    --node-count $SYSTEM_NODE_COUNT \
    --node-vm-size=$SYSTEM_NODE_SIZE \
    --vm-set-type VirtualMachineScaleSets \
    --windows-admin-username $WINDOWS_NODE_USERNAME \
    --windows-admin-password $WINDOWS_NODE_PASSWORD \
    --network-plugin azure \
    --vnet-subnet-id $SUBNET_ID \
    --service-cidr 172.171.0.0/16 \
    --dns-service-ip 172.171.0.10 \
    --enable-aad \
    --aad-admin-group-object-ids $AAD_GROUP_ID \
    --aad-tenant-id $TENANT_ID \
    --enable-managed-identity \
    --assign-identity $MANAGED_IDENTITY_ID \
    --kubernetes-version $K8S_VERSION \
    --nodepool-name systempool01 \
    --os-sku $OS_SKU

else
  echo -e "$COLOR_GREEN Creating Linux-based Cluster... $COLOR_RESET"
  az aks create \
    --resource-group $CLUSTER_RESOURCE_GRPUP \
    --name $CLUSTER_NAME \
    --location $CLUSTER_LOCATION \
    --generate-ssh-keys \
    --node-count $SYSTEM_NODE_COUNT \
    --node-vm-size=$SYSTEM_NODE_SIZE \
    --vm-set-type VirtualMachineScaleSets \
    --network-plugin $CLUSTER_NETWORK \
    --vnet-subnet-id $SUBNET_ID \
    --service-cidr 172.171.0.0/16 \
    --dns-service-ip 172.171.0.10 \
    --enable-aad \
    --aad-admin-group-object-ids $AAD_GROUP_ID \
    --aad-tenant-id $TENANT_ID \
    --enable-managed-identity \
    --assign-identity $MANAGED_IDENTITY_ID \
    --kubernetes-version $K8S_VERSION \
    --nodepool-name $SYSTEMNODE_NAME \
    --os-sku $OS_SKU

fi

if [ $? -eq 0 ]; then
  echo -e "$COLOR_GREEN Adding User Node Pool $WORKERPOOL_NAME to the cluster... $COLOR_RESET"

  az aks nodepool add \
    --cluster-name $CLUSTER_NAME \
    --name $WORKERPOOL_NAME \
    --resource-group $CLUSTER_RESOURCE_GRPUP \
    --mode User \
    --node-count $USER_NODE_COUNT \
    --node-vm-size $USER_NODE_SIZE \
    --kubernetes-version $K8S_VERSION \
    --os-sku $OS_SKU

  echo -e "$COLOR_GREEN Congratulation AKS Cluster $CLUSTER_NAME has been created! $COLOR_RESET"
  echo -e "$COLOR_GREEN Logging into Cluster Now... $COLOR_RESET"

  az aks get-credentials --name $CLUSTER_NAME --resource-group $CLUSTER_RESOURCE_GRPUP --overwrite-existing --admin

  if [ $? -eq 0 ]; then
    echo -e "$COLOR_GREEN Do you want to Attach Azure Container Registry to the cluster ? [y/n] $COLOR_RESET"
    read -r ACR_ATTACH
    if [ $ACR_ATTACH == 'y' ]; then
      echo -e "$COLOR_GREEN What is the Container Register Name ? $COLOR_RESET"
      read -r ACR_NAME
      echo export ACR_NAME=$ACR_NAME >>./var.txt
      az aks update --name $CLUSTER_NAME -g $CLUSTER_RESOURCE_GRPUP --attach-acr $ACR_NAME
    else
      echo -e "."
    fi

    echo -e "$COLOR_GREEN Congratulation you have created Managed AAD Cluster with Managed Identity $COLOR_RESET"
  fi
else
  echo -e "$RED Failed to create the cluster!  $COLOR_RESET"
fi
