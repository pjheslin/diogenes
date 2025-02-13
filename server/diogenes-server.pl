#!/usr/bin/env perl

# Needs LWP-5.32 or better.
#
# Possible Todos:
#
# Handle decoding of multipart forms (which might then need to be
# re-encoded as URL-escaped query strings).

BEGIN
{
    print "\nStarting Diogenes...\n";
}

package Diogenes_Daemon;
require 5.005;
use strict;
use warnings;
use vars qw($params $flag $config);
$|=1;


# Script to run when nothing else is specified.
my $cgi_script = 'Diogenes.cgi';

use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
use Encode;

push @INC, '.';
# Use local CPAN
use lib ($Bin, catdir($Bin, '..', 'dependencies', 'CPAN') );

use HTTP::Daemon;
# use CGI qw(-nodebug -compile :standard);
use CGI qw(-nodebug :standard);
use CGI::Carp 'fatalsToBrowser';
# From v. 3.10 of CGI.pm XHTML defaults to 1, which turns on multipart
# forms, which we can't handle.
$CGI::XHTML = 0;

use HTTP::Request;
use HTTP::Status;
use HTTP::Headers;
use Cwd;
use Diogenes::Base;
use Diogenes::Script;
use Diogenes::Perseus;
use Net::Domain qw(hostfqdn);
use Socket;
use Getopt::Std;
use vars qw/$opt_d $opt_p $opt_h $opt_H $opt_l $opt_m $opt_D $opt_P/;

my $config_dir = $Diogenes::Base::config_dir;
unlink $config_dir if (-e $config_dir and not -d $config_dir);
mkdir $config_dir unless (-e $config_dir and -d $config_dir);
my $lock_file = File::Spec->catfile($config_dir, 'diogenes-lock.json');
my $lock_file_temp = File::Spec->catfile($config_dir, 'diogenes-lock-temp.json');

# Mozilla wants this: it ignores css files of type text/plain.
use LWP::MediaTypes qw(add_type);
add_type('text/css', '.css');

unless (getopts('dDp:hH:lm:bP:'))
{
    print <<"END";

USAGE: diogenes-server.pl [-dhlb] [-p port] [-H host] [-m netmask]

    -h  Use current network hostname instead of localhost (the default).

    -H  Specify the hostname or IP address to bind to, so that Diogenes
        can be accessed by other computers on the network.  Do not
        expose this server to the public Internet, as it has not been
        designed with that level of security. 

    -p  Specify a port to bind to (8888 is the default; the usual range
        is between 1024 and 65535).  If the specified port is
        unavailable, it will try again by increasing the number.

    -l  Check to make sure that all queries are from localhost.

    -m  Specify the netmask (eg. 255.255.0.0); external queries will be
        refused.

    -P  Specify the path to the Perseus data directory

    -d  Turn on debugging output.

END
    exit;
}

my %tll_list;
my $debug = 0;
$debug = 1 if $opt_d;
$ENV{Diogenes_Debug} = 1 if $debug;
$| = 1;

print "\@INC: ", join "\n", @INC, "\n" if $debug;

# To let the CGI program know it is us that invoked it.
$flag = 1;

$ENV{Diogenes_Perseus_Dir} = $opt_P if $opt_P;
# binmode STDOUT, ':utf8';

# Port to start attempting to listen at:
my $PORT = '8888';
$PORT = $opt_p if defined $opt_p;
if ($PORT =~ /\D/ or $PORT < 1024)
{
    print "\nInvalid port number!\n";
    exit;
}

# Hostname

# my $HOST = 'localhost'; ## Not defined in later Fedora
my $HOST = '127.0.0.1';
$HOST = hostfqdn() if defined $opt_h;
$HOST = $opt_H if defined $opt_H;
#my $HOST_num = gethostbyname $HOST or die "Can't resolve $HOST: $!\n;
#$HOST_num = join ".", unpack('C4', $HOST_num);
my $HOST_dot = inet_ntoa(inet_aton($HOST));
my $HOST_long = unpack ('N', inet_aton($HOST));

# Netmask
my $netmask = 0;
$netmask = unpack ('N', inet_aton($opt_m)) if defined $opt_m;

# CGI dirs
my $root_dir = $Bin;
$root_dir .= '/' unless $root_dir =~ m#[/\\]$#;

print "Server Root: $root_dir\n" if $debug;

my $server;
my $max_port_tries = 20;
my $port_tries = 0;

while ($port_tries < $max_port_tries)
{
    $server = HTTP::Daemon->new
        (LocalAddr => $HOST,
         Reuse => 1,
         LocalPort => $PORT);
    last if $server;
    $port_tries++;
    $PORT++;
}
unless ($server)
{
    print "Unable to bind to a port after $port_tries attempts, up to $PORT of $HOST: $!\n";
    exit;
}

warn "Local address: $HOST_dot\n" if $debug;

# The fork() emulation in Perl under MS Windows is broken, and
# segfaults frequently in a normally forking server. An entirely
# non-forking server, however, leads to problems with cleaning up the
# state after an interrupted query.  So instead, we pre-fork one and
# only one child to handle connections.  Pre-forking more children
# than that does not work reliably under Windows.  This single child is
# really a thread, so it dies correctly when the parent process quits.

# The protocol is HTTP 1.1 with keep-alive header, so the server will
# keep the connection open for a long time (e.g. to the Electron
# client) after serving a request, which means that a non-forking
# server will block other clients, such as a browser wanting to
# download a PDF.  Easiest solution is to timeout connections on
# Windows after 1 second.  This does degrade performance a bit.

# Occasionally, on Windows, the accept loop falls through.  So we wrap
# the whole thing in a loop.

write_lock();
print "\nStartup complete. ",
    "You may now point your browser at ",
    "this address:\n",
    "http://$HOST:$PORT\n";

my $pid;
while (1)
{
    if ($Diogenes::Base::OS eq 'windows')
    {
        $pid = fork;
        if ($pid)
        {   # I am the parent -- I do nothing but wait for my child to exit.
            write_lock();
            wait;
        }
        elsif (not defined $pid)
        {
            # Fork failed.
            print STDERR "Unable to fork!\n";
        }
        else
        {
            # I am the child -- I wait for a request and process it.
            while (my $client = $server->accept)
            {
                # Single child, so must not let keep-alive connections block
                $client->timeout(1);
                print STDERR "New conn.\n" if $debug;
                # Windows gets confused if we die in midstream w/o chdir'ing # back
                chdir $root_dir or die "Couldn't chdir to $root_dir: $!\n";
                handle_request($client);
                $client->close;
                print STDERR "Closed conn.\n" if $debug;
            }
        }
    }
    else
    {
        # A "normal" forking server
        write_lock();
        while (my $client = $server->accept)
        {
            handle_connection($client);
        }
    }
    print STDERR "Starting again ...\n";
}
print "An error has occurred.\n";
exit;

# Process each request by forking a child (forking server, unix only).
sub handle_connection
{
    my $client = shift;
    $pid = fork;
    if ($pid)
    {
        # I am the parent -- I do nothing.
        $client->close;
        return;
    }
    elsif (not defined $pid)
    {
        # Fork failed.
        print STDERR "Unable to fork!\n";
    }
    else
    {
        # I am the child -- I process the request.
        handle_request($client);
        $client->close;
        exit 0; # Kill children off to reclaim their memory
    }
}

sub handle_request
{
    my $client = shift;
    my $remote_host = $client->peerhost;
    warn "Request from: ".$remote_host."\n" if $debug;

    my $request = $client->get_request;
    print STDERR $request->as_string if $debug and defined $request;

    unless (defined $request)
    {
        warn "Null request: ".$client->reason."\n";
        return;
    }
    warn "Requested URL: ".$request->url->as_string."\n" if $debug;
    #         warn "Full request from browser: ". $request->as_string if $debug;

    if (not defined $remote_host
        or ($opt_l and $remote_host ne $HOST_dot )
        or ($netmask and (unpack ('N', inet_aton($remote_host)) & $netmask) !=
            ($HOST_long & $netmask) ))
    {
        warn  "WARNING! WARNING! ... \n" .
            "Connection attempted from an unauthorized " .
            "computer: $remote_host\n";
        $client->send_error(RC_FORBIDDEN);
        return;
    }

    # We only deal with GET and POST methods
    unless ($request->method eq 'GET' or $request->method eq 'POST')
    {
        warn "Illegal method: only GET and POST are supported: ".$request->method."\n";
        $client->send_error(RC_NOT_IMPLEMENTED);
        return;
    }
    my $requested_file = ($request->url->path);
    warn "Requested file: $requested_file; cwd: ".cwd."\n" if $debug;
    my $leading_slash = ($requested_file =~ m#^/#) ? 1 : 0;
    if ($requested_file =~ m#\.\.#)
    {
        warn "Warning: attempted directory traversal: $requested_file \n";
        $client->send_error(RC_FORBIDDEN);
        return;
    }
    $requested_file = $cgi_script if $requested_file eq '/';
    # Internet exploder stupidity
    $requested_file =~ s#^\Q$root_dir\E##;
    $requested_file =~ s#^[/\\]##;
    $requested_file = $cgi_script if $requested_file =~ m/diogenes-server/i;
    $requested_file = $cgi_script if $requested_file =~ m/Diogenes\.cgi/i;
    warn "Relative file name: $requested_file\n" if $debug;

    my $cookie = $request->header('Cookie');
    $ENV{HTTP_COOKIE} = $cookie if $cookie;

    # Deal with the various ways our CGI script might be
    # requested by a browser.

    # $params is a global which is accessed by the CGI script and
    # passed as a parameter to CGI->new in order to instantiate
    # the CGI object.  We could pass this info via environment
    # variables, except that for POST methods, CGI.pm wants to
    # read the query data from STDIN.
    $params = '';
    if ($requested_file =~ m/\.cgi/i or $requested_file eq $cgi_script)
    {
        if ($request -> method eq 'GET')
        {
            $params = $request->url->query;
            $params ||= '';
            warn "GET request.".($params ? " Query:$params\n" : "\n") if $debug;
            $ENV{REQUEST_METHOD} = 'GET';
            $ENV{QUERY_STRING} = $params;
        }
        else ## eq 'POST'
        {
            my $content_type = $request->headers->content_type;
            if ($content_type =~ /multipart.*/) {
                # We do not handle multipart submission, since that
                # would need to be turned into a URL-encoded string to
                # pass as an initializer for CGI.pm.  TODO?
                warn "Multipart form submission is not supported by the Diogenes server.\n";
                $client->send_error(RC_NOT_IMPLEMENTED);
                return;
            }
            else {
                $params = $request->content;
                $params ||= '';
                warn "POST request. Content: $params\n" if $debug;
                # We pass the params via the global $param, since
                # otherwise, we'd need to stuff the params into
                # our own STDIN, which would cost a fork,
                # probably.  Tried pretending this was a GET
                # request, and passing via %ENV, but that was Bad.
            }
        }
        # Workaround for annoying CGI.pm bug/warning
        $ENV{QUERY_STRING} = '' unless $ENV{QUERY_STRING};

        $client->send_basic_header(RC_OK, '(OK)', 'HTTP/1.1');
        # This tells CGI.pm the name of the host and script, which goes into
        # the action parameter of the form element(s)
        my $host = $request->header('Host');
        $ENV{HTTP_HOST} = $host if $host;
        $ENV{SCRIPT_NAME} = ($leading_slash ? '/' : '') . "$requested_file";

        # We 'use' the cgi script (which avoids re-parsing the file
        # for each request).  That file should end in a true statement
        # and is lexically scoped but shares our namespace, which it
        # should not pollute: i.e it should use lexical vars to hold
        # subroutine refs.  The script does not see $client, which is
        # lexically scoped to this file, but it shares STDOUT with us,
        # so the select command passes the reference to the correct
        # filehandle.

        select $client;

        if ($requested_file eq $cgi_script) {
            # The module has been pre-compiled, and we use eval here
            # to trap errors (especially important for the non-forking
            # server).
            eval { $Diogenes::Script::go->($params) }
        }
        elsif ($requested_file eq 'Perseus.cgi') {
            eval { $Diogenes::Perseus::go->($params) }
        }
        else {
            # Other scripts have to be re-parsed each time.
            do $requested_file;
        }
        warn "Diogenes Error: $@" if $@;

    }
    elsif ($requested_file =~ m#^tll-pdf|ox-lat-dict\.pdf#) {
        $client->send_basic_header(RC_OK, '(OK)', 'HTTP/1.1');
        # Serve TLL/OLD pdfs, but first translate filename
        my %args_init = (-type => 'none');
        my $init = new Diogenes::Base(%args_init);
        my ($pdf_path, $pdf_file);

        if ($requested_file =~ m#^tll-pdf#) {
            $requested_file =~ m#^tll-pdf/([\d\.o]+).pdf#;
            my $file_number = $1;
            warn "Bad PDF file URI" unless $file_number;

            tll_list_read() unless %tll_list;
            $pdf_file = $tll_list{$file_number};
            warn "Bad PDF file number" unless $pdf_file;
            warn "Translating PDF file $file_number as $pdf_file\n" if $debug;

            if ($Diogenes::Base::OS eq 'windows') {
                # Data is proper utf-8, not octets.
                $pdf_file = Encode::encode($Diogenes::Base::code_page, $pdf_file);
            }
            $pdf_path = $init->{tll_pdf_dir};
            $pdf_file = File::Spec->catfile($pdf_path, $pdf_file);
        }
        else {
            $pdf_path = $init->{old_pdf_dir};
            $pdf_file = $init->{old_pdf_dir};
        }

        unless ($pdf_path) {
            warn "Error: pdf_path not set\n";
            $client->send_error(RC_NOT_FOUND, "Location of the requested pdf file has not been set.");
            return;
        }
        unless (-e $pdf_path) {
            warn "Error: pdf_path ($pdf_path) does not exist.\n";
            $client->send_error(RC_NOT_FOUND, "The requested pdf file ($pdf_path) was not found.");
            return;
        }
        warn "Serving PDF file $pdf_file\n" if $debug;
        unless (-e $pdf_file) {
            warn "Error: pdf_file ($pdf_file) does not exist\n";
            $client->send_error(RC_NOT_FOUND, "Requested pdf file ($pdf_file) was not found.");
            return;
        }

        my $ret = $client->send_file_response($pdf_file);
        warn "File $requested_file failed to send!\n" unless $ret eq RC_OK;
    }
    else
    {
        # Merrily serve up all non .cgi files (but only files in the
        # root dir).
        $requested_file =~ s#^/##;
        $requested_file = $root_dir . $requested_file;
        warn "Sending file: $requested_file\n" if $debug;
        #Windows IE doesn't like this:
        #my $ret = $client->send_file_response($root_dir.$requested_file);
        my $ret = $client->send_file_response($requested_file);
        warn "File $requested_file not found!\n" unless $ret eq RC_OK;
    }
}

sub write_lock
{
    # Write number of port to lock file to indicate that we are ready
    # to receive connections.
    unlink $lock_file;
    unlink $lock_file_temp;
    print "Writing $lock_file\n" if $debug;
    open FLAG, ">$lock_file_temp" or warn "Could not create lock file: $!";
    print FLAG
"{
\"port\": $PORT,
\"pid\": $$
}";
    # Flush filehandle
    close FLAG;
    # This ought to address the race condition whereby the browser process can read the file after it has been created but before it has been written to.  The linking action within the rename ought to be atomic.
    rename $lock_file_temp, $lock_file;

}

sub tll_list_read {
    my $data_dir = File::Spec->catdir($Bin, '..', 'dependencies', 'data');
    my $list = File::Spec->catfile($data_dir, 'tll-pdf-list.txt');

    open my $list_fh, '<:encoding(UTF-8)', $list or
        die "Could not open $list: $!";
    while (<$list_fh>) {
        m/^([\d\.o]+)\t(.*)$/ or die "Malformed list entry: $_";
        $tll_list{$1} = $2;
    }
}

