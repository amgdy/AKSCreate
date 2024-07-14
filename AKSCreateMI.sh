#!/bin/bash

set -e

ANSI_COLOR_GREEN=$'\e[0;32m'
ANSI_COLOR_GREEN_LIGHT=$'\e[0;92m'
ANSI_COLOR_RED=$'\e[31m'
ANSI_COLOR_CYAN=$'\e[0;36m'
ANSI_COLOR_YELLOW=$'\e[0;33m'
ANSI_RESET=$'\e[0m'
ANSI_ITALIC=$'\e[3m'
ANSI_BOLD=$'\e[1m'
SYSTEMPOOL_NAME=syspool001
WORKERPOOL_NAME=usrpool001
WINPOOL_NAME=winnp1
TIMESTAMP=$(date +"%y%m%d-%H%M%S")
vars_file="logs/vars-$TIMESTAMP.txt"

pod_cidr='172.16.0.0/16'
services_cidr='172.17.0.0/16'
dns_service_ip='172.17.0.10'

network_params=()
cluster_params=()
workerpool_params=()

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

function echo_yellow() {
    local message="$*"
    echo -e "${ANSI_COLOR_YELLOW}${message}${ANSI_RESET}"
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
        echo "Invalid response. Please enter 'Y' for Yes, 'N' for No, or press Enter to accept the default ($default)." >&2
    done

    echo "${input:-$default}" | tr '[:upper:]' '[:lower:]'
}

function input_question() {
    local prompt_message="$1: "
    local input_value
    while [[ -z "$input_value" ]]; do
        echo -n -e "${ANSI_BOLD}$prompt_message${ANSI_RESET}" >&2
        read -r input_value
        if [[ -z "$input_value" ]]; then
            echo "Your input is required. Please provide a valid response." >&2
        fi
    done

    echo "$input_value"
}

function select_item() {
    local items=("$@")
    local select_message="$1"

    if [[ -z "$select_message" ]]; then
        echo "Error: The selection prompt is empty. Please provide a valid prompt." >&2
        return 1
    fi

    local items_to_select=("${items[@]:1}") # Exclude the first element

    if [[ ${#items_to_select[@]} -eq 0 ]]; then
        echo "Error: The list of items to select from is empty. Please provide a valid list." >&2
        return
    fi

    echo_bold "$select_message: " >&2
    PS3="Please enter the number corresponding to your choice: "
    select option in "${items_to_select[@]}"; do
        if [[ -n "$option" ]]; then
            # this is for the selected value. The selected value should be between [ and ] like: This is main item [main]
            if [[ $option =~ \[(.+)\] ]]; then
                local selected_item="${BASH_REMATCH[1]}"
                echo_italic "You've selected: $option" >&2
                echo "$selected_item"
                break
            else
                echo "Error: The selected item's format is invalid. Please try again." >&2
            fi
        else
            echo "Error: The selection is invalid. Please try again." >&2
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

mkdir -p logs

if [ -n "$1" ]; then
    vars_file=$1
fi

cat <<EOF

░█▀█░█░█░█▀▀░░░█▀█░█▀▄░█▀█░█░█░▀█▀░█▀▀░▀█▀░█▀█░█▀█░█▀▀░█▀▄
░█▀█░█▀▄░▀▀█░░░█▀▀░█▀▄░█░█░▀▄▀░░█░░▀▀█░░█░░█░█░█░█░█▀▀░█▀▄
░▀░▀░▀░▀░▀▀▀░░░▀░░░▀░▀░▀▀▀░░▀░░▀▀▀░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░▀

EOF

echo_green "Welcome. This script will guide you through the process of creating an Azure Kubernetes Service (AKS) cluster. For more information about AKS, please visit: https://azure.microsoft.com/en-us/products/kubernetes-service"
echo_green "Before we begin, please ensure you have the following prerequisites: 
- Permissions:
    - Azure Subscription Owner
    - Global Administrator for Azure Active Directory (optional if your cluster admins group is already created)
- Pre-provisioned resources:
    - A Virtual Network for the cluster connection.
    - An optional subnet within the Virtual Network (the script can create this if not already present)."
echo_green "----------------------------------- "

echo_cyan "The log file for variables will be stored at: $vars_file" && log ""

echo_green "The current Azure subscription in use is:" && echo ""
az account show --query "{subscriptionName:name, subscriptionId:id}" --output table

echo_cyan "ensuring that you have the latest aks-preview command module installed before we start ..."
az extension update --name aks-preview --allow-preview true

echo ""
GPU_ENABLED=$(yes_no_question "Will the cluster require GPU capabilities?")
log export GPU_ENABLED="$GPU_ENABLED"

if [ "$GPU_ENABLED" == 'y' ]; then
    WORKERPOOL_NAME=gpupool001
    echo_lightgreen "Initiating the registration of GPU-enabled AKS feature in the subscription."
    status=$(az feature show --namespace "Microsoft.ContainerService" --name "GPUDedicatedVHDPreview" --query "properties.state" --output tsv)
    if [ "$status" == "Registered" ]; then
        echo "The feature is already registered."
    else
        echo "Activating feature. Please note, this process can take up to 15 minutes."
        echo "Start time: $(date "+%Y-%m-%d %H:%M:%S")"
        az feature register --namespace "Microsoft.ContainerService" --name "GPUDedicatedVHDPreview"
        echo "Awaiting feature registration..."

        while true; do
            # Get the current status
            status=$(az feature show --namespace "Microsoft.ContainerService" --name "GPUDedicatedVHDPreview" --query "properties.state" --output tsv)

            # Check if the status is "Registered"
            if [ "$status" == "Registered" ]; then
                break
            fi

            # Wait for a while before checking again (adjust the sleep duration as needed)
            sleep 10
        done
        az provider register --namespace Microsoft.ContainerService
        echo "Completion time: $(date "+%Y-%m-%d %H:%M:%S")"
        echo_green "Feature registration successful."

    fi

    workerpool_params+=(--node-taints sku=gpu:NoSchedule)
    workerpool_params+=(--aks-custom-headers UseGPUDedicatedVHD=true)
fi

cluster_params+=(--generate-ssh-keys)
cluster_params+=(--vm-set-type VirtualMachineScaleSets)
cluster_params+=(--load-balancer-sku standard)

echo_green "Cluster Name"
CLUSTER_NAME=$(input_question "Kindly provide the desired name for the cluster")
log export CLUSTER_NAME="$CLUSTER_NAME"
cluster_params+=(--name "$CLUSTER_NAME")

echo_green "Cluster Location (Region)"
recommended_regions=(
    "(Europe) North Europe [northeurope]"
    "(Europe) West Europe [westeurope]"
    "(Europe) France Central [francecentral]"
    "(Middle East) UAE North [uaenorth]"
    "(Middle East) Qatar Central [qatarcentral]"
    "(Asia Pacific) Central India [centralindia]"
    "(US) East US [eastus]"
    "Specify a different location (region) [_] https://azure.microsoft.com/en-us/explore/global-infrastructure/geographies/#choose-your-region"
)
CLUSTER_LOCATION=$(select_item "Please select the desired location for the cluster" "${recommended_regions[@]}")
if [ "$CLUSTER_LOCATION" == '_' ]; then
    CLUSTER_LOCATION=$(input_question "Kindly specify the cluster location (Example: westeurope or uaenorth)")
fi
log export CLUSTER_LOCATION="$CLUSTER_LOCATION"
cluster_params+=(--location "$CLUSTER_LOCATION")

all_resourceGroups=$(az group list --query '[].{name:name, location:location}' --output tsv | awk '{print "[" $1 "] (" $2 ") "}' | sort)
ifs_current=$IFS && IFS=$'\n' all_resourceGroups=($all_resourceGroups) && IFS=$ifs_current

CLUSTER_RESOURCE_GROUP=$(select_item "Please select the resource group for the cluster" "${all_resourceGroups[@]}")
log export CLUSTER_RESOURCE_GROUP="$CLUSTER_RESOURCE_GROUP"
cluster_params+=(--resource-group "$CLUSTER_RESOURCE_GROUP")

private_cluster=$(yes_no_question "Do you want to enable a private cluster to restrict worker node to API access for cluster: $CLUSTER_NAME?")
if [ "$private_cluster" == 'y' ]; then
    cluster_params+=(--enable-private-cluster)
    echo_lightgreen "Private AKS clusters do not have their API server accessible from the public internet. To access the private cluster, deploy it into a virtual network that is accessible from your computer or follow the AKS private cluster documentation."
fi

# if private_cluster is enabled then ask to Disable a public FQDN
if [ "$private_cluster" == 'y' ]; then
    disable_public_fqdn=$(yes_no_question "Do you want to disable the public FQDN for the cluster: $CLUSTER_NAME?")
    if [ "$disable_public_fqdn" == 'y' ]; then
        cluster_params+=(--disable-public-fqdn)
        echo_lightgreen "Public FQDN is disabled for the cluster."
    fi
fi

echo_green "Retrieving tenant ID... "
TENANT_ID=$(az account show --query tenantId -o tsv)
log export TENANT_ID="$TENANT_ID"

echo_lightgreen "Utilizing Tenant ID: $TENANT_ID"

echo_green "Enabling Entra ID (Azure AD) Authentication with Kubernetes RBAC"
echo_lightgreen "Configuring Cluster admin ClusterRoleBinding. Please note that Kubernetes local accounts will be enabled by default."
aad_group_status=$(yes_no_question "Do you have an existing Azure AD Group to utilize?")
if [ "$aad_group_status" == 'y' ]; then
    while true; do
        aad_group_name=$(input_question "Please provide the name of the group to use.")
        log export AAD_GROUP_NAME="$aad_group_name"

        AAD_GROUP_ID=$(az ad group show -g "$aad_group_name" --query id -o tsv)

        if [[ -n $AAD_GROUP_ID ]]; then
            log export AAD_GROUP_ID="$AAD_GROUP_ID"
            break
        else
            echo "It appears the group name you provided does not exist. Please try again." >&2
        fi
    done
else
    aad_group_name_new=$(input_question "Please provide the name of the group to create.")
    log export AAD_NEW_GROUP_NAME="$aad_group_name_new"

    echo_green "Creating Azure AD Group.."
    AAD_GROUP_ID=$(az ad group create \
        --display-name "$aad_group_name_new" \
        --mail-nickname "$aad_group_name_new" \
        --query id -o tsv)
    echo_lightgreen "Azure AD Group $aad_group_name_new has been successfully created."
    log export AAD_GROUP_ID="$AAD_GROUP_ID"
fi
cluster_params+=(--enable-aad --aad-admin-group-object-ids "$AAD_GROUP_ID" --aad-tenant-id "$TENANT_ID")

echo_bold "Node Pools Configuration"

echo_green "Configuring Cluster SYSTEM and USER node pools"
echo_lightgreen "System node pools are primarily used for hosting critical system pods such as CoreDNS, konnectivity, metrics-server... "

SYSTEM_NODE_COUNT=$(input_question "Please provide the count of System node pools. (A minimum of 2 is recommended)")
log export SYSTEM_NODE_COUNT="$SYSTEM_NODE_COUNT"
echo_italic "System node pools count has been set to $SYSTEM_NODE_COUNT "
cluster_params+=(--nodepool-name "$SYSTEMPOOL_NAME")
cluster_params+=(--node-count "$SYSTEM_NODE_COUNT")

system_node_sizes=(
    "Standard  D2ds v5  [Standard_D2ds_v5] -  2 vCPUs |  8 GiB Memory |  75 GiB SSD Temp Storage"
    "Standard  D4ds v5  [Standard_D4ds_v5] -  4 vCPUs | 16 GiB Memory | 150 GiB SSD Temp Storage"
    "Standard  D8ds v5  [Standard_D8ds_v5] -  8 vCPUs | 32 GiB Memory | 300 GiB SSD Temp Storage"
    "Standard D16ds v5 [Standard_D16ds_v5] - 16 vCPUs | 64 GiB Memory | 600 GiB SSD Temp Storage"
    "Specify a different size [_] - https://learn.microsoft.com/en-us/azure/virtual-machines/sizes"
)
SYSTEM_NODE_SIZE=$(select_item "Please select the VM Size for the system node pools." "${system_node_sizes[@]}")

if [ "$SYSTEM_NODE_SIZE" == '_' ]; then
    SYSTEM_NODE_SIZE=$(input_question "Please provide the VM Size for the system node pools. (Example: Standard_DS4_v2)")
fi

log export SYSTEM_NODE_SIZE="$SYSTEM_NODE_SIZE"
echo_italic "System node pools VM Size has been set to $SYSTEM_NODE_SIZE"
cluster_params+=(--node-vm-size "$SYSTEM_NODE_SIZE")

echo_green "Configuring System Node Pool host OS"
echo_lightgreen "Azure Linux on AKS offers a native, lightweight image built from validated source packages, designed specifically for Linux development in containers. It includes only essential packages, reducing the attack surface and eliminating the need for patching unnecessary packages. Its base layer features a Microsoft hardened kernel, optimized for Azure, ensuring secure and efficient container workloads."

syspool_os_skus=(
    "Azure Linux [AzureLinux] - RECOMMENDED."
    "Ubuntu [ubuntu].")
SYSPOOL_OS_SKU=$(select_item "Please select the host OS for the system node pool cluster" "${syspool_os_skus[@]}")
log export SYSPOOL_OS_SKU="$SYSPOOL_OS_SKU"
cluster_params+=(--os-sku "$SYSPOOL_OS_SKU")

# add max pods and make sure it should not exceed 250
while true; do
    system_nodes_max_pods=$(input_question "Please provide the maximum number of pods per node (30-250).")
    if [ "$system_nodes_max_pods" -gt 250 ]; then
        echo_red "The maximum number of pods per node should not exceed 250. Please try again."
    elif [ "$system_nodes_max_pods" -lt 30 ]; then
        echo_red "The minimum number of pods per node should be at least 30. Please try again."
    else
        break
    fi
done
log export SYSTEM_NODES_MAX_PODS="$system_nodes_max_pods"
cluster_params+=(--max-pods "$system_nodes_max_pods")

echo_lightgreen "User node pools are primarily used for hosting your application pods."

USER_NODE_COUNT=$(input_question "Please provide the user node pools count. (A minimum of 3 and preferably an odd number is recommended)")
log export USER_NODE_COUNT="$USER_NODE_COUNT"

if [ "$USER_NODE_COUNT" -gt 0 ]; then

    workerpool_params+=(--cluster-name "$CLUSTER_NAME")
    workerpool_params+=(--resource-group "$CLUSTER_RESOURCE_GROUP")
    workerpool_params+=(--mode User)

    echo_italic "User node pools count has been set to $USER_NODE_COUNT "
    workerpool_params+=(--node-count "$USER_NODE_COUNT")

    user_node_sizes=(
        "Standard  D2ds v5  [Standard_D2ds_v5] -  2 vCPUs |  8 GiB Memory |  75 GiB SSD Temp Storage"
        "Standard  D4ds v5  [Standard_D4ds_v5] -  4 vCPUs | 16 GiB Memory | 150 GiB SSD Temp Storage"
        "Standard  D8ds v5  [Standard_D8ds_v5] -  8 vCPUs | 32 GiB Memory | 300 GiB SSD Temp Storage"
        "Standard D16ds v5 [Standard_D16ds_v5] - 16 vCPUs | 64 GiB Memory | 600 GiB SSD Temp Storage"
        "Specify a different size [_] - https://learn.microsoft.com/en-us/azure/virtual-machines/sizes"
    )
    USER_NODE_SIZE=$(select_item "Please select the VM Size for the user node pools." "${user_node_sizes[@]}")

    if [ "$USER_NODE_SIZE" == '_' ]; then
        USER_NODE_SIZE=$(input_question "Please provide the VM Size for the user node pools. (Example: Standard_D8s_v5)")
    fi

    log export USER_NODE_SIZE="$USER_NODE_SIZE"
    echo_italic "User node pools VM Size has been set to $USER_NODE_SIZE"
    workerpool_params+=(--node-vm-size "$USER_NODE_SIZE")

    echo_green "Configuring User Node Pool host OS"
    usrpool_os_skus=()

    if [ "$GPU_ENABLED" == 'y' ]; then
        echo_cyan "AKS does not support Windows GPU-enabled node pools."
        echo_cyan "AzureLinux (CBLMariner) does not currently support UseGPUDedicatedVHD."
        usrpool_os_skus+=("Ubuntu [ubuntu].")
    else
        usrpool_os_skus+=("Azure Linux [AzureLinux] - RECOMMENDED Linux.")
        usrpool_os_skus+=("Ubuntu [ubuntu].")

        if [ "$CLUSTER_NETWORK" == 'kubenet' ]; then
            echo_cyan "Windows node pool cannot be created with Kubenet network plugin."
        else
            usrpool_os_skus+=("Windows Server 2022 [Windows2022] - RECOMMENDED Windows.")
            usrpool_os_skus+=("Windows Server 2019 [Windows2019].")
        fi
    fi

    USRPOOL_OS_SKU=$(select_item "Please select the host OS for the user node pool" "${usrpool_os_skus[@]}")
    log export USRPOOL_OS_SKU="$USRPOOL_OS_SKU"

    if [ "$USRPOOL_OS_SKU" == 'Windows2022' ] || [ "$USRPOOL_OS_SKU" == 'Windows2019' ]; then
        workerpool_params+=(--name "$WINPOOL_NAME")
        workerpool_params+=(--os-type Windows)
        workerpool_params+=(--os-sku "$USRPOOL_OS_SKU")

        WINDOWS_NODE_USERNAME=$(input_question "Please provide the Windows Admin Username.")
        log export WINDOWS_NODE_USERNAME="$WINDOWS_NODE_USERNAME"
        cluster_params+=(--windows-admin-username "$WINDOWS_NODE_USERNAME")

        WINDOWS_NODE_PASSWORD=$(input_question "Please provide the Windows Admin Password (minimum of 14 characters).")
        log export WINDOWS_NODE_PASSWORD="$WINDOWS_NODE_PASSWORD"
        cluster_params+=(--windows-admin-password "$WINDOWS_NODE_PASSWORD")
    else
        workerpool_params+=(--name "$WORKERPOOL_NAME")
        workerpool_params+=(--os-type Linux)
        workerpool_params+=(--os-sku "$USRPOOL_OS_SKU")
    fi

    while true; do
        user_nodes_max_pods=$(input_question "Please provide the maximum number of pods per node (30-250).")
        if [ "$user_nodes_max_pods" -gt 250 ]; then
            echo_red "The maximum number of pods per node should not exceed 250. Please try again."
        elif [ "$user_nodes_max_pods" -lt 30 ]; then
            echo_red "The minimum number of pods per node should be at least 30. Please try again."
        else
            break
        fi
    done
    log export USER_NODES_MAX_PODS="$user_nodes_max_pods"
    workerpool_params+=(--max-pods "$user_nodes_max_pods")

else
    echo_red "User node pool configuration will be skipped."
fi

SYETEM_IP_COUNT=$(((SYSTEM_NODE_COUNT + 1) + ((SYSTEM_NODE_COUNT + 1) * system_nodes_max_pods)))
USER_IP_COUNT=$(((USER_NODE_COUNT + 1) + ((USER_NODE_COUNT + 1) * user_nodes_max_pods)))
RECOMMENDED_IPS=$((SYETEM_IP_COUNT + USER_IP_COUNT))

# Display the informational message
echo_green "The anticipated IP address count for the system node pool stands at: $SYETEM_IP_COUNT."
echo_green "For the user node pool, the projected IP address count is: $USER_IP_COUNT."
echo_green "Cumulatively, the cluster is expected to require: $((RECOMMENDED_IPS + 1)) IP addresses."

# Assuming RECOMMENDED_IPS is already calculated
total_ips_needed=$((RECOMMENDED_IPS + 1)) # Adding 1 for network address

# Find the smallest subnet size that can accommodate the total IP count
subnet_mask=32
while [ $((2 ** (32 - subnet_mask))) -lt $total_ips_needed ]; do
    ((subnet_mask--))
done

# Recommend a CIDR range
base_ip="10.0.0.0"
recommended_cidr="$base_ip/$subnet_mask"

# Display the recommended CIDR range
echo_green "Based on the total required IP addresses ($RECOMMENDED_IPS), the recommended CIDR range is: $$subnet_mask or higher."

echo_green "Cluster Network Connectivity"

SUBNET_ID=
while [[ -z $SUBNET_ID ]]; do

    vnet_inputs=(
        "Create a new Virtual Network [new]."
        "Utilize an existing Virtual Network [existing]."
    )
    VNET_INPUT=$(select_item "Would you like to create a new Virtual Network (VNET) or use an existing one?" "${vnet_inputs[@]}")

    if [ "$VNET_INPUT" == 'new' ]; then

        echo_lightgreen "Initiating the creation of a new Virtual Network"
        VNET_RESOURCE_GROUP=$(select_item "Please select the resource group for the Virtual Network" "${all_resourceGroups[@]}")
        log export VNET_RESOURCE_GROUP="$VNET_RESOURCE_GROUP"

        VNET_NAME=$(input_question "Please provide the name for the Virtual Network (Example: vnet-aks-enu-01)")
        log export VNET_NAME="$VNET_NAME"

        SUBNET_NAME=$(input_question "Please provide the name for the Subnet (Example: snet-aks-01)")
        log export SUBNET_NAME="$SUBNET_NAME"

        vnet_address_space=$(input_question "Please provide the address space for the virtual network (Example: 10.200.0.0/16)")
        log export vnet_address_space="$vnet_address_space"

        subnet_address_prefix=$(input_question "Please provide the address prefix for the subnet (Example: 10.200.1.0/24)")
        log export subnet_address_prefix="$subnet_address_prefix"

        echo_green "Creating the virtual network and the subnet for the AKS cluster... "
        SUBNET_ID=$(az network vnet create --name "$VNET_NAME" --resource-group "$VNET_RESOURCE_GROUP" --address-prefix "$vnet_address_space" --subnet-name "$SUBNET_NAME" --subnet-prefixes "$subnet_address_prefix" --query 'newVNet.subnets[0].id' -o json | tr -d '"')
        log export SUBNET_ID="$SUBNET_ID"
        echo_green "Subnet $SUBNET_ID has been successfully created!... "
    else
        echo_lightgreen "Utilizing an existing Virtual Network"

        all_vnets_json=$(az network vnet list --query "[?location==\`${CLUSTER_LOCATION}\`].{name:name, resourceGroup:resourceGroup, location:location, id:id}" --output json)

        all_vnets=$(echo "$all_vnets_json" | jq -r '.[] | "\(.name) [\(.name)|\(.resourceGroup)]"' | sort)
        ifs_current=$IFS && IFS=$'\n' all_vnets=($all_vnets) && IFS=$ifs_current

        selected_vnet=$(select_item "Please select the Virtual Network resource group located at $CLUSTER_LOCATION. (The Virtual Network should be located in the same region as the cluster)" "${all_vnets[@]}")

        if [[ -z $selected_vnet ]]; then
            echo_yellow "It appears you do not have Virtual Networks for the selected region: ${CLUSTER_LOCATION}. Please try again." >&2
            continue
        fi

        ifs_current=$IFS && IFS='|' read -r VNET_NAME VNET_RESOURCE_GROUP <<<"$selected_vnet" && IFS=$ifs_current

        VNET_ID=$(echo "$all_vnets_json" | jq --arg target_name "$VNET_NAME" --arg target_rg "$VNET_RESOURCE_GROUP" '.[] | select(.name == $target_name and .resourceGroup == $target_rg) | .id')
        echo_green "Selected Virtual Network details:"
        echo_green "    Name: $VNET_NAME"
        echo_green "    Resource Group: $VNET_RESOURCE_GROUP"
        echo_green "    Location: $CLUSTER_LOCATION"
        echo_green "    ID: $VNET_ID"

        all_subnets=$(az network vnet subnet list --resource-group "$VNET_RESOURCE_GROUP" --vnet-name "$VNET_NAME" --query '[].{name:name, addressPrefix:addressPrefix}' -o tsv | awk '{print "[" $1 "] (" $2 ")" }')
        ifs_current=$IFS && IFS=$'\n' all_subnets=($all_subnets) && IFS=$ifs_current

        if [ -z "${all_subnets[*]}" ]; then
            echo_yellow "It appears you do not have any subnets in the selected Virtual Network $VNET_NAME. Please create the subnet and try again." >&2
            continue
        fi

        SUBNET_NAME=$(select_item "Please select the subnet" "${all_subnets[@]}")

        SUBNET_ID=$(az network vnet subnet show --resource-group "$VNET_RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME" --query id -o tsv)

        log export VNET_ID="$VNET_ID"
        log export VNET_NAME="$VNET_NAME"
        log export VNET_RESOURCE_GROUP="$VNET_RESOURCE_GROUP"
        log export SUBNET_NAME="$SUBNET_NAME"
        log export SUBNET_ID="$SUBNET_ID"

        echo_green "Selected Subnet id $SUBNET_ID"
    fi
done
echo_green "Cluster Network Plugin"

network_plugins=(
    "Azure CNI Overlay [overlay]: Assigns pod IP addresses from a private IP space. Best for scalability (Linux & Windows)."
    "Azure CNI Node Subnet [azure]: Previously named Azure CNI. Assigns pod IP addresses from your host VNet. Best for workloads where pods must be reachable by other VNet resources (Linux & Windows)."
    "Kubenet [kubenet]: Older, route table-based Overlay with limited scalability. Not recommended for most clusters (Linux Only)."
)
CLUSTER_NETWORK=$(select_item "Please select the desired cluster network configuration" "${network_plugins[@]}")

if [ "$CLUSTER_NETWORK" == 'kubenet' ] || [ "$CLUSTER_NETWORK" == 'overlay' ]; then
    echo_green "Cluster Pods CIDR: A CIDR notation IP range from which each pod will be assigned a unique IP address."
    POD_CIDR=$(input_question "Please provide the pods CIDR to use (Example: ${pod_cidr})")
    log export POD_CIDR="$POD_CIDR"
fi

echo_green "Kubernetes service address range: A CIDR notation IP range from which to assign service cluster IPs. It must not overlap with any Subnet IP ranges."
SERVICES_CIDR=$(input_question "Please provide the services CIDR to use. The service address CIDR must be smaller than /12 (Example: ${services_cidr})")
log export SERVICES_CIDR="$SERVICES_CIDR"

echo_green "Kubernetes DNS service IP address: An IP address assigned to the Kubernetes DNS service. It must be within the Kubernetes service address range."
DNS_SERVICE_IP=$(input_question "Please provide the DNS service IP to use (Example: ${dns_service_ip})")
log export DNS_SERVICE_IP="$DNS_SERVICE_IP"

log export CLUSTER_NETWORK="$CLUSTER_NETWORK"
cluster_params+=(--vnet-subnet-id "$SUBNET_ID")

case "$CLUSTER_NETWORK" in
azure)
    network_params+=(--network-plugin azure)
    network_params+=(--service-cidr "$SERVICES_CIDR")
    network_params+=(--dns-service-ip "$DNS_SERVICE_IP")
    ;;
kubenet)
    network_params+=(--network-plugin "kubenet")
    network_params+=(--pod-cidr "$POD_CIDR")
    network_params+=(--service-cidr "$SERVICES_CIDR")
    network_params+=(--dns-service-ip "$DNS_SERVICE_IP")
    ;;
overlay)
    network_params+=(--network-plugin azure)
    network_params+=(--network-plugin-mode overlay)
    network_params+=(--pod-cidr "$POD_CIDR")
    network_params+=(--service-cidr "$SERVICES_CIDR")
    network_params+=(--dns-service-ip "$DNS_SERVICE_IP")
    ;;
*)
    # should not reach here
    ;;
esac

network_policies=(
    "[none]: Allow all ingress and egress traffic to the pods"
    "[calico]: Open-source networking solution. Best for large-scale deployments with strict security requirements"
    "[azure]: Native networking solution. Best for simpler deployments with basic security and networking requirements"
)
#NETWORK_POLICY=$(select_item "Please select the network policy for the cluster" "${network_policies[@]}")

echo_green "Managed Identity for the Cluster"
echo_lightgreen "A User-assigned Managed Identity will be created for the cluster."
managed_identity_name=$(input_question "Please provide the name for your Managed Identity to be used/created.")
MANAGED_IDENTITY_ID=$(az identity create --name "$managed_identity_name" --resource-group "$CLUSTER_RESOURCE_GROUP" --query "id" | tr -d '"')
log export MANAGED_IDENTITY_ID="$MANAGED_IDENTITY_ID"
cluster_params+=(--enable-managed-identity --assign-identity "$MANAGED_IDENTITY_ID")

echo_green "Kubernetes Version for the Cluster"
echo_lightgreen "You will need to select a Kubernetes version from the available versions in your specified location."
location_k8s_versions=($(az aks get-versions --location "$CLUSTER_LOCATION" --output json --query 'values[?isPreview == `null`].patchVersions[].keys(@)[] | sort(@)[::-1]' | jq -c '.[] | "[" + . + "]"' | tr -d '"'))
K8S_VERSION=$(select_item "Select the kubernetes version from ${CLUSTER_LOCATION} available versions" "${location_k8s_versions[@]}")
log export K8S_VERSION="$K8S_VERSION"
cluster_params+=(--kubernetes-version "$K8S_VERSION")
workerpool_params+=(--kubernetes-version "$K8S_VERSION")

echo_green "Automatic Upgrade for the Cluster"
echo_lightgreen "The Automatic Upgrade option will be enabled and set to the latest patch version of the selected minor version."
cluster_params+=(--auto-upgrade-channel patch)

echo_green "Pricing and SLA Tier for the Cluster"
cluster_tiers=(
    "[Free]: The cluster management is free, but you'll be charged for VM, storage, and networking usage. Best for experimenting, learning, simple testing, or workloads with fewer than 10 nodes."
    "[Standard]: Recommended for mission-critical and production workloads. Includes Kubernetes control plane autoscaling, workload-intensive testing, and up to 5,000 nodes per cluster. Uptime SLA is 99.95% for clusters using Availability Zones and 99.9% for clusters not using Availability Zones."
    "[Premium]: Recommended for mission-critical and production workloads requiring TWO YEARS of support. Includes all current AKS features from standard tier."
)
CLUSTER_TIER=$(select_item "Please select the pricing tier for your cluster" "${cluster_tiers[@]}")
# CLUSTER_TIER to lower case
CLUSTER_TIER=$(echo "$CLUSTER_TIER" | tr '[:upper:]' '[:lower:]')
log export CLUSTER_TIER="$CLUSTER_TIER"
cluster_params+=(--tier "$CLUSTER_TIER")

echo_green "Connection of Cluster to Container Registry"
attach_acr=$(yes_no_question "Would you like to attach an Azure Container Registry to the cluster?")

if [ "$attach_acr" == 'y' ]; then
    available_acrs=$(az acr list --query '[].{name:name, loginServer:loginServer}' --output tsv | awk '{print "[" $1 "] (" $2 ")" }' | sort)
    ifs_current=$IFS && IFS=$'\n' available_acrs=($available_acrs) && IFS=$ifs_current
    ACR_NAME=$(select_item "Please select the container registry" "${available_acrs[@]}")
    log export ACR_NAME="$ACR_NAME"
    cluster_params+=(--attach-acr "$ACR_NAME")
fi

echo_green "Microsoft Entra Workload ID utilizes Service Account Token Volume Projection, enabling pods to use a Kubernetes identity, i.e., a service account. A Kubernetes token is issued and OIDC federation allows Kubernetes applications to securely access Azure resources based on annotated service accounts."
echo_green "For more information, please visit: https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview"
enable_oidc=$(yes_no_question "Would you like to enable Microsoft Entra Workload ID on $CLUSTER_NAME?")
log export ENABLE_OIDC="$enable_oidc"
if [ "$enable_oidc" == 'y' ]; then
    cluster_params+=(--enable-oidc-issuer --enable-workload-identity)
fi

echo_green "KEDA (Kubernetes-based Event Driven Autoscaler) allows for the scaling of any container in Kubernetes based on the number of events that need processing."
echo_green "For more information, please visit: https://keda.sh/"
enable_keda=$(yes_no_question "Would you like to enable KEDA on $CLUSTER_NAME?")
if [ "$enable_keda" == 'y' ]; then
    cluster_params+=(--enable-keda)
fi

enable_kvsp=$(yes_no_question "Would you like to enable the Azure Key Vault provider for the Secrets Store CSI Driver on $CLUSTER_NAME?")
if [ "$enable_kvsp" == 'y' ]; then
    cluster_params+=(--enable-addons azure-keyvault-secrets-provider)
fi

# add Managed NGINX ingress with the application routing add-on
echo_green "Managed NGINX Ingress Controller offers in-cluster, scalable NGINX ingress controllers with basic load balancing and routing, internal/external load balancer setup, static IP configuration, Azure Key Vault and DNS Zones integration for certificate and DNS management, and supports the Ingress API."
enable_ingress=$(yes_no_question "Would you like to enable the Managed NGINX Ingress Controller on $CLUSTER_NAME?")
if [ "$enable_ingress" == 'y' ]; then
    cluster_params+=(--enable-app-routing)
fi

enable_defender=$(yes_no_question "Would you like to enable the Microsoft Defender security profile on $CLUSTER_NAME?")
if [ "$enable_defender" == 'y' ]; then
    cluster_params+=(--enable-defender)
fi

# Cost Management Your cluster must be either Standard or Premium tier, not the Free tier.
if [ "$CLUSTER_TIER" != 'free' ]; then
    enable_cost_management=$(yes_no_question "Would you like to enable Cost Management on $CLUSTER_NAME? (Must be Standard or Premium tier)")
    if [ "$enable_cost_management" == 'y' ]; then
        cluster_params+=(--enable-cost-analysis)
    fi
fi

start_provision=$(yes_no_question "Are you ready to begin the provisioning process?")

if [ "$start_provision" == 'n' ]; then
    echo_red "The cluster provisioning process has been cancelled."
    exit 0
fi

echo_lightgreen "Initiating the provisioning process..."

start_time=$(date +%s)

create_command="az aks create ${cluster_params[@]} ${network_params[@]}"
log "$create_command"

worker_command="az aks nodepool add ${workerpool_params[@]}"
log "$worker_command"

echo "Executing: $create_command" >&2

if [ "$USER_NODE_COUNT" -gt 0 ]; then
    echo_lightgreen "Adding User Node Pool to the cluster... "
    echo "Executing: $worker_command" >&2
    az aks nodepool add "${workerpool_params[@]}"
fi

az aks create "${cluster_params[@]}" "${network_params[@]}"

if [ $? -eq 0 ]; then

    if [ "$USER_NODE_COUNT" -gt 0 ]; then
        echo_lightgreen "Adding User Node Pool to the cluster... "
        worker_command="az aks nodepool add ${workerpool_params[@]}"
        echo "Executing: $worker_command" >&2
        log "$worker_command"
        az aks nodepool add "${workerpool_params[@]}"
    fi

    end_time=$(date +%s)
    execution_time=$((end_time - start_time))
    echo "Provisioning duration: $execution_time seconds"
    echo_green "Success! AKS Cluster ${ANSI_COLOR_CYAN}$CLUSTER_NAME${ANSI_COLOR_GREEN_LIGHT} has been created! "
    echo_cyan "Log file: $vars_file"

    echo_green "Cluster Details: "
    echo_lightgreen "Name: $CLUSTER_NAME"
    echo_lightgreen "Resource Group: $CLUSTER_RESOURCE_GROUP"

    if [ "$enable_oidc" == 'y' ]; then
        oidc_url=$(az aks show -g "$CLUSTER_RESOURCE_GROUP" -n "$CLUSTER_NAME" --query "oidcIssuerProfile.issuerUrl" -o tsv)
        echo_lightgreen "OIDC Issuer URL: $oidc_url"
    fi

    echo_green "API Server FQDN: $(az aks show -g "$CLUSTER_RESOURCE_GROUP" -n "$CLUSTER_NAME" --query "fqdn" -o tsv)"
    if [ "$private_cluster" == 'y' ]; then
        echo_green "Private API Server FQDN: $(az aks show -g "$CLUSTER_RESOURCE_GROUP" -n "$CLUSTER_NAME" --query "privateFqdn" -o tsv)"
    fi

    echo_green "You have successfully created a Managed Cluster with Managed Identity."

    echo_green "Proceeding to log into the Cluster... "

    az aks get-credentials --resource-group "$CLUSTER_RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing --admin
    kubelogin convert-kubeconfig -l azurecli
    echo_green "Listing all deployments across all namespaces"

    az aks command invoke --resource-group "$CLUSTER_RESOURCE_GROUP" --name "$CLUSTER_NAME" --command "kubectl get deployments --all-namespaces=true -o wide"

else
    echo_red "Cluster creation process failed!"
fi
