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

def install_package_apt(package):
    """
    Install a package using apt package manager (Debian, Ubuntu).
    """
    command = f"apt-get install -y {package}"
    output, error = run_command(command)
    if error:
        print(f"Failed to install {package}. Error: {error}")
    else:
        print(f"Installed {package} successfully.")

def install_package_pacman(package):
    """
    Install a package using pacman package manager (Arch Linux).
    """
    command = f"pacman -Syu --noconfirm {package}"
    output, error = run_command(command)
    if error:
        print(f"Failed to install {package}. Error: {error}")
    else:
        print(f"Installed {package} successfully.")

def install_package_yum(package):
    """
    Install a package using yum package manager (RHEL, CentOS).
    """
    command = f"yum install -y {package}"
    output, error = run_command(command)
    if error:
        print(f"Failed to install {package}. Error: {error}")
    else:
        print(f"Installed {package} successfully.")

def check_and_install_commands(commands):
    """
    Check if commands are available and install missing ones.
    """
    for command in commands:
        output, _ = run_command(f"which {command}")
        if not output:
            os_name = distro.name().lower()
            if os_name in ["debian", "ubuntu"]:
                install_package_apt(command)
            elif os_name == "arch":
                install_package_pacman(command)
            elif os_name in ["rhel", "centos"]:
                install_package_yum(command)
            else:
                print(f"Package manager not found for {command}. Please install it manually.")

def detect_virtualization():
    """
    Detect the virtualization system enabled on the kernel.
    """
    dmesg_output, _ = run_command("dmesg")
    virtualization_systems = ["KVM", "Xen", "VMware", "Microsoft Hyper-V"]

    for system in virtualization_systems:
        if system.lower() in dmesg_output.lower():
            print(f"Detected virtualization system: {system}")
            return system

    return None

def unbind_devices(system):
    """
    Unbind PCI devices from their current drivers based on the virtualization system.
    """
    if system.lower() == "kvm":
        devices, _ = run_command("lspci -D -nn | grep 'VGA' | cut -d ' ' -f 1")
        for device in devices.split("\n"):
            if device:
                command = f"sh -c 'echo 0000:{device} > /sys/bus/pci/devices/0000:{device}/driver/unbind'"
                output, error = run_command(command)
                if error:
                    print(f"Failed to unbind device {device}. Error: {error}")
                else:
                    print(f"Unbound device {device} successfully.")
    elif system.lower() == "xen":
        devices, _ = run_command("lspci -D -nn | grep 'VGA' | cut -d ' ' -f 1")
        for device in devices.split("\n"):
            if device:
                command = f"sh -c 'echo {device} > /sys/bus/pci/drivers/pciback/new_slot'"
                output, error = run_command(command)
                if error:
                    print(f"Failed to unbind device {device}. Error: {error}")
                else:
                    print(f"Unbound device {device} successfully.")
    elif system.lower() == "vmware":
        devices, _ = run_command("lspci -D -nn | grep 'VGA' | cut -d ' ' -f 1")
        for device in devices.split("\n"):
            if device:
                command = f"sh -c 'echo {device} > /sys/bus/pci/drivers/vfio-pci/bind'"
                output, error = run_command(command)
                if error:
                    print(f"Failed to unbind device {device}. Error: {error}")
                else:
                    print(f"Unbound device {device} successfully.")
    elif system.lower() == "microsoft hyper-v":
        print("Hyper-V detected. No need to unbind devices.")
    else:
        print("Virtualization system not supported.")
        sys.exit(1)

def log_pci_device_info(device_id):
    """
    Log information about the PCI device.
    """
    output, _ = run_command(f"lspci -D -nn -s {device_id}")
    with open("pci_devices.log", "a") as f:
        f.write(f"Device ID: {device_id}\n")
        f.write(f"Device Info: {output}\n\n")

def bind_device(device_id):
    """
    Bind the specified device to vfio-pci driver.
    """
    command = f"sh -c 'echo {device_id} > /sys/bus/pci/drivers/vfio-pci/bind'"
    output, error = run_command(command)
    if error:
        print(f"Failed to bind device {device_id}. Error: {error}")
    else:
        print(f"Bound device {device_id} successfully.")

def download_file(url, destination):
    """
    Download a file from the specified URL and save it to the destination path.
    """
    try:
        urllib.request.urlretrieve(url, destination)
        print(f"Downloaded file from {url} to {destination} successfully.")
    except Exception as e:
        print(f"Failed to download file from {url}. Error: {e}")

def main():
    required_commands = ["lspci", "dmesg"]
    check_and_install_commands(required_commands)

    virtualization_system = detect_virtualization()

    if virtualization_system:
        unbind_devices(virtualization_system)

        # Find and bind the VGA card with vfio-pci
        vga_card_device_id = ""
        devices, _ = run_command("lspci -D -nn | grep 'VGA' | cut -d ' ' -f 1")
        for device in devices.split("\n"):
            if device:
                vga_card_device_id = device
                bind_device(vga_card_device_id)
                log_pci_device_info(vga_card_device_id)
                break

        if vga_card_device_id:
            # Download TinyCore Linux ISO
            iso_url = "http://tinycorelinux.net/14.x/x86/release/Core-current.iso"
            iso_destination = "tinycore.iso"
            download_file(iso_url, iso_destination)

            # Run QEMU with TinyCore Linux ISO
            qemu_command = f"qemu-system-x86_64 -m 2G -boot d -cdrom {iso_destination}"
            output, error = run_command(qemu_command)
            if error:
                print(f"Failed to run QEMU command. Error: {error}")

            # Re-bind the VGA card to its original driver
            bind_device(vga_card_device_id)

        else:
            print("No VGA card found for passthrough.")

    else:
        print("No supported virtualization system detected.")

if __name__ == "__main__":
    main()
