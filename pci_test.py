import urllib.request
import platform
import subprocess
import sys
import os
import distro

def run_command(command):
    """
    Run a shell command and return the output and error.
    """
    process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, error = process.communicate()
    return output.decode().strip(), error.decode().strip()

def install_package(package):
    """
    Install a package using the system's package manager.
    """
    os_name = distro.name().lower()
    package_manager = ""

    if os_name in ["debian", "ubuntu"]:
        package_manager = "apt"
    elif os_name == "arch":
        package_manager = "pacman"
    elif os_name in ["rhel", "centos"]:
        package_manager = "yum"

    if package_manager:
        command = f"sudo {package_manager} install -y {package}"
        output, error = run_command(command)
        if error:
            print(f"Failed to install {package}. Error: {error}")
        else:
            print(f"Installed {package} successfully.")
    else:
        print("Package manager not found for your operating system.")
        sys.exit(1)

def check_and_install_commands(commands):
    """
    Check if commands are available and install missing ones.
    """
    for command in commands:
        output, _ = run_command(f"which {command}")
        if not output:
            install_package(command)

def detect_virtualization():
    """
    Detect the virtualization system enabled on the kernel.
    """
    dmesg_output, _ = run_command("dmesg")
    virtualization_systems = ["KVM", "Xen", "VMware", "Microsoft Hyper-V"]

    for system in virtualization_systems:
        if system in dmesg_output:
            print(f"Detected virtualization system: {system}")
            return system

    return None

def unbind_devices(system):
    """
    Unbind PCI devices from their current drivers based on the virtualization system.
    """
    if system in ["KVM", "Xen", "VMware"]:
        devices, _ = run_command("lspci -nn | grep 'VGA' | cut -d ' ' -f 1")
        for device in devices.split("\n"):
            if device:
                command = f"sudo sh -c 'echo {device} > /sys/bus/pci/drivers/pciback/new_slot'"
                output, error = run_command(command)
                if error:
                    print(f"Failed to unbind device {device}. Error: {error}")
                else:
                    print(f"Unbound device {device} successfully.")
    elif system == "Microsoft Hyper-V":
        print("Hyper-V detected. No need to unbind devices.")
    else:
        print("Virtualization system not supported.")
        sys.exit(1)

def bind_device(device_id):
    command = f"sudo modprobe vfio-pci ids={device_id}"
    output, error = run_command(command)
    if error:
        print(f"Failed to bind device {device_id} with vfio-pci. Error: {error}")
    else:
        print(f"Bound device {device_id} with vfio-pci successfully.")

def download_file(url, destination):
    try:
        urllib.request.urlretrieve(url, destination)
        print(f"Downloaded file from {url} successfully.")
    except Exception as e:
        print(f"Failed to download file from {url}. Error: {e}")

def main():
    required_commands = ["lspci", "dmesg", "modprobe"]
    check_and_install_commands(required_commands)

    virtualization_system = detect_virtualization()

    if virtualization_system:
        unbind_devices(virtualization_system)

        # Find and bind the VGA card with vfio-pci
        vga_card_device_id = ""
        devices, _ = run_command("lspci -nn | grep 'VGA' | cut -d ' ' -f 1")
        for device in devices.split("\n"):
            if device:
                vga_card_device_id = device
                bind_device(vga_card_device_id)
                break

        if vga_card_device_id:
            # Download TinyCore Linux ISO
            iso_url = "http://tinycorelinux.net/14.x/x86/release/Core-current.iso"
            iso_destination = "tinycore.iso"
            download_file(iso_url, iso_destination)

            # Run QEMU with TinyCore Linux ISO
            qemu_command = f"qemu-system-x86_64 -nographic -enable-kvm -m 4G -cpu host -device vfio-pci,host={vga_card_device_id} -cdrom {iso_destination}"
            output, error = run_command(qemu_command)
            if error:
                print(f"Failed to run QEMU. Error: {error}")
            else:
                print("QEMU started successfully.")
        else:
            print("No VGA card found for binding.")
    else:
        print("No supported virtualization system detected.")

if __name__ == "__main__":
    main()
