#!/usr/bin/perl

# This is directly from the POE::Wheel::Run POD, but filtered through perltidy.

use warnings;
use strict;

use Cwd;
use POE qw( Wheel::Run );

POE::Session->create(
    inline_states => {
        _start           => \&on_start,
        got_child_stdout => \&on_child_stdout,
        got_child_stderr => \&on_child_stderr,
        got_child_close  => \&on_child_close,
        got_child_signal => \&on_child_signal,
    }
);

POE::Kernel->run();
exit 0;

sub on_start {
    my $child = POE::Wheel::Run->new(
        Program     => [ ssh => '-t', 'localhost', (@ARGV ? @ARGV : (qw(ls --color=auto -hl), getcwd())) ],
        StdoutEvent => "got_child_stdout",
        StderrEvent => "got_child_stderr",
        CloseEvent  => "got_child_close",

        Conduit => "pty-pipe",
        Winsize => [ 80, 25 ],
    );

    $_[KERNEL]->sig_child( $child->PID, "got_child_signal" );

    # Wheel events include the wheel's ID.
    $_[HEAP]{children_by_wid}{ $child->ID } = $child;

    # Signal events include the process ID.
    $_[HEAP]{children_by_pid}{ $child->PID } = $child;

    print( "Child pid ", $child->PID, " started as wheel ", $child->ID, ".\n" );
}

# Wheel event, including the wheel's ID.
sub on_child_stdout {
    my ( $stdout_line, $wheel_id ) = @_[ ARG0, ARG1 ];
    my $child = $_[HEAP]{children_by_wid}{$wheel_id};
    print "pid ", $child->PID, " STDOUT: $stdout_line\n";
}

# Wheel event, including the wheel's ID.
sub on_child_stderr {
    my ( $stderr_line, $wheel_id ) = @_[ ARG0, ARG1 ];
    my $child = $_[HEAP]{children_by_wid}{$wheel_id};
    print "pid ", $child->PID, " STDERR: $stderr_line\n";
}

# Wheel event, including the wheel's ID.
sub on_child_close {
    my $wheel_id = $_[ARG0];
    my $child    = delete $_[HEAP]{children_by_wid}{$wheel_id};

    # May have been reaped by on_child_signal().
    unless ( defined $child ) {
        print "wid $wheel_id closed all pipes.\n";
        return;
    }

    print "pid ", $child->PID, " closed all pipes.\n";
    delete $_[HEAP]{children_by_pid}{ $child->PID };
}

sub on_child_signal {
    print "pid $_[ARG1] exited with status $_[ARG2].\n";
    my $child = delete $_[HEAP]{children_by_pid}{ $_[ARG1] };

    # May have been reaped by on_child_close().
    return unless defined $child;

    delete $_[HEAP]{children_by_wid}{ $child->ID };
}
