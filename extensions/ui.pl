# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/ui.pl,v 1.24 2000/02/12 00:37:37 tale Exp $ 
use strict;

=head1 NAME

ui.pl - User Interface functions

=head1 DESCRIPTION

This extension contains %commands for dealing with the user interface.

=head1 COMMANDS

=over 10
=cut
#
# Keybindings.
#

=item %bind

Binds a key to a command.  See L<"%help bind"|%help bind> for details.

=cut

my $bind_help = qq{
Usage: %bind ["locally"] [key [command]]

%bind binds a key to a command.  The actual set of commands you can bind \
a key to is unfortunately poorly specified at this time.  If the \"locally\" \
argument is specified (or a substring thereof), the binding will apply only \
to the current UI; otherwise, it will be a global binding. \

If the command argument is not specified, the binding of the key in the \
current UI will be printed.

If the key argument is not specified, all bindings in the current UI \
will be printed, except for keys which do "insert-self".

(The 1 and 2 argument versions of %bind are currently only available with \
the Curses UI.)

(see also %keyname)
};

my $keyname_help = "
Usage: %keyname

Prints the name (suitable for use in %bind) of the next key pressed.

(see also %bind)
";

sub bind_command {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;
    my $local;

    if ($args[0] && index("locally", $args[0]) == 0 && length($args[0]) > 1) {
	shift @args;
	$local = 1;
    }

    if (@args < 2) {
        $local = 1;
    } elsif (@args > 2) {
	$ui->print("(%bind [locally] key command; type %help for help)\n");
	return;
    }

    $ui->print("(binding \"$args[0]\" to \"$args[1]\")\n") if @args > 1;
    if ($local) {
	$ui->bind(@args);
    } else {
	TLily::UI::bind(@args);
    }

    return;
}
command_r('bind' => \&bind_command);
shelp_r('bind' => "Bind a key to a command.");
help_r('bind' => $bind_help);


=item %key

Echos the key symbol of the next key pressed.  See L<"%help key"|%help key> for details.

=cut

sub name_self {
    my($ui, $command, $key) = @_;
    $ui->intercept_u($command);
    $ui->print("(you pressed \"$key\")\n");
    return 1;
}
TLily::UI::command_r("name-self" => \&name_self);


sub keyname_command {
    my($ui, $args) = @_;

    if ($args) {
	$ui->print("(%keyname; type %help for help)\n");
	return;
    }

    if (!$ui->intercept_r("name-self")) {
	$ui->print("(sorry; a keyboard intercept is already in place)\n");
	return;
    }

    $ui->print("Press any key.\n");
    return;
}
command_r(keyname => \&keyname_command);
shelp_r(keyname => "Print the name of the next key pressed.");
help_r(keyname => $keyname_help);


#
# Windows.
#

sub ui_command {
    my($ui, $args) = @_;
    my($cmd, @args) = split /\s+/, $args;

    #my $newui = TLily::UI::Curses->new(name => 'sub');
    #$newui->print("foo\n");
}
#command_r(ui => \&ui_command);


=item %page

Enables and disables output paging.  See L<"%help page"|%help page> for details.

=cut

#
# Paging.
#

my $page_help = "
Usage: %page [on | off]

%page enables and disables output paging.
";

sub page_command {
    my($ui, $args) = @_;

    if ($args eq "") {
	if ($ui->page()) {
		$ui->print("(paging is currently enabled)\n");
	} else {
		$ui->print("(paging is currently disabled)\n");
	}
    } elsif ($args eq "on") {
	$config{page} = 1;
	$ui->page(1);
	$ui->print("(paging is now enabled)\n");
    } elsif ($args eq "off") {
	$config{page} = 0;
	$ui->page(0);
	$ui->print("(paging is now disabled)\n");
    } else {
	$ui->print("(%page on|off; type %help for help)\n");
    }

    return;
}
command_r(page => \&page_command);
shelp_r(page => "Turn output paging on and off.");
help_r(page => $page_help);

=item Input Contexts

Input cut buffers.  See L<"%help icontext"|%help icontext> for details.

=cut

#
# Input contexts.
#

my $icontext_help = qq{
Have you ever typed in half of a very long send, when suddenly you want to \
make a quick send to someone else, or check if a person is on line?  Input \
contexts are designed to save the contents of the input buffer and return \
to it later.  If you press the next-input-context key (bound to C-x by \
default), your current input state is saved, and a new one opened.  Press \
the key again to move to the next input context.

An example may make this easier to understand.  Type "foo", and press C-x. \
The input line clears.  Press C-x again, and "foo" returns.  You can have \
more than one saved input context: Press C-x.  (The input line clears.)  \
Type "bar", and press C-x again.  The input line clears, as you move to a \
third input context.  Press C-x again, and you return to the first context
("foo").

(see also: %bind)
};

sub next_input_context {
    my($ui, $command, $key) = @_;
    my($pos, $line) = $ui->get_input;
    $ui->{input}->{_context} ||= [];
    my $context = $ui->{input}->{_context};

    my $cidx = $ui->{input}->{_context_idx} || 0;

    if (length $line) {
	$context->[$cidx] = [$pos, $line];
	$cidx++;
	$context->[$cidx] ||= [0, ""];
    }
    else {
	splice(@$context, $cidx, 1);
	$cidx = 0 if ($cidx >= @$context);
    }

    $ui->set_input(@{$context->[$cidx]});
    $ui->{input}->{_context_idx} = $cidx;
}
TLily::UI::command_r("next-input-context" => \&next_input_context);
TLily::UI::bind("C-x" => "next-input-context");
shelp_r("icontext" => "Input contexts let you defer sends until later.",
        "concepts");
help_r("icontext" => $icontext_help);

#
# Input history searching
#

=item Input History Searching

Allows you to search your input buffer for a string, as in bash.
See L<"%help isearch"|%help isearch> for details.

=cut

my $isearch_help = qq{
You can search your input buffer history (but not input contexts) for \
a string.  After switching into search mode (default key is C-r), each \
additional key will build a search string, and search backwards in your \
input buffer for that string.  If a character is typed that would cause \
the string not to be found, it is ignored, and tlily will beep.  Any \
control characters will terminate search mode.
};

sub input_search_mode {
    my($ui, $command, $key) = @_;

    # ASSERT().
    die "key is null in input_search_mode at "
        unless defined($key) && $key ne "";

    $key = "" if $key eq "C-r";

    if (length($key) == 1) {
        unless ($ui->{input}->search_history(string =>
                                             $ui->{_search_text} . $key,
                                             reset => 1)) {
            $ui->bell();
        } else {
            $ui->{_search_text} .= $key;
            $ui->prompt("(rev-i-search)'$ui->{_search_text}':");
        }
        return 1;
    } else {
        $ui->command("toggle-input-search-mode");
        # if the key was C-r, return 1 so the key processing function
        # does not continue.
        return 1 if $key eq "";
    }
    return;
}

sub toggle_input_search_mode {
    my($ui) = @_;
    $ui->{_search_text} = "";
    $ui->{_search_idx} = $#{$ui->{input}->{history}};
    if ($ui->intercept_u("input-search-mode")) {
        $ui->prompt("");
        $ui->{input}->search_history(reset => 1);
    }
    elsif ($ui->intercept_r("input-search-mode")) {
        $ui->prompt("(rev-i-search):");
    }
}

TLily::UI::command_r("toggle-input-search-mode" => \&toggle_input_search_mode);
TLily::UI::command_r("input-search-mode" => \&input_search_mode);
TLily::UI::bind("C-r" => "toggle-input-search-mode");
shelp_r("isearch" => "Search your input buffer for a string.",
        "concepts");
help_r("isearch" => $isearch_help);

#
# Styles.
#

=item %style

Allows you to redefine the attributes used to render text in monochrome
mode.
See L<"%help style"|%help style> for details.

=cut

my $style_help = "
Usage: %style style attr ...
       %cstyle style fg bg attr ...

%style and %cstyle set the attributes to print a style in monochrome and \
color modes, respectively.

Valid attribute values are:
  normal, standout, underline, reverse, blink, dim, bold, altcharset

Valid color values are:
  black, red, green, yellow, blue, magenta, cyan, white

The actual rendering of these attributes and colors is very much up to the
specific UI in use.

(see also: styles)
";

sub style_command {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;

    if (@args < 2) {
	$ui->print("(%style style attr ...; type %help for help)\n");
	return;
    }

    my $style = shift @args;
    $config{mono_attrs}->{$style} = \@args;
    $ui->defstyle($style, @args);
    $ui->redraw();
    return;
}
command_r(style => \&style_command);
shelp_r(style => "Set the attributes of a text style.");
help_r(style => $style_help);

=item %cstyle

Allows you to redefine the colors and attributes used to render text
in color mode.
See L<"%help cstyle"|%help cstyle> for details.

=cut


sub cstyle_command {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;

    if (@args < 4) {
	$ui->print("(%cstyle style fg bg attr ...; type %help for help)\n");
	return;
    }

    my $style = shift @args;
    $config{color_attrs}->{$style} = \@args;
    $ui->defcstyle($style, @args);
    $ui->redraw();
    return;
}
command_r(cstyle => \&cstyle_command);
shelp_r(cstyle => "Set the color and attributes of a text style.");
help_r(cstyle => $style_help);

TLily::Config::callback_r(Variable => '-ALL-',
			  List => 'color_attrs',
			  State => 'STORE',
			  Call => sub {
			      my($tr, %ev) = @_;
			      my $ui = ui_name();

			      if(! $config{mono}) {
				  $ui->defcstyle(${$ev{Key}}, @{${$ev{Value}}});
 			          $ui->redraw();
			      }
		          });

my $styles_help = "
The currently available styles are:
status_window   The status line at the bottom of the screen.
input_window    The input line you are typing
input_error     Words not found by the spellchecker in your input line
text_window     The default characteristics of the window (background, etc.)
public_header   The text in the header of a public message
public_sender   The name of the sender of a public message
public_dest     The names of the recipients of a public message
public_body     The actual message of a public message
private_header  The text in the header of a private message
private_sender  The name of the sender of a private message
private_dest    The names of the recipients of a private message
private_body    The actual message of a private message
emote_body      The message text of an emote message
emote_dest      The names of the recipients of an emote message
emote_sender    The name of the sender of an emote message
review          (Currently unused)
slcp            SLCP status messages, indicating a user state change
user_input      User input lines shown in the output window.
yellow          Used for the tlily logo
green           Used for the tlily logo
bwhite          Used for the tlily logo
normal          /info text, /memo text, non-SLCP server messages
default         Used for any style that is not explicitly set.
";
shelp_r("styles" => "The various display styles.", "concepts");
help_r("styles" => $styles_help);


TLily::Config::callback_r(Variable => '-ALL-',
			  List => 'mono_attrs',
			  State => 'STORE',
			  Call => sub {
			      my($tr, %ev) = @_;
			      my $ui = ui_name();

			      if($config{mono}) {
				  $ui->defstyle(${$ev{Key}}, @{${$ev{Value}}});
  			          $ui->redraw();
			      }
		          });


TLily::Config::callback_r(Variable => 'mono',
			  List => 'config',
			  State => 'STORE',
			  Call => sub {
			      my($tr, %ev) = @_;
			      my $ui = ui_name();
			      $ui->configure(color => !$ {$ev{Value}});
			      return;
		          });


sub load {
    # Set colors from what the config files read
    my($k,$v);
    my $ui = ui_name();
    while (($k,$v) = each %{$config{'mono_attrs'}}) {
	$ui->defstyle($k, @{$v});
    }

    while (($k,$v) = each %{$config{'color_attrs'}}) {
	$ui->defcstyle($k, @{$v});
    }
    $ui->redraw;
}

