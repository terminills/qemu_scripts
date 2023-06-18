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

# Function to determine the drive controller of the boot drive
determine_boot_drive_controller() {
  boot_drive_controller=""
  while IFS= read -r line; do
    read -r drive mount_point _ <<< "$line"
    if [[ $mount_point == "/" || $mount_point == "/boot" ]]; then
      boot_drive_controller=$(basename "$drive")
      break
    fi
  done < <(mount | grep -E '(/|/boot) ' | awk '{print $1,$2}')
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

# Function to print the configuration menu
print_menu() {
  clear
  echo "Configuration Menu:"
  echo "1. Reconfigure BIOS"
  echo "2. Reconfigure ISO"
  echo "3. Enable PCI passthrough"
  echo "4. Disable PCI passthrough"
  echo "5. Configure memory"
  echo "6. View current configuration"
  echo "7. Continue with existing configuration"
  echo "8. Exit"
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

  # Prompt the user to select a BIOS file
  read -r -p "Select a BIOS file (enter the number): " bios_index

  # Validate user choice
  if [[ "$bios_index" =~ ^[0-9]+$ ]] && [ "$bios_index" -lt "${#bios_files[@]}" ]; then
    bios_path="${bios_files[bios_index]}"
    bios_selected=true
  else
    echo "Invalid BIOS file selected. Please try again."
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

  # Prompt the user to select an ISO file
  read -r -p "Select an ISO file (enter the number): " iso_index

  # Validate user choice
  if [[ "$iso_index" =~ ^[0-9]+$ ]] && [ "$iso_index" -lt "${#iso_files[@]}" ]; then
    iso_path="${iso_files[iso_index]}"
    iso_selected=true
  else
    echo "Invalid ISO file selected. Please try again."
  fi
}

# Function to enable PCI passthrough
enable_pci_passthrough() {
  detect_pci_devices

  # Display available PCI devices
  echo "PCI devices available for passthrough:"
  for index in "${!available_pci_devices[@]}"; do
    pci_device="${available_pci_devices[index]}"
    echo "$index: $pci_device"
    device_info=$(get_device_info "$pci_device")
    echo "$device_info"
    echo
  done

  # Prompt the user to select specific PCI devices or choose automatic pass-through
  read -r -p "Select specific PCI devices (enter numbers separated by space) or choose automatic pass-through (A): " selection

  # Validate user choice
  if [[ "$selected_pci_indices" =~ ^[0-9\ ]+$ ]]; then
    selected_pci_indices=$selection
  elif [[ "$selection" =~ ^[Aa]$ ]]; then
    selected_pci_indices="auto"
  else
    echo "Invalid input. Exiting."
    exit 1
  fi

  if [[ "$selected_pci_indices" == "auto" ]]; then
  # Determine the drive controller of the boot drive
  determine_boot_drive_controller

  # Filter out the boot drive controller and the boot display
  filtered_pci_devices=()
  for pci_device in "${available_pci_devices[@]}"; do
    if [[ "$pci_device" != "$boot_drive_controller" ]]; then
      filtered_pci_devices+=("$pci_device")
    fi
  done

  if [[ "${#filtered_pci_devices[@]}" -eq 0 ]]; then
    echo "No PCI devices available for automatic pass-through. Exiting."
    exit 1
  fi

  selected_pci_indices=$(printf '%s\n' "${filtered_pci_devices[@]}")
fi

  pci_device_options="$selected_pci_indices"

  # Detach PCI devices from their current driver
  for pci_device in $pci_device_options; do
    # Run lspci -s to find the slot information and driver name
    slot_info=$(lspci -s "$pci_device" | awk '{print $1}')
    driver_name=$(basename "$(readlink "/sys/bus/pci/devices/$pci_device/driver")")
    # Detach the PCI device from the current driver
    detach_pci_device "$slot_info" "$driver_name"
  done

  # Attach PCI devices to VFIO driver
  for pci_device in $pci_device_options; do
    # Run lspci -v -s to find the vendor ID and device code
    vendor_id=$(lspci -v -s "$pci_device" | awk -F '[][]' '/Subsys/{print $2}')
    device_code=$(lspci -v -s "$pci_device" | awk -F '[][]' '/Subsys/{print $4}')
    # Attach the PCI device to the VFIO driver
    attach_pci_device "$vendor_id" "$device_code"
  done

  pci_passthrough_enabled=true

  echo "PCI passthrough enabled."
}

# Function to disable PCI passthrough
disable_pci_passthrough() {
  # Clear the stored PCI device options
  pci_device_options=""

  pci_passthrough_enabled=false

  echo "PCI passthrough disabled."
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

# Function to exit the script
exit_script() {
  echo "Exiting..."
  exit 0
}

# Function to run QEMU with the selected configuration
run_qemu() {
  if $pci_passthrough_enabled; then
    # Determine the drive controller of the boot drive
    determine_boot_drive_controller

    # Check if the boot drive controller is in the PCI device options
    if [[ -n $boot_drive_controller && "$pci_device_options" == *"$boot_drive_controller"* ]]; then
      echo "Cannot pass through the drive controller of the boot drive."
      read -n 1 -s -r -p "Press any key to continue..."
      return
    fi
  fi

  # Build the full QEMU command
  qemu_cmd="qemu-system-ppc -L pc-bios -M pegasos2"
  qemu_cmd+=" -bios \"$bios_path\""
  qemu_cmd+=" -vga none -device sm501"

  # Set ISO options based on user configuration
  qemu_cmd+=" -drive if=none,id=cd,file=$iso_path,format=raw -device ide-cd,drive=cd,bus=ide.1"

  qemu_cmd+=" -device rtl8139,netdev=net0 -netdev user,id=net0"
  qemu_cmd+=" -rtc base=localtime -serial stdio"

  # Add memory options based on user configuration
  qemu_cmd+=" -m $memory"

  # Add PCI device options if configured and enabled
  if [ -n "$pci_device_options" ] && $pci_passthrough_enabled; then
    qemu_cmd+=" $pci_device_options"
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

    # Return to the configuration menu after QEMU exits
    echo "QEMU has exited. Returning to the configuration menu..."
    read -n 1 -s -r -p "Press any key to continue..."
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
  print_menu

  read -r -p "Select an option: " choice

  case $choice in
    "1")
      select_bios
      ;;

    "2")
      select_iso
      ;;

    "3")
      enable_pci_passthrough
      ;;

    "4")
      disable_pci_passthrough
      ;;

    "5")
      configure_memory
      ;;

    "6")
      view_configuration
      ;;

    "7")
      if $bios_selected && $iso_selected && $memory_selected; then
        run_qemu
      else
        echo "Missing configuration settings. Please configure BIOS, ISO, and memory options before running QEMU."
      fi
      ;;

    "8")
      exit_script
      ;;

    *)
      echo "Invalid choice. Please try again."
      ;;
  esac
done
