use strict;

sub set_clock {
    my $ui = ui_name("main");
    
    my @a = localtime;
    if($config{clockdelta}) {
	my($t) = ($a[2] * 60) + $a[1] + $config{clockdelta};
	$t += (60 * 24) if ($t < 0);
	$t -= (60 * 24) if ($t >= (60 * 24));
	$a[2] = int($t / 60);
	$a[1] = $t % 60;
    }
    my($ampm);
    if(defined $config{clocktype}) {
	if($a[2] >= 12 && $config{clocktype} eq '12') {
	    $ampm = 'p';
	    $a[2] -= 12 if $a[2] > 12;
	}
	elsif($a[2] < 12 && $config{clocktype} eq '12') {
	    $ampm = 'a';
	}
	
	$ui->set(clock => sprintf("%02d:%02d%s", $a[2], $a[1], $ampm));
	return;
    }
}    

sub set_serverstatus {
    my $ui     = ui_name("main");
    my $server = server_name();
    return unless ($server);
    
    my $sname = $server->state(DATA => 1,
			       NAME => "NAME");
    $ui->set(server => $sname) if (defined $sname);
    
    my($name, %state);
    $name  = $server->user_name();
    return unless defined($name);
    
    %state = $server->state(NAME => $name);
    
    $name .= " [$state{BLURB}]" if ($state{BLURB} =~ /\S/);
    $ui->set(nameblurb => $name);
    $ui->set(state => $state{STATE}) if defined($state{STATE});
    
    return;
}


sub load {
    my $ui = ui_name("main");
    my $server = server_name();
    
    $ui->define(nameblurb => 'left');
    $ui->define(clock     => 'right');
    $ui->define(state     => 'right');
    $ui->define(server    => 'right');
    
    my $sec = (localtime)[0];
    set_clock();
    TLily::Event::time_r(after    => 60 - $sec,
			 interval => 60,
			 call     => \&set_clock);
    
    if ($server) {
	set_serverstatus();
    } else {
	event_r(type => 'userstate',
			      call => \&set_serverstatus);
	
	event_r(type => 'rename',
			      call => \&set_serverstatus);
	
	event_r(type => 'blurb',
			      call => \&set_serverstatus);

	event_r(type => 'connected',
			      call => \&set_serverstatus);
    }
}
