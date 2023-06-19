#!/bin/bash

LOG_FILE="pci_passthrough.log"

# Function to log messages to the log file
log_message() {
    local message="$1"
    echo "$(date): $message" >> "$LOG_FILE"
}

# Function to retrieve the hardware name of a PCI device
get_hardware_name() {
    local device="$1"
    local hardware_name=""

    # Use lspci to retrieve the hardware name
    if hardware_name=$(lspci -vmm -s "$device" | awk -F'\t' '/^Device:/ { $1=""; print $0 }'); then
        # Trim leading and trailing spaces
        hardware_name="${hardware_name#"${hardware_name%%[![:space:]]*}"}"
        hardware_name="${hardware_name%"${hardware_name##*[![:space:]]}"}"
    fi

    echo "$hardware_name"
}

# Function to retrieve the controller information of a device using udevadm
get_controller_info() {
    local device="$1"
    local controller_info=""

    if controller_info=$(udevadm info -q path -n "$device"); then
        # Extract the controller path from the udevadm output
        controller_info="${controller_info%/*}"
        # Retrieve the controller name from the path
        controller_info="${controller_info##*/}"
    fi

    echo "$controller_info"
}

# Function to determine if a PCI device is the boot device
is_boot_device() {
    local device="$1"

    # Get the controller information of the device
    local controller_info="$(get_controller_info "$device")"

    # Scan the mount points and check if any of them match the boot controller
    local mount_points=($(lsblk -P -o MOUNTPOINT | grep -v "MOUNTPOINT=\"\""))

    for mount_point in "${mount_points[@]}"; do
        # Get the controller information of the mount point
        local mount_controller_info="$(get_controller_info "$mount_point")"

        # Compare the controller information to determine if it's the boot device
        if [ "$controller_info" = "$mount_controller_info" ]; then
            return 0
        fi
    done

    return 1
}

# Function to check if a PCI device is compatible with passthrough for a specific system
check_device_compatibility() {
    local device="$1"
    local system="$2"
    local driver_override_file="/sys/bus/pci/devices/$device/driver_override"
    local driver_directory=""

    case "$system" in
        "xen")
            driver_directory="/sys/bus/pci/drivers/xen-pciback"
            ;;
        "vfio")
            driver_directory="/sys/bus/pci/drivers/vfio-pci"
            ;;
        "virtio")
            driver_directory="/sys/bus/pci/drivers/virtio-pci"
            ;;
        # Add more cases for other systems if needed
        *)
            log_message "Unsupported system: $system"
            return 1
            ;;
    esac

    # Check if the driver override file exists
    if [ -e "$driver_override_file" ]; then
        # Check if the device is already bound to the driver
        if [ "$(readlink "$driver_directory/$device")" != "$device" ]; then
            local device_info="$(lspci -vmm -s "$device")"
            local device_type="$(echo "$device_info" | awk -F: '/^Class/{print $2}' | xargs)"
            local hardware_name="$(get_hardware_name "$device")"
            local is_boot=""

            # Check if the device is the boot device
            if is_boot_device "/dev/$device"; then
                is_boot=" (Boot Device)"
            fi

            log_message "PCI Device: $device"
            log_message "Hardware Name: $hardware_name$is_boot"
            log_message "Driver: $system"
            log_message "Device Type: $device_type"
            log_message "Compatibility: Compatible"

            # Generate and log QEMU settings based on device type
            generate_qemu_settings "$device_type" "$system"

            log_message ""
            return 0
        else
            log_message "PCI Device: $device"
            log_message "Hardware Name: $(get_hardware_name "$device")"
            log_message "Driver: $system"
            log_message "Compatibility: Already bound to $system"
            log_message ""
            return 0
        fi
    else
        log_message "PCI Device: $device"
        log_message "Hardware Name: $(get_hardware_name "$device")"
        log_message "Driver: Unknown"
        log_message "Compatibility: Incompatible"
        log_message ""
        return 1
    fi
}

# Function to generate QEMU settings based on the device type and system
generate_qemu_settings() {
    local device_type="$1"
    local system="$2"

    case "$device_type" in
        "SCSI storage controller")
            case "$system" in
                "xen")
                    log_message "QEMU Settings: -device xen-scsi"
                    ;;
                "vfio")
                    log_message "QEMU Settings: -device virtio-scsi-pci"
                    ;;
                "virtio")
                    log_message "QEMU Settings: -device virtio-scsi-pci"
                    ;;
            esac
            ;;
        "3D controller")
            case "$system" in
                "xen")
                    log_message "QEMU Settings: -device xen-vga"
                    ;;
                "vfio")
                    log_message "QEMU Settings: -device virtio-vga"
                    ;;
                "virtio")
                    log_message "QEMU Settings: -device virtio-vga"
                    ;;
            esac
            ;;
        "System peripheral")
            case "$system" in
                "xen")
                    log_message "QEMU Settings: -device xen-balloon"
                    ;;
                "vfio")
                    log_message "QEMU Settings: -device virtio-balloon"
                    ;;
                "virtio")
                    log_message "QEMU Settings: -device virtio-balloon"
                    ;;
            esac
            ;;
        "VGA compatible controller")
            case "$system" in
                "xen")
                    log_message "QEMU Settings: -device xen-vga"
                    ;;
                "vfio")
                    log_message "QEMU Settings: -device vfio-pci,host=01:00.0,multifunction=on"
                    ;;
                "virtio")
                    log_message "QEMU Settings: -device virtio-vga"
                    ;;
            esac
            ;;
        "Audio device")
            case "$system" in
                "xen")
                    log_message "QEMU Settings: -device xen-ac97"
                    ;;
                "vfio")
                    log_message "QEMU Settings: -device vfio-pci,host=00:1f.3"
                    ;;
                "virtio")
                    log_message "QEMU Settings: -device ac97"
                    ;;
            esac
            ;;
        "USB controller")
            case "$system" in
                "xen")
                    log_message "QEMU Settings: -device xen-usb"
                    ;;
                "vfio")
                    log_message "QEMU Settings: -device vfio-pci,host=00:14.0"
                    ;;
                "virtio")
                    log_message "QEMU Settings: -device usb-host"
                    ;;
            esac
            ;;
        "Ethernet controller")
            case "$system" in
                "xen")
                    log_message "QEMU Settings: -device xen-netfront"
                    ;;
                "vfio")
                    log_message "QEMU Settings: -device vfio-pci,host=00:19.0"
                    ;;
                "virtio")
                    log_message "QEMU Settings: -device virtio-net-pci"
                    ;;
            esac
            ;;
        "IDE interface")
            case "$system" in
                "xen")
                    log_message "QEMU Settings: -device xen-ide"
                    ;;
                "vfio")
                    log_message "QEMU Settings: -device ide-hd,bus=ide.0,drive=mydrive"
                    ;;
                "virtio")
                    log_message "QEMU Settings: -device ide-hd,bus=ide.0,drive=mydrive"
                    ;;
            esac
            ;;
        # Add more cases for other device types if needed
        *)
            log_message "QEMU Settings: No specific settings for device type '$device_type'"
            ;;
    esac
}

# Function to scan and test all PCI devices for passthrough compatibility against each system
scan_pci_devices() {
    local devices=($(find /sys/bus/pci/devices/* -maxdepth 0 -type l))

    for device in "${devices[@]}"; do
        device="${device##*/}"

        log_message "PCI Device: $device"
        log_message "Hardware Name: $(get_hardware_name "$device")"
        log_message ""

        check_device_compatibility "$device" "xen"
        check_device_compatibility "$device" "vfio"
        check_device_compatibility "$device" "virtio"

        log_message ""
    done
}

# Main script
{
    log_message "Running PCI device scan and compatibility test..."
    log_message ""

    scan_pci_devices

} > "$LOG_FILE" 2>&1
