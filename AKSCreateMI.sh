#!/bin/bash

set -e

ANSI_COLOR_GREEN=$'\e[0;32m'
ANSI_COLOR_GREEN_LIGHT=$'\e[0;92m'
ANSI_COLOR_RED=$'\e[31m'
ANSI_COLOR_CYAN=$'\e[0;36m'
ANSI_RESET=$'\e[0m'
ANSI_ITALIC=$'\e[3m'
ANSI_BOLD=$'\e[1m'
SYSTEMPOOL_NAME=syspool001
WORKERPOOL_NAME=usrpool001
TIMESTAMP=$(date +"%y%m%d-%H%M%S")
vars_file="vars-$TIMESTAMP.txt"

pod_cidr='172.16.0.0/16'
services_cidr='172.17.0.0/16'
dns_service_ip='172.17.0.10'

function echo_lightgreen() {
    echo -e "${ANSI_COLOR_GREEN_LIGHT}$*${ANSI_RESET}"
}

function echo_green() {
    echo -e "${ANSI_COLOR_GREEN}$*${ANSI_RESET}"
}

function echo_cyan() {
    echo -e "${ANSI_COLOR_CYAN}$*${ANSI_RESET}"
}

function echo_red() {
    echo -e "${ANSI_COLOR_RED}$*${ANSI_RESET}"
}

function echo_italic() {
    echo -e "${ANSI_ITALIC}$*${ANSI_RESET}"
}

function echo_bold() {
    echo -e "${ANSI_BOLD}$*${ANSI_RESET}"
}

function yes_no_question() {
    local input
    local prompt="$1 [Y/n]: "
    local default="${2:-Y}"

    while read -e -p "$prompt" -r -n 1 input && ! [[ "$input" =~ ^[YyNn]?$ ]]; do
        echo "Invalid input. Please enter 'Y', 'N', or press Enter for $default." >&2
    done

    echo "${input:-$default}" | tr '[:upper:]' '[:lower:]'
}

function input_question() {
    local prompt_message="$1: "
    local input_value
    while [[ -z "$input_value" ]]; do
        #read -p -e "$prompt_message" -r input_value
        echo -n -e "${ANSI_BOLD}$prompt_message${ANSI_RESET}" >&2
        read -r input_value
        if [[ -z "$input_value" ]]; then
            echo "Input cannot be empty. Please try again." >&2
        fi
    done

    echo "$input_value"
}
function select_item() {
    local items=("$@")
    local select_message="$1"

    if [[ -z "$select_message" ]]; then
        echo "Error: The first argument is empty." >&2
        return 1
    fi

    local items_to_select=("${items[@]:1}") # Exclude the first element

    if [[ ${#items_to_select[@]} -eq 0 ]]; then
        echo "The list is empty!" >&2
        return
    fi

    echo_bold "$select_message: " >&2
    PS3="Select the choice number #: "
    select option in "${items_to_select[@]}"; do
        if [[ -n "$option" ]]; then
            # this is for the selected value. The selected value should be between [ and ] like: This is main item [main]
            if [[ $option =~ \[(.+)\] ]]; then
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

function convert_to_array() {
    # Original IFS value backup
    original_ifs="$IFS"

    local input_string="$1"

    # Set IFS to a specific delimiter
    IFS=$'\n'

    # Convert the string to an array
    local result_array=($input_string)

    # Restore the original IFS value
    IFS="$original_ifs"

    # Return the array
    echo "${result_array[@]}"
}

if [ -n "$1" ]; then
    vars_file=$1
fi

cat <<EOF

░█▀█░█░█░█▀▀░░░█▀█░█▀▄░█▀█░█░█░▀█▀░█▀▀░▀█▀░█▀█░█▀█░█▀▀░█▀▄
░█▀█░█▀▄░▀▀█░░░█▀▀░█▀▄░█░█░▀▄▀░░█░░▀▀█░░█░░█░█░█░█░█▀▀░█▀▄
░▀░▀░▀░▀░▀▀▀░░░▀░░░▀░▀░▀▀▀░░▀░░▀▀▀░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░▀


EOF

echo_green "Hi!, This script will help you create Azure Kubernetes Services https://azure.microsoft.com/en-us/products/kubernetes-service"
echo_green "These are the prerequisistes needed: 
- Permissions:
    - Azure Subscription Owner
    - Entra ID (Azure AD) global administrator (optional if your have the cluster admins group already created)
- Pre-provisioned resources:
    - Virtual Network to connect the cluster to it.
    - Subnet inside that vnet (optional if you want the script to create it)"
echo_green "----------------------------------- "

echo_cyan "Variables log file will be: $vars_file" && log ""

echo_green "We're using the following subscription" && echo ""
az account show --query "{subscriptionName:name, subscriptionId:id}" --output table

echo ""
echo_green "Cluster Name"

CLUSTER_NAME=$(input_question "Please enter the name of the cluster")
log export CLUSTER_NAME="$CLUSTER_NAME"

echo_green "Cluster Location (Region)"
recommened_regions=(
    "(Europe) North Europe [northeurope]"
    "(Europe) West Europe [westeurope]"
    "(Europe) France Central [francecentral]"
    "(Middle East) UAE North [uaenorth]"
    "(Middle East) Qatar Central [qatarcentral]"
    "(Asia Pacific) Central India [centralindia]"
    "(US) East US [eastus]"
    "Type another location (region) [_] https://azure.microsoft.com/en-us/explore/global-infrastructure/geographies/#choose-your-region"
)
CLUSTER_LOCATION=$(select_item "Choose cluster location" "${recommened_regions[@]}")

if [ "$CLUSTER_LOCATION" == '_' ]; then
    CLUSTER_LOCATION=$(input_question "Please enter the cluster location (Example: westeurope or uaenorth)")
fi
log export CLUSTER_LOCATION="$CLUSTER_LOCATION"

all_resourceGroups=$(az group list --query '[].{name:name, location:location}' --output tsv | awk '{print "[" $1 "] (" $2 ") "}' | sort)
ifs_current=$IFS && IFS=$'\n' all_resourceGroups=($all_resourceGroups) && IFS=$ifs_current

echo_green "Cluster Network Connectivity"

VNET_RRSOURCE_GROUP=
while [[ -z $VNET_RRSOURCE_GROUP ]]; do

    vnet_inputs=(
        "Create new VNET [new]."
        "Use existing VNET [existing]."
    )
    VNET_INPUT=$(select_item "Do you want to create a new *virtual network* (vnet) or use an existing one?" "${vnet_inputs[@]}")

    if [ "$VNET_INPUT" == 'new' ]; then

        echo_lightgreen "Creating a new virual network"
        VNET_RRSOURCE_GROUP=$(select_item "Select vnet resource group" "${all_resourceGroups[@]}")
        log export VNET_RRSOURCE_GROUP="$VNET_RRSOURCE_GROUP"

        VNET_NAME=$(input_question "Please enter the vnet name")
        log export VNET_NAME="$VNET_NAME"
        subnet_address_prefix=$(input_question "Ok! What is the address-prefix for the subnet? (Example: 10.179.128.0/21)")
        echo_green "Creating subnet for AKS cluster... "
        VNET_ID=$(az network vnet show --resource-group "$VNET_RRSOURCE_GROUP" --name "$VNET_NAME" --query id -o tsv)
        log export VNET_ID="$VNET_ID"
        SUBNET_ID=$(az network vnet subnet create -n aks-subnet -g "$VNET_RRSOURCE_GROUP" --vnet-name "$VNET_NAME" --address-prefix "$subnet_address_prefix" --query "id" -o tsv)
        log export SUBNET_ID="$SUBNET_ID"
        echo_green "Subnet $SUBNET_ID has been created!... "
    else
        echo_lightgreen "Using an existing virtual network"
        all_vnets_json=$(az network vnet list --query "[?location==\`${CLUSTER_LOCATION}\`].{name:name, resourceGroup:resourceGroup, location:location, id:id}" --output json)

        all_vnets=$(echo "$all_vnets_json" | jq -r '.[] | "\(.name) [\(.name)|\(.resourceGroup)]"' | sort)

        selected_vnet=$(select_item "Select VNET resource group which is located at $CLUSTER_LOCATION. (vnet should be located in the same region of the cluster)" "${all_vnets[@]}")

        if [[ -z $selected_vnet ]]; then
            echo "Looks like you don't have vnets for the selected region: ${CLUSTER_LOCATION}. Please try again." >&2
            continue
        fi

        ifs_current=$IFS && IFS='|' read -r VNET_NAME VNET_RRSOURCE_GROUP <<<"$selected_vnet" && IFS=$ifs_current

        VNET_ID=$(echo "$all_vnets_json" | jq --arg target_name "$VNET_NAME" --arg target_rg "$VNET_RRSOURCE_GROUP" '.[] | select(.name == $target_name and .resourceGroup == $target_rg) | .id')
        echo_green "Selected VNET details:"
        echo_green "    Name: $VNET_NAME"
        echo_green "    Resource Group: $VNET_RRSOURCE_GROUP"
        echo_green "    Location: $CLUSTER_LOCATION"
        echo_green "    ID: $VNET_ID"

        all_subnets=$(az network vnet subnet list --resource-group "$VNET_RRSOURCE_GROUP" --vnet-name "$VNET_NAME" --query '[].{name:name, addressPrefix:addressPrefix}' -o tsv | awk '{print "[" $1 "] (" $2 ")" }')
        ifs_current=$IFS && IFS=$'\n' all_subnets=($all_subnets) && IFS=$ifs_current

        SUBNET_NAME=$(select_item "Select subnet" "${all_subnets[@]}")

        SUBNET_ID=$(az network vnet subnet show --resource-group "$VNET_RRSOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME" --query id -o tsv)

        log export VNET_ID="$VNET_ID"
        log export VNET_NAME="$VNET_NAME"
        log export VNET_RRSOURCE_GROUP="$VNET_RRSOURCE_GROUP"
        log export SUBNET_NAME="$SUBNET_NAME"
        log export SUBNET_ID="$SUBNET_ID"
    fi
done

echo_green "Cluster Network Plugin"

network_plugins=(
    "Azure CNI [azure]: Each pod and node is assigned a unique IP for advanced configurations. (Linux & Windows)"
    "Kubenet [kubenet]: Each pod is assigned a logically different IP address from the subnet for simpler setup. (Linux Only)"
)
CLUSTER_NETWORK=$(select_item "Choose cluster network configuration" "${network_plugins[@]}")

if [ "$CLUSTER_NETWORK" == 'kubenet' ]; then
    echo_green "Cluster Pods CIDR for kubenet network plugin"
    POD_CIDR=$(input_question "What is the group name to use? (Example: ${pod_cidr})")
    log export POD_CIDR="$POD_CIDR"
fi

echo_green "Kubernetes service address range. A CIDR notation IP range from which to assign service cluster IPs. It must not overlap with any Subnet IP ranges."
SERVICES_CIDR=$(input_question "What is the services CIDR to use? (Example: ${services_cidr})")
log export SERVICES_CIDR="$SERVICES_CIDR"

echo_green "Kubernetes DNS service IP address. An IP address assigned to the Kubernetes DNS service. It must be within the Kubernetes service address range."
DNS_SERVICE_IP=$(input_question "What is the DNS service IP to use? (Example: ${dns_service_ip})")
log export DNS_SERVICE_IP="$DNS_SERVICE_IP"

log export CLUSTER_NETWORK="$CLUSTER_NETWORK"

echo_green "Getting tenant ID... "
TENANT_ID=$(az account show --query tenantId -o tsv)
log export TENANT_ID="$TENANT_ID"

echo_lightgreen "Using Tenant ID: $TENANT_ID"

echo_green "Cluster RBAC Access Control"
is_aad_group_created=$(yes_no_question "Do you have an existing Entra ID (Azure AD) Group to use?")

if [ "$is_aad_group_created" == 'y' ]; then
    aad_existing_group_name=$(input_question "What is the group name to use?")
    log export AAD_GROUP_NAME="$aad_existing_group_name"

    AAD_GROUP_ID=$(az ad group show -g "$aad_existing_group_name" --query id -o tsv)
    log export AAD_GROUP_ID="$AAD_GROUP_ID"
else
    aad_new_group_name=$(input_question "What is the group name to create?")
    log export AAD_NEW_GROUP_NAME="$aad_new_group_name"

    echo_green "Creating AD Group.."
    AAD_GROUP_ID=$(az ad group create \
        --display-name "$aad_new_group_name" \
        --mail-nickname "$aad_new_group_name" \
        --query id -o tsv)
    echo_lightgreen "AD Group $aad_new_group_name has been created !"
    log export AAD_GROUP_ID="$AAD_GROUP_ID"
fi

echo_green "Cluster SYSTEM and USER node pools"
echo_lightgreen "System node pools serve the primary purpose of hosting critical ${ANSI_COLOR_CYAN}system pods${ANSI_COLOR_GREEN_LIGHT} such as CoreDNS, konnectivity, metrics-server... "

SYSTEM_NODE_COUNT=$(input_question "What is the count of System node pools? (2 or higher is recommended)")
log export SYSTEM_NODE_COUNT="$SYSTEM_NODE_COUNT"
echo_italic "System node pools count will be $SYSTEM_NODE_COUNT "

system_node_sizes=(
    "Standard  D2ds v5  [Standard_D2ds_v5] -  2 vCPUs |  8 GiB Memory |  75 GiB SSD Temp Storage"
    "Standard  D4ds v5  [Standard_D4ds_v5] -  4 vCPUs | 16 GiB Memory | 150 GiB SSD Temp Storage"
    "Standard  D8ds v5  [Standard_D8ds_v5] -  8 vCPUs | 32 GiB Memory | 300 GiB SSD Temp Storage"
    "Standard D16ds v5 [Standard_D16ds_v5] - 16 vCPUs | 64 GiB Memory | 600 GiB SSD Temp Storage"
    "Type another size [_] - https://learn.microsoft.com/en-us/azure/virtual-machines/sizes"
)
SYSTEM_NODE_SIZE=$(select_item "What is the system node pools VM Size?" "${system_node_sizes[@]}")

if [ "$SYSTEM_NODE_SIZE" == '_' ]; then
    SYSTEM_NODE_SIZE=$(input_question "What is the system node pools VM Size? (example: Standard_DS4_v2)")
fi

log export SYSTEM_NODE_SIZE="$SYSTEM_NODE_SIZE"
echo_italic "System node pools VM Size will be $SYSTEM_NODE_SIZE"

echo_lightgreen "User node pools serve the primary purpose of ${ANSI_COLOR_CYAN}hosting your application pods.${ANSI_RESET}"

USER_NODE_COUNT=$(input_question "What is the user node pools count? (3 or higher${ANSI_COLOR_CYAN} odd number${ANSI_RESET} is recommended)")
log export USER_NODE_COUNT="$USER_NODE_COUNT"

echo_italic "User node pools count will be $USER_NODE_COUNT."

user_node_sizes=(
    "Standard  D2ds v5  [Standard_D2ds_v5] -  2 vCPUs |  8 GiB Memory |  75 GiB SSD Temp Storage"
    "Standard  D4ds v5  [Standard_D4ds_v5] -  4 vCPUs | 16 GiB Memory | 150 GiB SSD Temp Storage"
    "Standard  D8ds v5  [Standard_D8ds_v5] -  8 vCPUs | 32 GiB Memory | 300 GiB SSD Temp Storage"
    "Standard D16ds v5 [Standard_D16ds_v5] - 16 vCPUs | 64 GiB Memory | 600 GiB SSD Temp Storage"
    "Type another size [_] - https://learn.microsoft.com/en-us/azure/virtual-machines/sizes"
)
USER_NODE_SIZE=$(select_item "What is the system node pools VM Size?" "${user_node_sizes[@]}")

if [ "$USER_NODE_SIZE" == '_' ]; then
    USER_NODE_SIZE=$(input_question "What is the user node pools VM Size? (example: Standard_D8s_v5)")
fi

log export USER_NODE_SIZE="$USER_NODE_SIZE"
echo_italic "User node pools VM Size will be $USER_NODE_SIZE"

echo_green "Cluster kubernetes version"
location_k8s_versions=$(az aks get-versions --location "$CLUSTER_LOCATION" --output json --query 'values[?isPreview == `null`].patchVersions[].keys(@)[]' | jq -r '.[] | "[\(.)]"' | sort -r)
ifs_current=$IFS && IFS=$'\n' location_k8s_versions=($location_k8s_versions) && IFS=$ifs_current
K8S_VERSION=$(select_item "Select the kubernetes version from ${CLUSTER_LOCATION} available versions" "${location_k8s_versions[@]}")
log export K8S_VERSION="$K8S_VERSION"

CLUSTER_RESOURCE_GRPUP=$(select_item "Select cluster resource group" "${all_resourceGroups[@]}")
log export CLUSTER_RESOURCE_GRPUP="$CLUSTER_RESOURCE_GRPUP"

echo_green "Cluster Managed Identity"
echo_lightgreen "We will User-assigned Managed Identity for the cluster"
managed_identity_name=$(input_question "What is the name of your Managed Identity to use/create ?")

MANAGED_IDENTITY_ID=$(az identity create --name "$managed_identity_name" --resource-group "$CLUSTER_RESOURCE_GRPUP" --query "id" | tr -d '"')
log export MANAGED_IDENTITY_ID="$MANAGED_IDENTITY_ID"

echo_green "Cluster host OS"
os_skus=(
    "Azure Linux [AzureLinux] - RECOMMENDED."
    "Ubuntu [ubuntu].")
OS_SKU=$(select_item "Choose cluster host OS" "${os_skus[@]}")
log export OS_SKU="$OS_SKU"

echo_green "Cluster price and SLA tier"
cluster_tiers=(
    "Standard [standard] - RECOMMENDED."
    "Free [free] - NO financially backed API server uptime SLA!"
)
CLUSTER_TIER=$(select_item "Choose cluster pricing tier" "${cluster_tiers[@]}")
log export CLUSTER_TIER="$CLUSTER_TIER"

echo_green "Cluster connected Container Registry"
attach_acr=$(yes_no_question "Do you want to Attach Azure Container Registry to the cluster ?")

if [ "$attach_acr" == 'y' ]; then
    available_acrs=$(az acr list --query '[].{name:name, loginServer:loginServer}' --output tsv | awk '{print "[" $1 "] (" $2 ")" }' | sort)
    ifs_current=$IFS && IFS=$'\n' available_acrs=($available_acrs) && IFS=$ifs_current
    ACR_NAME=$(select_item "Select the container registry" "${available_acrs[@]}")
    log export ACR_NAME="$ACR_NAME"
fi

# ask to create windows node pool only if selected Azure CNI
if [ "$CLUSTER_NETWORK" == 'azure' ]; then

    host_windows_node=$(yes_no_question "Would this cluster host Windows Nodes?")
    log export HOST_WINDOWS_NODE="$host_windows_node"
    if [ "$host_windows_node" == 'y' ]; then
        WINDOWS_NODE_USERNAME=$(input_question "Please provide username for Windows Nodes?")
        log export WINDOWS_NODE_USERNAME="$WINDOWS_NODE_USERNAME"

        WINDOWS_NODE_PASSWORD=$(input_question "Please provide password for Windows Nodes?")
        log export WINDOWS_NODE_PASSWORD="$WINDOWS_NODE_PASSWORD"
    fi
fi

start_provision=$(yes_no_question "Start the provisioning process now?")

if [ "$start_provision" == 'n' ]; then
    echo_red "Cancelling the cluster provisioning!!"
    exit 0
fi

echo_lightgreen "Starting the provisioning process..."

if [ "$host_windows_node" == 'y' ]; then
    echo_lightgreen "Creating Windows-based Cluster..."
    az aks create \
        --resource-group "$CLUSTER_RESOURCE_GRPUP" \
        --name "$CLUSTER_NAME" \
        --location "$CLUSTER_LOCATION" \
        --generate-ssh-keys \
        --node-count "$SYSTEM_NODE_COUNT" \
        --node-vm-size="$SYSTEM_NODE_SIZE" \
        --vm-set-type VirtualMachineScaleSets \
        --windows-admin-username "$WINDOWS_NODE_USERNAME" \
        --windows-admin-password "$WINDOWS_NODE_PASSWORD" \
        --network-plugin azure \
        --vnet-subnet-id "$SUBNET_ID" \
        --service-cidr $services_cidr \
        --dns-service-ip $dns_service_ip \
        --enable-aad \
        --aad-admin-group-object-ids "$AAD_GROUP_ID" \
        --aad-tenant-id "$TENANT_ID" \
        --enable-managed-identity \
        --assign-identity "$MANAGED_IDENTITY_ID" \
        --kubernetes-version "$K8S_VERSION" \
        --nodepool-name "$SYSTEMPOOL_NAME" \
        --os-sku "$OS_SKU" \
        --tier "$CLUSTER_TIER"

else
    echo_lightgreen "Creating Linux-based Cluster... "

    case "$CLUSTER_NETWORK" in
    azure)
        az aks create \
            --resource-group "$CLUSTER_RESOURCE_GRPUP" \
            --name "$CLUSTER_NAME" \
            --location "$CLUSTER_LOCATION" \
            --generate-ssh-keys \
            --node-count "$SYSTEM_NODE_COUNT" \
            --node-vm-size "$SYSTEM_NODE_SIZE" \
            --vm-set-type VirtualMachineScaleSets \
            --network-plugin "$CLUSTER_NETWORK" \
            --vnet-subnet-id "$SUBNET_ID" \
            --service-cidr "$SERVICES_CIDR" \
            --dns-service-ip "$DNS_SERVICE_IP" \
            --enable-aad \
            --aad-admin-group-object-ids "$AAD_GROUP_ID" \
            --aad-tenant-id "$TENANT_ID" \
            --enable-managed-identity \
            --assign-identity "$MANAGED_IDENTITY_ID" \
            --kubernetes-version "$K8S_VERSION" \
            --nodepool-name "$SYSTEMPOOL_NAME" \
            --os-sku "$OS_SKU" \
            --tier "$CLUSTER_TIER"
        ;;

    *)
        # default case: commands to create the cluster if CLUSTER_NETWORK doesn't match any of the above
        # kubenet
        az aks create \
            --resource-group "$CLUSTER_RESOURCE_GRPUP" \
            --name "$CLUSTER_NAME" \
            --location "$CLUSTER_LOCATION" \
            --generate-ssh-keys \
            --node-count "$SYSTEM_NODE_COUNT" \
            --node-vm-size "$SYSTEM_NODE_SIZE" \
            --vm-set-type VirtualMachineScaleSets \
            --network-plugin "$CLUSTER_NETWORK" \
            --vnet-subnet-id "$SUBNET_ID" \
            --pod-cidr "$POD_CIDR" \
            --service-cidr "$SERVICES_CIDR" \
            --dns-service-ip "$DNS_SERVICE_IP" \
            --enable-aad \
            --aad-admin-group-object-ids "$AAD_GROUP_ID" \
            --aad-tenant-id "$TENANT_ID" \
            --enable-managed-identity \
            --assign-identity "$MANAGED_IDENTITY_ID" \
            --kubernetes-version "$K8S_VERSION" \
            --nodepool-name "$SYSTEMPOOL_NAME" \
            --os-sku "$OS_SKU" \
            --tier "$CLUSTER_TIER"
        ;;
    esac
fi

if [ $? -eq 0 ]; then
    echo_lightgreen "Adding User Node Pool ${ANSI_COLOR_CYAN}$WORKERPOOL_NAME${ANSI_COLOR_GREEN_LIGHT} to the cluster... "

    az aks nodepool add \
        --cluster-name "$CLUSTER_NAME" \
        --name "$WORKERPOOL_NAME" \
        --resource-group "$CLUSTER_RESOURCE_GRPUP" \
        --mode User \
        --node-count "$USER_NODE_COUNT" \
        --node-vm-size "$USER_NODE_SIZE" \
        --kubernetes-version "$K8S_VERSION" \
        --os-sku "$OS_SKU"

    echo_green "Congratulation AKS Cluster ${ANSI_COLOR_CYAN}$CLUSTER_NAME${ANSI_COLOR_GREEN_LIGHT} has been created! "

    if [ "$attach_acr" == 'y' ]; then
        echo_green "Attaching $ACR_NAME Azure Container Registry to the cluster"
        az aks update --name "$CLUSTER_NAME" -g "$CLUSTER_RESOURCE_GRPUP" --attach-acr "$ACR_NAME"
    else
        echo_italic "Skipping attaching Azure Container Registry to the cluster."
    fi

    echo_green "Congratulation you have created Managed AAD Cluster with Managed Identity"

    echo_cyan "Variables log filenem: $vars_file"

    if [ $? -eq 0 ]; then
        echo_green "Logging into Cluster Now... "

        az aks get-credentials --name "$CLUSTER_NAME" --resource-group "$CLUSTER_RESOURCE_GRPUP" --overwrite-existing --admin
        kubelogin convert-kubeconfig -l azurecli

        echo_green "Listing all deployments in all namespaces"
        kubectl get deployments --all-namespaces=true -o wide
    fi
else
    echo_red "Failed to create the cluster!"
fi
