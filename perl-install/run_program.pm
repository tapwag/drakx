package run_program; # $Id$

use diagnostics;
use strict;
use c;

use MDK::Common;
use common; # for get_parent_uid()
use log;

1;

sub run_or_die {
    my ($name, @args) = @_;
    run($name, @args) or die "$name failed\n";
}
sub rooted_or_die {
    my ($root, $name, @args) = @_;
    rooted($root, $name, @args) or die "$name failed\n";
}

sub get_stdout {
    my ($name, @args) = @_;
    my @r;
    run($name, '>', \@r, @args) or return;
    wantarray() ? @r : join('', @r);
}
sub rooted_get_stdout {
    my ($root, $name, @args) = @_;
    my @r;
    rooted($root, $name, '>', \@r, @args) or return;
    wantarray() ? @r : join('', @r);
}

sub run { raw({}, @_) }

sub rooted {
    my ($root, $name, @args) = @_;
    raw({ root => $root }, $name, @args);
}

sub raw {
    my ($options, $name, @args) = @_;
    my $root = $options->{root} || '';
    my $real_name = ref($name) ? $name->[0] : $name;

    my ($stdout_raw, $stdout_mode, $stderr_raw, $stderr_mode);
    ($stdout_mode, $stdout_raw, @args) = @args if $args[0] =~ /^>>?$/;
    ($stderr_mode, $stderr_raw, @args) = @args if $args[0] =~ /^2>>?$/;

    my $home;
    if ($options->{as_user}) {
        my $user;
        $user = $ENV{USERHELPER_UID} && getpwuid($ENV{USERHELPER_UID});
        $user ||= common::get_parent_uid();
        $options->{setuid} = getpwnam($user) if $user;
        $home = $user->[7] if $user;
    }
    local $ENV{HOME} = $home if $home;

    my $args = $options->{sensitive_arguments} ? '<hidden arguments>' : join(' ', @args);
    log::explanations("running: $real_name $args" . ($root ? " with root $root" : ""));

    return if $root && $<;

    $root ? ($root .= '/') : ($root = '');
    
    my $tmpdir = sub {
	my $dir = $< != 0 ? "$ENV{HOME}/tmp" : -d '/root' ? '/root/tmp' : '/tmp';
	-d $dir or mkdir($dir, 0700);
	$dir;
    };
    my $stdout = $stdout_raw && (ref($stdout_raw) ? $tmpdir->() . "/.drakx-stdout.$$" : "$root$stdout_raw");
    my $stderr = $stderr_raw && (ref($stderr_raw) ? $tmpdir->() . "/.drakx-stderr.$$" : "$root$stderr_raw");

    #- checking if binary exist to avoid clobbering stdout file
    my $rname = $real_name =~ /(.*?)[\s\|]/ ? $1 : $real_name;    
    if (! ($rname =~ m!^/! 
	     ? -x "$root$rname" || $root && -l "$root$rname" #- handle non-relative symlink which can be broken when non-rooted
	     : whereis_binary($rname, $root))) {
	log::l("program not found: $real_name");
	return;
    }

    if (my $pid = fork()) {
	if ($options->{detach}) {
	    $pid;
	} else {
	    my $ok;
	    add2hash_($options, { timeout => 10 * 60 });
	    eval {
		local $SIG{ALRM} = sub { die "ALARM" };
		my $remaining = $options->{timeout} && $options->{timeout} ne 'never' &&  alarm($options->{timeout});
		waitpid $pid, 0;
		$ok = $? == -1 || ($? >> 8) == 0;
		alarm $remaining;
	    };
	    if ($@) {
		log::l("ERROR: killing runaway process (process=$real_name, pid=$pid, args=@args, error=$@)");
		kill 9, $pid;
		return;
	    }

	    if ($stdout_raw && ref($stdout_raw)) {	    
		if (ref($stdout_raw) eq 'ARRAY') { 
		    @$stdout_raw = cat_($stdout);
		} else { 
		    $$stdout_raw = cat_($stdout);
		}
		unlink $stdout;
	    }
	    if ($stderr_raw && ref($stderr_raw)) {
		if (ref($stderr_raw) eq 'ARRAY') { 
		    @$stderr_raw = cat_($stderr);
		} else { 
		    $$stderr_raw = cat_($stderr);
		}
		unlink $stderr;
	    }
	    $ok;
	}
    } else {
        if ($options->{setuid}) {
            require POSIX;
            my ($logname, $home) = (getpwuid($options->{setuid}))[0,7];
            $ENV{LOGNAME} = $logname if $logname;

            # if we were root and are going to drop privilege, keep a copy of the X11 cookie:
            if (!$> && $home) {
                # FIXME: it would be better to remove this but most callers are using 'detach => 1'...
                my $xauth = chomp_(`mktemp $home/.Xauthority.XXXXX`);
                system('cp', '-a', $ENV{XAUTHORITY}, $xauth);
                system('chown', $logname, $xauth);
                $ENV{XAUTHORITY} = $xauth;
            }

            # drop privileges:
            POSIX::setuid($options->{setuid});
        }

	sub die_exit {
	    log::l($_[0]);
	    c::_exit(128);
	}
	if ($stderr && $stderr eq 'STDERR') {
	} elsif ($stderr) {
	    $stderr_mode =~ s/2//;
	    open STDERR, "$stderr_mode $stderr" or die_exit("run_program cannot output in $stderr (mode `$stderr_mode')");
	} elsif ($::isInstall) {
	    open STDERR, ">> /tmp/ddebug.log" or open STDOUT, ">> /dev/tty7" or die_exit("run_program cannot log, give me access to /tmp/ddebug.log");
	}
	if ($stdout && $stdout eq 'STDOUT') {
	} elsif ($stdout) {
	    open STDOUT, "$stdout_mode $stdout" or die_exit("run_program cannot output in $stdout (mode `$stdout_mode')");
	} elsif ($::isInstall) {
	    open STDOUT, ">> /tmp/ddebug.log" or open STDOUT, ">> /dev/tty7" or die_exit("run_program cannot log, give me access to /tmp/ddebug.log");
	}

	$root and chroot $root;
	chdir($options->{chdir} || "/");

	my $ok = ref $name ? do {
	    exec { $name->[0] } $name->[1], @args;
	} : do {
	    exec $name, @args;
	};
	if (!$ok) {
	    die_exit("exec of $real_name failed: $!");
	}
    }

}

# run in background a sub that give back data through STDOUT a la run_program::get_stdout but w/ arbitrary perl code instead of external program
package bg_command;

sub new {
    my ($class, $sub) = @_;
    my $o = bless {}, $class;
    if ($o->{pid} = open(my $fd, "-|")) {
        $o->{fd} = $fd;
        $o;
    } else {
        $sub->();
        c::_exit(0);
    }
}

sub DESTROY {
    my ($o) = @_;
    close $o->{fd} or warn "kid exited $?";
    waitpid $o->{pid}, 0;
}

1;

#- Local Variables:
#- mode:cperl
#- tab-width:8
#- End:
