#!/bin/bash
set -e

color_green='\033[0;32m'
color_red=$'\033[31m'
color_cyan='\033[0;36m'
color_reset=$'\033[0m'
systempool_name=systempool01
workerpool_name=workerpool01
timestamp=$(date +"%Y%m%d%H%M%S")
vars_file="vars-$timestamp.txt"

function echo_green() {
  echo -e "$color_green$* $color_reset"
}

function echo_cyan() {
  echo -e "$color_cyan$* $color_reset"
}

function echo_red() {
  echo -e "$color_red$* $color_reset"
}

function echo_italic() {
  echo -e "\e[3m$* $color_reset\e[0m"
}

function yes_no_question() {
  local input
  local prompt="$1 [Y/n]: "
  local default="${2:-Y}"

  while read -e -p "$prompt" -r -n 1 input && ! [[ "$input" =~ ^[YyNn]?$ ]]; do
    echo "Invalid input. Please enter 'Y', 'N', or press Enter for $default."
  done

  echo "${input:-$default}" | tr '[:upper:]' '[:lower:]'
}

function input_question() {
  local prompt_message="$1: "
  local input_value
  while [[ -z "$input_value" ]]; do
    read -p "$prompt_message" -r input_value
    if [[ -z "$input_value" ]]; then
      echo "Input cannot be empty. Please try again."
    fi
  done

  echo "$input_value"
}
function select_item() {
  local items=("$@")
  local select_message="$1"
  local items_to_select=("${items[@]:1}") # Exclude the first element
  PS3="$select_message: "
  select option in "${items_to_select[@]}"; do
    if [[ -n "$option" ]]; then
      if [[ $option =~ \((.+)\) ]]; then
        local selected_item="${BASH_REMATCH[1]}"
        echo_italic "You've selected: $option" >&2
        echo "$selected_item"
        break
      else
        echo "Invalid format. Please try again." >&2
      fi
    else
      echo "Invalid selection. Please try again." >&2
    fi
  done
}

function log() {
  echo "$*" >>./"$vars_file"
}

if [ -n "$1" ]; then
  vars_file=$1
fi

echo_green "Hi!, This script will help you create Azure Kubernetes Services"
echo_green "These are the prerequisistes needed: 
- Permissions:
  - Azure Subscription Owner
  - Entra ID (Azure AD) global administrator (optional if your have the cluster admins group already created)
- Pre-provisioned resources:
  - Virtual Network to connect the cluster to it.
  - Subnet inside that vnet (optional if you want the script to create it)"
echo_green "----------------------------------- "

echo_cyan "Variables log file will be: $vars_file" && log ""

cluster_name=$(input_question "Please enter the name of the cluster")
log export CLUSTER_NAME="$cluster_name"

cluster_location=$(input_question "Please enter the cluster location (Example: westeurope or uaenorth)")
log export CLUSTER_LOCATION="$cluster_location"

vnet_resource_group=$(input_question "Please enter the Resource-Group for the VNET")
log export VNET_RRSOURCE_GROUP="$vnet_resource_group"

vnet_name=$(input_question "Please enter the vnet name")
log export VNET_NAME="$vnet_name"

subnet_name=$(input_question "Please enter the Subnet name")
log export SUBNET_NAME="$subnet_name"

is_snet_created=$(yes_no_question "Do you have the subnet ALREADY Created?")

if [ "$is_snet_created" == 'y' ]; then
  echo_green "Getting exisiting subnet... "
  vnet_id=$(az network vnet show --resource-group "$vnet_resource_group" --name "$vnet_name" --query id -o tsv)
  log export VNET_ID="$vnet_id"
  subnet_id=$(az network vnet subnet show --resource-group "$vnet_resource_group" --vnet-name "$vnet_name" --name "$subnet_name" --query id -o tsv)
  log export SUBNET_ID="$subnet_id"
else
  subnet_address_prefix=$(input_question "Ok! What is the address-prefix for the subnet? (Example: 10.179.128.0/21)")
  echo_green "Creating subnet for AKS cluster... "
  vnet_id=$(az network vnet show --resource-group "$vnet_resource_group" --name "$vnet_name" --query id -o tsv)
  log export VNET_ID="$vnet_id"
  subnet_id=$(az network vnet subnet create -n aks-subnet -g "$vnet_resource_group" --vnet-name "$vnet_name" --address-prefix "$subnet_address_prefix" --query "id" -o tsv)
  log export SUBNET_ID="$subnet_id"
  echo_green "Subnet $subnet_id has been created!... "
fi

network_plugins=(
  "Kubenet (kubenet): Each pod is assigned a logically different IP address from the subnet for simpler setup"
  "Azure CNI (azure): Each pod and node is assigned a unique IP for advanced configurations")
cluster_network=$(select_item "Choose cluster network configuration" "${network_plugins[@]}")

log export CLUSTER_NETWORK="$cluster_network"

echo_green "Geting tenant ID... "
tenant_id=$(az account show --query tenantId -o tsv)

is_aad_group_created=$(yes_no_question "Do you have an existing Entra ID (Azure AD) Group to use?")

if [ "$is_aad_group_created" == 'y' ]; then
  aad_existing_group_name=$(input_question "What is the group name to use?")
  log export AAD_GROUP_NAME="$aad_existing_group_name"

  aad_group_id=$(az ad group show -g "$aad_existing_group_name" --query id -o tsv)
  log export AAD_GROUP_ID="$aad_group_id"
else
  aad_new_group_name=$(input_question "What is the group name to create?")
  log export AAD_NEW_GROUP_NAME="$aad_new_group_name"

  echo_green "Creating AD Group.."
  aad_group_id=$(az ad group create \
    --display-name "$aad_new_group_name" \
    --mail-nickname "$aad_new_group_name" \
    --query id -o tsv)
  echo_green "AD Group $aad_new_group_name has been created !"
  log export AAD_GROUP_ID="$aad_group_id"
fi

echo_green "Now let's configure System and User node pools for the cluster: "
echo_green "System node pools serve the primary purpose of hosting critical$color_cyan system pods$color_reset such as CoreDNS, konnectivity, metrics-server... "

system_node_count=$(input_question "What is the count of System node pools? (2 or higher is recommended)")
log export SYSTEM_NODE_COUNT="$system_node_count"
echo_italic "System node pools count will be $system_node_count "

system_node_size=$(input_question "What is the system node pools VM Size? (example: Standard_DS4_v2)")
log export SYSTEM_NODE_SIZE="$system_node_size"
echo_italic "System node pools VM Size will be $system_node_size "

echo_green "User node pools serve the primary purpose of $color_cyan hosting your application pods.$color_reset"

user_node_count=$(input_question "What is the user node pools count? (3 or higher$color_cyan odd number$color_reset is recommended)")
log export USER_NODE_COUNT="$user_node_count"

echo_italic "User node pools count will be $user_node_count.  "

user_node_size=$(input_question "What is the user node pools VM Size? (example: Standard_D8s_v3)")
log export USER_NODE_SIZE="$user_node_size"
echo_italic "User node pools VM Size will be $user_node_size  "

echo_green "Current supported kubernetes versions for AKS in $color_cyan$cluster_location$color_reset region:"
az aks get-versions --location "$cluster_location" --output table

k8s_highest_version=$(az aks get-versions --location "$cluster_location" --output json --query 'values[?isPreview == `null`].patchVersions[].keys(@)[] | max(@)')

k8s_version=$(input_question "Specify kubernetes version for the cluster: (Example: $k8s_highest_version)")
log export K8S_VERSION="$k8s_version"

cluster_resource_group=$(input_question "What is the Resource Group for the Cluster?")
log export CLUSTER_RESOURCE_GRPUP="$cluster_resource_group"

echo_green "We will User-assigned Managed Identity for the cluster"
managed_identity_name=$(input_question "What is the name of your Managed Identity to use/create ?")
log export MANAGED_IDENTITY_NAME="$managed_identity_name"
managed_identity_id=$(az identity create --name "$managed_identity_name" --resource-group "$cluster_resource_group" --query "id" | tr -d '"')
log export MANAGED_IDENTITY_ID="$managed_identity_id"

os_skus=(
  "Azure Linux (AzureLinux) - Recommened"
  "Ubuntu (ubuntu)")
os_sku=$(select_item "Choose cluster host OS" "${os_skus[@]}")
log export OS_SKU="$os_sku"

cluster_tiers=(
  "Standard (standard) - Recommended"
  "Free (free) - NO financially backed API server uptime SLA!"
)

cluster_tier=$(select_item "Choose cluster pricing tier" "${cluster_tiers[@]}")
log export CLUSTER_TIER="$cluster_tier"

host_windows_node=$(yes_no_question "Would this cluster host Windows Nodes?")
log export HOST_WINDOWS_NODE="$host_windows_node"

if [ "$host_windows_node" == 'y' ]; then
  windows_node_username=$(input_question "Please provide username for Windows Nodes?")
  log export WINDOWS_NODE_USERNAME="$windows_node_username"

  windows_node_password=$(input_question "Please provide password for Windows Nodes?")
  log export WINDOWS_NODE_PASSWORD=

  echo_green "Creating Windows-based Cluster..."
  az aks create \
    --resource-group "$cluster_resource_group" \
    --name "$cluster_name" \
    --location "$cluster_location" \
    --generate-ssh-keys \
    --node-count "$system_node_count" \
    --node-vm-size="$system_node_size" \
    --vm-set-type VirtualMachineScaleSets \
    --windows-admin-username "$windows_node_username" \
    --windows-admin-password "$windows_node_password" \
    --network-plugin azure \
    --vnet-subnet-id "$subnet_id" \
    --service-cidr 172.171.0.0/16 \
    --dns-service-ip 172.171.0.10 \
    --enable-aad \
    --aad-admin-group-object-ids "$aad_group_id" \
    --aad-tenant-id "$tenant_id" \
    --enable-managed-identity \
    --assign-identity "$managed_identity_id" \
    --kubernetes-version "$k8s_version" \
    --nodepool-name "$systempool_name" \
    --os-sku "$os_sku" \
    --tier "$cluster_tier"

else
  echo_green "Creating Linux-based Cluster... "
  az aks create \
    --resource-group "$cluster_resource_group" \
    --name "$cluster_name" \
    --location "$cluster_location" \
    --generate-ssh-keys \
    --node-count "$system_node_count" \
    --node-vm-size "$system_node_size" \
    --vm-set-type VirtualMachineScaleSets \
    --network-plugin "$cluster_network" \
    --vnet-subnet-id "$subnet_id" \
    --service-cidr 172.171.0.0/16 \
    --dns-service-ip 172.171.0.10 \
    --enable-aad \
    --aad-admin-group-object-ids "$aad_group_id" \
    --aad-tenant-id "$tenant_id" \
    --enable-managed-identity \
    --assign-identity "$managed_identity_id" \
    --kubernetes-version "$k8s_version" \
    --nodepool-name "$systempool_name" \
    --os-sku "$os_sku" \
    --tier "$cluster_tier"
fi

if [ $? -eq 0 ]; then
  echo_green "Adding User Node Pool $workerpool_name to the cluster... "

  az aks nodepool add \
    --cluster-name "$cluster_name" \
    --name "$workerpool_name" \
    --resource-group "$cluster_resource_group" \
    --mode User \
    --node-count "$user_node_count" \
    --node-vm-size "$user_node_size" \
    --kubernetes-version "$k8s_version" \
    --os-sku "$os_sku"

  echo_green "Congratulation AKS Cluster $cluster_name has been created! "
  echo_green "Logging into Cluster Now... "

  az aks get-credentials --name "$cluster_name" --resource-group "$cluster_resource_group" --overwrite-existing --admin
  kubelogin convert-kubeconfig -l azurecli

  if [ $? -eq 0 ]; then
    attach_acr=$(yes_no_question "Do you want to Attach Azure Container Registry to the cluster ?")
    log export ATTACH_ACR="$attach_acr"

    if [ "$attach_acr" == 'y' ]; then
      acr_name=$(input_question "What is the Azure Container Register Name?")
      log export ACR_NAME="$acr_name"
      az aks update --name "$cluster_name" -g "$cluster_resource_group" --attach-acr "$acr_name"
    else
      echo -e "."
    fi

    echo_green "Congratulation you have created Managed AAD Cluster with Managed Identity"
    echo_green "Listing all deployments in all namespaces"
    kubectl get deployments --all-namespaces=true

  fi
else
  echo_red "Failed to create the cluster!"
fi
