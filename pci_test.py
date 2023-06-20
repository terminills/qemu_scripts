import platform
import subprocess
import sys


def run_command(command):
    """
    Run a shell command and return the output and error.
    """
    process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, error = process.communicate()
    output = output.decode().strip()
    error = error.decode().strip()
    return output, error


def install_package(package):
    """
    Install a package using the system's package manager.
    """
    os_name = platform.system().lower()
    package_manager = ""

    if os_name in ["debian", "ubuntu"]:
        package_manager = "apt"
    elif os_name in ["arch"]:
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
    if system in ["KVM", "kvm", "Xen", "VMware"]:
        devices_output, _ = run_command("lspci -nn | grep 'VGA\|Audio\|USB' | cut -d ' ' -f 1")
        devices = devices_output.split("\n")
        for device in devices:
            if device:
                unbind_command = f"sudo sh -c 'echo 0000:{device} > /sys/bus/pci/devices/0000:{device}/driver/unbind'"
                output, error = run_command(unbind_command)
                if error:
                    print(f"Failed to unbind device {device}. Error: {error}")
                else:
                    print(f"Unbound device {device} successfully.")
    elif system == "Microsoft Hyper-V":
        print("Hyper-V detected. No need to unbind devices.")
    else:
        print("Virtualization system not supported.")
        sys.exit(1)


def bind_devices(system):
    """
    Bind PCI devices to their appropriate drivers based on the virtualization system.
    """
    if system in ["KVM", "kvm", "Xen", "VMware"]:
        devices_output, _ = run_command("lspci -nn | grep 'VGA\|Audio\|USB' | cut -d ' ' -f 1")
        devices = devices_output.split("\n")
        for device in devices:
            if device:
                bind_command = f"sudo sh -c 'echo {device} > /sys/bus/pci/drivers/{system.lower()}/bind'"
                output, error = run_command(bind_command)
                if error:
                    print(f"Failed to bind device {device}. Error: {error}")
                else:
                    print(f"Bound device {device} successfully.")
    elif system == "Microsoft Hyper-V":
        print("Hyper-V detected. No need to bind devices.")
    else:
        print("Virtualization system not supported.")
        sys.exit(1)


def test_devices_with_qemu(devices):
    """
    Test the devices using QEMU.
    """
    for device in devices:
        print(f"Testing device: {device}")
        qemu_command = f"qemu-system-x86_64 -nographic -enable-kvm -m 4G -cpu host -device vfio-pci,host={device}"
        output, error = run_command(qemu_command)
        if error:
            print(f"Failed to run QEMU command for device {device}. Error: {error}")
        else:
            print(f"Successfully ran QEMU command for device {device}.")


def release_devices(system, devices):
    """
    Release the devices from their virtualization bindings.
    """
    if system in ["KVM", "kvm", "Xen", "VMware"]:
        for device in devices:
            if device:
                release_command = f"sudo sh -c 'echo {device} > /sys/bus/pci/drivers/{system.lower()}/unbind'"
                output, error = run_command(release_command)
                if error:
                    print(f"Failed to release device {device}. Error: {error}")
                else:
                    print(f"Released device {device} successfully.")
    elif system == "Microsoft Hyper-V":
        print("Hyper-V detected. No need to release devices.")
    else:
        print("Virtualization system not supported.")
        sys.exit(1)


def main():
    # List of commands to check and install if missing
    required_commands = ["lshw", "lspci", "dmesg", "qemu-system-x86_64"]

    check_and_install_commands(required_commands)
    virtualization_system = detect_virtualization()

    if virtualization_system:
        print(f"Detected virtualization system: {virtualization_system}")

        print("Unbinding devices...")
        unbind_devices(virtualization_system)

        # Get a list of available PCI devices
        lspci_output, _ = run_command("lspci -nn")
        devices = [line.split()[0] for line in lspci_output.split("\n")]

        print("Binding devices...")
        bind_devices(virtualization_system)

        print("Testing devices with QEMU...")
        test_devices_with_qemu(devices)

        print("Releasing devices...")
        release_devices(virtualization_system, devices)

    else:
        print("No supported virtualization system detected.")


if __name__ == "__main__":
    main()
