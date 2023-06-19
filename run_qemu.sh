#!/bin/bash

# Configuration file
config_file="config.txt"

# Function to detect available PCI devices
detect_pci_devices() {
  available_pci_devices=()
  while IFS= read -r -d $'\0' device; do
    pci_id=$(basename "$device")
    available_pci_devices+=("$pci_id")
  done < <(find /sys/bus/pci/devices -mindepth 1 -maxdepth 1 -type l -name "*:*:*.*" -print0)
}

# Function to get device information for a specific PCI device
get_device_info() {
  local pci_device=$1
  local device_info=$(lspci -s "$pci_device")
  echo "$device_info"
}

# Function to detach a PCI device from its current driver
detach_pci_device() {
  local slot_info=$1
  local driver_name=$2
  echo "$slot_info" > "/sys/bus/pci/drivers/$driver_name/unbind"
  echo "$(date): Detached PCI device $slot_info" >> "pci_passthrough.log"
}

# Function to attach a PCI device to the VFIO driver
attach_pci_device() {
  local vendor_id=$1
  local device_code=$2
  echo "$vendor_id $device_code" > "/sys/bus/pci/drivers/vfio-pci/new_id"
}

# Function to detect available ISO files in the script folder
detect_iso_files() {
  iso_files=()
  while IFS= read -r -d $'\0' file; do
    if [[ $file == *.iso ]]; then
      iso_files+=("$file")
    fi
  done < <(find . -maxdepth 1 -type f -name "*.iso" -print0)
}

# Function to detect available BIOS files in the script folder
detect_bios_files() {
  bios_files=()
  while IFS= read -r -d $'\0' file; do
    if [[ $file == *.rom ]]; then
      bios_files+=("$file")
    fi
  done < <(find . -maxdepth 1 -type f -name "*.rom" -print0)
}

# Function to load the configuration from the config file
load_configuration() {
  if [ -f "$config_file" ]; then
    source "$config_file"

    if [ -n "$bios_path" ]; then
      bios_selected=true
    fi

    if [ -n "$iso_path" ]; then
      iso_selected=true
    fi

    if [ -n "$pci_device_options" ]; then
      pci_passthrough_enabled=true
    fi

    if [ -n "$memory" ]; then
      memory_selected=true
    fi
  fi
}

# Function to save the configuration to the config file
save_configuration() {
  echo "bios_path=\"$bios_path\"" > "$config_file"
  echo "iso_path=\"$iso_path\"" >> "$config_file"
  echo "pci_device_options=\"$pci_device_options\"" >> "$config_file"
  echo "memory=\"$memory\"" >> "$config_file"
  echo "pci_passthrough_enabled=\"$pci_passthrough_enabled\"" >> "$config_file"
}

# Function to print the main menu
print_main_menu() {
  clear
  echo "Main Menu:"
  echo "1. Configuration Menu"
  echo "2. Run QEMU"
  echo "3. Exit"
}

# Function to print the configuration menu
print_configuration_menu() {
  clear
  echo "Configuration Menu:"
  echo "1. Reconfigure BIOS"
  echo "2. Reconfigure ISO"
  echo "3. Configure PCI passthrough"
  if $pci_passthrough_enabled; then
    echo "4. Disable PCI passthrough (Currently: Enabled)"
  else
    echo "4. Enable PCI passthrough (Currently: Disabled)"
  fi
  echo "5. Configure memory"
  echo "6. View current configuration"
  echo "7. Save and return to main menu"
  echo "8. Return to main menu without saving"
}

# Function to prompt the user for BIOS selection
select_bios() {
  echo "Reconfiguring BIOS..."
  detect_bios_files

  # Display available BIOS files
  echo "BIOS files available:"
  for index in "${!bios_files[@]}"; do
    bios_file="${bios_files[index]}"
    echo "$index: $bios_file"
  done

  # Prompt the user to select a BIOS file or download the Pegasos ROM
  read -r -p "Select a BIOS file (enter the number) or enter 'd' to download the Pegasos ROM: " bios_index

  # Validate user choice
  if [[ "$bios_index" =~ ^[0-9]+$ ]] && [ "$bios_index" -lt "${#bios_files[@]}" ]; then
    bios_path="${bios_files[bios_index]}"
    bios_selected=true
  elif [ "$bios_index" == "d" ]; then
    # Download the Pegasos ROM
    bios_url="http://web.archive.org/web/20071021223056/http://www.bplan-gmbh.de/up050404/up050404"
    bios_filename="up050404"
    echo "Downloading Pegasos ROM..."
    if curl -L -o "$bios_filename" "$bios_url"; then
      bios_path="./pegasos2.rom"
      bios_selected=true
      echo "Download successful."
      # Extract the ROM
      echo "Extracting Pegasos ROM..."
      tail -c +85581 "$bios_filename" | head -c 524288 > "pegasos2.rom"
      echo "Extraction successful."
    else
      echo "Download failed. Please try again."
    fi
  else
    echo "Invalid selection. Please try again."
  fi
}


# Function to prompt the user for ISO selection
select_iso() {
  echo "Reconfiguring ISO..."
  detect_iso_files

  # Display available ISO files
  echo "ISO files available:"
  for index in "${!iso_files[@]}"; do
    iso_file="${iso_files[index]}"
    echo "$index: $iso_file"
  done

  # Prompt the user to select an ISO file or download the MorphOS installer/trial ISO
  read -r -p "Select an ISO file (enter the number) or enter 'd' to download the MorphOS installer/trial ISO: " iso_index

  # Validate user choice
  if [[ "$iso_index" =~ ^[0-9]+$ ]] && [ "$iso_index" -lt "${#iso_files[@]}" ]; then
    iso_path="${iso_files[iso_index]}"
    iso_selected=true
  elif [ "$iso_index" == "d" ]; then
    # Download the MorphOS installer/trial ISO
    iso_url="https://morphos-team.net/morphos-3.18.iso"
    iso_filename="morphos-3.18.iso"
    echo "Downloading MorphOS installer/trial ISO..."
    if curl -L -o "$iso_filename" "$iso_url"; then
      iso_path="./$iso_filename"
      iso_selected=true
      echo "Download successful."
    else
      echo "Download failed. Please try again."
    fi
  else
    echo "Invalid selection. Please try again."
  fi
}

# Function to configure PCI passthrough for specific devices
configure_pci_passthrough() {
  detect_pci_devices

  # Exclude boot drive controller and display
  excluded_devices=("boot_drive_controller" "display")

  # Display available PCI devices with pagination
  page=0
  page_size=10
  total_devices=${#available_pci_devices[@]}
  max_pages=$((total_devices / page_size))
  if ((total_devices % page_size > 0)); then
    max_pages=$((max_pages + 1))
  fi

  while true; do
    clear
    echo "PCI devices available for passthrough (Page $((page + 1))/$max_pages):"
    start_index=$((page * page_size))
    end_index=$((start_index + page_size))

    for index in "${!available_pci_devices[@]}"; do
      if [[ index -ge start_index && index -lt end_index ]]; then
        pci_device="${available_pci_devices[index]}"
        if [[ ! " ${excluded_devices[@]} " =~ " ${pci_device} " ]]; then
          echo "$index: $pci_device"
          device_info=$(get_device_info "$pci_device")
          echo "$device_info"
          echo
        fi
      fi
    done

    read -n 1 -s -r -p "Press 'n' for the next page, 'p' for the previous page, or any other key to continue: " choice

    case $choice in
      "n")
        if ((page < max_pages - 1)); then
          page=$((page + 1))
        fi
        ;;

      "p")
        if ((page > 0)); then
          page=$((page - 1))
        fi
        ;;

      *)
        break
        ;;
    esac
  done

  # Prompt the user to select specific PCI devices or choose automatic passthrough
  read -r -p "Select specific PCI devices for passthrough (space-separated numbers) or press Enter for automatic passthrough: " selected_pci_indices

  if [ -z "$selected_pci_indices" ]; then
    # Automatic passthrough
    pci_device_options=""
    for index in "${!available_pci_devices[@]}"; do
      pci_device="${available_pci_devices[index]}"
      if [[ ! " ${excluded_devices[@]} " =~ " ${pci_device} " ]]; then
        pci_device_options+=" $pci_device"
      fi
    done
    echo "Automatically passthrough enabled for all available PCI devices except boot drive controller and display."
  else
    # Manual passthrough
    # Validate user choices
    valid_pci_devices=""
    for index in $selected_pci_indices; do
      if [[ "$index" =~ ^[0-9]+$ ]] && [ "$index" -lt "${#available_pci_devices[@]}" ]; then
        pci_device="${available_pci_devices[index]}"
        if [[ ! " ${excluded_devices[@]} " =~ " ${pci_device} " ]]; then
          valid_pci_devices+=" ${available_pci_devices[index]}"
        fi
      fi
    done

    if [ -z "$valid_pci_devices" ]; then
      echo "No valid PCI devices selected. Returning to the previous menu."
      return
    fi

    pci_device_options="$valid_pci_devices"
    echo "PCI passthrough configured for selected devices."
  fi

  pci_passthrough_enabled=true
}

# Function to toggle the enable/disable state of PCI passthrough
toggle_pci_passthrough() {
  if $pci_passthrough_enabled; then
    pci_passthrough_enabled=false
    echo "PCI passthrough disabled."
  else
    pci_passthrough_enabled=true
    echo "PCI passthrough enabled."
  fi
}

# Function to configure memory
configure_memory() {
  echo "Configuring memory..."
  echo "Memory Options:"
  echo "1. 256M"
  echo "2. 512M"
  echo "3. 1G"
  echo "4. 1.5G"
  echo "5. 2G"
  read -r -p "Select memory option: " memory_option

  case $memory_option in
    "1")
      memory="256M"
      memory_selected=true
      ;;
    "2")
      memory="512M"
      memory_selected=true
      ;;
    "3")
      memory="1G"
      memory_selected=true
      ;;
    "4")
      memory="1.5G"
      memory_selected=true
      ;;
    "5")
      memory="2G"
      memory_selected=true
      ;;
    *)
      echo "Invalid memory option. Please try again."
      ;;
  esac
}

# Function to view the current configuration
view_configuration() {
  echo "Current Configuration:"
  echo "BIOS Path: $bios_path"
  echo "ISO Path: $iso_path"
  echo "PCI Device Options: $pci_device_options"
  echo "Memory: $memory"
  echo "PCI Passthrough Enabled: $pci_passthrough_enabled"
  read -n 1 -s -r -p "Press any key to continue..."
}

# Function to exit the script without saving
exit_script() {
  echo "Exiting..."
  exit 0
}

# Function to run QEMU with the selected configuration
run_qemu() {
  # Determine if running on console or XWindows
  if [ -t 0 ]; then
    # Running on console
    qemu_cmd="qemu-system-ppc -L pc-bios -M pegasos2 -nographic -monitor telnet::45454,server,nowait -serial mon:stdio"
  else
    # Running on XWindows
    qemu_cmd="qemu-system-ppc -L pc-bios -M pegasos2 -vga none -device sm501 -serial stdio"
  fi

  # Build the full QEMU command
  qemu_cmd+=" -bios \"$bios_path\""

  # Set ISO options based on user configuration
  qemu_cmd+=" -drive if=none,id=cd,file=$iso_path,format=raw -device ide-cd,drive=cd,bus=ide.1"

  qemu_cmd+=" -device rtl8139,netdev=net0 -netdev user,id=net0"
  qemu_cmd+=" -rtc base=localtime"

  # Add memory options based on user configuration
  qemu_cmd+=" -m $memory"

  # Add PCI device options if configured and enabled
  if [ -n "$pci_device_options" ] && $pci_passthrough_enabled; then
    for pci_device in $pci_device_options; do
      qemu_cmd+=" -device vfio-pci,host=$pci_device"
    done
  fi

  echo "Starting QEMU with the following command:"
  echo "$qemu_cmd"

  # Check if running as root, elevate the script if necessary
  if [[ $EUID -ne 0 ]]; then
    echo "Not running as root. Elevating the script..."
    exec sudo -E "$0" --qemu-command "$qemu_cmd"
  else
    # Start QEMU with the selected configuration
    eval "$qemu_cmd"

    # Return to the main menu after QEMU exits
    echo "QEMU has exited. Returning to the main menu..."
    read -n 1 -s -r -p "Press any key to continue..."
  fi
}

# Function to download the Pegasos ROM
download_rom() {
  bios_url="http://web.archive.org/web/20071021223056/http://www.bplan-gmbh.de/up050404/up050404"
  bios_filename="up050404"

  echo "Downloading Pegasos ROM..."
  if curl -L -o "$bios_filename" "$bios_url"; then
    bios_path="./pegasos2.rom"
    bios_selected=true
    echo "Download successful."
    # Extract the ROM
    echo "Extracting Pegasos ROM..."
    tail -c +85581 "$bios_filename" | head -c 524288 > "pegasos2.rom"
    echo "Extraction successful."
  else
    echo "Download failed. Please try again."
  fi
}

# Function to download the MorphOS ISO
download_iso() {
  iso_url="https://morphos-team.net/morphos-3.18.iso"
  iso_filename="morphos-3.18.iso"

  echo "Downloading MorphOS installer/trial ISO..."
  if curl -L -o "$iso_filename" "$iso_url"; then
    iso_path="./$iso_filename"
    iso_selected=true
    echo "Download successful."
  else
    echo "Download failed. Please try again."
  fi
}

# Initialize variables
bios_selected=false
iso_selected=false
memory_selected=false
pci_passthrough_enabled=false

# Load the configuration
load_configuration

# Check if the script was invoked with a QEMU command
if [[ $# -gt 0 && $1 == "--qemu-command" ]]; then
  qemu_cmd=$2
  echo "Running QEMU with the provided command..."
  eval "$qemu_cmd"
  exit 0
fi

# Main loop
while true; do
  print_main_menu

  # Set timeout to 10 seconds for user input
  read -r -t 10 -p "Select an option (default: 2): " choice

  case $choice in
    "1")
      while true; do
        print_configuration_menu

        read -r -p "Select an option: " config_choice

        case $config_choice in
          "1")
            select_bios
            ;;

          "2")
            select_iso
            ;;

          "3")
            configure_pci_passthrough
            ;;

          "4")
            toggle_pci_passthrough
            ;;

          "5")
            configure_memory
            ;;

          "6")
            view_configuration
            ;;

          "7")
            save_configuration
            break # Return to the main menu
            ;;

          "8")
            break # Return to the main menu
            ;;

          *)
            echo "Invalid choice. Please try again."
            ;;
        esac
      done
      ;;

    "2" | "")
      if $bios_selected && $iso_selected && $memory_selected; then
        if [ -t 0 ]; then
          run_qemu
        else
          run_qemu -serial stdio
        fi
      else
        echo "Missing configuration settings. Please configure BIOS, ISO, and memory options before running QEMU."
      fi
      ;;

    "3")
      exit_script
      ;;

    *)
      echo "Invalid choice. Please try again."
      ;;
  esac
done
