package Xconfigurator;

use diagnostics;
use strict;
use vars qw($in $install $isLaptop @window_managers @depths @monitorSize2resolution @hsyncranges %min_hsync4wres @vsyncranges %depths @resolutions %serversdriver @svgaservers @accelservers @allbutfbservers @allservers %vgamodes %videomemory @ramdac_name @ramdac_id @clockchip_name @clockchip_id %keymap_translate %standard_monitors $XF86firstchunk_text $XF86firstchunk_text2 $keyboardsection_start $keyboardsection_start_v4 $keyboardsection_part2 $keyboardsection_part3 $keyboardsection_part3_v4 $keyboardsection_end $pointersection_text $pointersection_text_v4 $monitorsection_text1 $monitorsection_text2 $monitorsection_text3 $monitorsection_text4 $modelines_text_Trident_TG_96xx $modelines_text $devicesection_text $devicesection_text_v4 $screensection_text1 %lines @options %xkb_options $default_monitor $layoutsection_v4);

use common qw(:common :file :functional :system);
use log;
use detect_devices;
use run_program;
use Xconfigurator_consts;
use any;
use modules;
use my_gtk qw(:wrappers);

my $tmpconfig = "/tmp/Xconfig";

my ($prefix, %monitors);

1;

sub getVGAMode($) { $_[0]->{card}{vga_mode} || $vgamodes{"640x480x16"}; }

sub readCardsDB {
    my ($file) = @_;
    my ($card, %cards);

    local *F;
    open F, $file or die "file $file not found";

    my ($lineno, $cmd, $val) = 0;
    my $fs = {
        LINE => sub { push @{$card->{lines}}, $val unless $val eq "VideoRam" },
	NAME => sub {
	    $cards{$card->{type}} = $card if $card;
	    $card = { type => $val };
	},
	SEE => sub {
	    my $c = $cards{$val} or die "Error in database, invalid reference $val at line $lineno";

	    push @{$card->{lines}}, @{$c->{lines} || []};
	    add2hash($card->{flags}, $c->{flags});
	    add2hash($card, $c);
	},
	CHIPSET => sub {
	    $card->{chipset} = $val;
	    $card->{flags}{needChipset} = 1 if $val eq 'GeForce DDR';
	    $card->{flags}{needVideoRam} = 1 if member($val, qw(mgag10 mgag200 RIVA128 SiS6326));
	},
	SERVER => sub { $card->{server} = $val; },
	DRIVER => sub { $card->{driver} = $val; },
	RAMDAC => sub { $card->{ramdac} = $val; },
	DACSPEED => sub { $card->{dacspeed} = $val; },
	CLOCKCHIP => sub { $card->{clockchip} = $val; $card->{flags}{noclockprobe} = 1; },
	NOCLOCKPROBE => sub { $card->{flags}{noclockprobe} = 1 },
	UNSUPPORTED => sub { $card->{flags}{unsupported} = 1 },
	COMMENT => sub {},
    };

    foreach (<F>) { $lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;
	/^END/ and last;

	($cmd, $val) = /(\S+)\s*(.*)/ or next; #log::l("bad line $lineno ($_)"), next;

	my $f = $fs->{$cmd};

	$f ? &$f() : log::l("unknown line $lineno ($_)");
    }
    \%cards;
}
sub readCardsNames {
    my $file = "/usr/X11R6/lib/X11/CardsNames";
    local *F; open F, $file or die "can't find $file\n";
    map { (split '=>')[0] } <F>;
}
sub cardName2RealName {
    my $file = "/usr/X11R6/lib/X11/CardsNames";
    my ($name) = @_;
    local *F; open F, $file or die "can't find $file\n";
    foreach (<F>) { chop;
	my ($name_, $real) = split '=>';
	return $real if $name eq $name_;
    }
    $name;
}
sub updateCardAccordingName {
    my ($card, $name) = @_;
    my $cards = readCardsDB("/usr/X11R6/lib/X11/Cards+");

    add2hash($card->{flags}, $cards->{$name}{flags});
    add2hash($card, $cards->{$name});
    $card;
}

sub readMonitorsDB {
    my ($file) = @_;

    %monitors and return;

    local *F;
    open F, $file or die "can't open monitors database ($file): $!";
    my $lineno = 0; foreach (<F>) {
	$lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;

	my @fields = qw(vendor type eisa hsyncrange vsyncrange);
	my @l = split /\s*;\s*/;
	@l == @fields or log::l("bad line $lineno ($_)"), next;

	my %l; @l{@fields} = @l;
	if ($monitors{$l{type}}) {
	    my $i; for ($i = 0; $monitors{"$l{type} ($i)"}; $i++) {}
	    $l{type} = "$l{type} ($i)";
	}
	$monitors{"$l{vendor}|$l{type}"} = \%l;
    }
    while (my ($k, $v) = each %standard_monitors) {
	$monitors{_("Generic") . "|" . translate($k)} =
	    { hsyncrange => $v->[1], vsyncrange => $v->[2] };
    }
}

sub rewriteInittab {
    my ($runlevel) = @_;
    my $f = "$prefix/etc/inittab";
    -r $f or log::l("missing inittab!!!"), return;
    substInFile { s/^(id:)[35](:initdefault:)\s*$/$1$runlevel$2\n/ } $f;
}

sub keepOnlyLegalModes {
    my ($card, $monitor) = @_;
    my $mem = 1024 * ($card->{memory} || ($card->{server} eq 'FBDev' ? 2048 : 99999));
    my $hsync = max(split(/[,-]/, $monitor->{hsyncrange}));

    while (my ($depth, $res) = each %{$card->{depth}}) {
	@$res = grep {
	    $mem >= product(@$_, $depth / 8) &&
	    $hsync >= ($min_hsync4wres{$_->[0]} || 0) &&
	    ($card->{server} ne 'FBDev' || $vgamodes{"$_->[0]x$_->[1]x$depth"})
	} @$res;
	delete $card->{depth}{$depth} if @$res == 0;
    }
}

sub cardConfigurationAuto() {
    my $card;
    if (my ($c) = grep { $_->{driver} =~ /(Card|Server):/ } detect_devices::probeall()) {
	local $_ = $c->{driver};
	$card->{type} = $1 if /Card:(.*)/;
	$card->{server} = $1 if /Server:(.*)/;
	$card->{flags}{needVideoRam} &&= /86c368/;
	$card->{identifier} = $c->{description};
	push @{$card->{lines}}, @{$lines{$card->{identifier}} || []};
    }
    #- take a default on sparc if nothing has been found.
    if (arch() =~ /^sparc/ && !$card->{server} && !$card->{type}) {
        log::l("Using probe with /proc/fb as nothing has been found!");
	local $_ = cat_("/proc/fb");
	if (/Mach64/) { $card->{server} = "Mach64" }
	elsif (/Permedia2/) { $card->{server} = "3DLabs" }
	else { $card->{server} = "Sun24" }
    }
    $card;
}

sub cardConfiguration(;$$$) {
    my ($card, $noauto, $allowFB) = @_;
    $card ||= {};

    updateCardAccordingName($card, $card->{type}) if $card->{type}; #- try to get info from given type
    undef $card->{type} unless $card->{server}; #- bad type as we can't find the server
    add2hash($card, cardConfigurationAuto()) unless $card->{server} || $noauto;
    $card->{server} = 'FBDev' unless !$allowFB || $card->{server} || $card->{type} || $noauto;
    $card->{type} = cardName2RealName($in->ask_from_treelist(_("Graphic card"), _("Select a graphic card"), '|', ['Unlisted', readCardsNames()])) unless $card->{type} || $card->{server};
    undef $card->{type}, $card->{server} = $in->ask_from_list(_("X server"), _("Choose a X server"), $allowFB ? \@allservers : \@allbutfbservers ) if $card->{type} eq "Unlisted";

    updateCardAccordingName($card, $card->{type}) if $card->{type};
    add2hash($card, { vendor => "Unknown", board => "Unknown" });

    #- 3D acceleration configuration for XFree 3.3 using Utah-GLX.
    $card->{Utah_glx} = ($card->{identifier} =~ /Matrox.* G[24]00/ || #- 8bpp does not work.
			 $card->{identifier} =~ /3D Rage Pro AGP/ || #- by default only such card are supported, with AGP ?
			 $card->{type} =~ /Intel 810/);
    #- 3D acceleration configuration for XFree 3.3 using Utah-GLX but EXPERIMENTAL that may freeze the machine (FOR INFO NOT USED).
    $card->{Utah_glx_EXPERIMENTAL} = ($card->{type} =~ /RIVA TNT/ || #- all RIVA/GeForce comes from NVIDIA and may freeze (gltron).
				      $card->{type} =~ /RIVA128/ ||
				      $card->{type} =~ /GeForce 256/ ||
				      $card->{type} =~ /S3 Savage3D/ || #- only this one is evoluting (expect a stable release ?)
				      #- $card->{type} =~ /S3 ViRGE/ || #- 15bits only
				      $card->{type} =~ /SiS /);
    #- 3D acceleration configuration for XFree 4.0 using DRI.
    $card->{DRI_glx} = ($card->{identifier} =~ /Voodoo [35]/ || #- 16bit only #- NOT YET $card->{identifier} =~ /Voodoo Banshee/ ||
			#- NOT WORKING $card->{identifier} =~ /Matrox.* G[24]00/ || #- prefer 16bit (24bit not well tested according to DRI)
			$card->{type} =~ /Intel 810/ || #- 16bit
			$card->{type} =~ /ATI Rage 128/); #- 16 and 32 bits, prefer 16bit as no DMA.

    #- check to use XFree 4.0 or XFree 3.3.
    $card->{use_xf4} = $card->{driver} && !$card->{flags}{unsupported};

    #- basic installation, use of XFree 4.0 or XFree 3.3.
    my ($xf4_ver, $xf3_ver) = ("4.0.1", "3.3.6");
    my $xf3_tc = { text => _("XFree %s", $xf3_ver),
		   code => sub { $card->{Utah_glx} = $card->{DRI_glx} = ''; $card->{use_xf4} = '' } };
    my $msg = _("Which configuration of XFree do you want to have?");
    my @choices = $card->{use_xf4} ? ({ text => _("XFree %s", $xf4_ver),
					code => sub { $card->{Utah_glx} = $card->{DRI_glx} = '' } },
					  ($::expert ? ($xf3_tc) : ())) : ($xf3_tc);

    #- try to figure if 3D acceleration is supported
    #- by XFree 3.3 but not XFree 4.0 then ask user to keep XFree 3.3 ?
    if ($card->{Utah_glx}) {
	$msg = ($card->{use_xf4} && !$card->{DRI_glx} ?
_("Your card can have 3D hardware acceleration support but only with XFree %s.
Your card is supported by XFree %s which may have a better support in 2D.", $xf3_ver, $xf4_ver) :
_("Your card can have 3D hardware acceleration support with XFree %s.", $xf3_ver)) . "\n\n" . $msg;
	$::beginner and @choices = (); #- keep it by default here as it is the only choice available.
	unshift @choices, { text => _("XFree %s with 3D hardware acceleration", $xf3_ver),
			    code => sub { $card->{use_xf4} = '' } };
    }

    #- an expert user may want to try to use an EXPERIMENTAL 3D acceleration, currenlty
    #- this is with Utah GLX and so, it can provide a way of testing.
    if ($::expert && $card->{Utah_glx_EXPERIMENTAL}) {
	$msg = ($card->{use_xf4} && !$card->{DRI_glx} ?
_("Your card can have 3D hardware acceleration support but only with XFree %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.
Your card is supported by XFree %s which may have a better support in 2D.", $xf3_ver, $xf4_ver) :
_("Your card can have 3D hardware acceleration support with XFree %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.", $xf3_ver)) . "\n\n" . $msg;
	push @choices, { text => _("XFree %s with EXPERIMENTAL 3D hardware acceleration", $xf3_ver),
			 code => sub { $card->{use_xf4} = ''; $card->{Utah_glx} = 'EXPERIMENTAL' } };
    }

    #- ask the expert user to enable or not hardware acceleration support.
    if ($card->{use_xf4} && $card->{DRI_glx}) {
	$msg = _("Your card can have 3D hardware acceleration support with XFree %s.", $xf4_ver) . "\n\n" . $msg;
	$::expert or @choices = (); #- keep all user by default with XFree 4.0 including 3D acceleration.
	unshift @choices, { text => _("XFree %s with 3D hardware acceleration", $xf4_ver) };
    }

    #- examine choice of user, beware the list MUST NOT BE REORDERED AS THERE ARE FALL TRHOUGH!
    my $tc = $in->ask_from_listf(_("XFree configuration"), $msg, sub { translate($_[0]{text}) }, \@choices);
    $tc->{code} and $tc->{code}();

    $card->{prog} = "/usr/X11R6/bin/" . ($card->{use_xf4} ? 'XFree86' : $card->{server} =~ /Sun (.*)/x ?
					 "Xsun$1" : "XF86_$card->{server}");

    #- additional packages to install according available card.
    #- add XFree86-libs-DRI here if using DRI (future split of XFree86 TODO)
    my @l = ();
    if ($card->{DRI_glx}) {
	push @l, 'Glide_V5' if $card->{identifier} =~ /Voodoo 5/;
	push @l, 'Glide_V3-DRI' if $card->{identifier} =~ /Voodoo 3/;
	push @l, 'Device3Dfx', 'XFree86-glide-module' if $card->{identifier} =~ /Voodoo/;
    }
    if ($card->{Utah_glx}) {
	push @l, 'Mesa' if !$card->{use_xf4};
    }

    -x "$prefix$card->{prog}" or $install && do {
	$in->suspend if ref($in) =~ /newt/;
	&$install('server', @l) if $card->{use_xf4};
	&$install($card->{server}, @l) if !$card->{use_xf4};
	$in->resume if ref($in) =~ /newt/;
    };
    -x "$prefix$card->{prog}" or die "server $card->{server} is not available (should be in $prefix$card->{prog})";

    unless ($card->{type}) {
	$card->{flags}{noclockprobe} = member($card->{server}, qw(I128 S3 S3V Mach64));
    }
    $card->{options_xf3}{power_saver} = 1;
    $card->{options_xf4}{DPMS} = 1;

    $card->{flags}{needVideoRam} and
      $card->{memory} ||=
	$videomemory{$in->ask_from_list_('',
					 _("Select the memory size of your graphic card"),
					 [ sort { $videomemory{$a} <=> $videomemory{$b} }
					   keys %videomemory])};


    #- hack for ATI Mach64 card where two options should be used if using Utah-GLX.
    if ($card->{type} =~ /ATI Mach64/) {
	$card->{options_xf3}{no_font_cache} = $card->{Utah_glx};
	$card->{options_xf3}{no_pixmap_cache} = $card->{Utah_glx};
    }

    #- 3D acceleration configuration for XFree 4.0 using DRI, this is enabled by default
    #- but for some there is a need to specify VideoRam (else it won't run).
    if ($card->{DRI_glx}) {
	$card->{identifier} =~ /Matrox.* G[24]00/ and $card->{flags}{needVideoRam} = 'fakeVideoRam';
	$card->{type} =~ /Intel 810/ and ($card->{flags}{needVideoRam}, $card->{memory}) = ('fakeVideoRam', 10000);
    }

    if (!$::isStandalone && $card->{driver} eq "i810") {
	require modules;
	eval { modules::load("agpgart"); };
    }
    $card;
}

sub optionsConfiguration($) {
    my ($o) = @_;
    my @l;
    my %l;

    foreach (@options) {
	if ($o->{card}{server} eq $_->[1] && $o->{card}{identifier} =~ /$_->[2]/) {
	    my $options = 'options_' . ($o->{card}{server} eq 'XFree86' ? 'xf4' : 'xf3');
	    $o->{card}{$options}{$_->[0]} ||= 0;
	    unless ($l{$_->[0]}) {
		push @l, $_->[0], { val => \$o->{card}{$options}{$_->[0]}, type => 'bool' };
		$l{$_->[0]} = 1;
	    }
	}
    }
    @l = @l[0..19] if @l > 19; #- reduce list size to 10 for display (it's a hash).

    $in->ask_from_entries_refH('', _("Choose options for server"), \@l);
}

sub monitorConfiguration(;$$) {
    my $monitor = shift || {};
    my $useFB = shift || 0;

    $monitor->{hsyncrange} && $monitor->{vsyncrange} and return $monitor;

    readMonitorsDB("/usr/X11R6/lib/X11/MonitorsDB");

    add2hash($monitor, { type => $in->ask_from_treelist(_("Monitor"), _("Choose a monitor"), '|', ['Unlisted', keys %monitors], _("Generic") . '|' . translate($default_monitor)) }) unless $monitor->{type};
    if ($monitor->{type} eq 'Unlisted') {
	$in->ask_from_entries_ref('',
_("The two critical parameters are the vertical refresh rate, which is the rate
at which the whole screen is refreshed, and most importantly the horizontal
sync rate, which is the rate at which scanlines are displayed.

It is VERY IMPORTANT that you do not specify a monitor type with a sync range
that is beyond the capabilities of your monitor: you may damage your monitor.
 If in doubt, choose a conservative setting."),
				  [ _("Horizontal refresh rate"), _("Vertical refresh rate") ],
				  [ { val => \$monitor->{hsyncrange}, list => \@hsyncranges },
				    { val => \$monitor->{vsyncrange}, list => \@vsyncranges }, ]);
    } else {
	add2hash($monitor, $monitors{$monitor->{type}});
    }
    add2hash($monitor, { type => "Unknown", vendor => "Unknown", model => "Unknown", manual => 1 });
}

sub testConfig($) {
    my ($o) = @_;
    my ($resolutions, $clocklines);

    write_XF86Config($o, $tmpconfig);

    unlink "/tmp/.X9-lock";
    #- restart_xfs;

    my $f = $tmpconfig . ($o->{card}{use_xf4} && "-4");
    local *F;
    open F, "$prefix$o->{card}{prog} :9 -probeonly -pn -xf86config $f 2>&1 |";
    foreach (<F>) {
	$o->{card}{memory} ||= $2 if /(videoram|Video RAM):\s*(\d*)/;

	# look for clocks
	push @$clocklines, $1 if /clocks: (.*)/ && !/(pixel |num)clocks:/;

	push @$resolutions, [ $1, $2 ] if /: Mode "(\d+)x(\d+)": mode clock/;
	print;
    }
    close F or die "X probeonly failed";

    ($resolutions, $clocklines);
}

sub testFinalConfig($;$$) {
    my ($o, $auto, $skiptest) = @_;

    $o->{monitor}{hsyncrange} && $o->{monitor}{vsyncrange} or
      $in->ask_warn('', _("Monitor not configured")), return;

    $o->{card}{server} or
      $in->ask_warn('', _("Graphic card not configured yet")), return;

    $o->{card}{depth} or
      $in->ask_warn('', _("Resolutions not chosen yet")), return;

    my $f = "/etc/X11/XF86Config.test";
    write_XF86Config($o, $::testing ? $tmpconfig : "$prefix/$f");

    $skiptest || $o->{card}{server} =~ 'FBDev|Sun' and return 1; #- avoid testing with these.

    #- needed for bad cards not restoring cleanly framebuffer
    my $bad_card = $o->{card}{identifier} =~ /i740|ViRGE/;
    $bad_card ||= $o->{card}{identifier} eq "ATI|3D Rage P/M Mobility AGP 2x";
    $bad_card ||= $o->{card}{use_xf4}; #- TODO obsoleted to check, when using fbdev of XFree 4.0!
    log::l("the graphic card does not like X in framebuffer") if $bad_card;

    my $mesg = _("Do you want to test the configuration?");
    my $def = 1;
    if ($bad_card && !$::isStandalone) {
	!$::expert || $auto and return 1;
	$mesg = $mesg . "\n" . _("Warning: testing is dangerous on this graphic card");
	$def = 0;
    }
    $auto && $def or $in->ask_yesorno(_("Test of the configuration"), $mesg, $def) or return 1;

    unlink "$prefix/tmp/.X9-lock";

    #- create a link from the non-prefixed /tmp/.X11-unix/X9 to the prefixed one
    #- that way, you can talk to :9 without doing a chroot
    #- but take care of non X11 install :-)
    if (-d "/tmp/.X11-unix") {
	symlinkf "$prefix/tmp/.X11-unix/X9", "/tmp/.X11-unix/X9" if $prefix;
    } else {
	symlinkf "$prefix/tmp/.X11-unix", "/tmp/.X11-unix" if $prefix;
    }
    #- restart_xfs;

    my $f_err = "$prefix/tmp/Xoutput";
    my $pid;
    unless ($pid = fork) {
	open STDERR, ">$f_err";
	chroot $prefix if $prefix;
	exec $o->{card}{prog}, 
	  ($o->{card}{prog} !~ /Xsun/ ? ("-xf86config", ($::testing ? $tmpconfig : $f) . ($o->{card}{use_xf4} && "-4")) : ()),
	  ":9" or c::_exit(0);
    }

    do { sleep 1 } until c::Xtest(":9") || waitpid($pid, c::WNOHANG());

    my $b = before_leaving { unlink $f_err };

    unless (c::Xtest(":9")) {
	local $_;
	local *F; open F, $f_err;
      i: while (<F>) {
	    if (/\b(error|not supported)\b/i) {
		my @msg = !/error/ && $_ ;
		while (<F>) {
		    /not fatal/ and last i;
		    /^$/ and last;
		    push @msg, $_;
		}
		$in->ask_warn('', [ _("An error has occurred:"), " ", @msg, _("\ntry to change some parameters") ]);
		return 0;
	    }
	}
    }

    local *F;
    open F, "|perl" or die '';
    print F "use lib qw(", join(' ', @INC), ");\n";
    print F q{
	use interactive_gtk;
        use my_gtk qw(:wrappers);

	$ENV{DISPLAY} = ":9";

        gtkset_mousecursor_normal();
        gtkset_background(200 * 257, 210 * 257, 210 * 257);
        my ($h, $w) = Gtk::Gdk::Window->new_foreign(Gtk::Gdk->ROOT_WINDOW)->get_size;
        $my_gtk::force_position = [ $w / 3, $h / 2.4 ];
	$my_gtk::force_focus = 1;
        my $text = Gtk::Label->new;
        my $time = 8;
        Gtk->timeout_add(1000, sub {
	    $text->set(_("Leaving in %d seconds", $time));
	    $time-- or Gtk->main_quit;
	});

	exit (interactive_gtk->new->ask_yesorno('', [ _("Is this the correct setting?"), $text ], 0) ? 0 : 222);
    };
    my $rc = close F;
    my $err = $?;

    unlink "/tmp/.X11-unix/X9" if $prefix;
    kill 2, $pid;

    $rc || $err == 222 << 8 or $in->ask_warn('', _("An error has occurred, try to change some parameters"));
    $rc;
}

sub autoResolutions($;$) {
    my ($o, $nowarning) = @_;
    my $card = $o->{card};

    $nowarning || $in->ask_okcancel(_("Automatic resolutions"),
_("To find the available resolutions I will try different ones.
Your screen will blink...
You can switch if off if you want, you'll hear a beep when it's over"), 1) or return;

    #- swith to virtual console 1 (hopefully not X :)
    my $vt = setVirtual(1);

    #- Configure the modes order.
    my ($ok, $best);
    foreach (reverse @depths) {
	local $o->{default_depth} = $_;

	my ($resolutions, $clocklines) = eval { testConfig($o) };
	if ($@ || !$resolutions) {
	    delete $card->{depth}{$_};
	} else {
	    $card->{clocklines} ||= $clocklines unless $card->{flags}{noclockprobe};
	    $card->{depth}{$_} = [ @$resolutions ];
	}
    }

    #- restore the virtual console
    setVirtual($vt);
    local $| = 1; print "\a"; #- beeeep!
}

sub autoDefaultDepth($$) {
    my ($card, $wres_wanted) = @_;
    my ($best, $depth);

    return 24 if $card->{identifier} =~ /SiS/; #- assume 24 bit even for 3D acceleration (not enabled currently).
    return 16 if $card->{Utah_glx} || $card->{DRI_glx}; #- assume 16bit as most of them need 16.
    
    for ($card->{server}) {
	/FBDev/   and return 16; #- this should work by default, FBDev is allowed only if install currently uses it at 16bpp.
	/Sun24/   and return 24;
	/SunMono/ and return 2;
	/Sun/     and return 8;
    }

    while (my ($d, $r) = each %{$card->{depth}}) {
	$depth = max($depth || 0, $d);

	#- try to have resolution_wanted
	$best = max($best || 0, $d) if $r->[0][0] >= $wres_wanted;
    }
    $best || $depth or die "no valid modes";
}

sub autoDefaultResolution {
    return "1024x768" if $isLaptop;

    my ($size) = @_;
    $monitorSize2resolution[round($size || 14)] || #- assume a small monitor (size is in inch)
      $monitorSize2resolution[-1]; #- no corresponding resolution for this size. It means a big monitor, take biggest we have
}

sub chooseResolutionsGtk($$;$) {
    my ($card, $chosen_depth, $chosen_w) = @_;
    my $W = my_gtk->new(_("Resolution"));
    my %txt2depth = reverse %depths;
    my ($r, $depth_combo, %w2depth, %w2h, %w2widget);

    my $best_w;
    while (my ($depth, $res) = each %{$card->{depth}}) {
	foreach (@$res) {
	    $w2h{$_->[0]} = $_->[1];
	    push @{$w2depth{$_->[0]}}, $depth;

	    $best_w = max($_->[0], $best_w) if $_->[0] <= $chosen_w;
	}
    }
    $chosen_w = $best_w;

    my $set_depth = sub { $depth_combo->entry->set_text(translate($depths{$chosen_depth})) };

    #- the set function is usefull to toggle the CheckButton with the callback being ignored
    my $ignore;
    my $set = sub { $ignore = 1; $_[0]->set_active(1); $ignore = 0; };

    while (my ($w, $h) = each %w2h) {
	my $V = $w . "x" . $h;
	$w2widget{$w} = $r = new Gtk::RadioButton($r ? ($V, $r) : $V);
	&$set($r) if $chosen_w == $w;
	$r->signal_connect("clicked" => sub {
			       $ignore and return;
			       $chosen_w = $w;
			       unless (member($chosen_depth, @{$w2depth{$w}})) {
				   $chosen_depth = max(@{$w2depth{$w}});
				   &$set_depth();
			       }
			   });
    }
    gtkadd($W->{window},
	   gtkpack_($W->create_box_with_title(_("Choose the resolution and the color depth"),
					      "(" . ($card->{type} ? 
						     _("Graphic card: %s", $card->{type}) :
						     _("XFree86 server: %s", $card->{server})) . ")"
					     ),
		    1, gtkpack(new Gtk::HBox(0,20),
			       $depth_combo = new Gtk::Combo,
			       gtkpack_(new Gtk::VBox(0,0),
					map {; 0, $w2widget{$_} } ikeys(%w2widget),
					),
			       ),
		    0, gtkadd($W->create_okcancel,
			      gtksignal_connect(new Gtk::Button(_("Show all")), clicked => sub { $W->{retval} = 1; $chosen_w = 0; Gtk->main_quit })),
		    ));
    $depth_combo->disable_activate;
    $depth_combo->set_use_arrows_always(1);
    $depth_combo->entry->set_editable(0);
    $depth_combo->set_popdown_strings(map { translate($depths{$_}) } ikeys(%{$card->{depth}}));
    $depth_combo->entry->signal_connect(changed => sub {
       $chosen_depth = $txt2depth{untranslate($depth_combo->entry->get_text, keys %txt2depth)};
       my $w = $card->{depth}{$chosen_depth}[0][0];
       $chosen_w > $w and &$set($w2widget{$chosen_w = $w});
    });
    &$set_depth();
    $W->{ok}->grab_focus;

    $W->main or return;
    ($chosen_depth, $chosen_w);
}

sub chooseResolutions($$;$) {
    goto &chooseResolutionsGtk if ref($in) =~ /gtk/;

    my ($card, $chosen_depth, $chosen_w) = @_;

    my $best_w;
    local $_ = $in->ask_from_list(_("Resolutions"), "", 
				  [ map_each { map { "$_->[0]x$_->[1] ${main::a}bpp" } @$::b } %{$card->{depth}} ]) or return;
    reverse /(\d+)x\S+ (\d+)/;
}


sub resolutionsConfiguration($%) {
    my ($o, %options) = @_;
    my $card = $o->{card};

    #- For the mono and vga16 server, no further configuration is required.
    if (member($card->{server}, "Mono", "VGA16")) {
	$card->{depth}{8} = [[ 640, 480 ]];
	return;
    } elsif ($card->{server} =~ /Sun/) {
	$card->{depth}{2} = [[ 1152, 864 ]] if $card->{server} =~ /^(SunMono)$/;
	$card->{depth}{8} = [[ 1152, 864 ]] if $card->{server} =~ /^(SunMono|Sun)$/;
	$card->{depth}{24} = [[ 1152, 864 ]] if $card->{server} =~ /^(SunMono|Sun|Sun24)$/;
	$card->{default_wres} = 1152;
	$o->{default_depth} = max(keys %{$card->{depth}});
	return 1; #- aka we cannot test, assumed as good (should be).
    }

    #- some of these guys hate to be poked
    #- if we dont know then its at the user's discretion
    #-my $manual ||=
    #-	$card->{server} =~ /^(TGA|Mach32)/ ||
    #-	$card->{name} =~ /^Riva 128/ ||
    #-	$card->{chipset} =~ /^(RIVA128|mgag)/ ||
    #-	$::expert;
    #-
    #-my $unknown =
    #-	member($card->{server}, qw(S3 S3V I128 Mach64)) ||
    #-	member($card->{type},
    #-	       "Matrox Millennium (MGA)",
    #-	       "Matrox Millennium II",
    #-	       "Matrox Millennium II AGP",
    #-	       "Matrox Mystique",
    #-	       "Matrox Mystique",
    #-	       "S3",
    #-	       "S3V",
    #-	       "I128",
    #-	      ) ||
    #-	$card->{type} =~ /S3 ViRGE/;
    #-
    #-$unknown and $manual ||= !$in->ask_okcancel('', [ _("I can try to autodetect information about graphic card, but it may freeze :("),
    #-							_("Do you want to try?") ]);

    if (is_empty_hash_ref($card->{depth})) {
	$card->{depth}{$_} = [ map { [ split "x" ] } @resolutions ]
	  foreach @depths;

	unless ($options{noauto}) {
	    if ($options{nowarning} || $in->ask_okcancel(_("Automatic resolutions"),
_("I can try to find the available resolutions (eg: 800x600).
Sometimes, though, it may hang the machine.
Do you want to try?"), 1)) {
		autoResolutions($o, $options{nowarning});
		is_empty_hash_ref($card->{depth}) and $in->ask_warn('',
_("No valid modes found
Try with another video card or monitor")), return;
	    }
	}
    }

    #- sort resolutions in each depth
    foreach (values %{$card->{depth}}) {
	my $i = 0;
	@$_ = grep { first($i != $_->[0], $i = $_->[0]) }
	  sort { $b->[0] <=> $a->[0] } @$_;
    }

    #- remove unusable resolutions (based on the video memory size and the monitor hsync rate)
    keepOnlyLegalModes($card, $o->{monitor});

    my $res = $o->{resolution_wanted} || autoDefaultResolution($o->{monitor}{size});
    my $wres = first(split 'x', $res);

    #- take the first available resolution <= the wanted resolution
    $wres ||= max map { first(grep { $_->[0] <= $wres } @$_)->[0] } values %{$card->{depth}};
    my $depth = eval { $o->{default_depth} || autoDefaultDepth($card, $wres) };

    $options{auto} or ($depth, $wres) = chooseResolutions($card, $depth, $wres) or return;

    unless ($wres) {
	delete $card->{depth};
	return resolutionsConfiguration($o, noauto => 1);
    }

    #- needed in auto mode when all has been provided by the user
    $card->{depth}{$depth} or die "you selected an unusable depth";

    #- remove all biggest resolution (keep the small ones for ctl-alt-+)
    #- otherwise there'll be a virtual screen :(
    $card->{depth}{$depth} = [ grep { $_->[0] <= $wres } @{$card->{depth}{$depth}} ];
    $card->{default_wres} = $wres;
    $card->{vga_mode} = $vgamodes{"${wres}xx$depth"} || $vgamodes{"${res}x$depth"}; #- for use with frame buffer.
    $o->{default_depth} = $depth;
    1;
}


#- Create the XF86Config file.
sub write_XF86Config {
    my ($o, $file) = @_;
    my $O;

    local (*F, *G);
    open F, ">$file"   or die "can't write XF86Config in $file: $!";
    open G, ">$file-4" or die "can't write XF86Config in $file-4: $!";

    print F $XF86firstchunk_text, $XF86firstchunk_text2;
    print G $XF86firstchunk_text;
    print G qq(    Option "Pixmap"  "24"\n) if $o->{card}{type} eq "SiS 6326";
    print G $XF86firstchunk_text2;

    #- Write keyboard section.
    $O = $o->{keyboard};
    print F $keyboardsection_start;
    print G $keyboardsection_start_v4;
    print F qq(    XkbDisable\n) unless $O->{xkb_keymap};
    print G qq(    Option "XkbDisable"\n) unless $O->{xkb_keymap};
    print F $keyboardsection_part3;
    print G $keyboardsection_part3_v4;
    print F qq(    XkbLayout       "$O->{xkb_keymap}"\n);
    print G qq(    Option "XkbLayout" "$O->{xkb_keymap}"\n);
    print F join '', map { "    $_\n" } @{$xkb_options{$O->{xkb_keymap}} || []};
    print G join '', map { /(\S+)(.*)/; qq(    Option "$1" $2\n) } @{$xkb_options{$O->{xkb_keymap}} || []};
    print F $keyboardsection_end;
    print G $keyboardsection_end;

    #- Write pointer section.
    $O = $o->{mouse};
    print F $pointersection_text;
    print G $pointersection_text_v4;
    print F qq(    Protocol    "$O->{XMOUSETYPE}"\n);
    print G qq(    Option "Protocol"    "$O->{XMOUSETYPE}"\n);
    print F qq(    Device      "/dev/$O->{device}"\n);
    print G qq(    Option "Device"      "/dev/$O->{device}"\n);
    #- this will enable the "wheel" or "knob" functionality if the mouse supports it
    print F "    ZAxisMapping 4 5\n" if $O->{nbuttons} > 3;
    print F "    ZAxisMapping 6 7\n" if $O->{nbuttons} > 5;
    print G qq(    Option "ZAxisMapping" "4 5"\n) if $O->{nbuttons} > 3;
    print G qq(    Option "ZAxisMapping" "6 7"\n) if $O->{nbuttons} > 5;

    print F "#" unless $O->{XEMU3};
    print G "#" unless $O->{XEMU3};
    print F qq(    Emulate3Buttons\n);
    print G qq(    Option "Emulate3Buttons"\n);
    print F "#" unless $O->{XEMU3};
    print G "#" unless $O->{XEMU3};
    print F qq(    Emulate3Timeout    50\n\n);
    print G qq(    Option "Emulate3Timeout"    "50"\n\n);
    print F "# ChordMiddle is an option for some 3-button Logitech mice\n\n";
    print G "# ChordMiddle is an option for some 3-button Logitech mice\n\n";
    print F "#" unless $O->{chordmiddle};
    print G "#" unless $O->{chordmiddle};
    print F qq(    ChordMiddle\n\n);
    print G qq(    Option "ChordMiddle"\n\n);
    print F "    ClearDTR\n" if $O->{cleardtrrts};
    print F "    ClearRTS\n\n"  if $O->{cleardtrrts};
    print F "EndSection\n\n\n";
    print G "EndSection\n\n\n";

    #- write module section for version 3.
    if ($o->{wacom} || $o->{card}{Utah_glx}) {
	print F qq(Section "Module"
);
	print F qq(    Load "xf86Wacom.so"\n) if $o->{wacom};
	print F qq(    Load "glx-3.so"\n) if $o->{card}{Utah_glx}; #- glx.so may clash with server version 4.
	print F qq(EndSection

);
    }

    #- write wacom device support.
    print F qq(
Section "XInput"
    SubSection "WacomStylus"
        Port "/dev/$o->{wacom}"
        AlwaysCore
    EndSubSection
    SubSection "WacomCursor"
        Port "/dev/$o->{wacom}"
        AlwaysCore
    EndSubSection
    SubSection "WacomEraser"
        Port "/dev/$o->{wacom}"
        AlwaysCore
    EndSubSection
EndSection

) if $o->{wacom};

    print G qq(
Section "InputDevice"
    Identifier	"stylus"
    Driver	"wacom"
    Option	"Type" "stylus"
    Option	"Device" "/dev/$o->{wacom}"
EndSection
Section "InputDevice"
    Identifier	"eraser"
    Driver	"wacom"
    Option	"Type" "eraser"
    Option	"Device" "/dev/$o->{wacom}"
EndSection
Section "InputDevice"
    Identifier	"cursor"
    Driver	"wacom"
    Option	"Type" "cursor"
    Option	"Device" "/dev/$o->{wacom}"
EndSection
) if $o->{wacom};

    #- write modules section for version 4.
    print G qq(
Section "Module"

# This loads the DBE extension module.

    Load	"dbe"
);
    print G qq(
    Load	"glx"
    Load	"dri"
) if $o->{card}{DRI_glx};
    print G qq(

# This loads the miscellaneous extensions module, and disables
# initialisation of the XFree86-DGA extension within that module.

    SubSection	"extmod"
	Option	"omit xfree86-dga"
    EndSubSection

# This loads the Type1 and FreeType font modules

    Load	"type1"
    Load	"freetype"
EndSection
);
    print G qq(

Section "DRI"
    Mode	0666
EndSection
) if $o->{card}{DRI_glx};

    #- Write monitor section.
    $O = $o->{monitor};
    print F $monitorsection_text1;
    print G $monitorsection_text1;
    print F qq(    Identifier "$O->{type}"\n);
    print G qq(    Identifier "$O->{type}"\n);
    print F qq(    VendorName "$O->{vendor}"\n);
    print G qq(    VendorName "$O->{vendor}"\n);
    print F qq(    ModelName  "$O->{model}"\n\n);
    print G qq(    ModelName  "$O->{model}"\n\n);
    print F $monitorsection_text2;
    print G $monitorsection_text2;
    print F qq(    HorizSync  $O->{hsyncrange}\n\n);
    print G qq(    HorizSync  $O->{hsyncrange}\n\n);
    print F $monitorsection_text3;
    print G $monitorsection_text3;
    print F qq(    VertRefresh $O->{vsyncrange}\n\n);
    print G qq(    VertRefresh $O->{vsyncrange}\n\n);
    print F $monitorsection_text4;
    print F ($O->{modelines} || '') . ($o->{card}{type} eq "TG 96" ? $modelines_text_Trident_TG_96xx : $modelines_text);
    print F "\nEndSection\n\n\n";
    print G "\nEndSection\n\n\n";

    #- Write Device section.
    $O = $o->{card};
    print F $devicesection_text;
    print G $devicesection_text_v4;
    print F qq(Section "Device"\n);
    print G qq(Section "Device"\n);
    print F qq(    Identifier  "$O->{type}"\n);
    print G qq(    Identifier  "$O->{type}"\n);
    print F qq(    VendorName  "$O->{vendor}"\n);
    print G qq(    VendorName  "$O->{vendor}"\n);
    print F qq(    BoardName   "$O->{board}"\n);
    print G qq(    BoardName   "$O->{board}"\n);

    print F "#" if $O->{chipset} && !$O->{flags}{needChipset};
    print F qq(    Chipset     "$O->{chipset}"\n) if $O->{chipset};
    print G qq(    Driver      "$O->{driver}"\n);

    print F "#" if $O->{memory} && !$O->{flags}{needVideoRam};
    print G "#" if $O->{memory} && !$O->{flags}{needVideoRam};
    print F "    VideoRam    $O->{memory}\n" if $O->{memory};
    print G "    VideoRam    $O->{memory}\n" if $O->{memory};

    print F map { "    $_\n" } @{$O->{lines} || []};
    print G map { "    $_\n" } @{$O->{lines} || []};

    print F qq(    Ramdac      "$O->{ramdac}"\n) if $O->{ramdac};
    print G qq(    Ramdac      "$O->{ramdac}"\n) if $O->{ramdac};
    print F qq(    Dacspeed    "$O->{dacspeed}"\n) if $O->{dacspeed};
    print G qq(    Dacspeed    "$O->{dacspeed}"\n) if $O->{dacspeed};

    if ($O->{clockchip}) {
	print F qq(    Clockchip   "$O->{clockchip}"\n);
	print G qq(    Clockchip   "$O->{clockchip}"\n);
    } else {
	print F "    # Clock lines\n";
	print G "    # Clock lines\n";
	print F "    Clocks $_\n" foreach (@{$O->{clocklines}});
	print G "    Clocks $_\n" foreach (@{$O->{clocklines}});
    }
    do { print F; print G } for qq(

    # Uncomment following option if you see a big white block        
    # instead of the cursor!                                          
    #    Option      "sw_cursor"

);
    my $p = sub {
	my $l = $O->{$_[0]};
	map { (!$l->{$_} && '#') . qq(    Option      "$_"\n) } keys %{$l || {}};
    };
    print F $p->('options');
    print F $p->('options_xf3');
    print G $p->('options');
    print G $p->('options_xf4');
    print F "EndSection\n\n\n";
    print G "EndSection\n\n\n";

    #- Write Screen sections.
    print F $screensection_text1, "\n";
    print G $screensection_text1, "\n";

    my $subscreen = sub {
	my ($f, $server, $defdepth, $depths) = @_;
	print $f "    DefaultColorDepth $defdepth\n" if $defdepth;

        foreach (ikeys(%$depths)) {
	    my $m = $server ne "fbdev" ? join(" ", map { qq("$_->[0]x$_->[1]") } @{$depths->{$_}}) : qq("default"); #-"
	    print $f qq(    Subsection "Display"\n);
	    print $f qq(        Depth       $_\n) if $_;
	    print $f qq(        Modes       $m\n);
	    print $f qq(        ViewPort    0 0\n);
	    print $f qq(    EndSubsection\n);
	}
	print $f "EndSection\n";
    };

    my $screen = sub {
	my ($server, $defdepth, $device, $depths) = @_;
	print F qq(
Section "Screen"
    Driver "$server"
    Device      "$device"
    Monitor     "$o->{monitor}{type}"
); #-"
	$subscreen->(*F, $server, $defdepth, $depths);
    };

    #- SVGA screen section.
    print F qq(
# The Colour SVGA server
);

    if (member($O->{server}, @svgaservers)) {
	&$screen("svga", $o->{default_depth}, $O->{type}, $O->{depth});
    } else {
	&$screen("svga", '', "Generic VGA", { 8 => [[ 320, 200 ]] });
    }

    &$screen("vga16", '',
	     (member($O->{server}, "Mono", "VGA16") ? $O->{type} : "Generic VGA"),
	     { '' => [[ 640, 480 ], [ 800, 600 ]]});

    &$screen("vga2", '',
	     (member($O->{server}, "Mono", "VGA16") ? $O->{type} : "Generic VGA"),
	     { '' => [[ 640, 480 ], [ 800, 600 ]]});

    &$screen("accel", $o->{default_depth}, $O->{type}, $O->{depth});

    &$screen("fbdev", $o->{default_depth}, $O->{type}, $O->{depth});


    print G qq(
Section "Screen"
    Identifier "screen1"
    Device      "$O->{type}"
    Monitor     "$o->{monitor}{type}"
);
    #- bpp 32 not handled by XF4
    $subscreen->(*G, "svga", min($o->{default_depth}, 24), $O->{depth});

    print G '

Section "ServerLayout"
    Identifier "layout1"
    Screen     "screen1"
    InputDevice "Mouse1" "CorePointer"
';
    print G '
    InputDevice "stylus" "AlwaysCore"
    InputDevice "eraser" "AlwaysCore"
    InputDevice "cursor" "AlwaysCore"
' if $o->{wacom};
    print G '
    InputDevice "Keyboard1" "CoreKeyboard"
EndSection
'; #-"

    close F;
    close G;
}

sub XF86check_link {
    my ($ext) = @_;

    my $f = "$prefix/etc/X11/XF86Config$ext";
    touch($f);

    my $l = "$prefix/usr/X11R6/lib/X11/XF86Config$ext";

    if (-e $l && (stat($f))[1] != (stat($l))[1]) { #- compare the inode, must be the sames
	-e $l and unlink($l) || die "can't remove bad $l";
	symlinkf "../../../../etc/X11/XF86Config$ext", $l;
    }
}

sub show_info {
    my ($o) = @_;
    my $info;

    $info .= _("Keyboard layout: %s\n", $o->{keyboard}{xkb_keymap});
    $info .= _("Mouse type: %s\n", $o->{mouse}{XMOUSETYPE});
    $info .= _("Mouse device: %s\n", $o->{mouse}{device}) if $::expert;
    $info .= _("Monitor: %s\n", $o->{monitor}{type});
    $info .= _("Monitor HorizSync: %s\n", $o->{monitor}{hsyncrange}) if $::expert;
    $info .= _("Monitor VertRefresh: %s\n", $o->{monitor}{vsyncrange}) if $::expert;
    $info .= _("Graphic card: %s\n", $o->{card}{type});
    $info .= _("Graphic memory: %s kB\n", $o->{card}{memory}) if $o->{card}{memory};
    $info .= _("XFree86 server: %s\n", $o->{card}{server});

    $in->ask_warn('', $info);
}

#- Program entry point.
sub main {
    my ($o, $allowFB);
    ($prefix, $o, $in, $allowFB, $isLaptop, $install) = @_;
    $o ||= {};

      XF86check_link('');
      XF86check_link('-4');

    {
	my $w = $in->wait_message('', _("Preparing X-Window configuration"), 1);

	$o->{card} = cardConfiguration($o->{card}, $::noauto, $allowFB);

	$o->{monitor} = monitorConfiguration($o->{monitor}, $o->{card}{server} eq 'FBDev');
    }
    my $ok = resolutionsConfiguration($o, auto => $::auto, noauto => $::noauto);

    $ok &&= testFinalConfig($o, $::auto, $o->{skiptest});

    my $quit;
    until ($ok || $quit) {

	my %c = my @c = (
	   __("Change Monitor") => sub { $o->{monitor} = monitorConfiguration() },
           __("Change Graphic card") => sub { $o->{card} = cardConfiguration('', 'noauto', $allowFB) },
           ($::expert ? (__("Change Server options") => sub { optionsConfiguration($o) }) : ()),
	   __("Change Resolution") => sub { resolutionsConfiguration($o, noauto => 1) },
	   __("Automatical resolutions search") => sub {
	       delete $o->{card}{depth};
	       resolutionsConfiguration($o, nowarning => 1);
	   },
	   __("Show information") => sub { show_info($o) },
	   __("Test again") => sub { $ok = testFinalConfig($o, 1) },
	   __("Quit") => sub { $quit = 1 },
        );
	$in->set_help('configureXmain') unless $::isStandalone;
	my $f = $in->ask_from_list_(['XFdrake'],
				 _("What do you want to do?"),
				 [ grep { !ref } @c ]);
	eval { &{$c{$f}} };
	!$@ || $@ =~ /ask_from_list cancel/ or die;
	$in->kill;
    }
    if (!$ok) {
	$ok = !$in->ask_yesorno('', _("Forget the changes?"), 1);
    }
    if ($ok) {
	unless ($::testing) {
	    my $f = "$prefix/etc/X11/XF86Config";
	    if (-e "$f.test") {
		rename $f, "$f.old" or die "unable to make a backup of XF86Config";
		rename "$f-4", "$f-4.old";
		rename "$f.test", $f;
		rename "$f.test-4", "$f-4";
		symlinkf "../..$o->{card}{prog}", "$prefix/etc/X11/X";
	    }
	}

	if ($::isStandalone && $0 =~ /Xdrakres/) {
	    my $found;
	    foreach (@window_managers) {
		if (`pidof $_` > 0) {
		    if ($in->ask_okcancel('', _("Please relog into %s to activate the changes", ucfirst $_), 1)) {
			system("kwmcom logout") if /kwm/;

			open STDIN, "</dev/zero";
			open STDOUT, ">/dev/null";
			open STDERR, ">&STDERR";
			c::setsid();
		        exec qw(perl -e), q{
                          my $wm = shift;
  		          for (my $nb = 30; $nb && `pidof $wm` > 0; $nb--) { sleep 1 }
  		          system("killall X") unless `pidof $wm` > 0;
  		        }, $_;
		    }
		    $found = 1; last;
		}
	    }
	    $in->ask_warn('', _("Please log out and then use Ctrl-Alt-BackSpace")) unless $found;
	} else {
	    $in->set_help('configureXxdm') unless $::isStandalone;
	    my $run = exists $o->{xdm} ? $o->{xdm} : $::auto || $in->ask_yesorno(_("X at startup"),
_("I can set up your computer to automatically start X upon booting.
Would you like X to start when you reboot?"), 1);
	    rewriteInittab($run ? 5 : 3) unless $::testing;
	}
	my @etc_pass_fields = qw(name pw uid gid realname home shell);
	my @users = mapgrep {
	    my %l; @l{@etc_pass_fields} = split ':';
	    $l{uid} > 500, $l{name};
	} cat_("$o->{prefix}/etc/passwd");

	unless ($::auto || !@users || $o->{authentication}{NIS}) {
	    my $cmd = $prefix ? "chroot $prefix" : "";
	    my @wm = map { lc } (split (' ', `$cmd /usr/sbin/chksession -l`));

	    my %l = getVarsFromSh("$prefix/etc/sysconfig/autologin");
	    $o->{autologin} ||= $l{USER};

	    $in->ask_from_entries_refH(_("Autologin"),
_("I can set up your computer to automatically log on one user.
If you don't want to use this feature, click on the cancel button."),
				       [ _("Choose the default user:") => { val => \$o->{autologin}, list => [ '', @users ] },
					 _("Choose the window_manager to run:") => { val => \$o->{desktop}, list => \@wm }, ]) or delete $o->{autologin};
	}
	if ($o->{autologin}) {
	    $::isStandalone ? system("urpmi --auto autologin") : $::o->pkg_install("autologin");
	    any::setAutologin($prefix, $o->{autologin}, $o->{desktop});
	}
	run_program::rooted($prefix, "chkconfig", "--del", "gpm") if $o->{mouse}{device} =~ /ttyS/ && !$::isStandalone;
    }
}
