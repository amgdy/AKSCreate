#!/bin/bash

COLOR_GREEN="^[[0;32m"
COLOR_RED="[[31m"
COLOR_RESET="^[[0m"

yes_no_question() {
    local input
    local prompt="$1 [Y/n]: "
    local default="${2:-Y}"

    while read -e -p "$prompt" -r -n 1 input && ! [[ "$input" =~ ^[YyNn]?$ ]]; do
        echo "Invalid input. Please enter 'Y', 'N', or press Enter for $default."
    done

    echo "${input:-$default}"
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

input="This is a sample text with (some text inside parentheses) and more text."

# Using the regex to extract text between parentheses
# if [[ $input =~ \((.+)\) ]]; then
#     extracted_text="${BASH_REMATCH[1]}"
#     echo "Text between parentheses: $extracted_text"
# else
#     echo "No match found."
# fi

# Example usage:
# items=("AzureLinux: (recommend)" "Ubuntu")
# result=$(select_item "Select AKS cluster host OS" "${items[@]}")

items=(
    "Kubenet (kubenet)"
    "Azure CNI (azure) dasda"
    "welcome (ji)ff")
result=$(select_item "Select cluster network configuration" "${items[@]}")

echo $result
return 0
is_created=$(yes_no_question "is the app created?")

read -p $"Do you have the subnet ALREADY Created ? [Y/n] " -r IS_SNET_CREATED

IS_SNET_CREATED=$(echo "${IS_SNET_CREATED:-y}" | tr '[:upper:]' '[:lower:]')

echo $IS_SNET_CREATED

PS3='Cluster OS (choose number): '
os_list=("AzureLinux (recommened)" "Ubuntu")
while [ -z "$OS_SKU" ]; do
    select os in "${os_list[@]}"; do
        case $REPLY in
        1)
            echo "You've selected $os for your cluster."
            OS_SKU=AzureLinux
            break
            ;;
        2)
            echo "You've selected $os for your cluster."
            OS_SKU=Ubuntu
            break
            ;;
        *)
            echo "Unknown option, type the correct option number"
            break
            ;;
        esac
    done
done

echo "Cluster will use $OS_SKU"

# # Bash Menu Script Example

# PS3='Please enter your choice: '
# options=("Option 1" "Option 2" "Option 3" "Quit")
# select opt in "${options[@]}"; do
#     case $opt in
#     "Option 1")
#         echo "you chose choice 1"
#         ;;
#     "Option 2")
#         echo "you chose choice 2"
#         ;;
#     "Option 3")
#         echo "you chose choice $REPLY which is $opt"
#         ;;
#     "Quit")
#         break
#         ;;
#     *) echo "invalid option $REPLY" ;;
#     esac
# done

# PS3="Select item please: "

# items=("Item 1" "Item 2" "Item 3")

# while true; do
#     select item in "${items[@]}" Quit
#     do
#         case $REPLY in
#             1) echo "Selected item #$REPLY which means $item"; break;;
#             2) echo "Selected item #$REPLY which means $item"; break;;
#             3) echo "Selected item #$REPLY which means $item"; break;;
#             $((${#items[@]}+1))) echo "We're done!"; break 2;;
#             *) echo "Ooops - unknown choice $REPLY"; break;
#         esac
#     done
# done
