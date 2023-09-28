GREEN="\033[0;32m"
echo -e "$GREEN Hi!, This script will help you create Azure Kubernetes Services"
echo -e "$GREEN These are the prerequisistes needed: "
echo -e "$GREEN - Global Admin Permission on ADD"
echo -e "$GREEN - Subscription Owner"
echo -e "$GREEN Subnet created to Land AKS"
echo -e "$GREEN -----------------------------------"
echo -e "$GREEN Please enter the name of the cluster: "
read clusterName
echo export clusterName=$clusterName >>./var.txt
echo -e "$GREEN Please enter the cluster location: (Example: westeurope or uaenorth)"
read location
echo export location=$location >>./var.txt
echo -e "$GREEN Please enter the Resource-Group for the VNET: "
read vnetrg
echo export vnetrg=$vnetrg >>./var.txt
echo -e "$GREEN Please enter the vnet name: "
read vnetname
echo export vnetname=$vnetname >>./var.txt
echo -e "$GREEN Please enter the Subnet name: "
read subname
echo export subname=$subname >>./var.txt

echo -e "$GREEN Do you have the subnet Created ? y/n"
read subnetcreated
if [ $subnetcreated == 'y' ]; then
  echo -e "$GREEN Getting exisiting subnet..."
  VNET_ID=$(az network vnet show --resource-group ${vnetrg} --name $vnetname --query id -o tsv)
  echo export VNET_ID=$VNET_ID >>./var.txt
  SUBNET_ID=$(az network vnet subnet show --resource-group ${vnetrg} --vnet-name $vnetname --name $subname --query id -o tsv)
  echo export SUBNET_ID=$SUBNET_ID >>./var.txt
else

  echo -e "$GREEN Ok! What is the address-prefix for the subnet? (Example: 10.179.128.0/21)"
  read addressPrefix
  echo -e "$GREEN Creating subnet for AKS cluster..."
  VNET_ID=$(az network vnet show --resource-group ${vnetrg} --name $vnetname --query id -o tsv)
  echo export VNET_ID=$VNET_ID >>./var.txt
  SUBNET_ID=$(az network vnet subnet create -n aks-subnet -g ${vnetrg} --vnet-name $vnetname --address-prefix $addressPrefix --query "id" -o tsv)
  echo export SUBNET_ID=$SUBNET_ID >>./var.txt
  echo -e "$GREEN Subnet $SUBNET_ID has been created!..."
fi

echo -e "$GREEN Geting tenant ID..."
tenantId=$(az account show --query tenantId -o tsv)

echo -e "$GREEN do you have a predefined Admin Group ? [y/n]"
read createADGroup
if [ $createADGroup == 'y' ]; then
  echo -e "$GREEN What is the name of the predefined AD Group?"
  read ADGroup
  echo export ADGroup=$ADGroup >>./var.txt
  GROUP_ID=$(az ad group show -g $ADGroup --query id -o tsv)
  echo export GROUP_ID=$GROUP_ID >>./var.txt
else
  echo -e "$GREEN What is the name of the new AD Group?"
  read ADNEWGroup
  echo export ADNEWGroup=$ADNEWGroup >>./var.txt
  echo -e "$GREEN Creating AD Group.."
  GROUP_ID=$(az ad group create \
    --display-name $ADNEWGroup \
    --mail-nickname $ADNEWGroup \
    --query id -o tsv)
  echo -e "$GREEN AD Group $ADNEWGroup has been created !"
  echo export GROUP_ID=$GROUP_ID >>./var.txt
fi

echo -e "$GREEN Now let's configure System and User node pools for the cluster: "
echo -e "$GREEN System node pools serve the primary purpose of hosting critical *system pods* such as CoreDNS, konnectivity, metrics-server..."
echo -e "$GREEN System node pools count: (2 or higher is recommended)"
read nodecount
echo export nodecount=$nodecount >>./var.txt
echo -e "$GREEN System node pools count will be $nodecount.."

echo -e "$GREEN System node pools VM Size: (example: Standard_DS4_v2)"
read nodeSize
echo export nodeSize=$nodeSize >>./var.txt
echo -e "$GREEN System node pools VM Size will be $nodeSize"

echo -e "$GREEN User node pools serve the primary purpose of hosting your application pods."

echo -e "$GREEN User node pools count: (3 or higher odd number is recommended)"
read userNodepoolCount
echo export userNodepoolCount=$userNodepoolCount >>./var.txt
echo -e "$GREEN User node pools count will be $userNodepoolCount."

echo -e "$GREEN User node pools VM Size: (example: Standard_D8s_v3)"
read userNodepoolSize
echo export userNodepoolSize=$userNodepoolSize >>./var.txt
echo -e "$GREEN User node pools VM Size will be $userNodepoolSize"

echo -e "$GREEN Specify AKS version: (Example: 1.27.3)"
read AKSVersion
echo export AKSVersion=$AKSVersion >>./var.txt

echo -e "$GREEN What is the Resource Group for the Cluster?"
read ResourceGroup
echo export ResourceGroup=$ResourceGroup >>./var.txt
# Assign subnet contributor permissions
#az role assignment create --assignee $SP_ID --scope $SUBNET_ID --role Contributor

echo -e "$GREEN What is the name of your Managed Identity to create ?"
read UManagedIdentity
echo export UManagedIdentity=$UManagedIdentity >>./var.txt
ManagedIdentityId=$(az identity create --name $UManagedIdentity --resource-group $ResourceGroup --query "id" | tr -d '"')

echo -e "$GREEN Would this cluster host Windows Nodes ? [y/n]"
read WindowsNode
echo export WindowsNode=$WindowsNode >>./var.txt

if [ $WindowsNode == 'y' ]; then

  echo -e "$GREEN Please provide username for Windows Nodes?"
  read WindowsNodeUsername

  echo -e "$GREEN Please provide Password for Windows Nodes?"
  read WindowsNodePassword

  echo export WindowsNodeUsername=$WindowsNodeUsername >>./var.txt
  echo export WindowsNodePassword=$WindowsNodePassword >>./var.txt
  echo -e "$GREEN Creating Windows-based Cluster..."
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
  echo -e "$GREEN Creating Linux-based Cluster..."
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
    --nodepool-name systempool01

fi

echo -e "$GREEN Adding User Node Pools to the cluster..."

az aks nodepool add \
  --cluster-name $clusterName \
  --name $userNodepoolCount \
  --resource-group $ResourceGroup \
  --mode User \
  --node-count $userNodepoolCount \
  --node-vm-size $userNodepoolSize \
  --kubernetes-version $AKSVersion

echo -e "$GREEN Congratulation AKS Cluster $clusterName has been created!"
echo -e "$GREEN Logging into Cluster Now..."

az aks get-credentials --name $clusterName --resource-group $ResourceGroup --overwrite-existing --admin

echo -e "$GREEN Do you want to Attach Azure Container Registry to the cluster ? [y/n]"
read attachACR
if [ $attachACR == 'y' ]; then
  echo -e "$GREEN What is the Container Register Name ?"
  read ACRName
  az aks update --name $clusterName -g $ResourceGroup --attach-acr $ACRName
else
  echo -e "$GREEN "
fi

echo -e "$GREEN Congratulation you have created Managed AAD Cluster with Managed Identity"
