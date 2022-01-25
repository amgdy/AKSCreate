GREEN="\033[0;32m"
echo -e "$GREEN Hi!, This script will help you create Azure Kubernetes Services"
echo -e "$GREEN These are the prerequisistes needed:"
echo -e "$GREEN - Global Admin Permission on ADD"
echo -e "$GREEN - Subscription Owner"
echo -e "$GREEN Subnet created to Land AKS"
echo -e "$GREEN -----------------------------------"
echo -e "$GREEN Please enter the name of the cluster:"
read clusterName
echo export clusterName=$clusterName >> ./var.txt
echo -e "$GREEN Please enter the location by example 'westeurope/uaenorth':"
read location
echo export location=$location >> ./var.txt
echo -e "$GREEN Please enter the Resource-Group for the VNET:"
read vnetrg
echo export vnetrg=$vnetrg >> ./var.txt
echo -e "$GREEN Please enter the vnet name:"
read vnetname
echo export vnetname=$vnetname >> ./var.txt
echo -e "$GREEN Please enter the Subnet name:"
read subname
echo export subname=$subname >> ./var.txt

echo -e "$GREEN Do you have the subnet Created ? y/n"
read subnetcreated
if [ $subnetcreated == 'y' ]
then
       echo -e "$GREEN Getting exisiting subnet..."
    VNET_ID=$(az network vnet show --resource-group ${vnetrg} --name $vnetname --query id -o tsv)
    echo export VNET_ID=$VNET_ID >> ./var.txt
    SUBNET_ID=$(az network vnet subnet show --resource-group ${vnetrg} --vnet-name $vnetname --name $subname --query id -o tsv)
    echo export SUBNET_ID=$SUBNET_ID >> ./var.txt
else

 echo -e "$GREEN Ok! What is the address-prefix for the subnet ? by example '10.179.128.0/21'"
    read addressPrefix
    echo -e "$GREEN Creating subnet for AKS cluster..."
    VNET_ID=$(az network vnet show --resource-group ${vnetrg} --name $vnetname --query id -o tsv)
    echo export VNET_ID=$VNET_ID >> ./var.txt
    SUBNET_ID=$(az network vnet subnet create -n aks-subnet -g ${vnetrg} --vnet-name $vnetname --address-prefix $addressPrefix --query "id" -o tsv)
    echo export SUBNET_ID=$SUBNET_ID >> ./var.txt
    echo -e "$GREEN Subnet $SUBNET_ID has been created!..."
    fi

echo -e "$GREEN Geting tenant ID..."
tenantId=$(az account show --query tenantId -o tsv)

 echo -e "$GREEN do you have a predefined Admin Group ? y/n"
    read createADGroup
        if [ $createADGroup == 'y' ]
        then
            echo -e "$GREEN What is the name of the predefined AD Group?"
            read ADGroup
            GROUP_ID=$(az ad group show -g $ADGroup --query objectId -o tsv)
        else
            echo -e "$GREEN What is the name of the new AD Group?"
            read ADNEWGroup
            echo -e "$GREEN Creating AD Group.."
            GROUP_ID=$(az ad group create \
            --display-name $ADNEWGroup \
            --mail-nickname $ADNEWGroup \
            --query objectId -o tsv)
            echo -e "$GREEN AD Group $ADNEWGroup has been created !"
        fi

echo -e "$GREEN Creating Cluster..."
echo -e "$GREEN How many nodes you require for the cluster ?"
read nodecount
echo -e "$GREEN Node Count will be $nodecount.."

echo -e "$GREEN what is node vm size ? example Standard_D8s_v3"
read nodeSize

echo -e "$GREEN Specify AKS version or 1.19.7"

read AKSVersion

echo -e "$GREEN What is the Resource Group for the Cluster ?"
read ResourceGroup
# Assign subnet contributor permissions
#az role assignment create --assignee $SP_ID --scope $SUBNET_ID --role Contributor

echo -e "$GREEN What is the name of your Managed Identity to create ?"
read UManagedIdentity

ManagedIdentityId= az identity create --name $UManagedIdentity --resource-group $ResourceGroup --query "id"

az aks create \
  --resource-group $ResourceGroup\
  --name $clusterName \
	--location $location \
  --generate-ssh-keys \
	--node-count $nodecount \
	--node-vm-size=$nodeSize \
	--vm-set-type VirtualMachineScaleSets \
  --network-plugin kubenet \
  --vnet-subnet-id $SUBNET_ID \
  --docker-bridge-address 172.170.0.1/16 \
  --service-cidr 172.171.0.0/16 \
  --dns-service-ip 172.171.0.10 \
  --enable-aad \
  --aad-admin-group-object-ids $GROUP_ID \
  --aad-tenant-id $tenantId \
  --enable-managed-identity \
  --assign-identity $ManagedIdentityId
  --kubernetes-version $AKSVersion

echo -e "$GREEN Congratulation AKS Cluster $clusterName has been created!"
echo -e "$GREEN Logging into Cluster Now..."

az aks get-credentials --name $clusterName --resource-group $ResourceGroup --overwrite-existing --admin

echo -e "$GREEN Do you want to Attach Azure Container Registry to the cluster ? y/n"
read attachACR
if [ $attachACR == 'y' ]
then
echo -e "$GREEN What is the Container Register Name ?"
read ACRName
az aks update --name $clusterName -g $ResourceGroup --attach-acr $ACRName
else
  echo -e "$GREEN "
fi

echo -e "$GREEN Congratulation you have created Managed AAD Cluster with Managed Identity"
