package Xconfig::main; # $Id$

use diagnostics;
use strict;

use Xconfig::monitor;
use Xconfig::card;
use Xconfig::resolution_and_depth;
use Xconfig::various;
use Xconfig::screen;
use Xconfig::test;
use common;
use any;


sub configure_monitor {
    my ($in, $raw_X) = @_;

    Xconfig::monitor::configure($in, $raw_X) or return;
    $raw_X->write;
    'config_changed';
}

sub configure_resolution {
    my ($in, $raw_X) = @_;

    my $card = Xconfig::card::from_raw_X($raw_X);
    my $monitor = Xconfig::monitor::from_raw_X($raw_X);
    Xconfig::resolution_and_depth::configure($in, $raw_X, $card, $monitor) or return;
    $raw_X->write;
    'config_changed';
}


sub configure_everything_auto_install {
    my ($raw_X, $do_pkgs, $old_X, $options) = @_;
    
    my $card = Xconfig::card::configure_auto_install($raw_X, $do_pkgs, $old_X, $options) or return;
    my $monitor = Xconfig::monitor::configure_auto_install($raw_X, $old_X) or return;
    Xconfig::screen::configure($raw_X, $card) or return;
    my $resolution = Xconfig::resolution_and_depth::configure_auto_install($raw_X, $card, $monitor, $old_X);

    export_to_install_X($card, $monitor, $resolution);
    $raw_X->write;
    symlinkf "../..$card->{prog}", "$::prefix/etc/X11/X" if $card->{server} !~ /Xpmac/;

    any::runlevel($::prefix, exists $old_X->{xdm} && !$old_X->{xdm} ? 3 : 5);
}

sub configure_everything {
    my ($in, $raw_X, $do_pkgs, $auto, $options) = @_;
    my $X = {};
    my $ok = 1;
    $ok &&= $X->{card} = Xconfig::card::configure($in, $raw_X, $do_pkgs, $auto, $options);
    $ok &&= $X->{monitor} = Xconfig::monitor::configure($in, $raw_X, $auto);
    $ok &&= Xconfig::screen::configure($raw_X, $X->{card});
    $ok &&= $X->{resolution} = Xconfig::resolution_and_depth::configure($in, $raw_X, $X->{card}, $X->{monitor}, $auto);
    $ok &&= Xconfig::test::test($in, $raw_X, $X->{card}, $auto);

    if (!$ok) {
	($ok) = configure_chooser_raw($in, $raw_X, $do_pkgs, $options, $X, 1);
    } else {
	Xconfig::various::various($in, $X->{card}, $options, $auto);
    }
    $ok = &write($in, $raw_X, $X, $ok);
    
    $ok && 'config_changed';
}

sub configure_chooser_raw {
    my ($in, $raw_X, $do_pkgs, $options, $X, $modified) = @_;

    my %texts;

    my $update_texts = sub {
	$texts{card} = $X->{card} && $X->{card}{BoardName} || _("Custom");
	$texts{monitor} = $X->{monitor} && $X->{monitor}{ModelName} || _("Custom");
	$texts{resolution} = Xconfig::resolution_and_depth::to_string($X->{resolution});

	$texts{$_} =~ s/(.{20}).*/$1.../ foreach keys %texts; #- ensure not too long
    };
    $update_texts->();

    my $may_set = sub {
	my ($field, $val) = @_;
	if ($val) {
	    $X->{$field} = $val;
	    $X->{"modified_$field"} = 1;
	    $modified = 1;
	    $update_texts->();
	}
    };

    my $ok;
    $in->ask_from_({ ok => '' }, 
		   [
		    { label => _("Graphic Card"), val => \$texts{card}, icon => "eth_card_mini", clicked => sub { 
			  $may_set->('card', Xconfig::card::configure($in, $raw_X, $do_pkgs, 0, $options));
		      } },
		    { label => _("Monitor"), val => \$texts{monitor}, icon => "ic82-systemeplus-40", clicked => sub { 
			  $may_set->('monitor', Xconfig::monitor::configure($in, $raw_X));
		      } },
		    { label => _("Resolution"), val => \$texts{resolution}, icon => "X", disabled => sub { !$X->{card} || !$X->{monitor} }, 
		      clicked => sub {
			  if (grep { delete $X->{"modified_$_"} } 'card', 'monitor') {
			      Xconfig::screen::configure($raw_X, $X->{card});
			  }
			  $may_set->('resolution', Xconfig::resolution_and_depth::configure($in, $raw_X, $X->{card}, $X->{monitor}));
		      } },
		    { val => _("Test"), icon => "warning", disabled => sub { !$X->{card} || !$X->{monitor} || !$modified || !Xconfig::card::check_bad_card($X->{card}) },
		      clicked => sub {
			  $ok = Xconfig::test::test($in, $raw_X, $X->{card}, 1);
		      } },
		    { val => _("Options"), icon => "ic82-tape-40", clicked => sub {
			  Xconfig::various::various($in, $X->{card}, $options);
		      } },
		    { val => $::isInstall ? _("Ok") : _("Quit"), icon => "exit", clicked_may_quit => sub { 1 } },
		   ]);
    $ok, $modified;
}

sub configure_chooser {
    my ($in, $raw_X, $do_pkgs, $options) = @_;

    my $X = {
	card => eval { Xconfig::card::from_raw_X($raw_X) },
	monitor => $raw_X->get_monitors && Xconfig::monitor::from_raw_X($raw_X),
	resolution => eval { $raw_X->get_resolution },
    };
    my ($ok, $modified) = configure_chooser_raw($in, $raw_X, $do_pkgs, $options, $X);

    $modified and &write($in, $raw_X, $X, $ok) or return;

    'config_changed';
}

sub write {
    my ($in, $raw_X, $X, $ok) = @_;

    $ok ||= $in->ask_yesorno('', _("Keep the changes?
The current configuration is:

%s", Xconfig::various::info($raw_X, $X->{card})), 1);

    $ok or return;

    export_to_install_X($X);
    $raw_X->write;
    Xconfig::various::check_XF86Config_symlink();
    symlinkf "../..$X->{card}{prog}", "$::prefix/etc/X11/X" if $X->{card}{server} !~ /Xpmac/;
    1;
}

sub export_to_install_X {
    my ($X) = @_;

    $::isInstall or return;

    $::o->{X}{resolution_wanted} = $X->{resolution}{X};
    $::o->{X}{default_depth} = $X->{resolution}{Depth};
    $::o->{X}{bios_vga_mode} = $X->{resolution}{bios};
    $::o->{X}{monitor} = $X->{monitor} if $X->{monitor}{manually_chosen};
    $::o->{X}{card} = $X->{monitor} if $X->{card}{manually_chosen};
}


#- most usefull XFree86-4.0.1 server options. Default values is the first ones.
our @options_serverflags = (
			'DontZap'                 => [ "Off", "On" ],
			'DontZoom'                => [ "Off", "On" ],
			'DisableVidModeExtension' => [ "Off", "On" ],
			'AllowNonLocalXvidtune'   => [ "Off", "On" ],
			'DisableModInDev'         => [ "Off", "On" ],
			'AllowNonLocalModInDev'   => [ "Off", "On" ],
			'AllowMouseOpenFail'      => [ "False", "True" ],
			'VTSysReq'                => [ "Off", "On" ],
			'BlankTime'               => [ "10", "5", "3", "15", "30" ],
			'StandByTime'             => [ "20", "10", "6", "30", "60" ],
			'SuspendTime'             => [ "30", "15", "9", "45", "90" ],
			'OffTime'                 => [ "40", "20", "12", "60", "120" ],
			'Pixmap'                  => [ "32", "24" ],
			'PC98'                    => [ "auto-detected", "False", "True" ],
			'NoPM'                    => [ "False", "True" ],
);

1;
