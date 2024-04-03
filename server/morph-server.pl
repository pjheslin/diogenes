#!/usr/bin/env perl
# Code for pre-forking server is from Perl Cookbook 17.12
# This server is used by DiogenesWeb.

use strict;
use warnings;
use Symbol;
use POSIX;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
push @INC, '.';
# Use local CPAN
use lib ($Bin, catdir($Bin, '..', 'dependencies', 'CPAN') );
use HTTP::Daemon;
use HTTP::Request;
use HTTP::Status;
use Net::Domain qw(hostfqdn);

use Diogenes::Perseus;
my $debug = 0;
# my $HOST = 'localhost';
#my $HOST = hostfqdn();
# All addresses on the local machine (for Docker)
my $HOST = '0.0.0.0';
my $PORT = 8990;
my $server = HTTP::Daemon->new
    (LocalAddr => $HOST,
     Reuse => 1,
     LocalPort => $PORT) or
    die "Error starting server: $@\n";


# global variables
use vars qw($PREFORK $MAX_CLIENTS_PER_CHILD %children $children);
$PREFORK = 25; # number of children to maintain
$MAX_CLIENTS_PER_CHILD = 10; # number of clients each child should process
%children = (); # keys are current child process IDs
$children = 0; # current number of children

sub REAPER {
    # takes care of dead children
    $SIG{CHLD} = \&REAPER;
    my $pid = wait;
    $children --;
    delete $children{$pid};
}

sub HUNTSMAN {
    # signal handler for SIGINT
    local($SIG{CHLD}) = 'IGNORE'; # we're going to kill our children
    kill 'INT' => keys %children;
    exit; # clean up with dignity
}

# Fork off our children.
for (1 .. $PREFORK) {
    make_new_child();
}

# Install signal handlers.
$SIG{CHLD} = \&REAPER;
$SIG{INT} = \&HUNTSMAN;

print STDERR "Morphology server started.\n";

# And maintain the population.
while (1) {
    sleep; # wait for a signal (i.e., child's death)
    for (my $i = $children; $i < $PREFORK; $i++) {
        make_new_child(); # top up the child pool
    }
}
sub make_new_child {
    my $pid;
    my $sigset;
    # block signal for fork
    $sigset = POSIX::SigSet->new(SIGINT);
    sigprocmask(SIG_BLOCK, $sigset) or
        die "Can't block SIGINT for fork: $!\n";
    die "fork: $!" unless defined ($pid = fork);
    if ($pid) {
        # Parent records the child's birth and returns.
        sigprocmask(SIG_UNBLOCK, $sigset) or
            die "Can't unblock SIGINT for fork: $!\n";
        $children{$pid} = 1;
        $children++;
        return;
    }
    else {
        # Child can *not* return from this subroutine.
        $SIG{INT} = 'DEFAULT'; # make SIGINT kill us as it did before
        # unblock signals
        sigprocmask(SIG_UNBLOCK, $sigset) or
            die "Can't unblock SIGINT for fork: $!\n";
        # handle connections until we've reached $MAX_CLIENTS_PER_CHILD
        for (my $i=0; $i < $MAX_CLIENTS_PER_CHILD; $i++) {
            my $client = $server->accept or last;

            my $remote_host = $client->peerhost;
            warn "Request from: ".$remote_host."\n" if $debug;
            my $request = $client->get_request;
            next unless $request;
            if ($request->method eq 'GET') {
                my $requested_file = $request->url->path;
                print STDERR "File: $requested_file\n" if $debug;
                if ($requested_file eq '/parse') {
                    my $params = $request->url->query;
                    print STDERR "$params\n" if $debug;
                    if ($params !~ m/user=(acad|stud|other|none)/) {
                        $client->send_error(RC_UNAUTHORIZED, "Error: Type of user was not specified.");
                    }
                    else {
                        select $client;
                        eval { $Diogenes::Perseus::go->($params) }
                    }
                }
                else {
                    $client->send_error(RC_NOT_FOUND, "Bad request.");
                }
            }
            else {
                warn "Error: Can only handle GET method.\n";
            }
            $client->close;
        }
 
        # this exit is VERY important, otherwise the child will become
        # a producer of more and more children, forking yourself into
        # process death.
        exit;
    }
}
