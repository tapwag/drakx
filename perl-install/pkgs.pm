package pkgs; # $Id$

use diagnostics;
use strict;
use vars qw(*LOG %preferred $limitMinTrans %compssListDesc);

use MDK::Common::System;
use URPM;
use URPM::Resolve;
use common;
use install_any;
use run_program;
use detect_devices;
use log;
use fs;
use loopback;
use c;



my @preferred = qw(perl-GTK postfix gcc gcc-cpp gcc-c++ proftpd ghostscript-X vim-minimal kernel db1 db2 ispell-en Bastille-Curses-module nautilus libxpm4 zlib1 libncurses5 harddrake);
@preferred{@preferred} = ();

#- lower bound on the left ( aka 90 means [90-100[ )
%compssListDesc = (
   5 => __("must have"),
   4 => __("important"),
   3 => __("very nice"),
   2 => __("nice"),
   1 => __("maybe"),
);

#- constant for small transaction.
$limitMinTrans = 8;

##- constant for package accessor (via table).
#my $FILE                 = 0;
#my $FLAGS                = 1;
#my $SIZE_DEPS            = 2;
#my $MEDIUM               = 3;
#my $PROVIDES             = 4;
#my $VALUES               = 5;
#my $HEADER               = 6;
#my $INSTALLED_CUMUL_SIZE = 7;
#my $EPOCH                = 8;
#
##- constant for packing flags, see below.
#my $PKGS_SELECTED  = 0x00ffffff;
#my $PKGS_FORCE     = 0x01000000;
#my $PKGS_INSTALLED = 0x02000000;
#my $PKGS_BASE      = 0x04000000;
#my $PKGS_UPGRADE   = 0x20000000;

#- package to ignore, typically in Application CD.
my %ignoreBadPkg = (
		    'civctp-demo'   => 1,
		    'eus-demo'      => 1,
		    'myth2-demo'    => 1,
		    'heretic2-demo' => 1,
		    'heroes3-demo'  => 1,
		    'rt2-demo'      => 1,
		   );

#- basic methods for extracting informations about packages.
#- to save memory, (name, version, release) are no more stored, they
#- are directly generated from (file).
#- all flags are grouped together into (flags), these includes the
#- following flags : selected, force, installed, base, skip.
#- size and deps are grouped to save memory too and make a much
#- simpler and faster depslist reader, this gets (sizeDeps).
#sub packageHeaderFile   { $_[0] ? $_[0]->[$FILE]
#			    : die "invalid package from\n" . backtrace() }
#sub packageName         { $_[0] && $_[0]->[$FILE] =~ /^([^:\s]*)-[^:\-\s]+-[^:\-\s]+\.[^:\.\-\s]*(?::.*)?/ ? $1
#			    : die "invalid file `" . ($_[0] && $_[0]->[$FILE]) . "'\n" . backtrace() }
#sub packageVersion      { $_[0] && $_[0]->[$FILE] =~ /^[^:\s]*-([^:\-\s]+)-[^:\-\s]+\.[^:\.\-\s]*(?::.*)?/ ? $1
#			    : die "invalid file `" . ($_[0] && $_[0]->[$FILE]) . "'\n" . backtrace() }
#sub packageRelease      { $_[0] && $_[0]->[$FILE] =~ /^[^:\s]*-[^:\-\s]+-([^:\-\s]+)\.[^:\.\-\s]*(?::.*)?/ ? $1
#			    : die "invalid file `" . ($_[0] && $_[0]->[$FILE]) . "'\n" . backtrace() }
#sub packageArch         { $_[0] && $_[0]->[$FILE] =~ /^[^:\s]*-[^:\-\s]+-[^:\-\s]+\.([^:\.\-\s]*)(?::.*)?/ ? $1
#			    : die "invalid file `" . ($_[0] && $_[0]->[$FILE]) . "'\n" . backtrace() }
#sub packageFile         { $_[0] && $_[0]->[$FILE] =~ /^([^:\s]*-[^:\-\s]+-[^:\-\s]+\.[^:\.\-\s]*)(?::(.*))?/ ? ($2 || $1) . ".rpm"
#			    : die "invalid file `" . ($_[0] && $_[0]->[$FILE]) . "'\n" . backtrace() }
#sub packageEpoch        { $_[0] && $_[0]->[$EPOCH] || 0 }
#
#sub packageSize   { to_int($_[0] && ($_[0]->[$SIZE_DEPS] - ($_[0]->[$INSTALLED_CUMUL_SIZE] || 0))) }
#sub packageDepsId { split ' ', ($_[0] && ($_[0]->[$SIZE_DEPS] =~ /^\d*\s*(.*)/)[0]) }
#
#sub packageFlagSelected  { $_[0] && $_[0]->[$FLAGS] & $PKGS_SELECTED }
#sub packageFlagForce     { $_[0] && $_[0]->[$FLAGS] & $PKGS_FORCE }
#sub packageFlagInstalled { $_[0] && $_[0]->[$FLAGS] & $PKGS_INSTALLED }
#sub packageFlagBase      { $_[0] && $_[0]->[$FLAGS] & $PKGS_BASE }
#sub packageFlagUpgrade   { $_[0] && $_[0]->[$FLAGS] & $PKGS_UPGRADE }
#
#sub packageSetFlagSelected  { $_[0]->[$FLAGS] &= ~$PKGS_SELECTED; $_[0]->[$FLAGS] |= $_[1] & $PKGS_SELECTED; }
#
#sub packageSetFlagForce     { $_[0] or die "invalid package from\n" . backtrace();
#			      $_[1] ? ($_[0]->[$FLAGS] |= $PKGS_FORCE)     : ($_[0]->[$FLAGS] &= ~$PKGS_FORCE); }
#sub packageSetFlagInstalled { $_[0] or die "invalid package from\n" . backtrace();
#			      $_[1] ? ($_[0]->[$FLAGS] |= $PKGS_INSTALLED) : ($_[0]->[$FLAGS] &= ~$PKGS_INSTALLED); }
#sub packageSetFlagBase      { $_[0] or die "invalid package from\n" . backtrace();
#			      $_[1] ? ($_[0]->[$FLAGS] |= $PKGS_BASE)      : ($_[0]->[$FLAGS] &= ~$PKGS_BASE); }
#sub packageSetFlagUpgrade   { $_[0] or die "invalid package from\n" . backtrace();
#			      $_[1] ? ($_[0]->[$FLAGS] |= $PKGS_UPGRADE)   : ($_[0]->[$FLAGS] &= ~$PKGS_UPGRADE); }
#
sub packageMedium { my ($packages, $p) = @_; $p or die "invalid package from\n" . backtrace();
		    foreach (values %{$packages->{mediums}}) {
			$p->id >= $_->{start} && $p->id <= $_->{end} and return $_;
		    }
		    return }

#sub packageProvides { $_[1] or die "invalid package from\n" . backtrace();
#		      map { $_[0]->{depslist}[$_] || die "unkown package id $_" } unpack "s*", $_[1]->[$PROVIDES] }
#
#sub packageRate          { substr($_[0] && $_[0]->[$VALUES], 0, 1) }
#sub packageRateRFlags    { my ($rate, @flags) = split "\t", $_[0] && $_[0]->[$VALUES]; ($rate, @flags) }
#sub packageSetRateRFlags { my ($pkg, $rate, @flags) = @_; $pkg or die "invalid package from\n" . backtrace();
#			   $pkg->[$VALUES] = join("\t", $rate, @flags) }
#
#sub packageHeader     { $_[0] && $_[0]->[$HEADER] }
#sub packageFreeHeader { $_[0] && c::headerFree(delete $_[0]->[$HEADER]) }

#sub packageSelectedOrInstalled { $_[0] && ($_[0]->flag_selected || $_[0]->flag_installed) }

#sub packageId {
#    my ($packages, $pkg) = @_;
#    my $i = 0;
#    foreach (@{$packages->{depslist}}) { return $i if $pkg == $packages->{depslist}[$i]; $i++ }
#    return;
#}

sub cleanHeaders {
    my ($prefix) = @_;
    rm_rf("$prefix/tmp/headers") if -e "$prefix/tmp/headers";
}

#- get all headers from an hdlist file.
sub extractHeaders {
    my ($prefix, $pkgs, $media) = @_;
    my %medium2pkgs;

    cleanHeaders($prefix);

    foreach (@$pkgs) {
	foreach my $medium (values %$media) {
	    $_->id >= $medium->{start} && $_->id <= $medium->{end} or next;
	    push @{$medium2pkgs{$medium->{medium}} ||= []}, $_;
	}
    }

    foreach (keys %medium2pkgs) {
	my $medium = $media->{$_};

	eval {
	    require packdrake;
	    my $packer = new packdrake("/tmp/$medium->{hdlist}", quiet => 1);
	    $packer->extract_archive("$prefix/tmp/headers", map { $_->header_filename } @{$medium2pkgs{$_}});
	};
    }

    foreach (@$pkgs) {
	my $f = "$prefix/tmp/headers/". $_->header_filename;
	$_->update_header($f) or log::l("unable to open header file $f"), next;
    }
}

#- TODO BEFORE TODO
#- size and correction size functions for packages.
my $B = 1.20873;
my $C = 4.98663; #- doesn't take hdlist's into account as getAvailableSpace will do it.
sub correctSize { $B * $_[0] + $C }
sub invCorrectSize { ($_[0] - $C) / $B }

sub selectedSize {
    my ($packages) = @_;
    my $size = 0;
    foreach (@{$packages->{depslist}}) {
	$_->flag_selected and $size += $_->size;
    }
    $size;
}
sub correctedSelectedSize { correctSize(selectedSize($_[0]) / sqr(1024)) }

sub size2time {
    my ($x, $max) = @_;
    my $A = 7e-07;
    my $limit = min($max * 3 / 4, 9e8);
    if ($x < $limit) {
	$A * $x;
    } else { 
	$x -= $limit;
	my $B = 6e-16;
	my $C = 15e-07;
	$B * $x ** 2 + $C * $x + $A * $limit;
    }
}


#- searching and grouping methods.
#- package is a reference to list that contains
#- a hash to search by name and
#- a list to search by id.
sub packageByName {
    my ($packages, $name) = @_;
    #- search package with given name and compatible with current architecture.
    #- take the best one found (most up-to-date).
    my @packages;
    foreach (keys %{$packages->{provides}{$name} || {}}) {
	my $pkg = $packages->{depslist}[$_];
	$pkg->is_arch_compat or next;
	$pkg->name eq $name or next;
	push @packages, $pkg;
    }
    my $best;
    foreach (@packages) {
	if ($best && $best != $_) {
	    $_->compare_pkg($best) > 0 and $best = $_;
	} else {
	    $best = $_;
	}
    }
    $best or log::l("unknown package `$name'") && undef;
}
sub packageById {
    my ($packages, $id) = @_;
    my $pkg = $packages->{depslist}[$id]; #- do not log as id unsupported are still in depslist.
    $pkg->is_arch_compat && $pkg;
}
sub packagesOfMedium {
    my ($packages, $medium) = @_;
    $medium->{start} <= $medium->{end} ? @{$packages->{depslist}}[$medium->{start} .. $medium->{end}] : ();
}
sub packagesToInstall {
    my ($packages) = @_;
    my @packages;
    foreach (values %{$packages->{mediums}}) {
	$_->{selected} or next;
	log::l("examining packagesToInstall of medium $_->{descr}");
	push @packages, grep { $_->flag_selected } packagesOfMedium($packages, $_);
    }
    log::l("found " .scalar(@packages). " packages to install");
    @packages;
}

sub allMediums {
    my ($packages) = @_;
    sort { $a <=> $b } keys %{$packages->{mediums}};
}
sub mediumDescr {
    my ($packages, $medium) = @_;
    $packages->{mediums}{$medium}{descr};
}

sub packageRequest {
    my ($packages, $pkg) = @_;

    #- check if the same or better version is installed,
    #- do not select in such case.
    $pkg && ($pkg->flag_upgrade || !$pkg->flag_installed) or return;

    #- check for medium selection, if the medium has not been
    #- selected, the package cannot be selected.
    foreach (values %{$packages->{mediums}}) {
	!$_->{selected} && $pkg->id >= $_->{start} && $pkg->id <= $_->{end} and return;
    }

    return { $pkg->id => 1 };
}

sub packageCallbackChoices {
    my ($urpm, $db, $state, $choices) = @_;
    my $prefer;
    foreach (@$choices) {
	exists $preferred{$_->name} and $prefer = $_;
	$_->name =~ /kernel-\d/ and $prefer ||= $_;
    }
    $prefer || $choices->[0]; #- first one (for instance).
}

#- selection, unselection of package.
sub selectPackage {
    my ($packages, $pkg, $base, $otherOnly) = @_;

    #- select package and dependancies, otherOnly may be a reference
    #- to a hash to indicate package that will strictly be selected
    #- when value is true, may be selected when value is false (this
    #- is only used for unselection, not selection)
    my $state = $packages->{state} ||= {};
    $state->{selected} = {};
    $state->{requested} = packageRequest($packages, $pkg) or return;
    $packages->resolve_requested($packages->{rpmdb}, $state, no_flag_update => $otherOnly, keep_state => $otherOnly,
				 callback_choices => \&packageCallbackChoices);

    if ($base || $otherOnly) {
	foreach (keys %{$state->{selected}}) {
	    my $p = $packages->{depslist}[$_] or next;
	    #- if base is activated, propagate base flag to all selection.
	    $base and $p->set_flag_base;
	    $otherOnly and $otherOnly->{$_} = $state->{selected}{$_};
	}
    }
    1;
}

sub unselectPackage($$;$) {
    my ($packages, $pkg, $otherOnly) = @_;

    #- base package are not unselectable,
    #- and already unselected package are no more unselectable.
    $pkg->flag_base and return;
    $pkg->flag_selected or return;

    #- try to unwind selection (requested or required) by keeping
    #- rpmdb is right place.
    #TODO
    if ($otherOnly) {
	$otherOnly->{$pkg->id} = undef;
    } else {
	$pkg->set_flag_requested(0);
	$pkg->set_flag_required(0);

	#- clear state.
	my $state = $packages->{state} ||= {};
	$state->{selected} = { $pkg->id };
	$state->{requested} = {};
	$packages->resolve_requested($packages->{rpmdb}, $state, keep_state => 1);
    }
    1;
}
sub togglePackageSelection($$;$) {
    my ($packages, $pkg, $otherOnly) = @_;
    $pkg->flag_selected ? unselectPackage($packages, $pkg, $otherOnly) : selectPackage($packages, $pkg, 0, $otherOnly);
}
sub setPackageSelection($$$) {
    my ($packages, $pkg, $value) = @_;
    $value ? selectPackage($packages, $pkg) : unselectPackage($packages, $pkg);
}

sub unselectAllPackages($) {
    my ($packages) = @_;
    my %selected;
    foreach (@{$packages->{depslist}}) {
	unless ($_->flag_base || $_->flag_installed && $_->flag_selected) {
	    #- deselect all packages except base or packages that need to be upgraded.
	    $_->set_flag_requested(0);
	    $_->set_flag_required(0);
	    $selected{$_->id} = undef;
	}
    }
    if (%selected && %{$packages->{state} || {}}) {
	my $state = $packages->{state} ||= {};
	$state->{selected} = \%selected;
	$state->{requested} = {};
	$packages->resolve_requested($packages->{rpmdb}, $state, keep_state => 1);
    }
}
sub unselectAllPackagesIncludingUpgradable($) {
    my ($packages, $removeUpgradeFlag) = @_;
    my %selected;
    foreach (@{$packages->{depslist}}) {
	unless ($_->flag_base) {
	    $_->set_flag_requested(0);
	    $_->set_flag_required(0);
	    $selected{$_->id} = undef;
	}
    }
    if (%selected && %{$packages->{state} || {}}) {
	my $state = $packages->{state} ||= {};
	$state->{selected} = \%selected;
	$state->{requested} = {};
	$packages->resolve_requested($packages->{rpmdb}, $state, keep_state => 1);
    }
}

sub psUpdateHdlistsDeps {
    my ($prefix, $method, $packages) = @_;
    my ($good_hdlists_deps, $mediums) = (0, 0);

    #- check if current configuration is still up-to-date and do not need to be updated.
    foreach (values %{$packages->{mediums}}) {
	my $hdlistf = "$prefix/var/lib/urpmi/hdlist.$_->{fakemedium}.cz" . ($_->{hdlist} =~ /\.cz2/ && "2");
	my $synthesisf = "$prefix/var/lib/urpmi/synthesis.hdlist.$_->{fakemedium}.cz" . ($_->{hdlist} =~ /\.cz2/ && "2");
	-s $hdlistf == $_->{hdlist_size} && -s $synthesisf == $_->{synthesis_hdlist_size} and ++$good_hdlists_deps;
	++$mediums;
    }
    $good_hdlists_deps > 0 && $good_hdlists_deps == $mediums and return; #- nothing to do.

    #- at this point, this means partition has problably be reformatted and hdlists should be retrieved.
    install_any::useMedium($install_any::boot_medium);

    my $listf = install_any::getFile('Mandrake/base/hdlists') or die "no hdlists found";

    #- WARNING: this function should be kept in sync with functions
    #- psUsingHdlists and psUsingHdlist.
    #- it purpose it to update hdlist files on system to install.

    #- parse hdlist.list file.
    my $medium = 1;
    foreach (<$listf>) {
	chomp;
	s/\s*#.*$//;
	/^\s*$/ and next;
	m/^\s*(hdlist\S*\.cz2?)\s+(\S+)\s*(.*)$/ or die "invalid hdlist description \"$_\" in hdlists file";
	my ($hdlist, $rpmsdir, $descr) = ($1, $2, $3);

	#- copy hdlist file directly to $prefix/var/lib/urpmi, this will be used
	#- for getting header of package during installation or after by urpmi.
	my $fakemedium = "$descr ($method$medium)";
	my $newf = "$prefix/var/lib/urpmi/hdlist.$fakemedium.cz" . ($hdlist =~ /\.cz2/ && "2");
	-e $newf and do { unlink $newf or die "cannot remove $newf: $!"; };
	install_any::getAndSaveFile("Mandrake/base/$hdlist", $newf) or die "no $hdlist found";
	symlinkf $newf, "/tmp/$hdlist";
	install_any::getAndSaveFile("Mandrake/base/synthesis.$hdlist",
				    "$prefix/var/lib/urpmi/synthesis.hdlist.$fakemedium.cz" . ($hdlist =~ /\.cz2/ && "2"));
	++$medium;
    }

    #- this is necessary for urpmi.
    install_any::getAndSaveFile("Mandrake/base/$_", "$prefix/var/lib/urpmi/$_") foreach qw(rpmsrate);
}

sub psUsingHdlists {
    my ($prefix, $method) = @_;
    my $listf = install_any::getFile('Mandrake/base/hdlists') or die "no hdlists found";
    my $packages = new URPM;

    #- add additional fields used by DrakX.
    @{$packages}{qw(count mediums)} = (0, {});

    #- parse hdlists file.
    my $medium = 1;
    foreach (<$listf>) {
	chomp;
	s/\s*#.*$//;
	/^\s*$/ and next;
	m/^\s*(hdlist\S*\.cz2?)\s+(\S+)\s*(.*)$/ or die "invalid hdlist description \"$_\" in hdlists file";

	#- make sure the first medium is always selected!
	#- by default select all image.
	psUsingHdlist($prefix, $method, $packages, $1, $medium, $2, $3, 1);

	++$medium;
    }

    log::l("psUsingHdlists read " . scalar @{$packages->{depslist}} .
	   " headers on " . scalar keys(%{$packages->{mediums}}) . " hdlists");

    $packages;
}

sub psUsingHdlist {
    my ($prefix, $method, $packages, $hdlist, $medium, $rpmsdir, $descr, $selected, $fhdlist) = @_;
    my $fakemedium = "$descr ($method$medium)";
    my ($relocated, $ignored) = (0, 0);
    log::l("trying to read $hdlist for medium $medium");

    #- if the medium already exist, use it.
    $packages->{mediums}{$medium} and return $packages->{mediums}{$medium};

    my $m = $packages->{mediums}{$medium} = { hdlist     => $hdlist,
					      method     => $method,
					      medium     => $medium,
					      rpmsdir    => $rpmsdir, #- where is RPMS directory.
					      descr      => $descr,
					      fakemedium => $fakemedium,
#					      min        => $packages->{count},
#					      max        => -1, #- will be updated after reading current hdlist.
					      selected   => $selected, #- default value is only CD1, it is really the minimal.
					    };

    #- copy hdlist file directly to $prefix/var/lib/urpmi, this will be used
    #- for getting header of package during installation or after by urpmi.
    my $newf = "$prefix/var/lib/urpmi/hdlist.$fakemedium.cz" . ($hdlist =~ /\.cz2/ && "2");
    -e $newf and do { unlink $newf or die "cannot remove $newf: $!"; };
    install_any::getAndSaveFile($fhdlist || "Mandrake/base/$hdlist", $newf) or die "no $hdlist found";
    $m->{hdlist_size} = -s $newf; #- keep track of size for post-check.
    symlinkf $newf, "/tmp/$hdlist";

    #- if $fhdlist is defined, this is preferable not to try to find the associated synthesis.
    my $newsf = "$prefix/var/lib/urpmi/synthesis.hdlist.$fakemedium.cz" . ($hdlist =~ /\.cz2/ && "2");
    unless ($fhdlist) {
	#- copy existing synthesis file too.
	install_any::getAndSaveFile("Mandrake/base/synthesis.$hdlist", $newsf);
	$m->{synthesis_hdlist_size} = -s $newsf; #- keep track of size for post-check.
	-s $newsf > 0 or unlink $newsf;
    }

    #- avoid using more than one medium if Cd is not ejectable.
    #- but keep all medium here so that urpmi has the whole set.
    $method eq 'cdrom' && $medium > 1 && !common::usingRamdisk() and return;

    #- parse synthesis (if available) of directly hdlist (with packing).
    if (-s $newsf) {
	($m->{start}, $m->{end}) = $packages->parse_synthesis($newsf);
    } elsif (-s $newf) {
	($m->{start}, $m->{end}) = $packages->parse_hdlist($newf, 1);
    } else {
	die "fatal: no hdlist nor synthesis to read for $fakemedium";
    }
    $m->{start} > $m->{end} and die "fatal: nothing read in hdlist or synthesis for $fakemedium";
    log::l("read " . ($m->{end} - $m->{start} + 1) . " packages in $hdlist");
    $m;
}

#OBSOLETED TODO
sub getOtherDeps($$) {
    return; #TODO
#    my ($packages, $f) = @_;
#
#    #- this version of getDeps is customized for handling errors more easily and
#    #- convert reference by name to deps id including closure computation.
#    local $_;
#    while (<$f>) {
#	my ($name, $version, $release, $size, $deps) = /^(\S*)-([^-\s]+)-([^-\s]+)\s+(\d+)\s+(.*)/;
#	my $pkg = $packages->{names}{$name};
#
#	$pkg or log::l("ignoring package $name-$version-$release in depslist is not in hdlist"), next;
#	$version eq packageVersion($pkg) and $release eq packageRelease($pkg)
#	  or log::l("warning package $name-$version-$release in depslist mismatch version or release in hdlist ($version ne ",
#		    packageVersion($pkg), " or $release ne ", packageRelease($pkg), ")"), next;
#
#	my $index = scalar @{$packages->{depslist}};
#	$index >= packageMedium($packages, $pkg)->{min} && $index <= packageMedium($packages, $pkg)->{max}
#	  or log::l("ignoring package $name-$version-$release in depslist outside of hdlist indexation");
#
#	#- here we have to translate referenced deps by name to id.
#	#- this include a closure on deps too.
#	my %closuredeps;
#	@closuredeps{map { packageId($packages, $_), packageDepsId($_) }
#		       grep { $_ }
#			 map { packageByName($packages, $_) or do { log::l("unknown package $_ in depslist for closure"); undef } }
#			   split /\s+/, $deps} = ();
#
#	$pkg->[$SIZE_DEPS] = join " ", $size, keys %closuredeps;
#
#	push @{$packages->{depslist}}, $pkg;
#    }
#
#    #- check for same number of package in depslist and hdlists, avoid being to hard.
#    scalar(keys %{$packages->{names}}) == scalar(@{$packages->{depslist}})
#      or log::l("other depslist has not same package as hdlist file");
}

#OBSOLETED TODO
sub getDeps {
    return; #TODO
#    my ($prefix, $packages) = @_;
#
#    #- this is necessary for urpmi.
#    install_any::getAndSaveFile('Mandrake/base/depslist.ordered', "$prefix/var/lib/urpmi/depslist.ordered");
#    install_any::getAndSaveFile('Mandrake/base/provides', "$prefix/var/lib/urpmi/provides");
#
#    #- beware of heavily mismatching depslist.ordered file against hdlist files.
#    my $mismatch = 0;
#
#    #- count the number of packages in deplist that are also in hdlist
#    my $nb_deplist = 0;
#
#    #- update dependencies list, provides attributes are updated later
#    #- cross reference to be resolved on id (think of loop requires)
#    #- provides should be updated after base flag has been set to save
#    #- memory.
#    local *F; open F, "$prefix/var/lib/urpmi/depslist.ordered" or die "can't find dependancies list";
#    local $_;
#    while (<F>) {
#	my ($name, $version, $release, $arch, $epoch, $sizeDeps) =
#	  /^([^:\s]*)-([^:\-\s]+)-([^:\-\s]+)\.([^:\.\-\s]*)(?::(\d+)\S*)?\s+(.*)/;
#	my $pkg = $packages->{names}{$name};
#
#	#- these verification are necessary in case of error, but are no more fatal as
#	#- in case of only one medium taken into account during install, there should be
#	#- silent warning for package which are unknown at this point.
#	$pkg or
#	  log::l("ignoring $name-$version-$release.$arch in depslist is not in hdlist");
#	$pkg && $version ne packageVersion($pkg) and
#	  log::l("ignoring $name-$version-$release.$arch in depslist mismatch version in hdlist"), $pkg = undef;
#	$pkg && $release ne packageRelease($pkg) and
#	  log::l("ignoring $name-$version-$release.$arch in depslist mismatch release in hdlist"), $pkg = undef;
#	$pkg && $arch ne packageArch($pkg) and
#	  log::l("ignoring $name-$version-$release.$arch in depslist mismatch arch in hdlist"), $pkg = undef;
#
#	if ($pkg) {
#	    $nb_deplist++;
#	    $epoch && $epoch > 0 and $pkg->[$EPOCH] = $epoch; #- only 5% of the distribution use epoch (serial).
#	    $pkg->[$SIZE_DEPS] = $sizeDeps;
#
#	    #- check position of package in depslist according to precomputed
#	    #- limit by hdlist, very strict :-)
#	    #- above warning have chance to raise an exception here, but may help
#	    #- for debugging.
#	    my $i = scalar @{$packages->{depslist}};
#	    $i >= packageMedium($packages, $pkg)->{min} && $i <= packageMedium($packages, $pkg)->{max} or
#	      log::l("inconsistency in position for $name-$version-$release.$arch in depslist and hdlist"), $mismatch = 1;
#	}
#
#	#- package are already sorted in depslist to enable small transaction and multiple medium.
#	push @{$packages->{depslist}}, $pkg;
#    }
#
#    #- check for mismatching package, it should break with above die unless depslist has too many errors!
#    $mismatch and die "depslist.ordered mismatch against hdlist files";
#
#    #- check for same number of package in depslist and hdlists.
#    my $nb_hdlist = keys %{$packages->{names}};
#    $nb_hdlist == $nb_deplist or die "depslist.ordered has not same package as hdlist files ($nb_deplist != $nb_hdlist)";
}

#OBSOLETED TODO
sub getProvides($) {
    return; #TODO
#    my ($packages) = @_;
#
#    #- update provides according to dependencies, here are stored
#    #- reference to package directly and choice are included, this
#    #- assume only 1 of the choice is selected, else on unselection
#    #- the provided package will be deleted where other package still
#    #- need it.
#    #- base package are not updated because they cannot be unselected,
#    #- this save certainly a lot of memory since most of them may be
#    #- needed by a large number of package.
#    #- now using a packed of signed short, this means no more than 32768
#    #- packages can be managed by DrakX (currently about 2000).
#    my $i = 0;
#    foreach my $pkg (@{$packages->{depslist}}) {
#	$pkg or next;
#	unless (packageFlagBase($pkg)) {
#	    foreach (map { split '\|' } grep { !/^NOTFOUND_/ } packageDepsId($pkg)) {
#		my $provided = packageById($packages, $_) or next;
#		packageFlagBase($provided) or $provided->[$PROVIDES] = pack "s*", (unpack "s*", $provided->[$PROVIDES]), $i;
#	    }
#	}
#	++$i;
#    }
}

sub read_rpmsrate {
    my ($packages, $f) = @_;
    my $line_nb = 0;
    my $fatal_error;
    my (@l);
    while (<$f>) {
	$line_nb++;
	/\t/ and die "tabulations not allowed at line $line_nb\n";
	s/#.*//; # comments

	my ($indent, $data) = /(\s*)(.*)/;
	next if !$data; # skip empty lines

	@l = grep { $_->[0] < length $indent } @l;

	my @m = @l ? @{$l[$#l][1]} : ();
	my ($t, $flag, @l2);
	while ($data =~ 
	       /^((
                   [1-5]
                   |
                   (?:            (?: !\s*)? [0-9A-Z_]+(?:".*?")?)
                   (?: \s*\|\|\s* (?: !\s*)? [0-9A-Z_]+(?:".*?")?)*
                  )
                  (?:\s+|$)
                 )(.*)/x) { #@")) {
	    ($t, $flag, $data) = ($1,$2,$3);
	    while ($flag =~ s,^\s*(("[^"]*"|[^"\s]*)*)\s+,$1,) {}
	    my $ok = 0;
	    $flag = join('||', grep { 
		if (my ($inv, $p) = /^(!)?HW"(.*)"/) {
		    ($inv xor detect_devices::matching_desc($p)) and $ok = 1;
		    0;
		} else {
		    1;
		}
	    } split '\|\|', $flag);
	    push @m, $ok ? 'TRUE' : $flag || 'FALSE';
	    push @l2, [ length $indent, [ @m ] ];
	    $indent .= $t;
	}
	if ($data) {
	    # has packages on same line
	    my ($rate) = grep { /^\d$/ } @m or die sprintf qq(missing rate for "%s" at line %d (flags are %s)\n), $data, $line_nb, join('&&', @m);
	    foreach (split ' ', $data) {
		if ($packages) {
		    my $p = packageByName($packages, $_) or next;
		    my @m2 = map { if_(/locales-(.*)/, qq(LOCALES"$1")) } $p->requires_nosense;
		    my @m3 = ((grep { !/^\d$/ } @m), @m2);
		    if (member('INSTALL', @m3)) {
			member('NOCOPY', @m3) or push @{$packages->{needToCopy} ||= []}, $_;
			next; #- don't need to put INSTALL flag for a package.
		    }
		    if ($p->rate) {
			my @m4 = $p->rflags;
			if (@m3 > 1 || @m4 > 1) {
			    log::l("can't handle complicate flags for packages appearing twice ($_)");
			    $fatal_error++;
			}
			log::l("package $_ appearing twice with different rates ($rate != ".$p->rate.")") if $rate != $p->rate;
			$p->set_rate($rate);
			$p->set_rflags("$m3[0]||$m4[0]");
		    } else {
			$p->set_rate($rate);
			$p->set_rflags(@m3);
		    }
		} else {
		    print "$_ = ", join(" && ", @m), "\n";
		}
	    }
	    push @l, @l2;
	} else {
	    push @l, [ $l2[0][0], $l2[$#l2][1] ];
	}
    }
    $fatal_error and die "$fatal_error fatal errors in rpmsrate";
}

sub readCompssUsers {
    my ($meta_class) = @_;
    my (%compssUsers, @sorted, $l);

    my $file = 'Mandrake/base/compssUsers';
    my $f = $meta_class && install_any::getFile("$file.$meta_class") || install_any::getFile($file) or die "can't find $file";
    local $_;
    while (<$f>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;

	if (/^(\S.*)/) {
	    my $verbatim = $_;
	    my ($icon, $descr, $path);
	    /^(.*?)\s*\[path=(.*?)\](.*)/  and $_ = "$1$3", $path  = $2;
	    /^(.*?)\s*\[icon=(.*?)\](.*)/  and $_ = "$1$3", $icon  = $2;
	    /^(.*?)\s*\[descr=(.*?)\](.*)/ and $_ = "$1$3", $descr = $2;
	    $compssUsers{"$path|$_"} = { label => $_, verbatim => $verbatim, path => $path, icons => $icon, descr => $descr, flags => $l=[] };
	    push @sorted, "$path|$_";
	} elsif (/^\s+(.*?)\s*$/) {
	    push @$l, $1;
	}
    }
    \%compssUsers, \@sorted;
}
sub saveCompssUsers {
    my ($prefix, $packages, $compssUsers, $sorted) = @_;
    my $flat;
    foreach (@$sorted) {
	my @fl = @{$compssUsers->{$_}{flags}};
	my %fl; $fl{$_} = 1 foreach @fl;
	$flat .= $compssUsers->{$_}{verbatim};
	foreach my $p (@{$packages->{depslist}}) {
	    my @flags = $p->rflags;
	    if ($p->rate && grep { grep { !/^!/ && $fl{$_} } split('\|\|') } @flags) {
		$flat .= sprintf "\t%d %s\n", $p->rate, $p->name;
	    }
	}
    }
    output "$prefix/var/lib/urpmi/compssUsers.flat", $flat;
}

sub setSelectedFromCompssList {
    my ($packages, $compssUsersChoice, $min_level, $max_size) = @_;
    $compssUsersChoice->{TRUE} = 1; #- ensure TRUE is set
    my $nb = selectedSize($packages);
    foreach my $p (sort { $b->rate <=> $a->rate } @{$packages->{depslist}}) {
	my @flags = $p->rflags;
	next if 
	  !$p->rate || $p->rate < $min_level || 
	  grep { !grep { /^!(.*)/ ? !$compssUsersChoice->{$1} : $compssUsersChoice->{$_} } split('\|\|') } @flags;

	#- determine the packages that will be selected when
	#- selecting $p. the packages are not selected.
	my $state = $packages->{state} ||= {};
	$state->{selected} = {};
	$state->{requested} = packageRequest($packages, $p) || {};

	$packages->resolve_requested($packages->{rpmdb}, $state, no_flag_update => 1,
				     callback_choices => \&packageCallbackChoices);

	#- this enable an incremental total size.
	my $old_nb = $nb;
	foreach (keys %{$state->{selected}}) {
	    my $p = $packages->{depslist}[$_] or next;
	    $nb += $p->size;
	}
	if ($max_size && $nb > $max_size) {
	    $nb = $old_nb;
	    $min_level = $p->rate;
	    $state->{requested} = {}; #- ensure no newer package will be selected.
	    $packages->resolve_requested($packages->{rpmdb}, $state, keep_state => 1); #- FIXME INCOMPLETE TODO
	    last;
	}

	#- do the effective selection (was not done due to no_flag_update option used.
	foreach (keys %{$state->{selected}}) {
	    my $pkg = $packages->{depslist}[$_];
	    $state->{selected}{$_} ? $pkg->set_flag_requested : $pkg->set_flag_required;
	}
    }
    log::l("setSelectedFromCompssList: reached size ", formatXiB($nb), ", up to indice $min_level (less than ", formatXiB($max_size), ")");
    log::l("setSelectedFromCompssList: ", join(" ", sort map { $_->name } grep { $_->flag_selected } @{$packages->{depslist}}));
    $min_level;
}

#- usefull to know the size it would take for a given min_level/max_size
#- just saves the selected packages, call setSelectedFromCompssList and restores the selected packages
sub saveSelected {
    my ($packages) = @_;
    my $state = delete $packages->{state};
    my @l = @{$packages->{depslist}};
    my @flags = map { ($_->flag_requested && 1) + ($_->flag_required && 2) + ($_->flag_upgrade && 4) } @l;
    [ $packages, $state, \@l, \@flags ];
}
sub restoreSelected {
    my ($packages, $state, $l, $flags) = @{$_[0]};
    $packages->{state} = $state;
    mapn { my ($pkg, $flag) = @_;
	   $pkg->set_flag_requested($flag & 1);
	   $pkg->set_flag_required($flag & 2);
	   $pkg->set_flag_upgrade($flag & 4);
         } $l, $flags;
}

sub computeGroupSize {
    my ($packages, $min_level) = @_;

    sub inside {
	my ($l1, $l2) = @_;
	my $i = 0;
	return if @$l1 > @$l2;
	foreach (@$l1) {
	    my $c;
	    while ($c = $l2->[$i++] cmp $_ ) {
		return if $c == 1 || $i > @$l2;
	    }
	}
	1;
    }

    sub or_ify {
	my ($first, @other) = @_;
	my @l = split('\|\|', $first);
	foreach (@other) {
	    @l = map {
		my $n = $_;
		map { "$_&&$n" } @l;
	    } split('\|\|');
	}
	#- HACK, remove LOCALES & CHARSET, too costly
	grep { !/LOCALES|CHARSET/ } @l;
    }
    sub or_clean {
	my (@l) = map { [ sort split('&&') ] } @_ or return '';
	my @r;
	B: while (@l) {
	    my $e = shift @l;
	    foreach (@r, @l) {
		inside($e, $_) and next B;
	    }
	    push @r, $e;
	}
	join("\t", map { join('&&', @$_) } @r);
    }
    my (%group, %memo);

    foreach my $p (@{$packages->{depslist}}) {
	my @flags = $p->rflags;
	next if !$p->rate || $p->rate < $min_level;

	my $flags = join("\t", @flags = or_ify(@flags));
	$group{$p->name} = ($memo{$flags} ||= or_clean(@flags));

	#- determine the packages that will be selected when selecting $p.
	#- make a fast selection (but potentially erroneous).
	my %newSelection;
	unless ($p->flag_available) {
	    my @l2 = ($p->id);
	    my $id;

	    while (defined($id = shift @l2)) {
		exists $newSelection{$id} and next;
		$newSelection{$id} = undef;

		my $pkg = $packages->{depslist}[$id];
		foreach ($pkg->requires_nosense) {
		    my ($candidate_id, $prefer_id);
		    foreach (keys %{$packages->{provides}{$_} || {}}) {
			my $ppkg = $packages->{depslist}[$_] or next;
			if ($ppkg->flag_available) {
			    $candidate_id = undef;
			    last;
			} else {
			    exists $preferred{$ppkg->name} and $prefer_id = $_;
			    $ppkg->name =~ /kernel-\d/ and $prefer_id ||= $_;
			    $candidate_id = $_;
			}
		    }
		    push @l2, $prefer_id || $candidate_id;
		}
	    }
	}

	foreach (keys %newSelection) {
	    my $p = $packages->{depslist}[$_] or next;
	    my $s = $group{$p->name} || do {
		join("\t", or_ify($p->rflags));
	    };
	    next if length($s) > 80; # HACK, truncated too complicated expressions, too costly
	    my $m = "$flags\t$s";
	    $group{$p->name} = ($memo{$m} ||= or_clean(@flags, split("\t", $s)));
	}
    }
    my (%sizes, %pkgs);
    while (my ($k, $v) = each %group) {
	my $pkg = packageByName($packages, $k) or next;
	push @{$pkgs{$v}}, $k;
	$sizes{$v} += $pkg->size;
    }
    log::l(sprintf "%s %dMB %s", $_, $sizes{$_} / sqr(1024), join(',', @{$pkgs{$_}})) foreach keys %sizes;
    \%sizes, \%pkgs;
}


sub openInstallLog {
    my ($prefix) = @_;

    my $f = "$prefix/root/drakx/install.log";
    open(LOG, ">> $f") ? log::l("opened $f") : log::l("Failed to open $f. No install log will be kept.");
    *LOG or *LOG = log::F() or *LOG = *STDERR;
    CORE::select((CORE::select(LOG), $| = 1)[0]);
    c::rpmErrorSetCallback(fileno LOG);
#-    c::rpmSetVeryVerbose();
}

sub closeInstallLog {
    log::l("closing install.log file");
    close LOG;
}

sub rpmDbOpen {
    my ($prefix, $rebuild_needed) = @_;

    if ($rebuild_needed) {
	if (my $pid = fork()) {
	    waitpid $pid, 0;
	    ($? & 0xff00) and die "rebuilding of rpm database failed";
	} else {
	    log::l("rebuilding rpm database");
	    my $rebuilddb_dir = "$prefix/var/lib/rpmrebuilddb.$$";
	    -d $rebuilddb_dir and log::l("removing stale directory $rebuilddb_dir"), rm_rf($rebuilddb_dir);

	    URPM::DB::rebuild($prefix) or log::l("rebuilding of rpm database failed: ". c::rpmErrorString()), c::_exit(2);

	    c::_exit(0);
	}
    }

    my $db;
    if ($db = URPM::DB::open($prefix)) {
	log::l("opened rpm database for examining existing packages");
    } else {
	log::l("unable to open rpm database, using empty rpm db emulation");
	$db = new URPM;
    }

    $db;
}

sub cleanOldRpmDb {
    my ($prefix) = @_;
    my $failed;

    foreach (qw(Basenames Conflictname Group Name Packages Providename Requirename Triggername)) {
	-s "$prefix/var/lib/rpm/$_" or $failed = 'failed';
    }
    #- rebuilding has been successfull, so remove old rpm database if any.
    #- once we have checked the rpm4 db file are present and not null, in case
    #- of doubt, avoid removing them...
    unless ($failed) {
	log::l("rebuilding rpm database completed successfully");
	foreach (qw(conflictsindex.rpm fileindex.rpm groupindex.rpm nameindex.rpm packages.rpm
                    providesindex.rpm requiredby.rpm triggerindex.rpm)) {
	    -e "$prefix/var/lib/rpm/$_" or next;
	    log::l("removing old rpm file $_");
	    rm_rf("$prefix/var/lib/rpm/$_");
	}
    }
}

sub selectPackagesAlreadyInstalled {
    my ($packages, $prefix) = @_;

    log::l("computing installed flags only");
    $packages->compute_installed_flags($packages->{rpmdb});
}

sub selectPackagesToUpgrade {
    my ($packages, $prefix, $base, $toRemove, $toSave) = @_;

    log::l("selecting packages to upgrade");

    my $state = $packages->{state} ||= {};
    $state->{selected} = {};
    $state->{requested} = {};

    $packages->resolve_packages_to_upgrade($packages->{rpmdb}, $state, requested => undef);
    $packages->resolve_requested($packages->{rpmdb}, $state, callback_choices => \&packageCallbackChoices);
}
#    return;
#    my ($packages, $prefix, $base, $toRemove, $toSave) = @_;
#    local $_; #- else perl complains on the map { ... } grep { ... } @...;
#
#    local (*UPGRADE_INPUT, *UPGRADE_OUTPUT); pipe UPGRADE_INPUT, UPGRADE_OUTPUT;
#    if (my $pid = fork()) {
#	@{$toRemove || []} = (); #- reset this one.
#
#	close UPGRADE_OUTPUT;
#	while (<UPGRADE_INPUT>) {
#	    chomp;
#	    my ($action, $name) = /^([\w\d]*):(.*)/;
#	    for ($action) {
#		/remove/    and do { push @$toRemove, $name; next };
#		/keepfiles/ and do { push @$toSave, $name; next };
#
#		my $p = $packages->{names}{$name} or die "unable to find package ($name)";
#		/^\d*$/     and do { $p->[$INSTALLED_CUMUL_SIZE] = $action; next };
#		/installed/ and do { packageSetFlagInstalled($p, 1); next };
#		/select/    and do { selectPackage($packages, $p); next };
#
#		die "unknown action ($action)";
#	    }
#	}
#	close UPGRADE_INPUT;
#	waitpid $pid, 0;
#    } else {
#	close UPGRADE_INPUT;
#	
#	my $db = rebuild_db_open_for_traversal($packages, $prefix);
#	#- used for package that are not correctly updated.
#	#- should only be used when nothing else can be done correctly.
#	my %upgradeNeedRemove = (
##				 'libstdc++' => 1,
##				 'compat-glibc' => 1,
##				 'compat-libs' => 1,
#				);
#
#	#- generel purpose for forcing upgrade of package whatever version is.
#	my %packageNeedUpgrade = (
#				  #'lilo' => 1, #- this package has been misnamed in 7.0.
#				 );
#
#	#- help removing package which may have different release numbering
#	my %toRemove; map { $toRemove{$_} = 1 } @{$toRemove || []};
#
#	#- help searching package to upgrade in regard to already installed files.
#	my %installedFilesForUpgrade;
#
#	#- help keeping memory by this set of package that have been obsoleted.
#	my %obsoletedPackages;
#
#	#- make a subprocess here for reading filelist, this is important
#	#- not to waste a lot of memory for the main program which will fork
#	#- latter for each transaction.
#	local (*INPUT, *OUTPUT_CHILD); pipe INPUT, OUTPUT_CHILD;
#	local (*INPUT_CHILD, *OUTPUT); pipe INPUT_CHILD, OUTPUT;
#	if (my $pid = fork()) {
#	    close INPUT_CHILD;
#	    close OUTPUT_CHILD;
#	    select((select(OUTPUT), $| = 1)[0]);
#
#	    #- internal reading from interactive mode of parsehdlist.
#	    #- takes a code to call with the line read, this avoid allocating
#	    #- memory for that.
#	    my $ask_child = sub {
#		my ($name, $tag, $code) = @_;
#		$code or die "no callback code for parsehdlist output";
#		print OUTPUT "$name:$tag\n";
#
#		local $_;
#		while (<INPUT>) {
#		    chomp;
#		    /^\s*$/ and last;
#		    $code->($_);
#		}
#	    };
#
#	    #- select packages which obseletes other package, obselete package are not removed,
#	    #- should we remove them ? this could be dangerous !
#	    foreach my $p (values %{$packages->{names}}) {
#		$ask_child->(packageName($p), "obsoletes", sub {
#				 #- take care of flags and version and release if present
#				 local ($_) = @_;
#				 if (my ($n,$o,$v,$r) = /^(\S*)\s*(\S*)\s*([^\s-]*)-?(\S*)/) {
#				     my $obsoleted = 0;
#				     my $check_obsoletes = sub {
#					 my ($header) = @_;
#					 (!$v || eval(versionCompare(c::headerGetEntry($header, 'version'), $v) . $o . 0)) &&
#					   (!$r || versionCompare(c::headerGetEntry($header, 'version'), $v) != 0 ||
#					    eval(versionCompare(c::headerGetEntry($header, 'release'), $r) . $o . 0)) or return;
#					 ++$obsoleted;
#				     };
#				     c::rpmdbNameTraverse($db, $n, $check_obsoletes);
#				     if ($obsoleted > 0) {
#					 log::l("selecting " . packageName($p) . " by selection on obsoletes");
#					 $obsoletedPackages{$1} = undef;
#					 selectPackage($packages, $p);
#				     }
#				 }
#			     });
#	    }
#
#	    #- mark all files which are not in /etc/rc.d/ for packages which are already installed but which
#	    #- are not in the packages list to upgrade.
#	    #- the 'installed' property will make a package unable to be selected, look at select.
#	    c::rpmdbTraverse($db, sub {
#				 my ($header) = @_;
#				 my $otherPackage = (c::headerGetEntry($header, 'release') !~ /mdk\w*$/ &&
#						     (c::headerGetEntry($header, 'name'). '-' .
#						      c::headerGetEntry($header, 'version'). '-' .
#						      c::headerGetEntry($header, 'release')));
#				 my $p = $packages->{names}{c::headerGetEntry($header, 'name')};
#
#				 if ($p) {
#				     my $epoch_cmp = c::headerGetEntry($header, 'epoch') <=> packageEpoch($p);
#				     my $version_cmp = $epoch_cmp == 0 && versionCompare(c::headerGetEntry($header, 'version'),
#											 packageVersion($p));
#				     my $version_rel_test = $epoch_cmp > 0 || $epoch_cmp == 0 &&
#				       ($version_cmp > 0 || $version_cmp == 0 &&
#					versionCompare(c::headerGetEntry($header, 'release'), packageRelease($p)) >= 0);
#				     if ($packageNeedUpgrade{packageName($p)}) {
#					 log::l("package ". packageName($p) ." need to be upgraded");
#				     } elsif ($version_rel_test) { #- by default, package are upgraded whatever version is !
#					 if ($otherPackage && $version_cmp <= 0) {
#					     log::l("force upgrading $otherPackage since it will not be updated otherwise");
#					 } else {
#					     #- let the parent known this installed package.
#					     print UPGRADE_OUTPUT "installed:" . packageName($p) . "\n";
#					     packageSetFlagInstalled($p, 1);
#					 }
#				     } elsif ($upgradeNeedRemove{packageName($p)}) {
#					 my $otherPackage = (c::headerGetEntry($header, 'name'). '-' .
#							     c::headerGetEntry($header, 'version'). '-' .
#							     c::headerGetEntry($header, 'release'));
#					 log::l("removing $otherPackage since it will not upgrade correctly!");
#					 $toRemove{$otherPackage} = 1; #- force removing for theses other packages, select our.
#				     }
#				 } else {
#				     if (exists $obsoletedPackages{c::headerGetEntry($header, 'name')}) {
#					 my @files = c::headerGetEntry($header, 'filenames');
#					 @installedFilesForUpgrade{grep { ($_ !~ m|^/dev/| && $_ !~ m|^/etc/rc.d/| && $_ !~ m|\.la$| &&
#									   ! -d "$prefix/$_" && ! -l "$prefix/$_") } @files} = ();
#				     }
#				 }
#			     });
#
#	    #- find new packages to upgrade.
#	    foreach my $p (values %{$packages->{names}}) {
#		my $skipThis = 0;
#		my $count = c::rpmdbNameTraverse($db, packageName($p), sub {
#						     my ($header) = @_;
#						     $skipThis ||= packageFlagInstalled($p);
#						 });
#
#		#- skip if not installed (package not found in current install).
#		$skipThis ||= ($count == 0);
#
#		#- make sure to upgrade package that have to be upgraded.
#		$packageNeedUpgrade{packageName($p)} and $skipThis = 0;
#
#		#- select the package if it is already installed with a lower version or simply not installed.
#		unless ($skipThis) {
#		    my $cumulSize;
#
#		    selectPackage($packages, $p);
#
#		    #- keep in mind installed files which are not being updated. doing this costs in
#		    #- execution time but use less memory, else hash all installed files and unhash
#		    #- all file for package marked for upgrade.
#		    c::rpmdbNameTraverse($db, packageName($p), sub {
#					     my ($header) = @_;
#					     $cumulSize += c::headerGetEntry($header, 'size');
#					     my @files = c::headerGetEntry($header, 'filenames');
#					     @installedFilesForUpgrade{grep { ($_ !~ m|^/dev/| && $_ !~ m|^/etc/rc.d/| && $_ !~ m|\.la$| &&
#									   ! -d "$prefix/$_" && ! -l "$prefix/$_") } @files} = ();
#					 });
#
#		    $ask_child->(packageName($p), "files", sub {
#				     delete $installedFilesForUpgrade{$_[0]};
#				 });
#
#		    #- keep in mind the cumul size of installed package since they will be deleted
#		    #- on upgrade, only for package that are allowed to be upgraded.
#		    if (allowedToUpgrade(packageName($p))) {
#			print UPGRADE_OUTPUT "$cumulSize:" . packageName($p) . "\n";
#		    }
#		}
#	    }
#
#	    #- unmark all files for all packages marked for upgrade. it may not have been done above
#	    #- since some packages may have been selected by depsList.
#	    foreach my $p (values %{$packages->{names}}) {
#		if (packageFlagSelected($p)) {
#		    $ask_child->(packageName($p), "files", sub {
#				     delete $installedFilesForUpgrade{$_[0]};
#				 });
#		}
#	    }
#
#	    #- select packages which contains marked files, then unmark on selection.
#	    #- a special case can be made here, the selection is done only for packages
#	    #- requiring locales if the locales are selected.
#	    #- another special case are for devel packages where fixes over the time has
#	    #- made some files moving between the normal package and its devel couterpart.
#	    #- if only one file is affected, no devel package is selected.
#	    foreach my $p (values %{$packages->{names}}) {
#		unless (packageFlagSelected($p)) {
#		    my $toSelect = 0;
#		    $ask_child->(packageName($p), "files", sub {
#				     if ($_[0] !~ m|^/dev/| && $_[0] !~  m|^/etc/rc.d/| &&  $_ !~ m|\.la$| && exists $installedFilesForUpgrade{$_[0]}) {
#					 ++$toSelect if ! -d "$prefix/$_[0]" && ! -l "$prefix/$_[0]";
#				     }
#				     delete $installedFilesForUpgrade{$_[0]};
#				 });
#		    if ($toSelect) {
#			if ($toSelect <= 1 && packageName($p) =~ /-devel/) {
#			    log::l("avoid selecting " . packageName($p) . " as not enough files will be updated");
#			} else {
#			    #- default case is assumed to allow upgrade.
#			    my @deps = map { my $p = packageById($packages, $_);
#					     if_($p && packageName($p) =~ /locales-/, $p) } packageDepsId($p);
#			    if (@deps == 0 || @deps > 0 && (grep { !packageFlagSelected($_) } @deps) == 0) {
#				log::l("selecting " . packageName($p) . " by selection on files");
#				selectPackage($packages, $p);
#			    } else {
#				log::l("avoid selecting " . packageName($p) . " as its locales language is not already selected");
#			    }
#			}
#		    }
#		}
#	    }
#
#	    #- clean memory...
#	    %installedFilesForUpgrade = ();
#
#	    #- no need to still use the child as this point, we can let him to terminate.
#	    close OUTPUT;
#	    close INPUT;
#	    waitpid $pid, 0;
#	} else {
#	    close INPUT;
#	    close OUTPUT;
#	    open STDIN, "<&INPUT_CHILD";
#	    open STDOUT, ">&OUTPUT_CHILD";
#	    exec if_($ENV{LD_LOADER}, $ENV{LD_LOADER}), "parsehdlist", "--interactive", map { "/tmp/$_->{hdlist}" } values %{$packages->{mediums}}
#	      or c::_exit(1);
#	}
#
#	#- let the parent known about what we found here!
#	foreach my $p (values %{$packages->{names}}) {
#	    print UPGRADE_OUTPUT "select:" . packageName($p) . "\n" if packageFlagSelected($p);
#	}
#
#	#- clean false value on toRemove.
#	delete $toRemove{''};
#
#	#- get filenames that should be saved for packages to remove.
#	#- typically config files, but it may broke for packages that
#	#- are very old when compabilty has been broken.
#	#- but new version may saved to .rpmnew so it not so hard !
#	if ($toSave && keys %toRemove) {
#	    c::rpmdbTraverse($db, sub {
#				 my ($header) = @_;
#				 my $otherPackage = (c::headerGetEntry($header, 'name'). '-' .
#						     c::headerGetEntry($header, 'version'). '-' .
#						     c::headerGetEntry($header, 'release'));
#				 if ($toRemove{$otherPackage}) {
#				     print UPGRADE_OUTPUT "remove:$otherPackage\n";
#				     if (packageFlagBase($packages->{names}{c::headerGetEntry($header, 'name')})) {
#					 delete $toRemove{$otherPackage}; #- keep it selected, but force upgrade.
#				     } else {
#					 my @files = c::headerGetEntry($header, 'filenames');
#					 my @flags = c::headerGetEntry($header, 'fileflags');
#					 for my $i (0..$#flags) {
#					     if ($flags[$i] & c::RPMFILE_CONFIG()) {
#						 print UPGRADE_OUTPUT "keepfiles:$files[$i]\n" unless $files[$i] =~ /kdelnk/;
#					     }
#					 }
#				     }
#				 }
#			     });
#	}
#
#	#- close db, job finished !
#	c::rpmdbClose($db);
#	log::l("done selecting packages to upgrade");
#
#	close UPGRADE_OUTPUT;
#	c::_exit(0);
#    }
#
#    #- keep a track of packages that are been selected for being upgraded,
#    #- these packages should not be unselected (unless expertise)
#    foreach my $p (values %{$packages->{names}}) {
#	packageSetFlagUpgrade($p, 1) if packageFlagSelected($p);
#    }
#}

sub allowedToUpgrade { $_[0] !~ /^(kernel|kernel22|kernel2.2|kernel-secure|kernel-smp|kernel-linus|kernel-linus2.2|hackkernel|kernel-enterprise)$/ }

sub installTransactionClosure {
    my ($packages, $id2pkg) = @_;
    my ($id, %closure, @l, $medium, $min_id, $max_id);

    @l = sort { $a <=> $b } keys %$id2pkg;

    #- search first usable medium (sorted by medium ordering).
    foreach (sort { $a->{start} <=> $b->{start} } values %{$packages->{mediums}}) {
	$_->{selected} or next;
	if ($l[0] <= $_->{end}) {
	    #- we have a candidate medium, it could be the right one containing
	    #- the first package of @l...
	    $l[0] >= $_->{start} and $medium = $_, last;
	    #- ... but it could be necessary to find the first
	    #- medium containing package of @l.
	    foreach $id (@l) {
		$id >= $_->{start} && $id <= $_->{end} and $medium = $_, last;
	    }
	    $medium and last;
	}
    }
    $medium or return (); #- no more medium usable -> end of installation by returning empty list.
    ($min_id, $max_id) = ($medium->{start}, $medium->{end});

    #- it is sure at least one package will be installed according to medium chosen.
    install_any::useMedium($medium->{medium});
    if ($medium->{method} eq 'cdrom') {
	my $pkg = $packages->{depslist}[$l[0]];

	#- force changeCD callback to be called from main process.
	install_any::getFile($pkg->filename, $medium->{descr});
	#- close opened handle above.
	install_any::getFile('XXX');
    }

    while (defined($id = shift @l)) {
	my @l2 = ($id);

	while (defined($id = shift @l2)) {
	    exists $closure{$id} and next;
	    $id >= $min_id && $id <= $max_id or next;
	    $closure{$id} = undef;

	    my $pkg = $packages->{depslist}[$id];
	    foreach ($pkg->requires_nosense) {
		foreach (keys %{$packages->{provides}{$_} || {}}) {
		    if ($id2pkg->{$_}) {
			push @l2, $_;
			last;
		    }
		}
	    }
	}

	keys %closure >= $limitMinTrans and last;
    }

    map { delete $id2pkg->{$_} } grep { $id2pkg->{$_} } keys %closure;
}

sub installCallback {
#    my $msg = shift;
#    log::l($msg .": ". join(',', @_));
}

sub install($$$;$$) {
    my ($prefix, $isUpgrade, $toInstall, $packages) = @_;
    my %packages;

    return if $::g_auto_install || !scalar(@$toInstall);

    #- for root loopback'ed /boot
    my $loop_boot = loopback::prepare_boot($prefix);

    #- first stage to extract some important informations
    #- about the packages selected. this is used to select
    #- one or many transaction.
    my ($total, $nb);
    foreach my $pkg (@$toInstall) {
	$packages{$pkg->id} = $pkg;
	$nb++;
	$total += to_int($pkg->size); #- do not correct for upgrade!
    }

    log::l("pkgs::install $prefix");
    log::l("pkgs::install the following: ", join(" ", map { $_->name } values %packages));
    eval { fs::mount("/proc", "$prefix/proc", "proc", 0) } unless -e "$prefix/proc/cpuinfo";

    openInstallLog($prefix);

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install_steps_gtk.pm,...).
    installCallback($packages, 'user', undef, 'install', $nb, $total);

    do {
	my @transToInstall = installTransactionClosure($packages, \%packages);
	$nb = values %packages;

	#- added to exit typically after last media unselected.
	if ($nb == 0 && scalar(@transToInstall) == 0) {
	    cleanHeaders($prefix);

	    loopback::save_boot($loop_boot);
	    return;
	}

	#- extract headers for parent as they are used by callback.
	extractHeaders($prefix, \@transToInstall, $packages->{mediums});

	my ($retry_pkg, $retry_count);
	while ($retry_pkg || @transToInstall) {
	    local (*INPUT, *OUTPUT); pipe INPUT, OUTPUT;
	    if (my $pid = fork()) {
		close OUTPUT;
		my $error_msg = '';
		local $_;
		while (<INPUT>) {
		    if (/^die:(.*)/) {
			$error_msg = $1;
			last;
		    } else {
			chomp;
			my @params = split ":";
			if ($params[0] eq 'close') {
			    my $pkg = $packages->{depslist}[$params[1]];
			    $pkg->set_flag_installed(1);
			    $pkg->set_flag_upgrade(0);
			} else {
			    installCallback($packages, @params);
			}
		    }
		}
		$error_msg and $error_msg .= join('', <INPUT>);
		waitpid $pid, 0;
		close INPUT;
		$error_msg and die $error_msg;
	    } else {
		#- child process will run each transaction.
		$SIG{SEGV} = sub { log::l("segmentation fault on transactions"); c::_exit(0) };
		my @prev_pids = grep { /^\d+$/ } all("/proc");
		my $db;
		eval {
		    close INPUT;
		    select((select(OUTPUT),  $| = 1)[0]);
		    my $db = URPM::DB::open($prefix, 1) or die "error opening RPM database: ", c::rpmErrorString();
		    my $trans = $db->create_transaction($prefix);
		    if ($retry_pkg) {
			log::l("opened rpm database for retry transaction of 1 package only");
			$trans->add($retry_pkg, $isUpgrade && allowedToUpgrade($retry_pkg->name));
		    } else {
			log::l("opened rpm database for transaction of ". scalar @transToInstall .
			       " new packages, still $nb after that to do");
			$trans->add($_, $isUpgrade && allowedToUpgrade($_->name))
			  foreach @transToInstall;
		    }

		    $trans->order or die "error ordering package list: " . c::rpmErrorString();
		    $trans->set_script_fd(fileno LOG);

		    log::l("rpm transactions start");
		    my @probs = $trans->run($packages, force => 1, nosize => 1, callback_open => sub {
						my ($data, $type, $id) = @_;
						my $pkg = defined $id && $data->{depslist}[$id];
						my $f = $pkg && $pkg->filename;
						print LOG "$f\n";
						#my $fd = install_any::getFile($f, $media->{$p->[$MEDIUM]}{descr});
						my $fd = install_any::getFile($f);
						$fd ? fileno $fd : -1;
					    }, callback_close => sub {
						my ($data, $type, $id) = @_;
						my $pkg = defined $id && $data->{depslist}[$id] or return;
						my $check_installed;
						$db->traverse_tag('name', [ $pkg->name ], sub {
								      my ($p) = @_;
								      $check_installed ||= $pkg->compare_pkg($p) == 0;
								  });
						$check_installed and print OUTPUT "close:$id\n";
					    }, callback_inst => sub {
						my ($data, $type, $id, $subtype, $amount, $total) = @_;
						print OUTPUT "$type:$id:$subtype:$amount:$total\n";
					    });
		    log::l("transactions done, now trying to close still opened fd");
		    install_any::getFile('XXX'); #- close still opened fd.

		    @probs and die "installation of rpms failed:\n  ", join("\n  ", @probs);
		}; $@ and print OUTPUT "die:$@\n";
		close OUTPUT;

		#- now search for child process which may be locking the cdrom, making it unable to be ejected.
		my @allpids = grep { /^\d+$/ } all("/proc");
		my %ppids;
		foreach (@allpids) {
		    cat_("/proc/$_/status") =~ /^PPid:\s+(\d+)/m;
		    push @{$ppids{$1 || 1}}, $_;
		}
		my @killpid = difference2(\@allpids, [ @prev_pids, 
						       difference2([ $$, hashtree2list(getppid, \%ppids) ],
								   [ hashtree2list($$, \%ppids) ]) ]);
	
		if (@killpid) {
		    foreach (@killpid) {
			my $s = "$_: " . join(' ', split("\0", cat_("/proc/$_/cmdline")));
			log::l("ERROR: DrakX should not have to clean the packages shit. Killing $s");
		    }
		    kill 15, @killpid;
		    sleep 2;
		    kill 9, @killpid;
		}

		c::_exit(0);
	    }

	    #- if we are using a retry mode, this means we have to split the transaction with only
	    #- one package for each real transaction.
	    unless ($retry_pkg) {
		my @badPackages;
		foreach (@transToInstall) {
		    if (!$_->flag_installed && packageMedium($packages, $_)->{selected} && !exists($ignoreBadPkg{$_->name})) {
			push @badPackages, $_;
			log::l("bad package ".$_->fullname);
		    } else {
			$_->free_header;
		    }
		}
		@transToInstall = @badPackages;
		#- if we are in retry mode, we have to fetch only one package at a time.
		$retry_pkg = shift @transToInstall;
		$retry_count = 3;
	    } else {
		if (!$retry_pkg->flag_installed && packageMedium($packages, $retry_pkg)->{selected} && !exists($ignoreBadPkg{$retry_pkg->name})) {
		    if ($retry_count) {
			log::l("retrying installing package ".$retry_pkg->fullname." alone in a transaction");
			--$retry_count;
		    } else {
			log::l("bad package ". $retry_pkg->fullname ." unable to be installed");
			$retry_pkg->set_flag_requested(0);
			$retry_pkg->set_flag_required(0);
			cdie ("error installing package list: ". $retry_pkg->fullname);
		    }
		}
		if ($retry_pkg->flag_installed || !$retry_pkg->flag_selected) {
		    $retry_pkg->free_header;
		    $retry_pkg = shift @transToInstall;
		    $retry_count = 3;
		}
	    }
	}
	cleanHeaders($prefix);
    } while ($nb > 0 && !$pkgs::cancel_install);

    closeInstallLog();

    cleanHeaders($prefix);

    loopback::save_boot($loop_boot);
}

sub remove($$) {
    my ($prefix, $toRemove) = @_;

    return if $::g_auto_install || !@{$toRemove || []};

    my $db = URPM::DB::open($prefix, 1) or die "error opening RPM database: ", c::rpmErrorString();
    my $trans = $db->create_transaction($prefix);

    foreach my $p (@$toRemove) {
	#- stuff remove all packages that matches $p, not a problem since $p has name-version-release format.
	$trans->remove($p) if allowedToUpgrade($p);
    }

    eval { fs::mount("/proc", "$prefix/proc", "proc", 0) } unless -e "$prefix/proc/cpuinfo";

    my $callbackOpen = sub { log::l("trying to open file from $_[0] which should not happen"); };
    my $callbackClose = sub { log::l("trying to close file from $_[0] which should not happen"); };

    #- we are not checking depends since it should come when
    #- upgrading a system. although we may remove some functionalities ?

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install_steps_gtk.pm,...).
    installCallback($db, 'user', undef, 'remove', scalar @$toRemove);

    if (my @probs = $trans->run(undef, force => 1)) {
	die "removing of old rpms failed:\n  ", join("\n  ", @probs);
    }

    #- keep in mind removing of these packages by cleaning $toRemove.
    @{$toRemove || []} = ();
}

sub selected_leaves {
    my ($packages) = @_;
    my @leaves;

    foreach (@{$packages->{depslist}}) {
	$_->flag_requested && !$_->flag_base and push @leaves, $_->name;
    }
#    my %l;
#
#    #- initialize l with all id, not couting base package.
#    foreach my $id (0 .. $#{$packages->{depslist}}) {
#	my $pkg = packageById($packages, $id) or next;
#	packageSelectedOrInstalled($pkg) && !$pkg->flag_base or next;
#	$l{$id} = 1;
#    }
#
#    foreach my $id (keys %l) {
#	#- when a package is in a choice, increase its value in hash l, because
#	#- it has to be examined before when we will select them later.
#	#- NB: this number may be computed before to save time.
#	my $p = $packages->{depslist}[$id] or next;
#	foreach (packageDepsId($p)) {
#	    if (/\|/) {
#		foreach (split '\|') {
#		    exists $l{$_} or next;
#		    $l{$_} > 1 + $l{$id} or $l{$_} = 1 + $l{$id};
#		}
#	    }
#	}
#    }
#
#    #- at this level, we can remove selected packages that are already
#    #- required by other, but we have to sort according to choice usage.
#    foreach my $id (sort { $l{$b} <=> $l{$a} || $b <=> $a } keys %l) {
#	#- do not count already deleted id, else cycles will be removed.
#	$l{$id} or next;
#
#	my $p = $packages->{depslist}[$id] or next;
#	foreach (packageDepsId($p)) {
#	    #- choices need no more to be examined, this has been done above.
#	    /\|/ and next;
#	    #- improve value of this one, so it will be selected before.
#	    $l{$id} < $l{$_} and $l{$id} = $l{$_};
#	    $l{$_} = 0;
#	}
#    }
#
#    #- now sort again according to decrementing value, and gives packages name.
#    [ map { packageName($packages->{depslist}[$_]) } sort { $l{$b} <=> $l{$a} } grep { $l{$_} > 0 } keys %l ];
    \@leaves;
}


sub naughtyServers {
    my ($packages) = @_;

    my @old_81 = qw(
freeswan
);
    my @old_82 = qw(
vnc-server
postgresql-server
mon
);

    my @new_80 = qw(
jabber
FreeWnn
MySQL
am-utils
apache
boa
cfengine
cups
drakxtools-http
finger-server
imap
leafnode
lpr
ntp
openssh-server
pidentd
postfix
proftpd
rwall
rwho
squid
webmin
wu-ftpd
ypbind
); # nfs-utils-clients portmap
   # X server

    my @new_81 = qw(
apache-mod_perl
ftp-server-krb5
mcserv
samba
telnet-server-krb5
ypserv
);

    my @new_82 = qw(
LPRng
bind
httpd-naat
ibod
inn
netatalk
nfs-utils
rusers-server
samba-swat
tftp-server
ucd-snmp
);

    my @naughtyServers = (@new_80, @new_81, @new_82);

    grep {
	my $p = packageByName($packages, $_);
	$p && $p->flag_selected;
    } @naughtyServers;
}

sub hashtree2list {
    my ($e, $h) = @_;
    my @l;
    my @todo = $e;
    while (@todo) {
	my $e = shift @todo;
	push @l, $e;
	push @todo, @{$h->{$e}};
    }
    @l;
}

1;
