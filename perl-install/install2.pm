
package install2; # $Id$

use diagnostics;
use strict;
use Data::Dumper;

use vars qw($o $version);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :file :system :functional);
use install_any qw(:all);
use install_steps;
use commands;
use lang;
use keyboard;
use mouse;
use fsedit;
use devices;
use partition_table qw(:types);
use modules;
use detect_devices;
use run_program;
use log;
use fs;

$::VERSION = "7.1";
#-$::corporate=1;

#-######################################################################################
#- Steps table
#-######################################################################################
my (%installSteps, @orderedInstallSteps);
{    
    my @installStepsFields = qw(text redoable onError hidden needs); 
    #entered reachable toBeDone next done;
    my @installSteps = (
  selectLanguage     => [ __("Choose your language"), 1, 1, '' ],
  selectInstallClass => [ __("Select installation class"), 1, 1, '' ],
  setupSCSI          => [ __("Hard drive detection"), 1, 0, '' ],
  selectMouse        => [ __("Configure mouse"), 1, 1, '', "selectInstallClass" ],
  selectKeyboard     => [ __("Choose your keyboard"), 1, 1, '', "selectInstallClass" ],
  miscellaneous      => [ __("Miscellaneous"), 1, 1, '$::beginner' ],
  doPartitionDisks   => [ __("Setup filesystems"), 1, 0, '$o->{lnx4win}', "selectInstallClass" ],
  formatPartitions   => [ __("Format partitions"), 1, -1, '', "doPartitionDisks" ],
  choosePackages     => [ __("Choose packages to install"), 1, -2, '$::beginner', "formatPartitions" ],
  installPackages    => [ __("Install system"), 1, -1, '', ["formatPartitions", "selectInstallClass"] ],
  configureNetwork   => [ __("Configure networking"), 1, 1, '', "formatPartitions" ],
#-  installCrypto      => [ __("Cryptographic"), 1, 1, '!$::expert', "configureNetwork" ],
  configureTimezone  => [ __("Configure timezone"), 1, 1, '', "installPackages" ],
  configureServices  => [ __("Configure services"), 1, 1, '!$::expert', "installPackages" ],
  configurePrinter   => [ __("Configure printer"), 1, 0, '', "installPackages" ],
  setRootPassword    => [ __("Set root password"), 1, 1, '', "installPackages" ],
  addUser            => [ __("Add a user"), 1, 1, '', "installPackages" ],
arch() !~ /alpha/ ? (
  createBootdisk     => [ __("Create a bootdisk"), 1, 0, '$::o->{lnx4win} && !$::expert', "installPackages" ],
) : (),
  setupBootloader    => [ __("Install bootloader"), 1, 1, '$::o->{lnx4win} && !$::expert', "installPackages" ],
  configureX         => [ __("Configure X"), 1, 1, '', ["formatPartitions", "setupBootloader"] ],
arch() !~ /alpha/ ? (
  generateAutoInstFloppy => [ __("Auto install floppy"), 1, 1, '!$::expert || $o->{lnx4win}', "installPackages" ],
) : (),
  exitInstall        => [ __("Exit install"), 0, 0, '$::beginner' ],
);
    for (my $i = 0; $i < @installSteps; $i += 2) {
	my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
	$h{next}    = $installSteps[$i + 2];
	$h{entered} = 0;
	$h{onError} = $installSteps[$i + 2 * $h{onError}];
	$h{reachable} = !$h{needs};
	$installSteps{ $installSteps[$i] } = \%h;
	push @orderedInstallSteps, $installSteps[$i];
    }
    $installSteps{first} = $installSteps[0];
}
#-#####################################################################################
#-INTERNAL CONSTANT
#-#####################################################################################

my @install_classes = qw(normal developer server);

#-#####################################################################################
#-Default value
#-#####################################################################################
#- partition layout
my %suggestedPartitions = (
arch() =~ /^sparc/ ? (
  normal => [
    { mntpoint => "/",     size => 150 << 11, type => 0x83, ratio => 1, maxsize =>1000 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 1, maxsize => 250 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type => 0x83, ratio => 4, maxsize =>3000 << 11 },
    { mntpoint => "/home", size => 300 << 11, type => 0x83, ratio => 3 },
  ],
) : (
  normal => [
    { mntpoint => "/",     size => 300 << 11, type => 0x83, ratio => 5, maxsize =>3500 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 1, maxsize => 250 << 11 },
    { mntpoint => "/home", size => 300 << 11, type => 0x83, ratio => 3 },
  ],
),
  developer => [
    { mntpoint => "/",     size => 150 << 11, type => 0x83, ratio => 1, maxsize => 500 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 1, maxsize => 250 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type => 0x83, ratio => 4, maxsize =>3000 << 11 },
    { mntpoint => "/home", size => 100 << 11, type => 0x83, ratio => 5 },
  ],
  server => [
    { mntpoint => "/",     size => 150 << 11, type => 0x83, ratio => 1, maxsize => 250 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 2, maxsize => 400 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type => 0x83, ratio => 3, maxsize =>3000 << 11 },
    { mntpoint => "/var",  size => 100 << 11, type => 0x83, ratio => 4 },
    { mntpoint => "/home", size => 100 << 11, type => 0x83, ratio => 5 },
  ],
);
$suggestedPartitions{corporate} = $suggestedPartitions{server};

#-#######################################################################################
#-$O
#-the big struct which contain, well everything (globals + the interactive methods ...)
#-if you want to do a kickstart file, you just have to add all the required fields (see for example
#-the variable $default)
#-#######################################################################################
$o = $::o = {
#    bootloader => { linear => 0, lba32 => 1, message => 1, timeout => 5, restricted => 0 },
    autoSCSI   => 0,
    mkbootdisk => 1, #- no mkbootdisk if 0 or undef, find a floppy with 1, or fd1
#-    packages   => [ qw() ],
    partitioning => { clearall => 0, eraseBadPartitions => 0, auto_allocate => 0 }, #-, readonly => 0 },
#-    security => 2,
#arch() =~ /^sparc/ ? (
#  partitions => [
#    { mntpoint => "/",     size => 600 << 11, type => 0x83, ratio => 5, maxsize =>1000 << 11 },
#    { mntpoint => "swap",  size => 128 << 11, type => 0x82, ratio => 1, maxsize => 400 << 11 },
#    { mntpoint => "/usr",  size => 300 << 11, type => 0x83, ratio => 3, maxsize =>1500 << 11 },
#    { mntpoint => "/home", size => 300 << 11, type => 0x83, ratio => 5 },
#  ],
#) : (
#  partitions => [
#    { mntpoint => "/boot", size =>  10 << 11, type => 0x83, maxsize => 30 << 11 },
#    { mntpoint => "/",     size => 300 << 11, type => 0x83, ratio => 5, maxsize => 1500 << 11 },
#    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 1, maxsize => 250 << 11 },
#    { mntpoint => "/home", size => 300 << 11, type => 0x83, ratio => 5 },
#  ],
#),
#-    partitions => [
#-		      { mntpoint => "/boot", size =>  16 << 11, type => 0x83 },
#-		      { mntpoint => "/",     size => 256 << 11, type => 0x83 },
#-		      { mntpoint => "/usr",  size => 512 << 11, type => 0x83, growable => 1 },
#-		      { mntpoint => "/var",  size => 256 << 11, type => 0x83 },
#-		      { mntpoint => "/home", size => 512 << 11, type => 0x83, growable => 1 },
#-		      { mntpoint => "swap",  size =>  64 << 11, type => 0x82 }
#-		    { mntpoint => "/boot", size =>  16 << 11, type => 0x83 },
#-		    { mntpoint => "/",     size => 300 << 11, type => 0x83 },
#-		    { mntpoint => "swap",  size =>  64 << 11, type => 0x82 },
#-		   { mntpoint => "/usr",  size => 400 << 11, type => 0x83, growable => 1 },
#-	     ],
    authentication => { md5 => 1, shadow => 1 },
    lang         => 'en_US',
    isUpgrade    => 0,
    toRemove     => [],
    toSave       => [],
#-    simple_themes => 1,
#-    installClass => "normal",

    timezone => {
#-                   timezone => "Europe/Paris",
#-                   UTC      => 1,
                },
#-    superuser => { password => 'a', shell => '/bin/bash', realname => 'God' },
#-    user => { name => 'foo', password => 'bar', home => '/home/foo', shell => '/bin/bash', realname => 'really, it is foo' },

#-    keyboard => 'de',
#-    display => "192.168.1.19:1",
    steps        => \%installSteps,
    orderedSteps => \@orderedInstallSteps,

#- for the list of fields available for user and superuser, see @etc_pass_fields in install_steps.pm
#-    intf => { eth0 => { DEVICE => "eth0", IPADDR => '1.2.3.4', NETMASK => '255.255.255.128' } },

#-step : the current one
#-prefix
#-mouse
#-keyboard
#-netc
#-autoSCSI drives hds  fstab
#-methods
#-packages compss
#-printer haveone entry(cf printer.pm)

};

#-######################################################################################
#- Steps Functions
#- each step function are called with two arguments : clicked(because if you are a
#- beginner you can force the the step) and the entered number
#-######################################################################################

#------------------------------------------------------------------------------
sub selectLanguage {
    $::live and return;
    $o->selectLanguage($_[1] == 1);

    addToBeDone {
	lang::write($o->{prefix});
	keyboard::write($o->{prefix}, $o->{keyboard}, lang::lang2charset($o->{lang}));
    } 'installPackages' unless $::g_auto_install;
}

#------------------------------------------------------------------------------
sub selectMouse {
    $::live and return;
    my ($first_time) = $_[1] == 1;

    add2hash($o->{mouse} ||= {}, mouse::read($o->{prefix})) if $o->{isUpgrade} && $first_time;

    $o->selectMouse(!$first_time);
    addToBeDone { mouse::write($o->{prefix}, $o->{mouse}) } 'installPackages';
}

#------------------------------------------------------------------------------
sub setupSCSI {
    $::live and return;
    my ($clicked) = $_[0];
    $o->{autoSCSI} ||= $::beginner;

    $o->setupSCSI($o->{autoSCSI} && !$clicked, $clicked);
}

#------------------------------------------------------------------------------
sub selectKeyboard {
    $::live and return;
    my ($clicked) = $_[0];

    return if !$o->{isUpgrade} && $::beginner && !$clicked;

    $o->{keyboard} = keyboard::read($o->{prefix}) if $o->{isUpgrade} && !$clicked && $o->{keyboard_unsafe};
    $o->selectKeyboard;

    #- if we go back to the selectKeyboard, you must rewrite
    addToBeDone {
	lang::write($o->{prefix});
	keyboard::write($o->{prefix}, $o->{keyboard}, lang::lang2charset($o->{lang}));
    } 'installPackages' unless $::g_auto_install;
}

#------------------------------------------------------------------------------
sub selectInstallClass {
    $::live and return;
    $o->selectInstallClass(@install_classes);
   
    $o->{partitions} ||= $suggestedPartitions{$o->{installClass}};

    if ($o->{steps}{choosePackages}{entered} >= 1 && !$o->{steps}{installPackages}{done}) {
        $o->setPackages(\@install_classes);
        $o->selectPackagesToUpgrade if $o->{isUpgrade};
    }
    if ($o->{isUpgrade}) {
	@{$o->{orderedSteps}} = map { /setupSCSI/ ? ($_, "doPartitionDisks") : $_ } 
	                        grep { !/doPartitionDisks/ } @{$o->{orderedSteps}};
	my $s; foreach (@{$o->{orderedSteps}}) {
	    $s->{next} = $_ if $s;
	    $s = $o->{steps}{$_};
	}
    }
}

#------------------------------------------------------------------------------
sub doPartitionDisks {
    $::live and return;
    $o->{steps}{formatPartitions}{done} = 0;
    $o->doPartitionDisksBefore;
    $o->doPartitionDisks;
    $o->doPartitionDisksAfter;
}

sub formatPartitions {
    $::live and return;
    unless ($o->{isUpgrade}) {
	$o->choosePartitionsToFormat($o->{fstab});
	$o->formatMountPartitions($o->{fstab}) unless $::testing;
    }
    mkdir "$o->{prefix}/$_", 0755 foreach 
      qw(dev etc etc/profile.d etc/sysconfig etc/sysconfig/console etc/sysconfig/network-scripts
	home mnt tmp var var/tmp var/lib var/lib/rpm var/lib/urpmi);
    mkdir "$o->{prefix}/$_", 0700 foreach qw(root);

    require raid;
    raid::prepare_prefixed($o->{raid}, $o->{prefix});

    my $d = "/initrd/loopfs/lnx4win";
    if (-d $d) {
#-	install_any::useMedium(0);
	install_any::getAndSaveFile("lnx4win/$_", "$d/$_") foreach qw(ctl3d32.dll loadlin.exe linux.pif lnx4win.exe lnx4win.ico rm.exe uninstall.bat uninstall.pif);
    }

#-    chdir "$o->{prefix}"; was for core dumps

    #-noatime option for ext2 fs on laptops (do not wake up the hd)
    #-	 Do  not  update  inode  access times on this
    #-	 file system (e.g, for faster access  on  the
    #-	 news spool to speed up news servers).
    $o->{pcmcia} and $_->{options} = "noatime" foreach grep { isTrueFS($_) } @{$o->{fstab}};
}

#------------------------------------------------------------------------------
sub choosePackages {
    require pkgs;

    #- always setPackages as it may have to copy hdlist files and depslist file.
    $o->setPackages;

    #- for the first time, select package to upgrade.
    #- TOCHECK this may not be the best place for that as package are selected at some other point.
    if ($_[1] == 1) {
	$o->selectPackagesToUpgrade if $o->{isUpgrade};

	$o->{compssUsersChoice}{$_} = 1 foreach @{$o->{compssUsersSorted}}, 'Miscellaneous';
	# $o->{compssUsersChoice}{KDE} = 0 if $o->{lang} =~ /ja|el|ko|th|vi|zh/; #- gnome handles much this fonts much better
    }

    $o->choosePackages($o->{packages}, $o->{compss}, 
		       $o->{compssUsers}, $o->{compssUsersSorted}, $_[1] == 1);
    my $pkg = pkgs::packageByName($o->{packages}, 'kdesu');
    pkgs::unselectPackage($o->{packages}, $pkg) if $pkg && $o->{security} > 3;

    #- check pre-condition where base backage has to be selected.
    pkgs::packageFlagSelected(pkgs::packageByName($o->{packages}, 'basesystem')) or die "basesystem package not selected";

    #- check if there are package that need installation.
    $o->{steps}{installPackages}{done} = 0 if $o->{steps}{installPackages}{done} && pkgs::packagesToInstall($o->{packages}) > 0;
}

#------------------------------------------------------------------------------
sub installPackages {
    $o->readBootloaderConfigBeforeInstall if $_[1] == 1;

    $o->beforeInstallPackages;
    $o->installPackages;
    $o->afterInstallPackages;
}
#------------------------------------------------------------------------------
sub miscellaneous {
    $::live and return;
    $o->miscellaneousBefore($_[0]);
    $o->miscellaneous($_[0]);

    addToBeDone {
	setVarsInSh("$o->{prefix}/etc/sysconfig/system", { 
            CLEAN_TMP => $o->{miscellaneous}{CLEAN_TMP},
            CLASS => $::expert && "expert" || $::beginner && "beginner" || "medium",
            TYPE => $o->{installClass},
            SECURITY => $o->{security},
	    META_CLASS => $o->{meta_class} || 'PowerPack',
        });

	my $f = "$o->{prefix}/etc/sysconfig/usb";
	output $f,
"USB=yes
MOUSE=
KEYBOARD=
STORAGE=
VISOR=no
" if modules::get_alias("usb-interface") && ! -e $f;

	install_any::fsck_option($o);
    } 'installPackages';
}

#------------------------------------------------------------------------------
sub configureNetwork {
    $::live and return;
    #- get current configuration of network device.
    require network;
    eval { network::read_all_conf($o->{prefix}, $o->{netc} ||= {}, $o->{intf} ||= {}) };
    $o->configureNetwork($_[1] == 1);
}
#------------------------------------------------------------------------------
sub installCrypto { $::live or $o->installCrypto }
#------------------------------------------------------------------------------
sub configureTimezone {
    $::live and return;
    my ($clicked) = @_;
    my $f = "$o->{prefix}/etc/sysconfig/clock";

    require timezone;
    if ($o->{isUpgrade} && -r $f && -s $f > 0) {
	return if $_[1] == 1 && !$clicked;
	#- can't be done in install cuz' timeconfig %post creates funny things
	add2hash($o->{timezone}, { timezone::read($f) });
    }
    $o->{timezone}{timezone} ||= timezone::bestTimezone(lang::lang2text($o->{lang}));
    $o->{timezone}{UTC} = !$::beginner && !grep { isFat($_) || isNT($_) } @{$o->{fstab}} unless exists $o->{timezone}{UTC};
    $o->configureTimezone($f, $clicked);
}
#------------------------------------------------------------------------------
sub configureServices { $::live or $::expert and $o->configureServices }
#------------------------------------------------------------------------------
sub configurePrinter  { $::live or $o->configurePrinter($_[0]) }
#------------------------------------------------------------------------------
sub setRootPassword {
    return if $o->{isUpgrade};

    $o->setRootPassword($_[0]);
    addToBeDone { install_any::setAuthentication($o) } 'installPackages';
}
#------------------------------------------------------------------------------
sub addUser {
    return if $o->{isUpgrade} && !$_[0];

    $o->addUser($_[0]);
    install_any::setAuthentication($o);
}

#------------------------------------------------------------------------------
sub createBootdisk {
    $::live and return;
    modules::write_conf($o->{prefix});
    $o->createBootdisk($_[1] == 1);
}

#------------------------------------------------------------------------------
sub setupBootloader {
    $::live and return;
    return if $::g_auto_install;

    modules::write_conf($o->{prefix});

    $o->setupBootloaderBefore if $_[1] == 1;
    $o->setupBootloader($_[1] - 1);
    
    local $ENV{DRAKX_PASSWORD} = $o->{bootloader}{password};
    run_program::rooted($o->{prefix}, "/usr/sbin/msec", $o->{security});
}
#------------------------------------------------------------------------------
sub configureX {
    $::live and return;
    my ($clicked) = $_[0];

    #- done here and also at the end of install2.pm, just in case...
    fs::write($o->{prefix}, $o->{fstab}, $o->{manualFstab}, $o->{useSupermount});
    modules::write_conf($o->{prefix});

    $o->configureX if pkgs::packageFlagInstalled(pkgs::packageByName($o->{packages}, 'XFree86')) && !$o->{X}{disabled} || $clicked;
}
#------------------------------------------------------------------------------
sub generateAutoInstFloppy { $::live or $o->generateAutoInstFloppy }

#------------------------------------------------------------------------------
sub exitInstall { $::live or $o->exitInstall(getNextStep() eq "exitInstall") }


#-######################################################################################
#- MAIN
#-######################################################################################
sub main {
    $SIG{__DIE__} = sub { chomp(my $err = $_[0]); log::l("warning: $err") };
    $SIG{SEGV} = sub { my $msg = "segmentation fault: seems like memory is missing as the install crashes"; print "$msg\n"; log::l($msg);
		       $o->ask_warn('', $msg);
		       setVirtual(1);
		       require install_steps_auto_install;
		       install_steps_auto_install::errorInStep();
		   };
    $ENV{SHARE_PATH} ||= "/usr/share";
    $ENV{PERL_BADLANG} = 1;

    $::beginner = $::expert = $::g_auto_install = 0;

#-    c::unlimit_core() unless $::testing;

    my ($cfg, $patch, $oem, @auto);
    my %cmdline; map { 
	my ($n, $v) = split '=';
	$cmdline{$n} = $v || 1;
    } split ' ', cat_("/proc/cmdline");

    my $opt; foreach (@_) {
	if (/^--?(.*)/) {
	    $cmdline{$opt} = 1 if $opt;
	    $opt = $1;
	} else {
	    $cmdline{$opt} = $_ if $opt;
	    $opt = '';
	}
    } $cmdline{$opt} = 1 if $opt;
    
    $::beginner = 1;

    map_each {
	my ($n, $v) = @_;
	my $f = ${{
	    oem       => sub { $oem = $v },
	    lang      => sub { $o->{lang} = $v },
	    flang     => sub { $o->{lang} = $v ; push @auto, 'selectLanguage' },
	    method    => sub { $o->{method} = $v },
	    pcmcia    => sub { $o->{pcmcia} = $v },
	    vga16     => sub { $o->{vga16} = $v },
	    vga       => sub { $o->{vga} = $v },
	    step      => sub { $o->{steps}{first} = $v },
	    expert    => sub { $::expert = 1; $::beginner = 0 },
	    beginner  => sub { $::beginner = $v },
	    class     => sub { $o->{installClass} = $v },
	    fclass    => sub { $o->{installClass} = $v; push @auto, 'selectInstallClass' },
	    desktop   => sub { $o->{meta_class} = 'desktop' },
	    lnx4win   => sub { $o->{lnx4win} = 1 },
	    readonly  => sub { $o->{partitioning}{readonly} = $v ne "0" },
	    display   => sub { $o->{display} = $v },
	    security  => sub { $o->{security} = $v },
	    live      => sub { $::live = 1 },
	    noauto    => sub { $::noauto = 1 },
	    test      => sub { $::testing = 1 },
            nopci     => sub { $::nopci = 1 },
	    patch     => sub { $patch = 1 },
	    defcfg    => sub { $cfg = $v },
	    newt      => sub { $o->{interactive} = "newt" },
	    text      => sub { $o->{interactive} = "newt" },
	    stdio     => sub { $o->{interactive} = "stdio"},
	    corporate => sub { $::corporate = 1 },
	    kickstart => sub { $::auto_install = $v },
	    auto_install => sub { $::auto_install = $v },
	    simple_themes => sub { $o->{simple_themes} = 1 },
	    useless_thing_accepted => sub { $o->{useless_thing_accepted} = 1 },
	    alawindows => sub { $o->{security} = 0; $o->{partitioning}{clearall} = 1; $o->{bootloader}{crushMbr} = 1 },
	    fdisk => sub { $o->{partitioning}{fdisk} = 1 },
	    g_auto_install => sub { $::testing = $::g_auto_install = 1; $o->{partitioning}{auto_allocate} = 1 },
	    nomouseprobe => sub { $o->{nomouseprobe} = $v },
	}}{lc $n}; &$f if $f;
    } %cmdline;

    undef $::auto_install if $cfg;
    if ($::g_auto_install) {
	(my $root = `/bin/pwd`) =~ s|(/[^/]*){5}$||;
	symlinkf $root, "/tmp/rhimage" or die "unable to create link /tmp/rhimage";
	$o->{method} ||= "cdrom";
	$o->{mkbootdisk} = 0;
    }
    unless ($::testing || $::live) {
	unlink $_ foreach ( $o->{pcmcia} ? () : ("/sbin/install"), #- #- install include cardmgr!
			   "/modules/modules.cgz",
			   "/sbin/insmod", "/sbin/rmmod",
			   "/modules/pcmcia_core.o", #- always use module from archive.
			   "/modules/i82365.o",
			   "/modules/tcic.o",
			   "/modules/ds.o",
			   );
    }

    print STDERR "in second stage install\n";
    log::openLog(($::testing || $o->{localInstall}) && 'debug.log');
    log::l("second stage install running");
    log::ld("extra log messages are enabled");

    eval { spawnShell() };

    $o->{prefix} = $::testing ? "/tmp/test-perl-install" : $::live ? "" : "/mnt";
    $o->{root}   = $::testing ? "/tmp/root-perl-install" : "/";
    if ($::live) {
	@{$o->{orderedSteps}} = grep { /choosePackages/ || /installPackages/ } @{$o->{orderedSteps}};
	my $s; foreach (@{$o->{orderedSteps}}) {
	    $s->{next} = $_ if $s;
	    $s = $o->{steps}{$_};
	}
	$o->{isUpgrade} = 1;
	$::beginner = 0; #- use custom by default.
	$::expert = 1;
    }
    mkdir $o->{prefix}, 0755;
    mkdir $o->{root}, 0755;

    #-  make sure we don't pick up any gunk from the outside world
    my $remote_path = "$o->{prefix}/sbin:$o->{prefix}/bin:$o->{prefix}/usr/sbin:$o->{prefix}/usr/bin:$o->{prefix}/usr/X11R6/bin";
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:/usr/X11R6/bin:$remote_path" unless $::g_auto_install;

    $o->{interactive} ||= 'gtk';
    if ($o->{interactive} eq "gtk" && availableMemory < 22 * 1024) {
	log::l("switching to newt install cuz not enough memory");
	$o->{interactive} = "newt";
    }

    if ($::auto_install) {
	require install_steps_auto_install;
	eval { $o = $::o = install_any::loadO($o, $::auto_install) };
	if ($@) {
	    log::l("error using auto_install, continuing");
	    undef $::auto_install;
	} else {
	    log::l("auto install config file loaded successfully");
	}
    }
    unless ($::auto_install) {
	$o->{interactive} ||= 'gtk';
	require"install_steps_$o->{interactive}.pm";
    }
    eval { $o = $::o = install_any::loadO($o, "patch") } if $patch;
    eval { $o = $::o = install_any::loadO($o, $cfg) } if $cfg;

    $o->{prefix} = $::testing ? "/tmp/test-perl-install" : $::live ? "" : "/mnt";
    mkdir $o->{prefix}, 0755;

    modules::unload($_) foreach qw(vfat msdos fat);
    modules::load_deps(($::testing ? ".." : "") . "/modules/modules.dep");
    modules::read_stage1_conf("/tmp/conf.modules");
    modules::read_already_loaded();

    eval { modules::load("af_packet") };

    map_index {
	modules::add_alias("sound-slot-$::i", $_->{driver});
    } modules::get_that_type('sound');

    #- needed very early for install_steps_gtk
    modules::load_thiskind("usb"); 
    eval { ($o->{mouse}, $o->{wacom}) = mouse::detect() } unless $o->{nomouseprobe} || $o->{mouse};

    lang::set($o->{lang}); #- mainly for defcfg

    $o->{allowFB} = listlength(cat_("/proc/fb"));

    my $o_;
    while (1) {
	require"install_steps_$o->{interactive}.pm";
    	$o_ = $::auto_install ?
    	  install_steps_auto_install->new($o) :
    	    $o->{interactive} eq "stdio" ?
    	  install_steps_stdio->new($o) :
    	    $o->{interactive} eq "newt" ?
    	  install_steps_newt->new($o) :
    	    $o->{interactive} eq "gtk" ?
    	  install_steps_gtk->new($o) :
    	    die "unknown install type";
	$o_ and last;

	$o->{interactive} = "newt";
	require install_steps_newt;
    }
    $o->{meta_class} = 'desktop' if cat__(install_any::getFile("VERSION")) =~ /desktop/i;
    if ($o->{meta_class} eq 'desktop') {
	$o->{installClass} = 'normal';
	push @auto, 'selectInstallClass';
    }
    if ($oem) {
	$o->{partitioning}{auto_allocate} = 1;
	$o->{compssListLevel} = 50;
	push @auto, 'selectInstallClass', 'selectMouse', 'doPartitionDisks', 'choosePackages', 'configureTimezone', 'exitInstall';
    }
    foreach (@auto) {
	eval "undef *" . (!/::/ && "install_steps_interactive::") . $_;
	my $s = $o->{steps}{/::(.*)/ ? $1 : $_} or next;
	$s->{hidden} = 1;
    }

    $::o = $o = $o_;

    if (-e "/tmp/network") {
	require network;
	#- get stage1 network configuration if any.
	$o->{netc} ||= network::read_conf("/tmp/network");
	if (my ($file) = glob_('/tmp/ifcfg-*')) {
	    log::l("found network config file $file");
	    my $l = network::read_interface_conf($file);
	    add2hash(network::findIntf($o->{intf} ||= {}, $l->{DEVICE}), $l);
	}
    }

    #-the main cycle
    my $clicked = 0;
    MAIN: for ($o->{step} = $o->{steps}{first};; $o->{step} = getNextStep()) {
	$o->{steps}{$o->{step}}{entered}++;
	$o->enteringStep($o->{step});
	eval {
	    &{$install2::{$o->{step}}}($clicked, $o->{steps}{$o->{step}}{entered});
	};
	$o->kill_action;
	$clicked = 0;
	while ($@) {
	    local $_ = $@;
	    $o->kill_action;
	    if (/^setstep (.*)/) {
		$o->{step} = $1;
		$o->{steps}{$1}{done} = 0;
		$clicked = 1;
		redo MAIN;
	    }
	    /^theme_changed$/ and redo MAIN;
	    unless (/^already displayed/ || /^ask_from_list cancel/) {
		eval { $o->errorInStep($_) };
		$@ and next;
	    }
	    $o->{step} = $o->{steps}{$o->{step}}{onError};
	    next MAIN unless $o->{steps}{$o->{step}}{reachable}; #- sanity check: avoid a step not reachable on error.
	    redo MAIN;
	}
	$o->{steps}{$o->{step}}{done} = 1;
	$o->leavingStep($o->{step});

	last if $o->{step} eq 'exitInstall';
    }
    install_any::clean_postinstall_rpms();
    install_any::ejectCdrom();

    $::live or fs::write($o->{prefix}, $o->{fstab}, $o->{manualFstab}, $o->{useSupermount});
    modules::write_conf($o->{prefix});

    #- to ensure linuxconf doesn't cry against those files being in the future
    foreach ('/etc/modules.conf', '/etc/crontab', '/etc/sysconfig/mouse', '/etc/sysconfig/network', '/etc/X11/fs/config') {
	my $now = time - 24 * 60 * 60;
	utime $now, $now, "$o->{prefix}/$_";
    }
    $::live or install_any::killCardServices();

    #- make sure failed upgrade will not hurt too much.
    install_steps::cleanIfFailedUpgrade($o);

    -e "$o->{prefix}/usr/bin/urpmi" or eval { commands::rm("-rf", "$o->{prefix}/var/lib/urpmi") };

    #- mainly for auto_install's
    run_program::rooted($o->{prefix}, "sh", "-c", $o->{postInstall}) if $o->{postInstall};
    do { local $ENV{PATH} = $remote_path;
	 run_program::run("bash", "-c", $o->{postInstallNonRooted}) } if $o->{postInstallNonRooted};

    #- have the really bleeding edge ddebug.log
    eval { commands::cp('-f', "/tmp/ddebug.log", "$o->{prefix}/root") };

    #- ala pixel? :-) [fpons]
    sync(); sync();

    log::l("installation complete, leaving");
    print "\n" x 80;
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
