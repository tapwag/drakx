use MDK::Common;
use ExtUtils::MakeMaker;
use Config;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $lib = arch() =~ /x86_64/ ? 'lib64' : 'lib';

my $libs = '-lparted';

my $pcmcia_probe_o = "/usr/$lib/drakx-installer/binaries/pcmcia_probe.o";

$CC = 'g++';

WriteMakefile(
    'NAME'	=> 'stuff',
    'OPTIMIZE'  => '-Os -Wall',
    'MAKEFILE'  => 'Makefile_c',
    'OBJECT'    => "stuff.o " . (-e $pcmcia_probe_o && " $pcmcia_probe_o"),
    'VERSION_FROM' => 'stuff.pm', # finds $VERSION
    'LIBS'	=> [$libs],   # e.g., '-lm' 
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'XSOPT'	=> '-C++',
    CC			=> $CC,
    LD			=> $CC,

);
