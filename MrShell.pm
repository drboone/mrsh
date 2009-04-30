package App::MrShell;

use strict;
use warnings;

use Carp;
use POSIX;
use Config::Tiny;
use POE qw( Wheel::Run );
use Term::ANSIColor qw(:constants);

our $VERSION = '2.0000';
our @DEFAULT_SHELL_COMMAND = (ssh => '-o', 'BatchMode yes', '-o', 'StrictHostKeyChecking no', '-o', 'ConnectTimeout 20');

# new {{{
sub new {
    my $this = bless { hosts=>[], cmd=>[], _shell_cmd=>[@DEFAULT_SHELL_COMMAND] };

    $this;
}
# }}}

# _process_space_delimited {{{
sub _process_space_delimited {
    my $this = shift;

    return
        grep {defined} ($_[0] =~ m/["']([^"']*?)["']|(\S+)/g)
}
# }}}
# _process_hosts {{{
sub _process_hosts {
    my $this = shift;
    my @h = map { my $k = $_; $k =~ s/^\@// ? @{$this->{groups}{$k} or die "couldn't find group: \@$k\n"} : $_ } @_;

    my $o = my $l = $this->{_host_width} || 0;
    for( map { length $_ } @h ) {
        $l = $_ if $_>$l
    }
    $this->{_host_width} = $l if $l != $o;

    @h;
}
# }}}
# _process_shell_command_option {{{
sub _process_shell_command_option {
    my $this = shift;
       $this->{_shell_cmd} = ($_[0] eq "none" ? [] : [ $this->_process_space_delimited($_[0]) ]);

    $this;
}
# }}}
# _process_group_option {{{
sub _process_group_option {
    my $this  = shift;
    my $name  = shift;
    my $value = shift;

    $this->{groups}{$name} = [ $this->_process_space_delimited( $value ) ];
    $this;
}
# }}}

# set_usage_error($&) {{{
sub set_usage_error($&) {
    my $this = shift;
    my $func = shift;
    my $pack = caller;
    my $name = $pack . "::$func";
    my @args = @_;

    $this->{_usage_error} = sub { no strict 'refs'; $name->(@args) };
    $this;
}
# }}}
# read_config {{{
sub read_config {
    my ($this, $that) = @_;

    $this->{_conf} = Config::Tiny->read($that) if -f $that;

    for my $group (keys %{ $this->{_conf}{groups} }) {
        $this->_process_group_option( $group => $this->{_conf}{groups}{$group} );
    }

    if( my $c = $this->{_conf}{options}{'shell-command'} ) {
        $this->_process_shell_command_option( $c );
    }

    $this;
}
# }}}
# set_hosts {{{
sub set_hosts {
    my $this = shift;

    $this->{hosts} = [ $this->_process_hosts(@_) ];
    $this;
}
# }}}
# queue_command {{{
sub queue_command {
    my $this = shift;
    my @hosts = @{$this->{hosts}};

    unless( @hosts ) {
        if( my $h = $this->{_conf}{options}{'default-hosts'} ) {
            @hosts = $this->_process_hosts( $this->_process_space_delimited($h) );

        } else {
            if( my $e = $this->{_usage_error} ) {
                warn "Error, no hosts specified\n";
                $e->();

            } else {
                croak "set_hosts before issuing queue_command";
            }
        }
    }

    for my $h (@hosts) {
        push @{$this->{_cmd_queue}{$h}}, \@_;
    }

    $this;
}
# }}}
# run_queue {{{
sub run_queue {
    my $this = shift;

    $this->{_session} = POE::Session->create( inline_states => {
        _start       => sub { $this->poe_start(@_) },
        child_stdout => sub { $this->line(1, @_) },
        child_stderr => sub { $this->line(2, @_) },
        child_close  => sub { $this->close(@_) },
        child_signal => sub { $this->sigchld(@_) },
        stall_close  => sub { $this->_close(@_) },
    });

    POE::Kernel->run();

    $this
}
# }}}

# std_msg {{{
sub std_msg {
    my $this  = shift;
    my $host  = shift;
    my $cmdno = shift;
    my $fh    = shift;
    my $msg   = shift;

    print strftime('%H:%M:%S ', localtime),
        sprintf('cn:%-2d %-*s', $cmdno, $this->{_host_width}+2, "$host: "),
            ( $fh==2 ? ('[',BOLD,YELLOW,'stderr',RESET,'] ') : () ), $msg, "\n";
}
# }}}

# line {{{
sub line {
    my $this = shift;
    my $fh   = shift;
    my ($line, $wid) = @_[ ARG0, ARG1 ];
    my ($kid, $host, $cmdno, $lineno) = @{$this->{_wid}{$wid}};

    $$lineno ++;
    $this->std_msg($host, $cmdno, $fh, $line);
}
# }}}

# sigchld {{{
sub sigchld {
    my $this = shift;
    my ($kid, $host, $cmdno, @c) = @{ delete $this->{_pid}{ $_[ARG1] } || return };
    delete $this->{_wid}{ $kid->ID };

    $this->std_msg($host, $cmdno, 0, '--error--');
}
# }}}
# close {{{

sub close {
    my $this = shift;

    $_[KERNEL]->yield( stall_close => $_[ARG0], 0 );
}
# }}}
# _close {{{
sub _close {
    my $this = shift;
    my ($wid, $count) = @_[ ARG0, ARG1 ];

    if( $count > 3 ) {
        my ($kid, $host, $cmdno, $lineno, @c) = @{ delete $this->{_wid}{$wid} };

        $this->std_msg($host, $cmdno, 0, BOLD.BLACK.'--eof--'.RESET) if $$lineno == 0;
        $this->start_one($_[KERNEL] => $host, $cmdno+1, @c) if @c;

        delete $this->{_pid}{ $kid->PID };

    } else {
        $_[KERNEL]->yield( stall_close => $wid, $count+1 );
    }
}
# }}}

# start_queue_on_host {{{
sub start_queue_on_host {
    my ($this, $kernel => $host, $cmdno, $cmd, @next) = @_;

    my $kid = POE::Wheel::Run->new(
        Program     => [ @{$this->{_shell_cmd}} => ($host, @$cmd) ],
        StdoutEvent => "child_stdout",
        StderrEvent => "child_stderr",
        CloseEvent  => "child_close",
    );

    $kernel->sig_child( $kid->PID, "child_signal" );

    my $lineno = 0;
    my $info = [ $kid, $host, $cmdno, \$lineno, @next ];
    $this->{_wid}{ $kid->ID } = $this->{_pid}{ $kid->PID } = $info;
}
# }}}
# poe_start {{{
sub poe_start {
    my $this = shift;

    for my $host (keys %{ $this->{_cmd_queue} }) {
        my @c = @{ $this->{_cmd_queue}{$host} };

        $this->start_queue_on_host($_[KERNEL] => $host, 1, @c);
    }

    delete $this->{_cmd_queue};
    return;
}
# }}}
