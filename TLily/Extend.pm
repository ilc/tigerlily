# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/Extend.pm,v 1.5 1999/02/26 21:29:05 josh Exp $ 

# initial version, 10/24/97, Josh Wilmes

# Provide a secure environment for user extensions to TigerLily.  We use
# an ExoSafe to provide strict control over what the extensions have access to.

package TLily::Extend;
use strict;
use vars qw(%config);

use TLily::ExoSafe;
use TLily::Config qw(%config);
use TLily::Registrar;
use TLily::User;

my %extensions = ();
my @share=qw(%config);

sub load {
    my ($name, $ui, $verbose)=@_;
    my $filename;
    
    if (-f $name) {
	$filename = $name;
	# $name = basename($name);
	$name =~ s|.*[/\\]||;
	$name =~ s|\.pl$||i;
    }
    
    if (defined $extensions{$name}) {
	$ui->print("(extension \"$name\" already loaded)\n") if ($ui);
	return 1;
    }
    
    if (!defined $filename) {
	my @ext_dirs = ("$ENV{HOME}/.lily/tlily/extensions",
			$main::TL_EXTDIR);
	my $dir;
	foreach $dir (@ext_dirs) {
	    if (-f "${dir}/${name}.pl") {
		$filename = "${dir}/${name}.pl";
		last;
	    }
	}
    }
    
    if (!defined $filename) {
	$ui->print("(cannot locate extension \"$name\")\n") if ($ui);
	return;
    }
    
    $ui->print("(loading \"$name\" from \"$filename\")\n")
      if ($ui && $verbose);
    
    my $reg  = TLily::Registrar->new($name)->push_default;
    my $safe = ExoSafe->new;
    
    $safe->share(@share);
    # This only works in perl 5.003_07+
    $safe->share_from('main', [ qw($TL_VERSION %ENV %INC @INC $@ $] $$) ]);
    
    $safe->rdo($filename);
    unless ($@) {
	$safe->reval("load();");
	$@ = undef if ($@ && $@ =~ /Undefined subroutine \S+load /);
    }
    
    $reg->pop_default;
    
    if ($@) {
	$ui->print("* error: $@") if ($ui);
	$reg->unwind;
	return;
    }
    
    $extensions{$name} = { file => $filename,
			   safe => $safe,
			   reg  => $reg };
    return 1;
}


# Unload an extension.
sub unload {
    my($name, $ui, $verbose) = @_;
    
    if (!defined $extensions{$name}) {
	$ui->print("(extension \"$name\" is not loaded)\n") if ($ui);
	return; 
    }
    
    $ui->print("(unloading \"$name\")\n") if ($ui && $verbose);
    $extensions{$name}->{reg}->push_default;
    $extensions{$name}->{safe}->reval("unload();");
    $extensions{$name}->{reg}->pop_default;
    
    $extensions{$name}->{reg}->unwind;
    
    delete $extensions{$name};
}


# Snarf extensions out of standard locations.
sub load_extensions {
    my($ui) = @_;
    my $ext;
    foreach $ext (@{$config{'load'}}) {
	load($ext,$ui);
    }   
    
    extension_cmd($ui,"list");
}


sub extension_cmd {
    my($ui, $args) = @_;
    my @argv = split /\s+/, $args;
    
    my $cmd = shift @argv || "";
    
    if ($cmd eq 'load') {
	my $ext;
	foreach $ext (@argv) {
	    load($ext,$ui,1);
	}
    } elsif ($cmd eq 'unload') {
	my $ext;
	foreach $ext (@argv) {
	    unload($ext,$ui,1);
	}
    } elsif ($cmd eq 'reload') {
	my $ext;
	foreach $ext (@argv) {
	    if ($extensions{$ext}) {
		my $f = $extensions{$ext}->{file};
		unload($ext, $ui);
		load($f, $ui, 1);
	    } else {
		load($ext, $ui, 1);
	    }
	}
    } elsif ($cmd eq 'list') {
	$ui->print("(Loaded extensions: ");
	$ui->print(join(" ", sort keys %extensions));
	$ui->print(")\n");
    } else {
	$ui->print
	  ("(unknown %extension command: see %help extension)\n");
    }
}


sub cmd_init {
    TLily::User::command_r(extension => \&extension_cmd);
    TLily::User::shelp_r  (extension => "manage tlily extensions");
    TLily::User::help_r   (extension => "
usage: %extension list
       %extension load <extension>
       %extension unload <extension>
       %extension reload <extension>
");
}


1;
