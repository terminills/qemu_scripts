import subprocess
import sys
import time
import distro


def run_command(command):
    """
    Run a shell command and return the output.
    """
    process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, error = process.communicate()
    return output.decode().strip()


def install_package(package):
    """
    Install a package using the system's package manager.
    """
    distro_name = distro.id().lower()
    package_manager = ""

    if distro_name in ["debian", "ubuntu"]:
        package_manager = "apt"
    elif distro_name in ["arch", "archlinux", "arch linux"]:
        package_manager = "pacman"
    elif distro_name in ["rhel", "centos"]:
        package_manager = "yum"

    if package_manager:
        command = f"{package_manager} install -y {package}"
        if os.geteuid() != 0:
            command = f"sudo {command}"
        run_command(command)
        print(f"Installed {package} successfully.")
    else:
        print("Package manager not found for your operating system.")
        sys.exit(1)
def check_and_install_commands(commands):
    """
    Check if commands are available and install missing ones.
    """
    for command in commands:
        output = run_command(f"which {command}")
        if not output:
            install_package(command)


def detect_virtualization():
    """
    Detect the virtualization system enabled on the kernel.
    """
    dmesg_output = run_command("dmesg")
    virtualization_systems = ["KVM", "kvm", "Xen", "VMware", "Microsoft Hyper-V"]

    for system in virtualization_systems:
        if system in dmesg_output:
            print(f"Detected virtualization system: {system}")
            return system

    return None


def unbind_devices(system):
    """
    Unbind PCI devices from their current drivers based on the virtualization system.
    """
    if system.lower() in ["kvm", "xen"]:
        devices = run_command("lspci -nn -D | grep 'VGA\|Audio\|USB' | cut -d ' ' -f 1")
        for device in devices.split("\n"):
            if device:
                location = run_command(f"find /sys/devices -name {device}")
                if location:
                    run_command(f"sh -c 'echo {device} > {location}/driver/unbind'")
                    with open("unbind_device.log", "a") as f:
                        f.write(f"Unbinding Location ({device}): {location}\n")
    elif system == "VMware":
        devices = run_command("lspci -nn -D | grep 'VGA\|Audio\|USB' | cut -d ' ' -f 1")
        for device in devices.split("\n"):
            if device:
                run_command(f"sh -c 'echo {device} > /sys/bus/pci/drivers/vfio-pci/bind'")
    elif system == "Microsoft Hyper-V":
        print("Hyper-V detected. No need to unbind devices.")
    else:
        print("Virtualization system not supported.")
        sys.exit(1)


def bind_device(device, driver):
    """
    Bind a device to a specific driver.
    """
    location = run_command(f"find /sys/devices -name {device}")
    if location:
        run_command(f"sh -c 'echo {device} > {location}/driver_override'")
        run_command(f"sh -c 'echo {driver} > {location}/driver/unbind'")
        run_command(f"sh -c 'echo {device} > /sys/bus/pci/drivers/{driver}/bind'")
        time.sleep(1)  # Wait for the device to bind


def get_pci_device_type(device):
    """
    Get the type of the PCI device using lshw.
    """
    output = run_command("lshw -businfo")
    lines = output.split("\n")
    device_type = None

    for line in lines:
        if device in line:
            columns = line.split()
            device_type = columns[2]
            break

    return device_type


def build_qemu_command(device):
    """
    Build and execute QEMU commands for PCI passthrough.
    """
    command = f"qemu-system-ppc -nographic -enable-kvm -m 1G -cpu host -device vfio-pci,host={device}"

    # Run the command and capture the output and error
    process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, error = process.communicate()
    output = output.decode().strip()
    error = error.decode().strip()

    # Log the output
    if output:
        print("QEMU Output:", output)

    # Log the error
    if error:
        with open("qemu_errors.log", "a") as f:
            f.write(f"QEMU Error ({device}): {error}\n")

    # Return the output or error
    if process.returncode == 0:
        return output
    else:
        return error


def log_valid_pci_ids(pci_id, device_type, kernel_driver, device_name, unbind_location, qemu_device_config):
    """
    Log valid PCI IDs, device types, kernel driver, device name, unbind location, and QEMU device configurations in a file.
    """
    with open("valid_pci_id.txt", "a") as f:
        f.write(f"PCI ID: {pci_id}\n")
        f.write(f"Device Type: {device_type}\n")
        f.write(f"Kernel Driver: {kernel_driver}\n")
        f.write(f"Device Name: {device_name}\n")
        f.write(f"Unbind Location: {unbind_location}\n")
        f.write(f"QEMU Device Config: {qemu_device_config}\n\n")


def main():
    # List of commands to check and install if missing
    required_commands = ["lshw", "lspci", "dmesg", "qemu-system-x86_64"]

    check_and_install_commands(required_commands)
    virtualization_system = detect_virtualization()

    if virtualization_system:
        unbind_devices(virtualization_system)

        # Get a list of available PCI devices
        lspci_output = run_command("lspci -nn -D")
        devices = []
        for line in lspci_output.split("\n"):
            device_info = line.split(" ")[0]
            if device_info:
                devices.append(device_info)

        # Build and test QEMU commands for each device
        for device in devices:
            print(f"Testing device: {device}")
            device_type = get_pci_device_type(device)
            output = run_command(f"lspci -nn -D -v -s {device}")
            kernel_driver = ""
            device_name = ""
            unbind_location = ""
            for line in output.split("\n"):
                if "Kernel driver in use:" in line:
                    kernel_driver = line.split(": ")[-1]
                elif "DeviceName:" in line:
                    device_name = line.split(": ")[-1]
                elif "Unbind location:" in line:
                    unbind_location = line.split(": ")[-1]
            result = build_qemu_command(device)
            if "error" not in result.lower():
                log_valid_pci_ids(device, device_type, kernel_driver, device_name, unbind_location,
                                  f"vfio-pci,host={device}")
                bind_device(device, kernel_driver)
                time.sleep(1)  # Wait for the device to bind
                # Put the device back one by one
                bind_device(device, "vfio-pci")
            else:
                print(f"Failed to run QEMU command for device {device}. Error: {result}")

            choice = input("Press Enter to continue or 's' to skip the next device test: ")
            if choice.lower() == "s":
                print("Skipping the next device test.")
                break
    else:
        print("No supported virtualization system detected.")


if __name__ == "__main__":
    main()
