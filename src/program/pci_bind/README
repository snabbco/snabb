Usage:
  pci_bind [-ubir] <PCI-ADDRESS>
  pci_bind [-ah]

  -a, --all
                             Restore all PCI addresses to kernel management
  -b, --bind <PCI-ADDRESS>
                             Bind the PCI address to the kernel
  -h, --help
                             Print usage information
  -i, --info <PCI-ADDRESS>
                             Print out the associated Linux interface name
  -r, --remove <PCI-ADDRESS>
                             Remove the specified PCI address
  -u, --unbind <PCI-ADDRESS>
                             Unbind the PCI address, so Snabb can use it

Manage PCI interfaces, readying them for Snabb or returning them to kernel
management.

Bind the specified PCI address, giving management to the Linux kernel with -b.
With -u, instead unbind the specified PCI address, readying it for use by Snabb.

Note that after using -r, a full PCI rescan is needed to use the device again,
which by default will bring all of the unbound network interfaces back under
kernel management. If you would like to avoid this, use -u and -b instead.

Both short-form and long-form PCI addresses are fine: 01:1f.3 or 0000:01:1f.3.


Examples:

Unbind PCI adress 01:00.0 from the kernel, readying it for Snabb.
pci_bind -u 01:00.0

Bind only 01:00.0 to the kernel, readying it for non-Snabb use.
pci_bind -b 01:00.0

Have the kernel take over all cards again:
pci_bind -a

Find the interface name of a Linux-managed card from the PCI address.
pci_bind -i 01:00.0

Make the kernel entirely forget about a PCI address.
This can be run before pci_bind -a; it does not make a card usable by Snabb.
Occasionally a card cannot be re-bound before doing this.
pci_bind -r 01:00.0
