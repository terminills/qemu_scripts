import os
import subprocess
import sys
import platform
import distro
import urllib.request

def download_file(url, destination):
    """
    Download a file from the given URL and save it to the destination path.
    """
    urllib.request.urlretrieve(url, destination)

def run_command(command):
    """
    Run a shell command and return the output.
    """
    process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, error = process.communicate()
    return output.decode().strip(), error.decode().strip()

def install_package(package):
    """
    Install a package using the system's package manager.
    """
    package_manager = get_package_manager()
    if package_manager:
        command = f"{package_manager} install -y {package}"
        output, error = run_command(command)
        print(f"Installed {package} successfully.")
    else:
        print("Package manager not found for your operating system.")
        sys.exit(1)

def get_package_manager():
    """
    Get the package manager based on the Linux distribution.
    """
    package_manager = ""
    dist_name = distro.id().lower()

    if dist_name in ["debian", "ubuntu"]:
        package_manager = "apt"
    elif dist_name in ["arch"]:
        package_manager = "pacman"
    elif dist_name in ["rhel", "centos"]:
        package_manager = "yum"

    return package_manager

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
        if system.lower() in dmesg_output.lower():
            print(f"Detected virtualization system: {system}")
            return system

    return None

def unbind_devices(system):
    """
    Unbind PCI devices from their current drivers based on the virtualization system.
    Flag the video card for testing PCI passthrough before other devices.
    """
    if system == "KVM":
        devices, _ = run_command("lspci -nn -D | grep 'VGA'")
        video_card_device = devices.split()[0]
        if video_card_device:
            command = f"sh -c 'echo 0000:{video_card_device} > /sys/bus/pci/devices/0000:{video_card_device}/driver/unbind'"
            output, error = run_command(command)
            print(f"Unbound video card device {video_card_device}.\nCommand: {command}\nOutput: {output}\nError: {error}")
        devices = devices.replace(video_card_device, "")  # Remove video card from the list of devices
        devices = devices.replace("\n", "")  # Remove newline characters
        devices = devices.split()  # Split remaining devices by whitespace
        for device in devices:
            if device:
                command = f"sh -c 'echo 0000:{device} > /sys/bus/pci/devices/0000:{device}/driver/unbind'"
                output, error = run_command(command)
                print(f"Unbound device {device}.\nCommand: {command}\nOutput: {output}\nError: {error}")
    elif system == "Xen":
        # Same as before, unbind VGA devices first
        devices, _ = run_command("lspci -nn -D | grep 'VGA'")
        video_card_device = devices.split()[0]
        if video_card_device:
            command = f"sh -c 'echo {video_card_device} > /sys/bus/pci/drivers/pciback/new_slot'"
            output, error = run_command(command)
            print(f"Unbound video card device {video_card_device}.\nCommand: {command}\nOutput: {output}\nError: {error}")
        devices = devices.replace(video_card_device, "")  # Remove video card from the list of devices
        devices = devices.replace("\n", "")  # Remove newline characters
        devices = devices.split()  # Split remaining devices by whitespace
        for device in devices:
            if device:
                command = f"sh -c 'echo {device} > /sys/bus/pci/drivers/pciback/new_slot'"
                output, error = run_command(command)
                print(f"Unbound device {device}.\nCommand: {command}\nOutput: {output}\nError: {error}")
    elif system == "VMware":
        # Same as before, unbind VGA devices first
        devices, _ = run_command("lspci -nn -D | grep 'VGA'")
        video_card_device = devices.split()[0]
        if video_card_device:
            command = f"sh -c 'echo {video_card_device} > /sys/bus/pci/drivers/vfio-pci/bind'"
            output, error = run_command(command)
            print(f"Bound video card device {video_card_device} to vfio-pci.\nCommand: {command}\nOutput: {output}\nError: {error}")
        devices = devices.replace(video_card_device, "")  # Remove video card from the list of devices
        devices = devices.replace("\n", "")  # Remove newline characters
        devices = devices.split()  # Split remaining devices by whitespace
        for device in devices:
            if device:
                command = f"sh -c 'echo {device} > /sys/bus/pci/drivers/vfio-pci/bind'"
                output, error = run_command(command)
                print(f"Bound device {device} to vfio-pci.\nCommand: {command}\nOutput: {output}\nError: {error}")
    elif system == "Microsoft Hyper-V":
        print("Hyper-V detected. No need to unbind devices.")
    else:
        print("Virtualization system not supported.")
        sys.exit(1)

def bind_device(device_ids):
    """
    Bind the specified device IDs to vfio-pci.
    """
    for device_id in device_ids:
        command = f"sh -c 'echo {device_id} > /sys/bus/pci/drivers/vfio-pci/new_id'"
        output, error = run_command(command)
        print(f"Bound device {device_id} to vfio-pci.\nCommand: {command}\nOutput: {output}\nError: {error}")

def build_qemu_command(device):
    """
    Build and execute QEMU commands for PCI passthrough.
    """
    command = f"qemu-system-x86_64 -nographic -m 4G -cpu host -device vfio-pci,host={device}"
    output, error = run_command(command)

    # Log the command
    with open("qemu_commands.log", "a") as f:
        f.write(f"QEMU Command: {command}\n")

    # Log the output
    if output:
        with open("qemu_output.log", "a") as f:
            f.write(f"QEMU Output ({device}): {output}\n")

    # Log the error
    if error:
        with open("qemu_errors.log", "a") as f:
            f.write(f"QEMU Error ({device}): {error}\n")

    # Return the output or error
    if not error:
        return output
    else:
        return error

def log_device_info(device_id, device_name, device_type, kernel_driver, unbind_location, qemu_device_config):
    """
    Log device information to a file.
    """
    with open("valid_pci_id.txt", "a") as f:
        f.write(f"PCI ID: {device_id}\n")
        f.write(f"Device Type: {device_type}\n")
        f.write(f"Kernel Driver: {kernel_driver}\n")
        f.write(f"Device Name: {device_name}\n")
        f.write(f"Unbind Location: {unbind_location}\n")
        f.write(f"QEMU Device Config: {qemu_device_config}\n\n")

def main():
    # Download TinyCore Linux ISO
    tinycore_url = "http://www.tinycorelinux.net/12.x/x86_64/release/CorePure64-12.0.iso"
    tinycore_destination = "./CorePure64-12.0.iso"

    print("Downloading TinyCore Linux...")
    download_file(tinycore_url, tinycore_destination)
    print("TinyCore Linux downloaded successfully.")

    # List of commands to check and install if missing
    required_commands = ["lspci", "dmesg", "qemu-system-x86_64"]
    check_and_install_commands(required_commands)

    virtualization_system = detect_virtualization()
    if virtualization_system:
        unbind_devices(virtualization_system)

        # Get a list of available PCI devices
        lspci_output, _ = run_command("lspci -nn -D")
        devices = []
        for line in lspci_output.split("\n"):
            devices.append(line.split()[0])

        # Bind devices to vfio-pci
        bind_device(devices)

        # Build and test QEMU commands for each device
        for device in devices:
            device_info, _ = run_command(f"lspci -nns {device}")
            device_info = device_info.strip()
            device_id = device_info.split()[0]
            device_name = " ".join(device_info.split()[1:-1])
            device_type = device_info.split()[-1]

            kernel_driver, _ = run_command(f"lspci -k -s {device}")
            kernel_driver = kernel_driver.strip().split(": ")[-1]

            unbind_location, _ = run_command(f"find /sys/devices -name {device}")
            unbind_location = unbind_location.strip()

            qemu_device_config = f"-device vfio-pci,host={device}"
            
            log_device_info(device_id, device_name, device_type, kernel_driver, unbind_location, qemu_device_config)

            print(f"Testing device: {device}")
            result = build_qemu_command(device)
            if "error" not in result.lower():
                print(f"Successfully ran QEMU command for device {device}.")
            else:
                print(f"Failed to run QEMU command for device {device}. Error: {result}")

    else:
        print("No supported virtualization system detected.")

if __name__ == "__main__":
    main()
