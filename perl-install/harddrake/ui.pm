package harddrake::ui;

use strict;

use harddrake::data;
use common;
use interactive;
use my_gtk qw(:helpers :wrappers);
use ugtk qw(:helpers :wrappers :various);


# { field => [ short_translation, full_description] }
my %fields = 
    (
	"Model" => [_("Model"), _("hard disk model")],
	"channel" => [_("Channel"), _("EIDE/SCSI channel")],
	"bus" => 
	[ _("Bus"), 
	  _("this is the physical bus on which the device is plugged (eg: PCI, USB, ...)")],
	"driver" => [ _("Module"), _("the module of the GNU/Linux kernel that handle that device")],
	"media_type" => [ _("Media class"), _("class of hardware device")],
	"description" => [ _("Description"), _("this field describe the device")],
	"bus_id" => 
	[ _("Bus identification"), 
	  _("- PCI and USB devices : this list the vendor, device, subvendor and subdevice PCI/USB ids")],
	"bus_location" => 
	[ _("Location on the bus"), 
	  _("- pci devices: this gives the PCI slot, device and function of this card
- eide devices: the device is either a slave or a master device
- scsi devices: the scsi bus and the scsi device ids")],
	"device" => [ _("Old device file"),
			    _("old static device name used in dev package")],
	"devfs_device" => [ _("New devfs device"),  
					_("new dinamic device name generated by incore kernel devfs")],
	"nbuttons" => [ _("Number of buttons"), "the number of buttons the mouse have"],
	"Vendor" => [ _("Vendor"), _("the vendor name of the device")]
	);


our $license ='Copyright (C) 1999-2002 MandrakeSoft by tvignaud@mandrakesoft.com

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
';

my ($in, $main_win, %IDs);

my @menu_items = ( { path => _("/_File"), type => '<Branch>' },
			    { path => _("/_File")._("/_Quit"), accelerator => _("<control>Q"), callback => \&quit_global	},
			    { path => _("/_Help"),type => '<Branch>' },
			    { path => _("/_Help")._("/_Help..."), callback => sub {
				   $in->ask_warn(_("Harddrake help"), 
							  _("Description of the fields:\n\n")
							  . join("\n\n", map { "$fields{$_}[0]: $fields{$_}[1]"} keys %fields));
			    }
			  },
			    { path => _("/_Help")._("/_About..."), callback => sub {
				   $in->ask_warn(_("About Harddrake"), 
							  join ("", _("This is HardDrake, a Mandrake hardware configuration tool.\nVersion:"), " $harddrake::data::version\n", 
								   _("Author:")," Thierry Vignaud <tvignaud\@mandrakesoft.com> \n\n" ,
								   formatAlaTeX($license)));
			    }
			  },
			    );

sub new {
    my ($pid, $sig_id);

    $in = 'interactive'->vnew('su', 'default');
    add_icon_path('/usr/share/pixmaps/harddrake2/');
    $main_win = $::isEmbedded ? new Gtk::Plug ($::XID) : new Gtk::Window -toplevel;
    $main_win->set_title(_("Harddrake2 version ") . $harddrake::data::version);
    $main_win->set_default_size(760, 350); # 760 should be ok for most wm in 800x600
    $main_win->set_policy(0, 1, 0);


    my $widget = new Gtk::ItemFactory('Gtk::MenuBar', '<main>', my $accel_group = new Gtk::AccelGroup);
    $widget->create_items(@menu_items);
    $main_win->add_accel_group($accel_group); #$accel_group->attach($main_win);

    gtkadd($main_win, my $main_vbox = gtkadd(gtkadd(gtkadd(new Gtk::VBox(0, 0), my $menubar = $widget->get_widget('<main>')), $widget = new Gtk::HPaned), my $statusbar = new Gtk::Statusbar));
    $main_vbox->set_child_packing($statusbar, 0, 0, 0, 'start');
    $main_vbox->set_child_packing($menubar, 0, 0, 0, 'start');

    $widget->pack1(gtkadd(new Gtk::Frame(_("Detected hardware")), createScrolledWindow(my $tree = new Gtk::Tree)), 1, 1);
    $widget->pack2(my $vbox = gtkadd(gtkadd(gtkadd(new Gtk::VBox, gtkadd(new Gtk::Frame(_("Informations")), gtkadd(new Gtk::HBox, createScrolledWindow(my $text = new Gtk::Text)))), my $module_cfg_button = new Gtk::Button(_("Configure module"))), my $config_button = new Gtk::Button(_("Run config tool"))),1,1);
    $vbox->set_child_packing($config_button, 0, 0, 0, 'start');
    $vbox->set_child_packing($module_cfg_button, 0, 0, 0, 'start');

    my $wait = $in->wait_message(_("Please wait"), _("Detection in progress"));

    $tree->append(my $root = new Gtk::TreeItem);

    $root->set_subtree(my $main_subtree = new Gtk::Tree);
    $main_subtree->show();
    
    foreach (@harddrake::data::tree){
	   my ($Ident, $title, $icon, $configurator, $detector) = @$_;
	   next if (ref($detector) ne "CODE"); #skip class witouth detector
	   my @devices = &$detector;
	   next if (!listlength(@devices)); # Skip empty class (no devices)
	   my ($hw_class_item, $hw_class_tree) = (new Gtk::TreeItem, new Gtk::Tree);
	   $main_subtree->append($hw_class_item);
	   $hw_class_item->signal_connect(select  => sub {
		  $text->backward_delete($text->get_point); # erase all previous text
		  $config_button->hide;
		  $module_cfg_button->hide;
	   }, , "");
	   
	   ugtk::tree_set_icon($hw_class_item, $title, $icon);
	   $hw_class_item->show();
	   $hw_class_item->set_subtree($hw_class_tree);
	   $hw_class_item->expand unless ($title =~ /Unknown/ );

	   foreach (@devices) {
		  if (exists $_->{bus} && $_->{bus} eq "PCI") {
			 my $i = $_;
			 $_->{bus_id} = join ':', map { if_($i->{$_} ne "65535",  sprintf("%lx", $i->{$_})) } qw(vendor id subvendor subid);
			 $_->{bus_location} = join ':', map { sprintf("%lx", $i->{$_} ) } qw(pci_bus pci_device pci_function);
		  }
		  # split description into manufacturer/description
		  ($_->{Vendor},$_->{description})=split(/\|/,$_->{description}) if exists $_->{description};
		  
		  if (exists $_->{val}) { # Scanner ?
			  my $val = $_->{val};
			  ($_->{Vendor},$_->{description}) = split(/\|/, $val->{DESCRIPTION});
		  }
		  # EIDE detection incoherency:
		  if (exists $_->{bus} && $_->{bus} eq 'ide') {
			 $_->{channel} = _($_->{channel} ? "secondary" : "primary");
			delete $_->{info};
		  } elsif ((exists $_->{id}) && ($_->{bus} ne 'PCI')) {
			 # SCSI detection incoherency:
			 my $i = $_;
			 $_->{bus_location} =  join ':', map { sprintf("%lx", $i->{$_} ) } qw(bus id);
		  }
		  foreach my $i (qw(vendor id subvendor subid pci_bus pci_device pci_function MOUSETYPE XMOUSETYPE unsafe val devfs_prefix wacom auxmouse)) { 
			 delete $_->{$i};
		  }
		  my $hw_item = new Gtk::TreeItem(defined($_->{device})? $_->{device}:
				(defined($_->{description})?$_->{description}:$title));
		  $_->{device}='/dev/'.$_->{device} if exists $_->{device};
		  $hw_class_tree->append($hw_item);
		  $hw_item->expand;
		  $hw_item->show;
		  my $data = $_;
		  $hw_item->signal_handlers_destroy();
		  $hw_item->signal_connect(select => sub {
			 $_ = $data;
			 $text->hide;
			 $text->backward_delete($text->get_point);
			 my $i = $_;
			 $text->insert("","","", join("\n", map { ($fields{$_}[0] ? $fields{$_}[0] : $_) . ": $i->{$_}\n"} sort keys %$i));
			 disconnect($module_cfg_button, 'module');
			 if (exists $_->{driver} &&  $_->{driver} ne "unknown" &&  $_->{driver} !~ /^Card:/) {
				$module_cfg_button->show;
				 $IDs{module} = $module_cfg_button->signal_connect(clicked => sub {
				    require modules;
				    modules::mergein_conf('/etc/modules.conf');
				    my (@l, %conf);
				    foreach (split(' ', modules::get_options($_->{driver}))) {
					   /(.*)=(.*)/;
					   $conf{$1} = $2;
				    };
				    require modparm;
				    foreach (modparm::parameters($_->{driver})) {
					   my ($name, $format, $description) = @$_;
					   push @l, { label => $name, help => "$description\n[$format]", val => \$conf{$name} };
				    }
				    if ($in->ask_from("Module configuration", _("You can configure each parameter of the module here."), \@l)) {
					   my $options = join(' ', map { if_($conf{$_}, "$_=$conf{$_}") } keys %conf);
					   if ($options) {
						  modules::set_options($_->{driver}, $options);
						  modules::write_conf;
					   }
				    }
				    gtkset_mousecursor_normal();
				});
			 }
			 disconnect($config_button, 'tool');
			 $text->show;
			 return unless -x $configurator;
			 $IDs{tool} = $config_button->signal_connect(clicked => sub {
				return if defined $pid;
				if ($pid = fork()) {
				    my $id = $statusbar->get_context_id("id");
				    $sig_id = $statusbar->push($id, _("Running \"%s\" ...", $configurator));
				} else { exec($configurator) or die "$configurator missing\n" }
			 }) ;
			 $config_button->show;
		  });
	   }
    }
    
    $SIG{CHLD} = sub { undef $pid; $statusbar->pop($sig_id) };
    $main_win->signal_connect (delete_event => \&quit_global);
    undef $wait;
    gtkset_mousecursor_normal();
    $main_win->set_position('center');
    $main_win->show_all();
    foreach ($module_cfg_button, $config_button) { $_->hide };
    Gtk->main;
}


sub quit_global {
    $main_win->destroy;
    $in->exit;
}

sub disconnect {
    my ($button, $id) = @_;
    if ($IDs{$id}) {
	   $button->signal_disconnect($IDs{$id});
	   $button->hide;
	   undef $IDs{$id};
    }
}

1;
