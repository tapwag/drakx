package help;

use common qw(:common);

%steps = (
selectLanguage =>
__("Choose preferred language for install and system usage."),

selectKeyboard =>
 __("Choose the layout corresponding to your keyboard from the list above"),

selectPath =>
 __("Choose \"Install\" if there are no previous versions of Linux
installed, or if you wish to use multiple distributions or versions.


Choose \"Upgrade\" if you wish to update a previous version of Mandrake
Linux: 5.1 (Venice), 5.2 (Leloo), 5.3 (Festen), 6.0 (Venus), 6.1
(Helios) or Gold 2000."),

selectInstallClass =>
 __("Select:

  - Recommended: If you have never installed Linux before.


  - Customized: If you are familiar with Linux, you will be able to 
select the usage for the installed system between normal, development or
server. Choose \"Normal\" for a general purpose installation of your
computer. You may choose \"Development\" if you will be using the computer
primarily for software development, or choose \"Server\" if you wish to
install a general purpose server (for mail, printing...).


  - Expert: If you are fluent with GNU/Linux and want to perform
a highly customized installation, this Install Class is for you. You will
be able to select the usage of your installed system as for \"Customized\"."),

setupSCSI =>
 __("DrakX will attempt at first to look for one or more PCI
SCSI adapter(s). If it finds it (or them)  and knows which driver(s)
to use, it will insert it (them)  automatically.


If your SCSI adapter is an ISA board, or is a PCI board but DrakX
doesn't know which driver to use for this card, or if you have no
SCSI adapters at all, you will then be prompted on whether you have
one or not. If you have none, answer \"No\". If you have one or more,
answer \"Yes\". A list of drivers will then pop up, from which you
will have to select one.


After you have selected the driver, DrakX will ask if you
want to specify options for it. First, try and let the driver
probe for the hardware: it usually works fine.


If not, do not forget the information on your hardware that you
could get from your documentation or from Windows (if you have it
on your system), as suggested by the installation guide. These
are the options you will need to provide to the driver."),

partitionDisks =>
 __("At this point, you may choose what partition(s) to use to install
your Linux-Mandrake system if they have been already defined (from a
previous install of Linux or from another partitionning tool). In other
cases, hard drive partitions must be defined. This operation consists of
logically dividing the computer's hard drive capacity into separate
areas for use.


If you have to create new partitions, use \"Auto allocate\" to automatically
create partitions for Linux. You can select the disk for partitionning by
clicking on \"hda\" for the first IDE drive,
\"hdb\" for the second or \"sda\" for the first SCSI drive and so on.


Two common partition are: the root partition (/), which is the starting
point of the filesystem's directory hierarchy, and /boot, which contains
all files necessary to start the operating system when the
computer is first turned on.


Because the effects of this process are usually irreversible, partitioning
can be intimidating and stressful to the unexperienced user. DiskDrake
simplifies the process so that it need not be. Consult the documentation
and take your time before proceeding."),

formatPartitions =>
 __("Any partitions that have been newly defined must be formatted for
use (formatting meaning creating a filesystem). At this time, you may
wish to re-format some already existing partitions to erase the data
they contain. Note: it is not necessary to re-format pre-existing
partitions, particularly if they contain files or data you wish to keep.
Typically retained are /home and /usr/local."),

choosePackages =>
 __("You may now select the packages you wish to install.


First you can select group of package to install or upgrade. After that
you can select more packages according to the total size you wish to
select.


If you are in expert mode, you can select packages individually.
Please note that some packages require the installation of others.
These are referred to as package dependencies. The packages you select,
and the packages they require will be automatically selected for
install. It is impossible to install a package without installing all
of its dependencies.


Informations on specific package are available in the
area titled \"Info\", located on the right of the list of
packages."),

doInstallStep =>
 __("The packages selected are now being installed. This operation
should take a few minutes unless you have chosen to upgrade an
existing system, in that case it can take more time even before
upgrade starts."),

selectMouse =>
 __("If DrakX failed to find your mouse, or if you want to
check what it has done, you will be presented the list of mice
above.


If you agree with DrakX' settings, just jump to the section
you want by clicking on it in the menu on the left. Otherwise,
choose a mouse type in the menu which you think is the closest
match for your mouse.


In case of a serial mouse, you will also have to tell DrakX
which serial port it is connected to."),

selectSerialPort =>
 __("Please select the correct port. For example, the COM1 port in MS Windows
is named ttyS0 in Linux."),

configureNetwork =>
 __("This section is dedicated to configuring a local area
network (LAN) or a modem.

Choose \"Local LAN\" and DrakX will
try to find an Ethernet adapter on your machine. PCI adapters
should be found and initialized automatically.
However, if your peripheral is ISA, autodetection will not work,
and you will have to choose a driver from the list that will appear then.


As for SCSI adapters, you can let the driver probe for the adapter
in the first time, otherwise you will have to specify the options
to the driver that you will have fetched from documentation of your
hardware.


If you install a Linux-Mandrake system on a machine which is part
of an already existing network, the network administrator will
have given you all necessary information (IP address, network
submask or netmask for short, and hostname). If you're setting
up a private network at home for example, you should choose
addresses.


Choose \"Dialup with modem\" and the Internet connection with
a modem will be configured. DrakX will try to find your modem,
if it fails you will have to select the right serial port where
your modem is connected to."),

configureNetworkIP =>
 __("Enter:

  - IP address: if you don't know it, ask your network administrator.


  - Netmask: \"255.255.255.0\" is generally a good choice. If you are not
sure, ask your network administrator.


  - Automatic IP: If your network uses bootp or dhcpd protocol, select 
this option. If selected, no value is needed in \"IP address\". If you are
not sure, ask your network administrator.
"),

configureNetworkISP =>
 __("You may now enter dialup options. If you're not sure what to enter, the
correct information can be obtained from your ISP."),

configureNetworkProxy =>
 __("If you will use proxies, please configure them now. If you don't know if
you will use proxies, ask your network administrator or your ISP."),

installCrypto =>
 __("You can install cryptographic package if your internet connection has been
set up correctly. First choose a mirror where you wish to download packages and
after that select the packages to install.

Note you have to select mirror and cryptographic packages according
to your legislation."),

configureTimezone =>
 __("You can now select your timezone according to where you live.


Linux manages time in GMT or \"Greenwich Meridian Time\" and translates it
in local time according to the time zone you have selected."),

configureServices =>
 __("Help"),

configurePrinter =>
 __("Linux can deal with many types of printer. Each of these
types require a different setup.


If your printer is directly connected to your computer, select
\"Local printer\". You will then have to tell which port your
printer is connected to, and select the appropriate filter.


If you want to access a printer located on a remote Unix machine,
you will have to select \"Remote lpd\". In order to make
it work, no username or password is required, but you will need
to know the name of the printing queue on this server.


If you want to access a SMB printer (which means, a printer located
on a remote Windows 9x/NT machine), you will have to specify its
SMB name (which is not its TCP/IP name), and possibly its IP address,
plus the username, workgroup and password required in order to
access the printer, and of course the name of the printer. The same goes
for a NetWare printer, except that you need no workgroup information."),

setRootPassword =>
 __("You can now enter the root password for your Linux-Mandrake
system. The password must be entered twice to verify that both
password entries are identical.


Root is the administrator of the system, and is the only user
allowed to modify the system configuration. Therefore, choose
this password carefully! Unauthorized use of the root account can
be extremely dangerous to the integrity of the system and its data,
and other systems connected to it. The password should be a
mixture of alphanumeric characters and a least 8 characters long. It
should *never* be written down. Do not make the password too long or
complicated, though: you must be able to remember without too much
effort."),

setRootPasswordMd5 =>
 __("To enable a more secure system, you should select \"Use shadow file\" and
\"Use MD5 passwords\"."),

setRootPasswordNIS =>
 __("If your network uses NIS, select \"Use NIS\". If you don't know, ask your
network administrator."),

addUser =>
 __("You may now create one or more \"regular\" user account(s), as
opposed to the \"privileged\" user account, root. You can create
one or more account(s) for each person you want to allow to use
the computer. Note that each user account will have its own
preferences (graphical environment, program settings, etc.)
and its own \"home directory\", in which these preferences are
stored.


First of all, create an account for yourself! Even if you will be the only user
of the machine, you may NOT connect as root for daily use of the system: it's a
very high security risk. Making the system unusable is very often a typo away.


Therefore, you should connect to the system using the user account
you will have created here, and login as root only for administration
and maintenance purposes."),

createBootdisk =>
 __("It is strongly recommended that you answer \"Yes\" here. If you install
Microsoft Windows at a later date it will overwrite the boot sector.
Unless you have made a bootdisk as suggested, you will not be able to
boot into Linux any more."),

setupBootloaderBeginner =>
 __("You need to indicate where you wish
to place the information required to boot to Linux.


Unless you know exactly what you are doing, choose \"First sector of
drive (MBR)\"."),

setupBootloader =>
 __("Unless you know specifically otherwise, the usual choice is \"/dev/hda\"
(the master drive on the primary channel)."),

setupBootloaderAddEntry =>
 __("LILO (the LInux LOader) can boot Linux and other operating systems.
Normally they are correctly detected during installation. If you don't
see yours detected, you can add one or more now.


If you don't want that everybody can access at one of them, you can remove
it now (a boot disk will be needed to boot it)."),

setupBootloaderGeneral =>
 __("LILO main options are:
  - Boot device: Sets the name of the device (e.g. a hard disk
partition) that contains the boot sector. Unless you know specifically
otherwise, choose \"/dev/hda\".


  - Linear: Generate linear sector addresses instead of
sector/head/cylinder addresses. Linear addresses are translated at run
time and do not depend on disk geometry. Note that boot disks may not be
portable if \"linear\" is used, because the BIOS service to determine the
disk geometry does not work reliably for floppy  disks. When using
\"linear\" with large disks, /sbin/lilo may generate references to
inaccessible disk areas, because 3D sector addresses are not known
before boot time.


  - Compact: Tries to merge read requests for adjacent sectors into a
single read request. This drastically reduces load time and keeps the
map smaller. Using \"compact\" is especially recommended when booting from
a floppy disk.


  - Delay before booting default image: Specifies the number in tenths
of a second the boot loader should wait before booting the first image.
This is useful on systems that immediately boot from the hard disk after
enabling the keyboard. The boot loader doesn't wait if \"delay\" is
omitted or is set to zero.


  - Video mode: This specifies the VGA text mode that should be selected
when booting. The following values are available: 
    * normal: select normal 80x25 text mode.
    * <number>:  use the corresponding text mode."),

configureX =>
 __("Now it's time to configure the X Window System, which is the
core of the Linux GUI (Graphical User Interface). For this purpose,
you must configure your video card and monitor. Most of these
steps are automated, though, therefore your work may only consist
of verifying what has been done and accept the settings :)


When the configuration is over, X will be started (unless you
ask DrakX not to) so that you can check and see if the
settings suit you. If they don't, you can come back and
change them, as many times as necessary."),

configureXmain =>
 __("If something is wrong in X configuration, use these options to correctly
configure the X Window System."),

configureXxdm =>
 __("If you prefer to use a graphical login, select \"Yes\". Otherwise, select
\"No\"."),

miscellaneous =>
 __("You can now select some miscellaneous options for you system.

  - Use hard drive optimizations: This option can improve hard disk
accesses but is only for advanced users, it can ruin your hard drive if
used incorrectly. Use it only if you know how.


  - Choose security level: You can choose a security level for your
system.
    Please refer to the manual for more information.


  - Precise RAM size if needed: In some cases, Linux is unable to
correctly detect all the installed RAM on  some systems. If this is the
case, specify the correct quantity. Note: a difference of 2 or 4 Mb is
normal.


  - Removable media automounting: If you would prefer not to manually
mount removable drives (CD-ROM, Floppy, Zip) by typing \"mount and
\"umount\", select this option. 


  - Enable Num Lock at startup: If you want Number Lock enabled after
booting, select this option (Note: Num Lock will still not work under
X)."),

exitInstall =>
 __("Your system is going to reboot.

After rebooting, your new Linux Mandrake system will load automatically.
If you want to boot into another existing operating system, please read
the additional instructions."),
);

#-#- ################################################################################
#-#- NO LONGER UP-TO-DATE...
#-%steps_long = (
#-selectLanguage =>
#- __("Choose preferred language for install and system usage."),
#-
#-selectKeyboard =>
#- __("Choose the layout corresponding to your keyboard from the list above"),
#-
#-selectPath =>
#- __("Choose \"Installation\" if there are no previous versions of Linux
#-installed, or if you wish to use multiple distributions or versions.
#-
#-
#-Choose \"Update\" if you wish to update a previous version of Mandrake
#-Linux: 5.1 (Venice), 5.2 (Leeloo), 5.3 (Festen) or 6.0 (Venus)."),
#-
#-selectInstallClass =>
#- __("Select:
#-
#-  - Beginner: If you have never installed Linux before, and wish to
#-install the distribution elected \"Product of the year\" for 1999,
#-click here.
#-
#-  - Developer: If you are familiar with Linux and will be using the
#-computer primarily for software development, you will find happiness
#-here.
#-
#-  - Server: If you wish to install a general purpose server, or the
#-Linux distribution elected \"Distribution/Server\" for 1999, select
#-this.
#-
#-  - Expert: If you are fluent with GNU/Linux and want to perform
#-a highly customized installation, this Install Class is for you."),
#-
#-setupSCSI =>
#- __("DrakX will attempt at first to look for one or more PCI
#-SCSI adapter(s). If it finds it (or them)  and knows which driver(s)
#-to use, it will insert it (them)  automatically.
#-
#-If your SCSI adapter is ISA, or is PCI but DrakX doesn't know
#-which driver to use for this card, or if you have no SCSI adapters
#-at all, you will then be prompted on whether you have one or not.
#-If you have none, answer \"No\". If you have one or more, answer
#-\"Yes\". A list of drivers will then pop up, from which you will
#-have to select one.
#-
#-After you have selected the driver, DrakX will ask if you
#-want to specify options for it. First, try and let the driver
#-probe for the hardware: it usually works fine.
#-
#-If not, do not forget the information on your hardware that you
#-could get from you documentation or from Windows (if you have
#-it on your system), as suggested by the installation guide.
#-These are the options you will need to provide to the driver."),
#-
#-partitionDisks =>
#- __("In this stage, you may choose what partition(s) use to install your
#-Linux-Mandrake system."),
#-
#-#At this point, hard drive partitions must be defined. (Unless you
#-#are overwriting a previous install of Linux and have already defined
#-#your hard drive partitions as desired.) This operation consists of
#-#logically dividing the computer's hard drive capacity into separate
#-#areas for use.
#-#
#-#
#-#Two common partition are: the root partition (/), which is the starting
#-#point of the filesystem's directory hierarchy, and /boot, which contains
#-#all files necessary to start the operating system when the
#-#computer is first turned on.
#-#
#-#
#-#Because the effects of this process are usually irreversible, partitioning
#-#can be intimidating and stressful to the unexperienced. DiskDrake
#-#simplifies the process so that it need not be. Consult the documentation
#-#and take your time before proceeding."),
#-
#-formatPartitions =>
#- __("Any partitions that have been newly defined must be formatted for
#-use (formatting meaning creating a filesystem). At this time, you may
#-wish to re-format some already existing partitions to erase the data
#-they contain. Note: it is not necessary to re-format pre-existing
#-partitions, particularly if they contain files or data you wish to keep.
#-Typically retained are /home and /usr/local."),
#-
#-choosePackages =>
#- __("You may now select the packages you wish to install.
#-
#-
#-Please note that some packages require the installation of others.
#-These are referred to as package dependencies. The packages you select,
#-and the packages they require will be automatically selected for
#-install. It is impossible to install a package without installing all
#-of its dependencies.
#-
#-
#-Information on each category and specific package is available in the
#-area titled \"Info\",  located between list of packages and the five
#-buttons \"Install\", \"Select more/less\" and \"Show more/less\"."),
#-
#-doInstallStep =>
#- __("The packages selected are now being installed.
#-
#-
#-This operation should take a few minutes."),
#-
#-selectMouse =>
#- __("If DrakX failed to find your mouse, or if you want to
#-check what it has done, you will be presented the list of mice
#-above.
#-
#-
#-If you agree with DrakX' settings, just jump to the section
#-you want by clicking on it in the menu on the left. Otherwise,
#-choose a mouse type in the menu which you think is the closest
#-match for your mouse.
#-
#-In case of a serial mouse, you will also have to tell DrakX
#-which serial port it is connected to."),
#-
#-configureNetwork =>
#- __("This section is dedicated to configuring a local area network,
#-or LAN. If you answer \"Yes\" here, DrakX will try to find an
#-Ethernet adapter on your machine. PCI adapters should be found and
#-initialized automatically. However, if your peripheral is ISA,
#-autodetection will not work, and you will have to choose a driver
#-from the list that will appear then.
#-
#-
#-As for SCSI adapters, you can let the driver probe for the adapter
#-in the first time, otherwise you will have to specify the options
#-to the driver that you will have fetched from Windows' control
#-panel.
#-
#-
#-If you install a Linux-Mandrake system on a machine which is part
#-of an already existing network, the network administrator will
#-have given you all necessary information (IP address, network
#-submask or netmask for short, and hostname). If you're setting
#-up a private network at home for example, you should choose
#-addresses "),
#-
#-configureTimezone =>
#- __("Help"),
#-
#-configureServices =>
#- __("Help"),
#-
#-configurePrinter =>
#- __("Linux can deal with many types of printer. Each of these
#-types require a different setup.
#-
#-
#-If your printer is directly connected to your computer, select
#-\"Local printer\". You will then have to tell which port your
#-printer is connected to, and select the appropriate filter.
#-
#-
#-If you want to access a printer located on a remote Unix machine,
#-you will have to select \"Remote lpd queue\". In order to make
#-it work, no username or password is required, but you will need
#-to know the name of the printing queue on this server.
#-
#-
#-If you want to access a SMB printer (which means, a printer located
#-on a remote Windows 9x/NT machine), you will have to specify its
#-SMB name (which is not its TCP/IP name), and possibly its IP address,
#-plus the username, workgroup and password required in order to
#-access the printer, and of course the name of the printer.The same goes
#-for a NetWare printer, except that you need no workgroup information."),
#-
#-setRootPassword =>
#- __("You must now enter the root password for your Linux-Mandrake
#-system. The password must be entered twice to verify that both
#-password entries are identical.
#-
#-
#-Root is the administrator of the system, and is the only user
#-allowed to modify the system configuration. Therefore, choose
#-this password carefully! Unauthorized use of the root account can
#-be extremely dangerous to the integrity of the system and its data,
#-and other systems connected to it. The password should be a
#-mixture of alphanumeric characters and a least 8 characters long. It
#-should *never* be written down. Do not make the password too long or
#-complicated, though: you must be able to remember without too much
#-effort."),
#-
#-addUser =>
#- __("You may now create one or more \"regular\" user account(s), as
#-opposed to the \"privileged\" user account, root. You can create
#-one or more account(s) for each person you want to allow to use
#-the computer. Note that each user account will have its own
#-preferences (graphical environment, program settings, etc.)
#-and its own \"home directory\", in which these preferences are
#-stored.
#-
#-
#-First of all, create an account for yourself! Even if you will be the only user
#-of the machine, you may NOT connect as root for daily use of the system: it's a
#-very high security risk. Making the system unusable is very often a typo away.
#-
#-
#-Therefore, you should connect to the system using the user account
#-you will have created here, and login as root only for administration
#-and maintenance purposes."),
#-
#-createBootdisk =>
#- __("Please, please, answer \"Yes\" here! Just for example, when you
#-reinstall Windows, it will overwrite the boot sector. Unless you have
#-made the bootdisk as suggested, you won't be able to boot into Linux
#-any more!"),
#-
#-setupBootloader =>
#- __("You need to indicate where you wish
#-to place the information required to boot to Linux.
#-
#-
#-Unless you know exactly what you are doing, choose \"First sector of
#-drive (MBR)\"."),
#-
#-configureX =>
#- __("Now it's time to configure the X Window System, which is the
#-core of the Linux GUI (Graphical User Interface). For this purpose,
#-you must configure your video card and monitor. Most of these
#-steps are automated, though, therefore your work may only consist
#-of verifying what has been done and accept the settings :)
#-
#-
#-When the configuration is over, X will be started (unless you
#-ask DrakX not to) so that you can check and see if the
#-settings suit you. If they don't, you can come back and
#-change them, as many times as necessary."),
#-
#-exitInstall =>
#- __("Help"),
#-);
