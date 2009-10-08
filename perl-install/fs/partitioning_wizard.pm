package fs::partitioning_wizard; # $Id$

use diagnostics;
use strict;
use utf8;

use common;
use devices;
use fsedit;
use fs::type;
use fs::mount_point;
use partition_table;
use partition_table::raw;
use partition_table::dos;

#- unit of $mb is mega bytes, min and max are in sectors, this
#- function is used to convert back to sectors count the size of
#- a partition ($mb) given from the interface (on Resize or Create).
#- modified to take into account a true bounding with min and max.
sub from_Mb {
    my ($mb, $min, $max) = @_;
    $mb <= to_Mb($min) and return $min;
    $mb >= to_Mb($max) and return $max;
    MB($mb);
}
sub to_Mb {
    my ($size_sector) = @_;
    to_int($size_sector / 2048);
}

sub partition_with_diskdrake {
    my ($in, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab) = @_;
    my $ok; 

    do {
	$ok = 1;
	my $do_force_reload = sub {
            my $new_hds = fs::get::empty_all_hds();
            fs::any::get_hds($new_hds, $fstab, $manual_fstab, $partitioning_flags, $skip_mtab, $in);
            %$all_hds = %$new_hds;
            $all_hds;
	};
	require diskdrake::interactive;
	{
	    local $::expert = 0;
	    diskdrake::interactive::main($in, $all_hds, $do_force_reload);
	}
	my @fstab = fs::get::fstab($all_hds);
	
	unless (fs::get::root_(\@fstab)) {
	    $ok = 0;
	    $in->ask_okcancel(N("Partitioning"), N("You must have a root partition.
For this, create a partition (or click on an existing one).
Then choose action ``Mount point'' and set it to `/'"), 1) or return;
	}
	if (!any { isSwap($_) } @fstab) {
	    $ok &&= $in->ask_okcancel('', N("You do not have a swap partition.\n\nContinue anyway?"));
	}
	if (arch() =~ /ia64/ && !fs::get::has_mntpoint("/boot/efi", $all_hds)) {
	    $in->ask_warn('', N("You must have a FAT partition mounted in /boot/efi"));
	    $ok = '';
	}
    } until $ok;
    1;
}

sub partitionWizardSolutions {
    my ($in, $all_hds, $all_fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab, $target) = @_;
    my $hds;
    my $fstab;
    if($target) {
        $hds = [ $target ];
        $fstab = [ grep { $_->{rootDevice} eq $target->{device} } fs::get::fstab($all_hds) ];
    } else {
        $hds = $all_hds->{hds};
        $fstab = [ fs::get::fstab($all_hds) ];
    }

    my @wizlog;
    my (%solutions);

    my $min_linux = MB(600);
    my $max_linux = MB(2000);
    my $min_swap = MB(50);
    my $max_swap = MB(300);
    my $min_freewin = MB(100);

    # each solution is a [ score, text, function ], where the function retunrs true if succeeded

    my @hds_rw = grep { !$_->{readonly} } @$hds;
    my @hds_can_add = grep { $_->can_add } @hds_rw;
    if (fs::get::hds_free_space(@hds_can_add) > $min_linux) {
	$solutions{free_space} = [ 30, N("Use free space"), sub { fsedit::auto_allocate($all_hds, $partitions); 1 } ];
    } else { 
	push @wizlog, N("Not enough free space to allocate new partitions") . ": " .
	  (@hds_can_add ? 
	   fs::get::hds_free_space(@hds_can_add) . " < $min_linux" :
	   "no harddrive on which partitions can be added");
    }

    if (my @truefs = grep { isTrueLocalFS($_) } @$fstab) {
	#- value twice the ext2 partitions
	$solutions{existing_part} = [ 20 + @truefs + @$fstab, N("Use existing partitions"), sub { fs::mount_point::ask_mount_points($in, $fstab, $all_hds) } ];
    } else {
	push @wizlog, N("There is no existing partition to use");
    }

    if (my @ok_for_resize_fat = grep { isFat_or_NTFS($_) && !fs::get::part2hd($_, $all_hds)->{readonly}
					 && !isRecovery($_) && $_->{size} > $min_linux + $min_swap + $min_freewin} @$fstab) {
        @ok_for_resize_fat = map {
            my $part = $_;
            my $hd = fs::get::part2hd($part, $all_hds);
            my $resize_fat = eval {
                my $pkg = $part->{fs_type} eq 'vfat' ? do { 
                    require resize_fat::main;
                    'resize_fat::main';
                } : do {
                    require diskdrake::resize_ntfs;
                    'diskdrake::resize_ntfs';
                };
                $pkg->new($part->{device}, devices::make($part->{device}));
            };
            if($@) {
                log::l("The FAT resizer is unable to handle $part->{device} partition%s", formatError($@));
                undef $part;
            }
            if ($part) {
                my $min_win = eval {
                    my $_w = $in->wait_message(N("Resizing"), N("Computing the size of the Microsoft Windows® partition"));
                    $resize_fat->min_size;
                };
                if($@) {
                    log::l("The FAT resizer is unable to get minimal size for $part->{device} partition %s", formatError($@));
                    undef $part;
                } else {
                    #- make sure that even after normalizing the size to cylinder boundaries, the minimun will be saved,
                    #- this save at least a cylinder (less than 8Mb).
                    $min_win += partition_table::raw::cylinder_size($hd);
                    
                    if ($part->{size} <= $min_linux + $min_swap + $min_freewin + $min_win) {
#                die N("Your Microsoft Windows® partition is too fragmented. Please reboot your computer under Microsoft Windows®, run the ``defrag'' utility, then restart the Mandriva Linux installation.");
                        undef $part;
                    } else {
                        $part->{resize_fat} = $resize_fat;
                        $part->{min_win} = $min_win;
                    }
                }
            }
            $part || ();
        } @ok_for_resize_fat;
	if(@ok_for_resize_fat) {
            $solutions{resize_fat} = 
                [ 20 - @ok_for_resize_fat, N("Use the free space on a Microsoft Windows® partition"),
                  sub {
                      my $part;
                      if ($in->{interactive} ne 'gtk') {
                          $part = $in->ask_from_listf_raw({ messages => N("Which partition do you want to resize?"),
                                                               interactive_help_id => 'resizeFATChoose',
                                                             }, \&partition_table::description, \@ok_for_resize_fat) or return;
                      } else {
                          ($part) = grep { $_->{req_size}} @ok_for_resize_fat;
                      }
                      my $resize_fat = $part->{resize_fat} ;
                      my $min_win = $part->{min_win};
                      my $hd = fs::get::part2hd($part, $all_hds);
                      if ($in->{interactive} ne 'gtk') {
                          $part->{size} > $min_linux + $min_swap + $min_freewin + $min_win or die N("Your Microsoft Windows® partition is too fragmented. Please reboot your computer under Microsoft Windows®, run the ``defrag'' utility, then restart the Mandriva Linux installation.");
                      }
                      $in->ask_okcancel('', formatAlaTeX(
                                            #-PO: keep the double empty lines between sections, this is formatted a la LaTeX
                                            N("WARNING!


Your Microsoft Windows® partition will be now resized.


Be careful: this operation is dangerous. If you have not already done so, you first need to exit the installation, run \"chkdsk c:\" from a Command Prompt under Microsoft Windows® (beware, running graphical program \"scandisk\" is not enough, be sure to use \"chkdsk\" in a Command Prompt!), optionally run defrag, then restart the installation. You should also backup your data.


When sure, press %s.", N("Next")))) or return;

                      my $oldsize = $part->{size};
                      if($in->{interactive} ne 'gtk') {
                          my $mb_size = to_Mb($part->{size});
                          $in->ask_from(N("Partitionning"), N("Which size do you want to keep for Microsoft Windows® on partition %s?", partition_table::description($part)), [
                                        { label => N("Size"), val => \$mb_size, min => to_Mb($min_win), max => to_Mb($part->{size} - $min_linux - $min_swap), type => 'range' },
                                    ]) or return;
                          $part->{size} = from_Mb($mb_size, $min_win, $part->{size});
                      } else {
                          $part->{size} = $part->{req_size};
                      }
                      
                      $hd->adjustEnd($part);
                      
                      eval { 
                          my $_w = $in->wait_message(N("Resizing"), N("Resizing Microsoft Windows® partition"));
                          $resize_fat->resize($part->{size});
                      };
                      if (my $err = $@) {
                          $part->{size} = $oldsize;
                          die N("FAT resizing failed: %s", formatError($err));
                      }
                      
                      $in->ask_warn('', N("To ensure data integrity after resizing the partition(s), 
filesystem checks will be run on your next boot into Microsoft Windows®")) if $part->{fs_type} ne 'vfat';
                      
                      set_isFormatted($part, 1);
                      partition_table::will_tell_kernel($hd, resize => $part); #- down-sizing, write_partitions is not needed
                      partition_table::adjust_local_extended($hd, $part);
                      partition_table::adjust_main_extended($hd);
                      
                      fsedit::auto_allocate($all_hds, $partitions);
                      1;
                  }, \@ok_for_resize_fat ];
        }
    } else {
	push @wizlog, N("There is no FAT partition to resize (or not enough space left)");
    }

    if (@$fstab && @hds_rw) {
	$solutions{wipe_drive} =
	  [ 10, fsedit::is_one_big_fat_or_NT($hds) ? N("Remove Microsoft Windows®") : N("Erase and use entire disk"), 
	    sub {
                my $hd;
                if($in->{interactive} ne 'gtk') {
                    $hd = $in->ask_from_listf_raw({ messages => N("You have more than one hard drive, which one do you install linux on?"),
                                                       title => N("Partitioning"),
                                                       interactive_help_id => 'takeOverHdChoose',
                                                     },
                                                     \&partition_table::description, \@hds_rw) or return;
                } else {
                    $hd = $target;
                }
		$in->ask_okcancel_({ messages => N("ALL existing partitions and their data will be lost on drive %s", partition_table::description($hd)),
				    title => N("Partitioning"),
				    interactive_help_id => 'takeOverHdConfirm' }) or return;
		fsedit::partition_table_clear_and_initialize($all_hds->{lvms}, $hd, $in);
		fsedit::auto_allocate($all_hds, $partitions);
		1;
	    } ];
    }

    if (@hds_rw || find { $_->isa('partition_table::lvm') } @$hds) {
	$solutions{diskdrake} = [ 0, N("Custom disk partitioning"), sub {
	    partition_with_diskdrake($in, $all_hds, $all_fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab);
        } ];
    }

    $solutions{fdisk} =
      [ -10, N("Use fdisk"), sub { 
	    $in->enter_console;
	    foreach (@$hds) {
		print "\n" x 10, N("You can now partition %s.
When you are done, do not forget to save using `w'", partition_table::description($_));
		print "\n\n";
		my $pid = 0;
		if (arch() =~ /ppc/) {
			$pid = fork() or exec "pdisk", devices::make($_->{device});
		} else {
			$pid = fork() or exec "fdisk", devices::make($_->{device});
		}			
		waitpid($pid, 0);
	    }
	    $in->leave_console;
	    0;
	} ] if $partitioning_flags->{fdisk};

    log::l("partitioning wizard log:\n", (map { ">>wizlog>>$_\n" } @wizlog));
    %solutions;
}

sub warn_reboot_needed {
    my ($in) = @_;
    $in->ask_warn(N("Partitioning"), N("You need to reboot for the partition table modifications to take place"));
}

sub create_display_box {
    my ($kind, $resize, $fill_empty) = @_;
    my @parts = fs::get::hds_fstab_and_holes($kind->{val});

    my $totalsectors = $kind->{val}->{totalsectors};

    my $width = 540;
    $width -= 24 if($resize || $fill_empty);
    my $minwidth = 40;

    my $display_box = ugtk2::gtkset_size_request(Gtk2::HBox->new(0,0), $width, 30);

    my $ratio = $totalsectors ? ($width - @parts * ($minwidth+1)) / $totalsectors : 1;
    while (1) {
        my $totalwidth = sum(map { $_->{size} * $ratio + $minwidth } @parts);
        $totalwidth <= $width and last;
        $ratio /= $totalwidth / $width * 1.1;
    }

    my $vbox = Gtk2::VBox->new();

    my $ev;
    my $desc;

    foreach my $entry (@parts) {
	my $info = $entry->{device_LABEL};
	my $w = Gtk2::Label->new($info);
	my @colorized_fs_types = qw(ext3 ext4 xfs swap vfat ntfs ntfs-3g);
        $ev = Gtk2::EventBox->new();
	$ev->add($w);
        my $part;
        if($resize) {
            ($part) = grep {$_->{device} eq "$entry->{device}"} @$resize;
        }
        if($resize && $part && !$desc) {
            $ev->set_name("PART_vfat");
            $w->set_size_request($ratio * $part->{min_win}, 0);
            my $ev2 = Gtk2::EventBox->new();
            my $b2 = Gtk2::Label->new("");
            $ev2->add($b2);
            $b2->set_size_request($ratio * MB(600), 0);
            $ev2->set_name("PART_ext4");
            
            my $hpane = Gtk2::HPaned->new();
            $hpane->add1($ev);
            $hpane->child1_shrink(0);
            $hpane->add2($ev2);
            $hpane->child2_shrink(0);
            $hpane->set_position($ratio * $part->{min_win});
            ugtk2::gtkset_size_request($hpane, $ratio * $part->{size}, 30);
            ugtk2::gtkpack__($display_box, $hpane);

            my $size = int($hpane->get_position / $ratio);

            $desc = ugtk2::gtkset_size_request(Gtk2::HBox->new(0,0), $width, 20);
            $ev = Gtk2::EventBox->new();
            $ev->add(Gtk2::Label->new(" " x 4));
            $ev->set_name("PART_vfat");
            ugtk2::gtkpack__($desc, $ev);
            ugtk2::gtkpack__($desc, Gtk2::Label->new(" Windows "));
            my $win_size_label = Gtk2::Label->new(sprintf("%10s", formatXiB($size, 512)));
            $desc->add($win_size_label);
            $ev = Gtk2::EventBox->new();
            $ev->add(Gtk2::Label->new(" " x 4));
            $ev->set_name("PART_ext4");
            ugtk2::gtkpack__($desc, $ev); 
            ugtk2::gtkpack__($desc, Gtk2::Label->new(" Mandriva "));
            my $mdv_size_label = Gtk2::Label->new(sprintf("%10s", formatXiB($part->{size}-$size, 512)));
            $desc->add($mdv_size_label);
            $hpane->signal_connect('size-allocate' => sub {
                my (undef, $alloc) = @_;
                $part->{width} = $alloc->width;
            });
            $hpane->signal_connect('motion-notify-event' => sub {
                $part->{req_size} = int($hpane->get_position * $part->{size} / $part->{width});
                $win_size_label->set_label(sprintf("%10s", formatXiB( $part->{req_size}, 512)));
                $mdv_size_label->set_label(sprintf("%10s", formatXiB($part->{size}- $part->{req_size}, 512)));
            });
        } else {
            if($fill_empty && isEmpty($entry)) {
                $w->set_text("Mandriva");
                $ev->set_name("PART_ext4");
            } else {
                $ev->set_name("PART_" . (isEmpty($entry) ? 'empty' : 
                                         $entry->{fs_type} && member($entry->{fs_type}, @colorized_fs_types) ? $entry->{fs_type} :
                                         'other'));
            }
            $w->set_size_request($entry->{size} * $ratio + $minwidth, 0);
            ugtk2::gtkpack__($display_box, $ev);
        }

	my $sep = Gtk2::Label->new(".");
	$ev = Gtk2::EventBox->new();
	$ev->add($sep);
	$sep->set_size_request(1, 0);

	ugtk2::gtkpack__($display_box, $ev);
    }
    $display_box->remove($ev);

    $vbox->add($display_box);
    $vbox->add($desc) if $desc;

    $vbox;
}

sub display_choices {
    my ($o, $contentbox, $mainw, %solutions) = @_;
    my @solutions = sort { $solutions{$b}->[0] <=> $solutions{$a}->[0] } keys %solutions;
    my @sol = grep { $solutions{$_}->[0] >= 0 } @solutions;
    
    log::l(''  . "solutions found: " . join('', map { $solutions{$_}->[1] } @sol) . 
           " (all solutions found: " . join('', map { $solutions{$_}->[1] } @solutions) . ")");
    
    @solutions = @sol if @sol > 1;
    log::l("solutions: ", int @solutions);
    @solutions or $o->ask_warn(N("Partitioning"), N("I can not find any room for installing")), die 'already displayed';
    
    log::l('HERE: ', join(',', map { $solutions{$_}->[1] } @solutions));
    
    $contentbox->foreach(sub { $contentbox->remove($_[0]) });
    
    $mainw->{kind}->{display_box} = create_display_box($mainw->{kind}) unless $mainw->{kind}->{display_box};
    ugtk2::gtkpack2__($contentbox, $mainw->{kind}->{display_box});
    ugtk2::gtkpack__($contentbox, ugtk2::gtknew('Label',
                                                text => N("The DrakX Partitioning wizard found the following solutions:"),
                                                alignment=> [0, 0]));
    
    my $choicesbox = ugtk2::gtknew('VBox');
    my $button;
    my $sep;
    foreach my $s (@solutions) {
        my $item;
        if($s eq 'free_space') {
            $item = create_display_box($mainw->{kind}, undef, 1);
        } elsif($s eq 'resize_fat') {
            $item = create_display_box($mainw->{kind}, $solutions{$s}->[3]);
        } elsif($s eq 'existing_part') {
        } elsif($s eq 'wipe_drive') {
            $item = Gtk2::EventBox->new();
            my $b2 = Gtk2::Label->new("Mandriva");
            $item->add($b2);
            $b2->set_size_request(516,30);
            $item->set_name("PART_ext4");
        } elsif($s eq 'diskdrake') {
        } else {
            log::l("$s");
            next;
        }
        $button = ugtk2::gtknew('RadioButton',
                                child => ugtk2::gtknew('VBox',
                                                       children_tight => [
                                                           ugtk2::gtknew('Label',
                                                                         text => $solutions{$s}->[1],
                                                                         alignment=> [0, 0]),
                                                           if_(defined($item), $item)
                                                       ],
                                ),
                                $button?(group=>$button->get_group):());
        $button->signal_connect('pressed', sub {$mainw->{sol} = $solutions{$s}; });
        ugtk2::gtkpack2__($choicesbox, $button);
        $sep = ugtk2::gtknew('HSeparator');
        ugtk2::gtkpack2__($choicesbox, $sep);
    }
    $choicesbox->remove($sep);
    ugtk2::gtkadd($contentbox, $choicesbox);
    $mainw->{sol} = $solutions{@solutions[0]}
}

sub main {
    my ($o, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab, $b_nodiskdrake) = @_;

    my $sol;

    if ($o->{interactive} eq 'gtk') {
        use ugtk2;
    
        my $mainw = ugtk2->new(N("Partitioning"), %$o, if__($::main_window, transient => $::main_window));
        $mainw->{box_allow_grow} = 1;
        
        mygtk2::set_main_window_size($mainw->{rwindow});
        
        use diskdrake::hd_gtk;
        diskdrake::hd_gtk::load_theme();

        my $mainbox = Gtk2::VBox->new();

        my @kinds = map { diskdrake::hd_gtk::hd2kind($_) } @{$all_hds->{hds}};

        my $hdchoice = Gtk2::HBox->new();
    
        my $hdchoicelabel = Gtk2::Label->new(N("Here is the content of you disk drive "));

        my $combobox = Gtk2::ComboBox->new_text;
        foreach (@kinds) {
            my $info = $_->{val}->{info};
            $info .= " (".formatXiB($_->{val}->{totalsectors}, 512).")" if $_->{val}->{totalsectors};
            $combobox->append_text($info);
        }
        $combobox->set_active(0);
        
        ugtk2::gtkpack2__($hdchoice, $hdchoicelabel);
        $hdchoice->add($combobox);
        
        ugtk2::gtkpack2__($mainbox, $hdchoice);
        
        my $contentbox = Gtk2::VBox->new(0, 24);
        $mainbox->add($contentbox);

        my $kind = @kinds[$combobox->get_active];
        my %solutions = partitionWizardSolutions($o, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab, diskdrake::hd_gtk::kind2hd($kind));
        delete $solutions{diskdrake} if $b_nodiskdrake;
        $mainw->{kind} = $kind;
        display_choices($o, $contentbox, $mainw, %solutions);
        
        $combobox->signal_connect("changed", sub {        
            $mainw->{kind} = @kinds[$combobox->get_active];
            my %solutions = partitionWizardSolutions($o, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab, diskdrake::hd_gtk::kind2hd($mainw->{kind}));
            delete $solutions{diskdrake} if $b_nodiskdrake;
            display_choices($o, $contentbox, $mainw, %solutions);
            $mainw->{window}->show_all;
        });

        my @more_buttons = (
            [ ugtk2::gtknew('Install_Button',
                            text => N("Help"),
                            clicked => sub { display_help($o, {interactive_help_id => 'doPartitionDisks'}, $mainw) }),
              undef, 1 ],
            );
        $::Wizard_no_previous = 1;
        my $buttons_pack = $mainw->create_okcancel(N("Next"), undef, '', @more_buttons);
        $mainbox->pack_end($buttons_pack, 0, 0, 0);
        ugtk2::gtkadd($mainw->{window}, $mainbox);
        $mainw->{window}->show_all;
        
        $mainw->main();

        $sol=$mainw->{sol};
    } else {
        my %solutions = partitionWizardSolutions($o, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab);

        delete $solutions{diskdrake} if $b_nodiskdrake;
        
        my @solutions = sort { $b->[0] <=> $a->[0] } values %solutions;

        my @sol = grep { $_->[0] >= 0 } @solutions;
        log::l(''  . "solutions found: " . join('', map { $_->[1] } @sol) . 
               " (all solutions found: " . join('', map { $_->[1] } @solutions) . ")");
        @solutions = @sol if @sol > 1;
        log::l("solutions: ", int @solutions);
        @solutions or $o->ask_warn(N("Partitioning"), N("I can not find any room for installing")), die 'already displayed';
        log::l('HERE: ', join(',', map { $_->[1] } @solutions));
        $o->ask_from_({ 
            title => N("Partitioning"),
            interactive_help_id => 'doPartitionDisks',
                      },
                      [
                       { label => N("The DrakX Partitioning wizard found the following solutions:"),  title => $::isInstall },
                       { val => \$sol, list => \@solutions, format => sub { $_[0][1] }, type => 'list' },
                      ]);
    }
    log::l("partitionWizard calling solution $sol->[1]");
    my $ok = eval { $sol->[2]->() };
    if (my $err = $@) {
        if ($err =~ /wizcancel/) {
            $_->destroy foreach $::WizardTable->get_children;
        } else {
            $o->ask_warn('', N("Partitioning failed: %s", formatError($err)));
        }
    }
    $ok or goto &main;
    1;
}

1;
