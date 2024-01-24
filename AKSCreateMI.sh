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

mkdir -p logs

if [ -n "$1" ]; then
    vars_file=$1
fi

cat <<EOF

░█▀█░█░█░█▀▀░░░█▀█░█▀▄░█▀█░█░█░▀█▀░█▀▀░▀█▀░█▀█░█▀█░█▀▀░█▀▄
░█▀█░█▀▄░▀▀█░░░█▀▀░█▀▄░█░█░▀▄▀░░█░░▀▀█░░█░░█░█░█░█░█▀▀░█▀▄
░▀░▀░▀░▀░▀▀▀░░░▀░░░▀░▀░▀▀▀░░▀░░▀▀▀░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░▀


EOF

echo_green "Hi!, This script will help you create Azure Kubernetes Services https://azure.microsoft.com/en-us/products/kubernetes-service"
echo_green "These are the prerequisites needed: 
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

GPU_ENABLED=$(yes_no_question "Will the cluster be GPU enabled?")
log export GPU_ENABLED="$GPU_ENABLED"

if [ "$GPU_ENABLED" == 'y' ]; then
    WORKERPOOL_NAME=gpupool001
    echo_lightgreen "Registering GPU enabled AKS feature is the subscription"
    status=$(az feature show --namespace "Microsoft.ContainerService" --name "GPUDedicatedVHDPreview" --query "properties.state" --output tsv)
    if [ "$status" == "Registered" ]; then
        echo "Feature already registered."
    else
        echo "Enabling feature (it can take up to 15mins)..."
        echo "Start time: $(date "+%Y-%m-%d %H:%M:%S")"
        az feature register --namespace "Microsoft.ContainerService" --name "GPUDedicatedVHDPreview"
        echo "Waiting for feature to be registered..."

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
        echo "Completed time: $(date "+%Y-%m-%d %H:%M:%S")"
        echo_green "Feature registered successfully."

    fi

    workerpool_params+=(--node-taints sku=gpu:NoSchedule)
    workerpool_params+=(--aks-custom-headers UseGPUDedicatedVHD=true)
fi

cluster_params+=(--generate-ssh-keys)
cluster_params+=(--vm-set-type VirtualMachineScaleSets)

echo_green "Cluster Name"
CLUSTER_NAME=$(input_question "Please enter the name of the cluster")
log export CLUSTER_NAME="$CLUSTER_NAME"
cluster_params+=(--name "$CLUSTER_NAME")

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
cluster_params+=(--location "$CLUSTER_LOCATION")

all_resourceGroups=$(az group list --query '[].{name:name, location:location}' --output tsv | awk '{print "[" $1 "] (" $2 ") "}' | sort)
ifs_current=$IFS && IFS=$'\n' all_resourceGroups=($all_resourceGroups) && IFS=$ifs_current

CLUSTER_RESOURCE_GROUP=$(select_item "Select cluster resource group" "${all_resourceGroups[@]}")
log export CLUSTER_RESOURCE_GROUP="$CLUSTER_RESOURCE_GROUP"
cluster_params+=(--resource-group "$CLUSTER_RESOURCE_GROUP")

echo_green "Cluster Network Connectivity"

VNET_RESOURCE_GROUP=
while [[ -z $VNET_RESOURCE_GROUP ]]; do

    vnet_inputs=(
        "Create new VNET [new]."
        "Use existing VNET [existing]."
    )
    VNET_INPUT=$(select_item "Do you want to create a new *virtual network* (vnet) or use an existing one?" "${vnet_inputs[@]}")

    if [ "$VNET_INPUT" == 'new' ]; then

        echo_lightgreen "Creating a new virual network"
        VNET_RESOURCE_GROUP=$(select_item "Select vnet resource group" "${all_resourceGroups[@]}")
        log export VNET_RESOURCE_GROUP="$VNET_RESOURCE_GROUP"

        VNET_NAME=$(input_question "Please enter the vnet name")
        log export VNET_NAME="$VNET_NAME"
        subnet_address_prefix=$(input_question "Ok! What is the address-prefix for the subnet? (Example: 10.179.128.0/21)")
        echo_green "Creating subnet for AKS cluster... "
        VNET_ID=$(az network vnet show --resource-group "$VNET_RESOURCE_GROUP" --name "$VNET_NAME" --query id -o tsv)
        log export VNET_ID="$VNET_ID"
        SUBNET_ID=$(az network vnet subnet create -n aks-subnet -g "$VNET_RESOURCE_GROUP" --vnet-name "$VNET_NAME" --address-prefix "$subnet_address_prefix" --query "id" -o tsv)
        log export SUBNET_ID="$SUBNET_ID"
        echo_green "Subnet $SUBNET_ID has been created!... "
    else
        echo_lightgreen "Using an existing virtual network"
        all_vnets_json=$(az network vnet list --query "[?location==\`${CLUSTER_LOCATION}\`].{name:name, resourceGroup:resourceGroup, location:location, id:id}" --output json)

        all_vnets=$(echo "$all_vnets_json" | jq -r '.[] | "\(.name) [\(.name)|\(.resourceGroup)]"' | sort)
        ifs_current=$IFS && IFS=$'\n' all_vnets=($all_vnets) && IFS=$ifs_current

        selected_vnet=$(select_item "Select VNET resource group which is located at $CLUSTER_LOCATION. (vnet should be located in the same region of the cluster)" "${all_vnets[@]}")

        if [[ -z $selected_vnet ]]; then
            echo "Looks like you don't have vnets for the selected region: ${CLUSTER_LOCATION}. Please try again." >&2
            continue
        fi

        ifs_current=$IFS && IFS='|' read -r VNET_NAME VNET_RESOURCE_GROUP <<<"$selected_vnet" && IFS=$ifs_current

        VNET_ID=$(echo "$all_vnets_json" | jq --arg target_name "$VNET_NAME" --arg target_rg "$VNET_RESOURCE_GROUP" '.[] | select(.name == $target_name and .resourceGroup == $target_rg) | .id')
        echo_green "Selected VNET details:"
        echo_green "    Name: $VNET_NAME"
        echo_green "    Resource Group: $VNET_RESOURCE_GROUP"
        echo_green "    Location: $CLUSTER_LOCATION"
        echo_green "    ID: $VNET_ID"

        all_subnets=$(az network vnet subnet list --resource-group "$VNET_RESOURCE_GROUP" --vnet-name "$VNET_NAME" --query '[].{name:name, addressPrefix:addressPrefix}' -o tsv | awk '{print "[" $1 "] (" $2 ")" }')
        ifs_current=$IFS && IFS=$'\n' all_subnets=($all_subnets) && IFS=$ifs_current

        SUBNET_NAME=$(select_item "Select subnet" "${all_subnets[@]}")

        SUBNET_ID=$(az network vnet subnet show --resource-group "$VNET_RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME" --query id -o tsv)

        log export VNET_ID="$VNET_ID"
        log export VNET_NAME="$VNET_NAME"
        log export VNET_RESOURCE_GROUP="$VNET_RESOURCE_GROUP"
        log export SUBNET_NAME="$SUBNET_NAME"
        log export SUBNET_ID="$SUBNET_ID"
    fi
done

echo_green "Cluster Network Plugin"

network_plugins=(
    "Azure CNI [azure]: Each pod and node is assigned a unique IP for advanced configurations (Linux & Windows)."
    "Kubenet [kubenet]: Each pod is assigned a logically different IP address from the subnet for simpler setup (Linux Only)."
    "Azure CNI Overlay [overlay]: Each pods is assigned IP addresses from a private CIDR logically different from the VNet (Linux & Windows). Has better performance and Azure Network Policies support over kubenet"
)
CLUSTER_NETWORK=$(select_item "Choose cluster network configuration" "${network_plugins[@]}")

if [ "$CLUSTER_NETWORK" == 'kubenet' ] || [ "$CLUSTER_NETWORK" == 'overlay' ]; then
    echo_green "Cluster Pods CIDR. A CIDR notation IP range from which to assign each pod a unique IP address."
    POD_CIDR=$(input_question "What is the pods CIDR to use? (Example: ${pod_cidr})")
    log export POD_CIDR="$POD_CIDR"
fi

echo_green "Kubernetes service address range. A CIDR notation IP range from which to assign service cluster IPs. It must not overlap with any Subnet IP ranges."
SERVICES_CIDR=$(input_question "What is the services CIDR to use? (Example: ${services_cidr})")
log export SERVICES_CIDR="$SERVICES_CIDR"

echo_green "Kubernetes DNS service IP address. An IP address assigned to the Kubernetes DNS service. It must be within the Kubernetes service address range."
DNS_SERVICE_IP=$(input_question "What is the DNS service IP to use? (Example: ${dns_service_ip})")
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

echo_green "Getting tenant ID... "
TENANT_ID=$(az account show --query tenantId -o tsv)
log export TENANT_ID="$TENANT_ID"

echo_lightgreen "Using Tenant ID: $TENANT_ID"

echo_green "Entra ID (Azure AD) Authentication with Kubernetes RBAC"
echo_lightgreen "Configuring Cluster admin ClusterRoleBinding. Note that Kubernetes local accounts will be enabled by default."
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
cluster_params+=(--enable-aad --aad-admin-group-object-ids "$AAD_GROUP_ID" --aad-tenant-id "$TENANT_ID")

echo_green "Cluster SYSTEM and USER node pools"
echo_lightgreen "System node pools serve the primary purpose of hosting critical ${ANSI_COLOR_CYAN}system pods${ANSI_COLOR_GREEN_LIGHT} such as CoreDNS, konnectivity, metrics-server... "

SYSTEM_NODE_COUNT=$(input_question "What is the count of System node pools? (2 or higher is recommended)")
log export SYSTEM_NODE_COUNT="$SYSTEM_NODE_COUNT"
echo_italic "System node pools count will be $SYSTEM_NODE_COUNT "
cluster_params+=(--nodepool-name "$SYSTEMPOOL_NAME")
cluster_params+=(--node-count "$SYSTEM_NODE_COUNT")

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
cluster_params+=(--node-vm-size "$SYSTEM_NODE_SIZE")

echo_green "System Node Pool host OS"
syspool_os_skus=(
    "Azure Linux [AzureLinux] - RECOMMENDED."
    "Ubuntu [ubuntu].")
SYSPOOL_OS_SKU=$(select_item "Choose system node pool cluster host OS" "${syspool_os_skus[@]}")
log export SYSPOOL_OS_SKU="$SYSPOOL_OS_SKU"
cluster_params+=(--os-sku "$SYSPOOL_OS_SKU")

echo_lightgreen "User node pools serve the primary purpose of ${ANSI_COLOR_CYAN}hosting your application pods.${ANSI_RESET}"

USER_NODE_COUNT=$(input_question "What is the user node pools count? (3 or higher${ANSI_COLOR_CYAN} odd number${ANSI_RESET} is recommended)")
log export USER_NODE_COUNT="$USER_NODE_COUNT"

if [ "$USER_NODE_COUNT" -gt 0 ]; then

    workerpool_params+=(--cluster-name "$CLUSTER_NAME")
    workerpool_params+=(--resource-group "$CLUSTER_RESOURCE_GROUP")
    workerpool_params+=(--mode User)

    echo_italic "User node pools count will be $USER_NODE_COUNT "
    workerpool_params+=(--node-count "$USER_NODE_COUNT")

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
    workerpool_params+=(--node-vm-size "$USER_NODE_SIZE")

    echo_green "User Node Pool host OS"
    usrpool_os_skus=(
        "Azure Linux [AzureLinux] - RECOMMENDED Linux."
        "Ubuntu [ubuntu].")

    if [ "$GPU_ENABLED" == 'y' ]; then
        echo_cyan "AKS does not support Windows GPU-enabled node pools."
    else
        if [ "$CLUSTER_NETWORK" == 'kubenet' ]; then
            echo_cyan "You can't create Windows node pool with Kubenet network plugin."
        else
            usrpool_os_skus+=("Windows Server 2022 [Windows2022] - RECOMMENDED Windows.")
            usrpool_os_skus+=("Windows Server 2019 [Windows2019].")
        fi
    fi

    USRPOOL_OS_SKU=$(select_item "Choose user node pool host OS" "${usrpool_os_skus[@]}")
    log export USRPOOL_OS_SKU="$USRPOOL_OS_SKU"

    if [ "$USRPOOL_OS_SKU" == 'Windows2022' ] || [ "$USRPOOL_OS_SKU" == 'Windows2019' ]; then
        workerpool_params+=(--name "$WINPOOL_NAME")
        workerpool_params+=(--os-type Windows)
        workerpool_params+=(--os-sku "$USRPOOL_OS_SKU")

        WINDOWS_NODE_USERNAME=$(input_question "Please provide Windows Admin Username?")
        log export WINDOWS_NODE_USERNAME="$WINDOWS_NODE_USERNAME"
        cluster_params+=(--windows-admin-username "$WINDOWS_NODE_USERNAME")

        WINDOWS_NODE_PASSWORD=$(input_question "Please provide Windows Admin Password (minimum of 14 characters)?")
        log export WINDOWS_NODE_PASSWORD="$WINDOWS_NODE_PASSWORD"
        cluster_params+=(--windows-admin-password "$WINDOWS_NODE_PASSWORD")
    else
        workerpool_params+=(--name "$WORKERPOOL_NAME")
        workerpool_params+=(--os-type Linux)
        workerpool_params+=(--os-sku "$USRPOOL_OS_SKU")
    fi

else
    echo_red "User node pool will be skipped"
fi

echo_green "Cluster Managed Identity"
echo_lightgreen "We will User-assigned Managed Identity for the cluster"
managed_identity_name=$(input_question "What is the name of your Managed Identity to use/create ?")
MANAGED_IDENTITY_ID=$(az identity create --name "$managed_identity_name" --resource-group "$CLUSTER_RESOURCE_GROUP" --query "id" | tr -d '"')
log export MANAGED_IDENTITY_ID="$MANAGED_IDENTITY_ID"
cluster_params+=(--enable-managed-identity --assign-identity "$MANAGED_IDENTITY_ID")

echo_green "Cluster kubernetes version"
location_k8s_versions=($(az aks get-versions --location "$CLUSTER_LOCATION" --output json --query 'values[?isPreview == `null`].patchVersions[].keys(@)[]' | jq -c '.[] | "[\(.)]"' | sort -r | tr "\n" " "))
K8S_VERSION=$(select_item "Select the kubernetes version from ${CLUSTER_LOCATION} available versions" "${location_k8s_versions[@]}")
log export K8S_VERSION="$K8S_VERSION"
cluster_params+=(--kubernetes-version "$K8S_VERSION")
workerpool_params+=(--kubernetes-version "$K8S_VERSION")

echo_green "Cluster Automatic Upgrade option"
echo_lightgreen "Auto-upgrade option will be enabled and will be set to the latest patch version of the minor version selected."
cluster_params+=(--auto-upgrade-channel patch)

echo_green "Cluster price and SLA tier"
cluster_tiers=(
    "Standard [standard] - RECOMMENDED."
    "Free [free] - NO financially backed API server uptime SLA!"
)
CLUSTER_TIER=$(select_item "Choose cluster pricing tier" "${cluster_tiers[@]}")
log export CLUSTER_TIER="$CLUSTER_TIER"
cluster_params+=(--tier "$CLUSTER_TIER")

echo_green "Cluster connected Container Registry"
attach_acr=$(yes_no_question "Do you want to Attach Azure Container Registry to the cluster ?")

if [ "$attach_acr" == 'y' ]; then
    available_acrs=$(az acr list --query '[].{name:name, loginServer:loginServer}' --output tsv | awk '{print "[" $1 "] (" $2 ")" }' | sort)
    ifs_current=$IFS && IFS=$'\n' available_acrs=($available_acrs) && IFS=$ifs_current
    ACR_NAME=$(select_item "Select the container registry" "${available_acrs[@]}")
    log export ACR_NAME="$ACR_NAME"
    cluster_params+=(--attach-acr "$ACR_NAME")
fi

echo_green "Microsoft Entra Workload ID uses Service Account Token Volume Projection enabling pods to use a Kubernetes identity (that is, a service account). A Kubernetes token is issued and OIDC federation enables Kubernetes applications to access Azure resources securely with Microsoft Entra ID based on annotated service accounts."
echo_green "More info can be found at: https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview"
enable_oidc=$(yes_no_question "Do you want to enable Microsoft Entra Workload ID on $CLUSTER_NAME ?")
log export ENABLE_OIDC="$enable_oidc"
if [ "$enable_oidc" == 'y' ]; then
    cluster_params+=(--enable-oidc-issuer --enable-workload-identity)
fi

echo_green "KEDA is a Kubernetes-based Event Driven Autoscaler. With KEDA, you can drive the scaling of any container in Kubernetes based on the number of events needing to be processed."
echo_green "More info can be found at: https://keda.sh/"
enable_keda=$(yes_no_question "Do you want to enable KEDA on $CLUSTER_NAME?")
if [ "$enable_keda" == 'y' ]; then
    cluster_params+=(--enable-keda)
fi

enable_kvsp=$(yes_no_question "Do you want to enable Azure Key Vault provider for Secrets Store CSI Driver on $CLUSTER_NAME ?")
if [ "$enable_kvsp" == 'y' ]; then
    cluster_params+=(--enable-addons azure-keyvault-secrets-provider)
fi

enable_defender=$(yes_no_question "Do you want to enable Microsoft Defender security profile on $CLUSTER_NAME ?")
if [ "$enable_defender" == 'y' ]; then
    cluster_params+=(--enable-defender)
fi

start_provision=$(yes_no_question "Start the provisioning process now?")

if [ "$start_provision" == 'n' ]; then
    echo_red "Cancelling the cluster provisioning!!"
    exit 0
fi

echo_lightgreen "Starting the provisioning process..."

create_command="az aks create ${cluster_params[@]} ${network_params[@]}"

echo "Running: $create_command" >&2
log "$create_command"
az aks create "${cluster_params[@]}" "${network_params[@]}"

if [ $? -eq 0 ]; then

    if [ "$USER_NODE_COUNT" -gt 0 ]; then
        echo_lightgreen "Adding User Node Pool to the cluster... "
        worker_command="az aks nodepool add ${workerpool_params[@]}"
        echo "Running: $worker_command" >&2
        log "$worker_command"
        az aks nodepool add "${workerpool_params[@]}"
    fi

    echo_green "Congratulations AKS Cluster ${ANSI_COLOR_CYAN}$CLUSTER_NAME${ANSI_COLOR_GREEN_LIGHT} has been created! "
    echo_cyan "Log file: $vars_file"

    echo_green "Cluster Details: "
    echo_lightgreen "Name: $CLUSTER_NAME"
    echo_lightgreen "Resource Group: $CLUSTER_RESOURCE_GROUP"

    if [ "$enable_oidc" == 'y' ]; then
        oidc_url=$(az aks show -g "$CLUSTER_RESOURCE_GROUP" -n "$CLUSTER_NAME" --query "oidcIssuerProfile.issuerUrl" -o tsv)
        echo_lightgreen "OIDC Issuer URL: $oidc_url"
    fi

    echo_green "Congratulation you have created Managed Cluster with Managed Identity"
    echo_green "Logging into Cluster Now... "

    az aks get-credentials --name "$CLUSTER_NAME" --resource-group "$CLUSTER_RESOURCE_GROUP" --overwrite-existing --admin
    kubelogin convert-kubeconfig -l azurecli
    echo_green "Listing all deployments in all namespaces"
    kubectl get deployments --all-namespaces=true -o wide

else
    echo_red "Failed to create the cluster!"
fi
