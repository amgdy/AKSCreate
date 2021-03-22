GREEN= "\033[0;32m"
echo -e "$GREEN What is the AKS Resource Group ?"
read ResourceGroup
echo -e "$GREEN What is the AKS Name ?"
read clusterName

AKS_ID=$(az aks show \
    --resource-group $ResourceGroup  \
    --name $clusterName \
    --query id -o tsv)

echo -e "$GREEN Do you want to create a namespace and give access to a specific AD Group to it ? y/n"
read createADGroup
if [ $createADGroup == 'y' ]
then
echo -e "$GREEN What is the name of the Namespace"
read NSName
echo -e "$GREEN Creating $NSName namespace..."
kubectl create namespace $NSName
echo -e "$GREEN $NSName namespace has been created!."
echo -e "$GREEN do you have a predefined AD Group ? y/n"
read createADGroup
    if [ $createADGroup == 'y' ]
    then
        echo -e "$GREEN What is the name of the predefined AD Group?"
        read ADGroup
        GROUP_ID=$(az ad group show -g $ADGroup --query objectId -o tsv)
        echo -e "$GREEN Assigning the group to role on the AKS cluster.."
        az role assignment create \
        --assignee $GROUP_ID \
        --role "Azure Kubernetes Service Cluster User Role" \
        --scope $AKS_ID
        RoleName="$ADGroup-full-access"
        rnd= $RANDOM
        sed -i ./RoleFullAccess.yaml -e "s/ROLENAME/$ROLEName/g" -e "s/NAMESPACENAME/$NSName/g" > ./RoleFullAccess-$rnd.yaml
        kubectl create -f ./RoleFullAccess-$rnd.yaml
        sed -i ./RoleBinding.yaml -e "s/groupObjectId/${GROUP_ID}/g" -e "s/ROLEBINDINGNAME/rolebindingnamehehe/g" -e "s/ROLENAME/$RoleName/g" -e "s/NAMESPACENAME/$NSName/g" > ./RoleBinding-$rnd.yaml
        kubectl create -f ./RoleBinding-$rnd.yaml
        echo -e "$GREEN group $ADGroup has been assign to namespace $NSName."
    else
        echo -e "$GREEN What is the name of the new AD Group?"
        read ADNEWGroup
        echo -e "$GREEN Creating AD Group.."
        GROUP_ID=$(az ad group create \
        --display-name $ADNEWGroup \
        --mail-nickname $ADNEWGroup \
        --query objectId -o tsv)
        echo -e "$GREEN AD Group $ADNEWGroup has been created !"
        echo -e "$GREEN Assigning the group to role on the AKS cluster.."
        az role assignment create \
        --assignee $GROUP_ID \
        --role "Azure Kubernetes Service Cluster User Role" \
        --scope $AKS_ID

        echo -e "$GREEN Creating Role"
        RoleName= "$ADGroup-full-access"
        rnd= $RANDOM
        sed -i ./RoleFullAccess.yaml -e "s/ROLENAME/$ROLEName/g" -e "s/NAMESPACENAME/$NSName/g" > ./RoleFullAccess-$rnd.yaml
        kubectl create -f ./RoleFullAccess-$rnd.yaml
        sed -i ./RoleBinding.yaml -e "s/groupObjectId/${GROUP_ID}/g" -e "s/ROLEBINDINGNAME/rolebindingnamehehe/g" -e "s/ROLENAME/$RoleName/g" -e "s/NAMESPACENAME/$NSName/g" > ./RoleBinding-$rnd.yaml
        kubectl create -f ./RoleBinding-$rnd.yaml
        echo -e "$GREEN group $ADGroup has been assign to namespace $NSName."
    fi

else
fi
