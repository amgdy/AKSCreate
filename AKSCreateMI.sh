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
read clusterName
echo export clusterName=$clusterName >>./var.txt
echo -e "$COLOR_GREEN Please enter the cluster location: (Example: westeurope or uaenorth) $COLOR_RESET"
read location
echo export location=$location >>./var.txt
echo -e "$COLOR_GREEN Please enter the Resource-Group for the VNET:  $COLOR_RESET"
read vnetrg
echo export vnetrg=$vnetrg >>./var.txt
echo -e "$COLOR_GREEN Please enter the vnet name:  $COLOR_RESET"
read vnetname
echo export vnetname=$vnetname >>./var.txt
echo -e "$COLOR_GREEN Please enter the Subnet name:  $COLOR_RESET"
read subname
echo export subname=$subname >>./var.txt

echo -e "$COLOR_GREEN Do you have the subnet ALREADY Created ? [y/n] $COLOR_RESET"
read subnetcreated
if [ $subnetcreated == 'y' ]; then
  echo -e "$COLOR_GREEN Getting exisiting subnet... $COLOR_RESET"
  VNET_ID=$(az network vnet show --resource-group ${vnetrg} --name $vnetname --query id -o tsv)
  echo export VNET_ID=$VNET_ID >>./var.txt
  SUBNET_ID=$(az network vnet subnet show --resource-group ${vnetrg} --vnet-name $vnetname --name $subname --query id -o tsv)
  echo export SUBNET_ID=$SUBNET_ID >>./var.txt
else

  echo -e "$COLOR_GREEN Ok! What is the address-prefix for the subnet? (Example: 10.179.128.0/21) $COLOR_RESET"
  read addressPrefix
  echo -e "$COLOR_GREEN Creating subnet for AKS cluster... $COLOR_RESET"
  VNET_ID=$(az network vnet show --resource-group ${vnetrg} --name $vnetname --query id -o tsv)
  echo export VNET_ID=$VNET_ID >>./var.txt
  SUBNET_ID=$(az network vnet subnet create -n aks-subnet -g ${vnetrg} --vnet-name $vnetname --address-prefix $addressPrefix --query "id" -o tsv)
  echo export SUBNET_ID=$SUBNET_ID >>./var.txt
  echo -e "$COLOR_GREEN Subnet $SUBNET_ID has been created!... $COLOR_RESET"
fi

echo -e "$COLOR_GREEN Geting tenant ID... $COLOR_RESET"
tenantId=$(az account show --query tenantId -o tsv)

echo -e "$COLOR_GREEN do you have a predefined Admin Group ? [y/n] $COLOR_RESET"
read createADGroup
if [ $createADGroup == 'y' ]; then
  echo -e "$COLOR_GREEN What is the name of the predefined AD Group? $COLOR_RESET"
  read ADGroup
  echo export ADGroup=$ADGroup >>./var.txt
  GROUP_ID=$(az ad group show -g $ADGroup --query id -o tsv)
  echo export GROUP_ID=$GROUP_ID >>./var.txt
else
  echo -e "$COLOR_GREEN What is the name of the new AD Group? $COLOR_RESET"
  read ADNEWGroup
  echo export ADNEWGroup=$ADNEWGroup >>./var.txt
  echo -e "$COLOR_GREEN Creating AD Group.."
  GROUP_ID=$(az ad group create \
    --display-name $ADNEWGroup \
    --mail-nickname $ADNEWGroup \
    --query id -o tsv)
  echo -e "$COLOR_GREEN AD Group $ADNEWGroup has been created ! $COLOR_RESET"
  echo export GROUP_ID=$GROUP_ID >>./var.txt
fi

echo -e "$COLOR_GREEN Now let's configure System and User node pools for the cluster:  $COLOR_RESET"
echo -e "$COLOR_GREEN System node pools serve the primary purpose of hosting critical *system pods* such as CoreDNS, konnectivity, metrics-server... $COLOR_RESET"
echo -e "$COLOR_GREEN What is the count of System node pools? (2 or higher is recommended) $COLOR_RESET"
read nodecount
echo export nodecount=$nodecount >>./var.txt
echo -e "$COLOR_GREEN System node pools count will be $nodecount $COLOR_RESET"

echo -e "$COLOR_GREEN What is the system node pools VM Size? (example: Standard_DS4_v2) $COLOR_RESET"
read nodeSize
echo export nodeSize=$nodeSize >>./var.txt
echo -e "$COLOR_GREEN System node pools VM Size will be $nodeSize $COLOR_RESET"

echo -e "$COLOR_GREEN User node pools serve the primary purpose of hosting your application pods. $COLOR_RESET"

echo -e "$COLOR_GREEN What is the user node pools count? (3 or higher *odd number* is recommended) $COLOR_RESET"
read userNodepoolCount
echo export userNodepoolCount=$userNodepoolCount >>./var.txt
echo -e "$COLOR_GREEN User node pools count will be $userNodepoolCount.  $COLOR_RESET"

echo -e "$COLOR_GREEN What is the user node pools VM Size? (example: Standard_D8s_v3) $COLOR_RESET"
read userNodepoolSize
echo export userNodepoolSize=$userNodepoolSize >>./var.txt
echo -e "$COLOR_GREEN User node pools VM Size will be $userNodepoolSize  $COLOR_RESET"

echo -e "$COLOR_GREEN Specify AKS version: (Example: 1.27.3) $COLOR_RESET"
read AKSVersion
echo export AKSVersion=$AKSVersion >>./var.txt

echo -e "$COLOR_GREEN What is the Resource Group for the Cluster? $COLOR_RESET"
read ResourceGroup
echo export ResourceGroup=$ResourceGroup >>./var.txt
# Assign subnet contributor permissions
#az role assignment create --assignee $SP_ID --scope $SUBNET_ID --role Contributor

echo -e "$COLOR_GREEN What is the name of your Managed Identity to create ? $COLOR_RESET"
read UManagedIdentity
echo export UManagedIdentity=$UManagedIdentity >>./var.txt
ManagedIdentityId=$(az identity create --name $UManagedIdentity --resource-group $ResourceGroup --query "id" | tr -d '"')

echo -e "$COLOR_GREEN Would this cluster host Windows Nodes ? [y/n] $COLOR_RESET"
read WindowsNode
echo export WindowsNode=$WindowsNode >>./var.txt

if [ $WindowsNode == 'y' ]; then

  echo -e "$COLOR_GREEN Please provide username for Windows Nodes? $COLOR_RESET"
  read WindowsNodeUsername

  echo -e "$COLOR_GREEN Please provide Password for Windows Nodes? $COLOR_RESET"
  read WindowsNodePassword

  echo export WindowsNodeUsername=$WindowsNodeUsername >>./var.txt
  echo export WindowsNodePassword=$WindowsNodePassword >>./var.txt
  echo -e "$COLOR_GREEN Creating Windows-based Cluster..."
  az aks create \
    --resource-group $ResourceGroup \
    --name $clusterName \
    --location $location \
    --generate-ssh-keys \
    --node-count $nodecount \
    --node-vm-size=$nodeSize \
    --vm-set-type VirtualMachineScaleSets \
    --windows-admin-username $WindowsNodeUsername \
    --windows-admin-password $WindowsNodePassword \
    --network-plugin azure \
    --vnet-subnet-id $SUBNET_ID \
    --service-cidr 172.171.0.0/16 \
    --dns-service-ip 172.171.0.10 \
    --enable-aad \
    --aad-admin-group-object-ids $GROUP_ID \
    --aad-tenant-id $tenantId \
    --enable-managed-identity \
    --assign-identity $ManagedIdentityId \
    --kubernetes-version $AKSVersion \
    --nodepool-name systempool01

else
  echo -e "$COLOR_GREEN Creating Linux-based Cluster... $COLOR_RESET"
  az aks create \
    --resource-group $ResourceGroup \
    --name $clusterName \
    --location $location \
    --generate-ssh-keys \
    --node-count $nodecount \
    --node-vm-size=$nodeSize \
    --vm-set-type VirtualMachineScaleSets \
    --network-plugin kubenet \
    --vnet-subnet-id $SUBNET_ID \
    --service-cidr 172.171.0.0/16 \
    --dns-service-ip 172.171.0.10 \
    --enable-aad \
    --aad-admin-group-object-ids $GROUP_ID \
    --aad-tenant-id $tenantId \
    --enable-managed-identity \
    --assign-identity $ManagedIdentityId \
    --kubernetes-version $AKSVersion \
    --nodepool-name $SYSTEMNODE_NAME

fi

if [ $? -eq 0 ]; then
  echo -e "$COLOR_GREEN Adding User Node Pool $WORKERPOOL_NAME to the cluster... $COLOR_RESET"

  az aks nodepool add \
    --cluster-name $clusterName \
    --name $WORKERPOOL_NAME \
    --resource-group $ResourceGroup \
    --mode User \
    --node-count $userNodepoolCount \
    --node-vm-size $userNodepoolSize \
    --kubernetes-version $AKSVersion

  echo -e "$COLOR_GREEN Congratulation AKS Cluster $clusterName has been created! $COLOR_RESET"
  echo -e "$COLOR_GREEN Logging into Cluster Now... $COLOR_RESET"

  az aks get-credentials --name $clusterName --resource-group $ResourceGroup --overwrite-existing --admin

  if [ $? -eq 0 ]; then
    echo -e "$COLOR_GREEN Do you want to Attach Azure Container Registry to the cluster ? [y/n] $COLOR_RESET"
    read attachACR
    if [ $attachACR == 'y' ]; then
      echo -e "$COLOR_GREEN What is the Container Register Name ? $COLOR_RESET"
      read ACRName
      az aks update --name $clusterName -g $ResourceGroup --attach-acr $ACRName
    else
      echo -e "."
    fi

    echo -e "$COLOR_GREEN Congratulation you have created Managed AAD Cluster with Managed Identity $COLOR_RESET"
  fi
else
  echo -e "$RED Failed to create the cluster!  $COLOR_RESET"
fi
