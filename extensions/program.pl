# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/program.pl,v 1.14 1999/12/20 20:37:25 mjr Exp $

$perms = undef;

sub verb_set(%) {
  my %args=@_;
  my $verb_spec=$args{'verb_spec'};
  my $edit=$args{'edit'};
  my $ui = $args{'ui'};

  my $tmpfile = "$::TL_TMPDIR/tlily.$$";

  my $server = $verb_spec->[0];
  my $verb_str = $server->name() . "::" . join(":", @{$verb_spec}[1..2]);

  if ($edit) {
    edit_text($ui, $args{'data'}) or return;
  }

  # If the server detected an error, try to save the verb to a dead file.
  my $id = event_r(type => 'text', order => 'after',
          call => sub {
              my($event,$handler) = @_;
              my $escaped_verbstr = $verb_str;
              $escaped_verbstr =~ s|/|,|g;
              my $deadfile = $ENV{HOME}."/.lily/tlily/dead.verb.$escaped_verbstr";
              if ($event->{text} =~ /^Verb (not )?programmed\./) {
                event_u($handler);

                unlink($deadfile);
                if ($1) {
                  local *DF;
                  my $rc = open(DF, ">$deadfile");
                  if (!$rc) {
                      $ui->print("(Unable to save verb: $!)\n");
                      return 0;
                  }

                  foreach my $l (@{$args{'data'}}) {
                      print DF $l, "\n";
                  }
                  $ui->print("(Saved verb to dead.verb.$escaped_verbstr)\n");
                }
                unlink($tmpfile);
              }
              return 0;
          }
        );
  $server->sendln("\@program " . join(":", @{$verb_spec}[1..2]));
  foreach (@{$args{'data'}}) { chomp; $server->sendln($_) }
  $server->sendln(".");
}

sub verb_showlist {
    my ($cmd, $ui, $verb_spec) = @_;
    my ($server, $obj, $verb) = @{$verb_spec};

    unless (defined($obj)) {
        $ui->print("Usage: %verb $cmd [server::]object[:verb]\n");
        return 0;
    }

    if (defined($verb)) {
        $server->sendln("\@list $obj:$verb") if ($cmd eq 'list');
        $server->sendln("\@show $obj:$verb") if ($cmd eq 'show');
    } else {
        my @lines = ();
        $server->cmd_process("\@show $obj", sub {
            my($event) = @_;
            $event->{NOTIFY} = 0;
            if ($event->{type} eq 'endcmd') {
                my $objRef = parse_show_obj(@lines);
                if (scalar(@{$objRef->{verbdefs}}) > 0) {
                    $ui->print(join("\n", @{columnize_list($ui, $objRef->{verbdefs})}, ""));
                } else {
                    $ui->print("(No verbs defined on $obj)\n");
                }
            } elsif ( $event->{type} ne 'begincmd' ) {
                my $l = $event->{text};
                if ( $l =~ /^Can\'t find anything named \'$obj\'\./ ) {
                    $event->{NOTIFY} = 1;
                    return 1;
                }
                push @lines, $l;
            }
            return 0;
        });
    }
}

sub obj_show {
  my ($cmd, $ui, $obj_spec) = @_;
  my $master = 0;
  my ($server, $obj) = @{$obj_spec};

  unless (defined($obj)) {
    $ui->print("Usage: %obj show [server::]{object|'master'}\n");
    return 0;
  }

  my @lines = ();

  if ($obj eq 'master') {
    $obj = '#0';
    $master = 1;
  }

  $server->cmd_process("\@show $obj", sub {
      my($event) = @_;
      # User doesn't want to see output of @show
      $event->{NOTIFY} = 0;
      if ($event->{type} eq 'endcmd') {
        # We've received all the output from @show. Now call parse_show_obj()
        # to parse the output for @show into something more easily usable.
        my $objRef = parse_show_obj(@lines);
        if ($master) {
          my @masterObjs = ();

          foreach my $prop (keys %{$objRef->{props}}) {
            push(@masterObjs, "\$$prop") if ($objRef->{props}{$prop} =~ /^#\d+$/);
          }
          $ui->print(join("\n", @{columnize_list($ui, [sort @masterObjs])},""));
        } else {
          $ui->print("Object: " . $objRef->{objid} .
              (($objRef->{name} ne "")?(" (" . $objRef->{name} . ")\n"):"\n"));
          $ui->print("Parent: " . $objRef->{parentid} .
              (($objRef->{parent} ne "")?(" (" . $objRef->{parent} . ")\n"):"\n"));
          $ui->print("Owner: " . $objRef->{ownerid} .
              (($objRef->{owner} ne "")?(" (" . $objRef->{owner} . ")\n"):"\n"));
          $ui->print("Flags: " . $objRef->{flags} . "\n");
          $ui->print("Location: " . $objRef->{location} . "\n");
        }
      } elsif ( $event->{type} ne 'begincmd' ) {
        my $l = $event->{text};
        if ( $l =~ /^Can\'t find anything named \'$obj\'\./ ) {
          $event->{NOTIFY} = 1;
          return 1;
        }
        push @lines, $l;
      }
      return 0;
  });
}

sub prop_show {
  my ($cmd, $ui, $prop_spec) = @_;

  my ($server, $obj, $prop) = @{$prop_spec};

  unless (defined($obj)) {
    $ui->print("Usage: %prop show[all] [server::]object[.prop]\n");
    return 0;
  }

  my @lines = ();

  # If $prop is defined, we were given a specific property to look at.  Do so.
  if (defined($prop)) {
    $server->sendln("\@show $obj.$prop");
  } else {
    # We need to list the properties on the object.  We will fire off
    # a @show cmd, and process the output to get the info we need.
    $server->cmd_process("\@show $obj", sub {
        my($event) = @_;
        # User doesn't want to see output of @show
        $event->{NOTIFY} = 0;
        if ($event->{type} eq 'endcmd') {
          # We've received all the output from @show. Now call parse_show_obj()
          # to parse the output for @show into something more easily usable.
          my $objRef = parse_show_obj(@lines);

          # OK - now to make a list of properties.  We have two lists to
          # choose from: properties directly defined on the object, or
          # all properties (including inherited ones).
          my @propList = ();
          if ($cmd eq 'show') {
            @propList = sort(@{$objRef->{propdefs}});
          } elsif ($cmd eq 'showall') {
            # User wants inherited properties too.
            @propList = sort(keys %{$objRef->{props}});
          }
          if (scalar(@propList) > 0) {
            $ui->print(join("\n", @{columnize_list($ui, \@propList)},""));
          } else {
            $ui->print("(No properties on $obj)\n");
          }
        } elsif ( $event->{type} ne 'begincmd' ) {
          my $l = $event->{text};
          if ( $l =~ /^Can\'t find anything named \'$obj\'\./ ) {
            $event->{NOTIFY} = 1;
            return 1;
          }
          push @lines, $l;
        }
        return 0;
    });
  }
}

sub parse_show_obj(@) {
  my $obj = {};

  foreach $l (@_) {
    chomp $l;
    if ( $l =~ /^Object ID:\s*(#\d+)/ ) {
      $obj->{objid} = $1;
    } elsif ( $l =~ /^Name:\s*(.*)/ ) {
      $obj->{name} = $1;
    } elsif ( $l =~ /^Parent:\s*([^\(]*)\s+\((#\d+)\)/ ) {
      $obj->{parent} = $1;
      $obj->{parentid} = $2;
    } elsif ( $l =~ /^Location:\s*(.*)/ ) {
      $obj->{location} = $1;
    } elsif ( $l =~ /^Owner:\s*([^\(]*)\s+\((#\d+)\)/ ) {
      $obj->{owner} = $1;
      $obj->{ownerid} = $2;
    } elsif ( $l =~ /^Flags:\s*(.*)/ ) {
      $obj->{flags} = $1;
    } elsif ( $l =~ /^Verb definitions:/ ) {
      $mode = "verbdef";
    } elsif ( $l =~ /^Property definitions:/ ) {
      $mode = "propdef";
    } elsif ( $l =~ /^Properties:/ ) {
      $mode = "prop";
    } elsif ( $l =~ /^\s+/g ) {
      if ($mode eq "verbdef") {
        $l =~ /\G(.+)$/g;
        push @{$obj->{verbdefs}}, $1;
      } elsif ($mode eq "propdef") {
        $l =~ /\G(.+)$/g;
        push @{$obj->{propdefs}}, $1;
      } elsif ($mode eq "prop") {
        $l =~ /\G([^:]+):\s+(.*)$/g;
        $obj->{props}{$1} = $2;
      }
    }
  }
  return $obj;
}

sub obj_cmd {
    my $ui = shift;
    my ($cmd,@args) = split /\s+/, "@_";
    my $obj_str = shift @args;
    my $obj_spec = [];

    # Attempt to split out the obj spec string.
    unless ($obj_str =~ /^(?:(.+)::)?(\#\-?\d+|\$[^:]+|master)$/i) {
      $ui->print("Usage: %obj cmd [server::]{object|'master'}\n");
      return 0;
    }
    @{$obj_spec} = ($1, $2);

    # Attempt to translate the servername given to a server object, or
    # the current active server if no name is given.
    my $server = TLily::Server::active();
    $server = TLily::Server::find($obj_spec->[0]) if ($obj_spec->[0]);
    unless (defined($server)) {
        $ui->print("No such server \"" . $obj_spec->[0] . "\"\n");
        return 0;
    }
    $obj_spec->[0] = $server;

    if ($cmd eq 'show') {
        obj_show($cmd, $ui, $obj_spec);
    } else {
        $ui->print("(unknown %obj command)\n");
    }
}

sub prop_cmd {
    my $ui = shift;
    my ($cmd,@args) = split /\s+/, "@_";
    my ($prop_str, $prop_val) = shift @args;

    # Attempt to split out the obj spec string.
    if ($prop_str =~ /^(?:(.+)::)?(\#\-?\d+|\$[^.]+)(?:\.(.+))?$/) {
        @{$prop_spec} = ($1, $2, $3);

        # Attempt to translate the servername given to a server object, or
        # the current active server if no name is given.
        my $server = TLily::Server::active();
        $server = TLily::Server::find($prop_spec->[0]) if ($prop_spec->[0]);
        unless (defined($server)) {
            $ui->print("No such server \"" . $prop_spec->[0] . "\"\n");
            return 0;
        }
        $prop_spec->[0] = $server;

        if ($cmd =~ /^show(?:all)?$/) {
            prop_show($cmd, $ui, $prop_spec);
        } elsif ($cmd =~ /^set$/) {
            if (defined($prop_spec->[2]) && defined($prop_val)) {
                $server->sendln("\@eval " . join(".", @{$prop_spec}[1..2])
                                . " = $prop_val");
            } else {
                $ui->print("Usage: %prop set object.verb moo-value\n");
            }
        } else {
            $ui->print("(unknown %prop command)\n");
        }
    } else {
        $ui->print("Usage: %prop set [server::]object.prop moo-value\n") if ($cmd eq 'set');
        $ui->print("Usage: %prop show[all] [server::]object.prop\n") if ($cmd ne 'set');
    }
    return 0;
}

sub verb_cmd {
    my $ui = shift;
    my ($cmd,@args) = split /\s+/, "@_";
    my $verb_str = shift @args;
    my $verb_spec = [];

    # Attempt to split out the verb spec string.
    goto verb_cmd_usage
      unless ($verb_str =~ /^(?:(.+)::)?(\#\-?\d+|\$[^:]+)(?::(.+))?$/);

    @{$verb_spec} = ($1, $2, $3);

    # Attempt to translate the servername given to a server object, or
    # the current active server if no name is given.
    my $server = TLily::Server::active();
    $server = TLily::Server::find($verb_spec->[0]) if ($verb_spec->[0]);
    unless (defined($server)) {
        $ui->print("No such server " . $verb_spec->[0] . "\n");
        return 0;
    }
    $verb_spec->[0] = $server;

    if ($cmd eq 'show' || $cmd eq 'list') {
        verb_showlist($cmd, $ui, $verb_spec);
    } elsif ($cmd eq 'diff' || $cmd eq 'copy') {
        my $verb2_str = shift @args;
        my $verb2_spec = [];
        my $server = TLily::Server::active();

        # Attempt to split out the verb spec string.
        goto verb_cmd_usage
          unless ($verb2_str =~ /^(?:(.+)::)?(\#\-?\d+|\$[^:]+)(?::(.+))?$/);
      
        # Attempt to translate the servername given to a server object, or
        # the current active server if no name is given.
        @{$verb2_spec} = ($1, $2, $3);
        $server = TLily::Server::find($verb2_spec->[0]) if ($verb2_spec->[0]);
        unless (defined($server)) {
            $ui->print("No such server " . $verb2_spec->[0] . "\n");
            return 0;
        }
        $verb2_spec->[0] = $server;

        verb_diff($cmd, $ui, $verb_spec, $verb2_spec) if ($cmd eq 'diff');
        verb_copy($cmd, $ui, $verb_spec, $verb2_spec) if ($cmd eq 'copy');
    } elsif ($cmd eq 'reedit') {
        # First generate the name of the file we think the dead verb would
        # be stored in.  Besure to translate the '/' chars into ',' chars.
        my $escaped_verbstr =
          $server->name() . "::" . join(":", @{$verb_spec}[1..2]);
        $escaped_verbstr =~ s|/|,|g;
        my $deadfile = $ENV{HOME}."/.lily/tlily/dead.verb.$escaped_verbstr";

        # Now attempt to open and snarf in the file.
        local *DF;
        my $rc = open(DF, "$deadfile");
        if (!$rc) {
            $ui->print("(Unable to recall verb from $escaped_verbstr: $!)\n");
        } else {
            my $lines = [];
            @{$lines} = <DF>;
            close DF;

            # Got the file, fire up the editor.
            verb_set(verb_spec => $verb_spec,
                     data      => $lines,
                     edit      => 1,
                     ui        => $ui);
        }
    } elsif ($cmd eq 'edit') {
        # Set up the callback that will check for errors and fire up the
        # editor if we managed to get the verb.
        my $sub = sub {
            my(%args) = @_;

            if (($args{text}[0] =~ /^That object does not define that verb\.$/) ||
              ($args{text}[0] =~ /^Invalid object \'.*\'\.$/)) {
                # Encountered an error.
                $args{ui}->print($args{text}[0] . "\n");
                return;
            } elsif ($args{text}[0] =~/^That verb has not been programmed\.$/) {
                # Verb exists, but there's no code for it yet.
                # We'll provide a comment saying so as the verb code.
                @{$args{text}} = ("/* This verb $verb_str has not yet been written. */");
            }

            verb_set(verb_spec => $verb_spec,
                     data      => $args{text},
                     edit      => 1,
                     ui        => $args{ui});
        };

        # Now try to fetch the verb.
        $server->fetch(ui     => $ui,
                       type   => "verb",
                       target => join(":", @{$verb_spec}[1..2]),
                       call   => $sub);

    } else {
verb_cmd_usage:
        $ui->print("Usage: %verb show|list [server::]object[:verb]\n");
        $ui->print("       %verb [re]edit [server::]object:verb\n");
        $ui->print("       %verb diff [server::]object:verb [server::]object:verb\n");
    }
    return 0;
}


sub verb_copy {
    my ($cmd, $ui, $verb1, $verb2) = @_;

    my $server1 = $verb1->[0];
    my $server2 = $verb2->[0];

    my $sub = sub {
        my(%args) = @_;

        if (($args{text}[0] =~ /^That object does not define that verb\.$/)
             || ($args{text}[0] =~ /^Invalid object \'.*\'\.$/)) {
            # Encountered an error.
            $args{ui}->print($args{server} . ": " . $args{text}[0] . "\n");
            return;
        } elsif ($args{text}[0] =~/^That verb has not been programmed\.$/) {
            # Verb exists, but there's no code for it yet.
            # We'll provide a comment saying so as the verb code.
            @{$args{text}} = ();
        }

        verb_set(verb_spec => $verb2,
                 data      => $args{text},
                 edit      => 0,
                 ui        => $ui);
    };

    $ui->print("(Copying verb ", scalar $verb1->[0]->name, "::", $verb1->[1], ":", $verb1->[2], " to ", scalar $verb2->[0]->name, "::", $verb2->[1], ":", $verb2->[2], ")\n");
    $server1->fetch(ui     => $ui,
                    type   => "verb",
                    target => $verb1->[1] . ':' . $verb1->[2],
                    call   => $sub);

}

sub verb_diff {
    my ($cmd, $ui, $verb1, $verb2) = @_;

    my $server1 = $verb1->[0];
    my $server2 = $verb2->[0];

    # A callback that will be called by both fetch()'s.  Once it has both
    # verbs, it will diff them.  This is a closure so we can preserve the
    # @data array between calls.
    my $subcon = sub {
        my @data = ();
        return sub {
            my(%args) = @_;

            if (($args{text}[0] =~ /^That object does not define that verb\.$/)
              || ($args{text}[0] =~ /^Invalid object \'.*\'\.$/)) {
                # Encountered an error.
                $args{ui}->print($args{server} . ": " . $args{text}[0] . "\n");
                return;
            } elsif ($args{text}[0] =~/^That verb has not been programmed\.$/) {
                # Verb exists, but there's no code for it yet.
                # We'll provide a comment saying so as the verb code.
                @{$args{text}} =
                  ("/* This verb $verb_spec has not yet been written. */");
            }

            # Put the text into a buffer.
            if ($args{server} == $server1) {
                $data[0] = $args{text};
            } else {
                $data[1] = $args{text};
            }

            # if we have both verbs, do the diff.
            if (defined($data[0]) && defined($data[1])) {
                my $diff = diff_text(@data);

                foreach (@{$diff}) { $ui->print($_) };
            }
        }
    };

    my $sub = &$subcon;
   
    $ui->print("(Diffing verb ", scalar $verb1->[0]->name, "::", $verb1->[1], ":", $verb1->[2], " against ", scalar $verb2->[0]->name, "::", $verb2->[1], ":", $verb2->[2], ")\n");
    $server1->fetch(ui     => $ui,
                    type   => "verb",
                    target => $verb1->[1] . ':' . $verb1->[2],
                    call   => $sub);

    $server2->fetch(ui     => $ui,
                    type   => "verb",
                    target => $verb2->[1] . ':' . $verb2->[2],
                    call   => $sub);

}

# This is a bit nasty.
# We want to figure out whether the user loading this module has
# programmer privs on the server.
# We will be sending an oob command "#$# options +usertype" to get
# the server to tell us what permissions we have.  Unfortunately,
# if you have no special permissions, the server doesn't give you
# an explicit NACK.  Fortunately, it _does_ send an %options line
# immediately afterwards, so also register a handler to look for
# that, and if we encounter that without encountering the %user_type
# line, we know we don't have any privs, and we unload the extension.

# FOO:  This is not multiserver compliant; it should check the permissions
# on all servers.  Maybe it shouldn't unload itself anymore?

$server = TLily::Server::active();
$ui = ui_name();

$id = event_r(type => 'text', order => 'before',
              call => sub {
                  my($event,$handler) = @_;
                  if ($event->{text} =~ /%user_type ([pah]+)/) {
                    $event->{NOTIFY} = 0;
                    $perms = $1;
                    event_u($handler);
                  }
                  return 1;
              }
      );

event_r(type => 'options',
        call => sub {
            my($event,$handler) = @_;
            event_u($handler);
            event_u($id);
            if (grep(/usertype/, @{$event->{options}})) {
              if (!defined($perms) || $perms !~ /p/) {
                $ui->print("You do not have programmer permissions on this server.\n");
                TLily::Extend::unload("program",$ui,0);
              }
            }
            return 1;
        }
);

$server->sendln("\#\$\# options +usertype");

command_r('verb', \&verb_cmd);
command_r('prop', \&prop_cmd);
command_r('obj', \&obj_cmd);

shelp_r("verb", "MOO verb manipulation functions");
shelp_r("prop", "MOO property manipulation functions");
shelp_r("obj", "MOO object manipulation functions");

help_r("verb", "
%verb show <obj>           - Lists the verbs defined on an object.
%verb show <obj>:<verb>    - Shows a verb's properties.
%verb list <obj>           - Lists the verbs defined on a object.
%verb list <obj>:<verb>    - Lists the code of a verb.
%verb edit <obj>:<verb>    - Edit a verb.
%verb reedit <obj>:<verb>  - Recalls a \"dead\" verb from a failed edit.

");

help_r("prop", "
%prop show <obj>            - Lists the properties defined on a object.
%prop show <obj>:<prop>     - Shows a property.
%prop showall <obj>         - Lists the properties defined on a object,
                              including inherited properties.
%prop showall <obj>:<prop>  - Shows the property.

");

help_r("obj", "
%obj show <obj>     - Shows the base info on the given object.
%obj show master    - Lists the master objects.

");

1;
