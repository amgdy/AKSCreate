echo "Hi!, This script will help you create Azure Kubernetes Services"
echo "These are the prerequisistes needed:"
echo "- Global Admin Permission on ADD"
echo "- Subscription Owner"
echo "Subnet created to Land AKS"
echo "-----------------------------------"
echo "Please enter the name of the cluster:"
read clusterName
echo export clusterName=$clusterName >> ./var.txt
echo "Please enter the location by example 'westeurope/northuae':"
read location
echo export location=$location >> ./var.txt
echo "Please enter the Resource-Group for the VNET:"
read vnetrg
echo export vnetrg=$vnetrg >> ./var.txt
echo "Please enter the vnet name:"
read vnetname
echo export vnetname=$vnetname >> ./var.txt
echo "Please enter the Subnet name:"
read subname
echo export subname=$subname >> ./var.txt

echo "Do you have the subnet Created ? y/n"
read subnetcreated
if [ $subnetcreated == 'y' ]
then
    echo "Ok! What is the address-prefix for the subnet ? by example '10.179.128.0/21'"
    read addressPrefix
    echo "Creating subnet for AKS cluster..."
    VNET_ID=$(az network vnet show --resource-group ${vnetrg} --name $vnetname --query id -o tsv)
    echo export VNET_ID=$VNET_ID >> ./var.txt
    SUBNET_ID=$(az network vnet subnet create -n aks-subnet -g ${vnetrg} --vnet-name $vnetname --address-prefix $addressPrefix --query "id" -o tsv)
    echo export SUBNET_ID=$SUBNET_ID >> ./var.txt
    echo "Subnet $SUBNET_ID has been created!..."
else
    echo "Getting exisiting subnet..."
    VNET_ID=$(az network vnet show --resource-group ${vnetrg} --name $vnetname --query id -o tsv)
    echo export VNET_ID=$VNET_ID >> ./var.txt
    SUBNET_ID=$(az network vnet subnet show --resource-group ${vnetrg} --vnet-name $vnetname --name $subname --query id -o tsv)
    echo export SUBNET_ID=$SUBNET_ID >> ./var.txt
fi

echo "Create app registration for Server app..."

serverApplicationId=$(az ad app create --display-name ${clusterName}Server --identifier-uris "https://${clusterName}Server" --query appId -o tsv)
echo export serverApplicationId=$serverApplicationId >> ./var.txt
az ad app update --id $serverApplicationId --set groupMembershipClaims=All
az ad sp create --id $serverApplicationId # Creating SP for app
serverApplicationSecret=$(az ad sp credential reset --name $serverApplicationId --credential-description "AKSPassword" --query password -o tsv)
echo export serverApplicationSecret=$serverApplicationSecret >> ./var.txt
az ad app permission add \
   --id $serverApplicationId \
   --api 00000003-0000-0000-c000-000000000000 \
   --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope 06da0dbc-49e2-44d2-8312-53f166ab848a=Scope 7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role
az ad app permission grant --id $serverApplicationId --api 00000003-0000-0000-c000-000000000000

echo "Please go to Azure Portal and grand Admin consent to APP Registration named ${clusterName}Server, from API Permissions."
read -p "Press enter to continue"


echo "Creating app registration for Client app..."
   clientApplicationId=$(az ad app create \
   --display-name "${clusterName}Client" \
   --native-app \
   --reply-urls "https://${clusterName}Client" \
   --query appId -o tsv) 
   echo export clientApplicationId=$clientApplicationId >> ./var.txt

az ad sp create --id $clientApplicationId
oAuthPermissionId=$(az ad app show --id $serverApplicationId --query "oauth2Permissions[0].id" -o tsv)
echo export oAuthPermissionId=$oAuthPermissionId >> ./var.txt
az ad app permission add --id $clientApplicationId --api $serverApplicationId --api-permissions $oAuthPermissionId=Scope
az ad app permission grant --id $clientApplicationId --api $serverApplicationId

echo "Geting tenant ID..."
tenantId=$(az account show --query tenantId -o tsv)

echo "Createing SP for AKS cluster and get SP id and password"
SP=$(az ad sp create-for-rbac --skip-assignment -o json)
echo export SP=$SP >> ./var.txt
SP_ID=$(echo $SP | jq '.appId' | tr -d '"') 
echo export SP_ID=$SP_ID >> ./var.txt
SP_PASSWORD=$(echo $SP | jq '.password' | tr -d '"')
echo export SP_PASSWORD=$SP_PASSWORD >> ./var.txt

read -p "Please allow for 5 seconds for SP propogation and then Press enter to continue.."

sleep 5

echo "Creating Cluster..."
echo "How many nodes you require for the cluster ?"
read nodecount
echo "Node Count will be $nodecount.."

echo "what is node vm size ? example Standard_D8s_v3"
read nodeSize

echo "Specify AKS version or 1.19.7"

read AKSVersion

echo "What is the Resource Group for the Cluster ?"
read ResourceGroup
# Assign subnet contributor permissions
#az role assignment create --assignee $SP_ID --scope $SUBNET_ID --role Contributor

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
    --aad-server-app-id $serverApplicationId \
    --aad-server-app-secret $serverApplicationSecret \
    --aad-client-app-id $clientApplicationId \
    --aad-tenant-id $tenantId \
    --service-principal $SP_ID \
    --client-secret $SP_PASSWORD \
	--kubernetes-version $AKSVersion

echo "Congratulation AKS Cluster $clusterName has been created!"
echo "Logging into Cluster Now..."

az aks get-credentials -n $clusterName -g $ResourceGroup --overwrite-existing --admin

echo "Do you want to Attach Azure Container Registry to the cluster ? y/n"
read attachACR
if [ $attachACR == 'y' ]
then
echo "What is the Container Register Name ?"
read ACRName
az aks update --name $clusterName -g $ResourceGroup --attach-acr $ACRName
else
  echo ""
fi
