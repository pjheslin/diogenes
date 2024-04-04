#!/usr/bin/env perl
use strict;
use warnings;
# Use local CPAN
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
use lib ($Bin, catdir($Bin, '..', 'dependencies', 'CPAN') );
push @INC, '.';
use Encode;
use URI::Escape;
use Diogenes::Base;
my $version = $Diogenes::Base::Version;
use LWP::UserAgent ();

# URLs at bottom of file
my @urls = tll_urls();
my %file_names;
@file_names{@urls} = tll_file_names();

my $path;
if ($ARGV[0]) {
    $path = $ARGV[0];
}
else {
    die "Error: No destination folder for the TLL files has been specified!\n";
}

$path =~ s#[\\/]$##;

unless (-e $path and -d $path) {
    mkdir $path or die "Error: Could not create folder $path! $!\n";
}

chdir $path or die "Error: could not chdir to $path: $!\n";

# Code is adapted from lwp-download.pl

my $ua = LWP::UserAgent->new(
   agent => "Diogenes/$version ",
   keep_alive => 1,
   env_proxy => 1,
    );

my $flength;   # formatted length
my $size;      # number of bytes received
my $start_t;   # start time of download
my $last_dur;  # time of last callback

my $interrupted;
$SIG{INT} =
    sub { print "Interrupted\n";
          $interrupted = 1;
};

$| = 1;  # autoflush

print "Downloading TLL PDF files.\n";

 FILE:
foreach my $url (@urls) {
    my $filename = $file_names{$url};
    $filename = uri_unescape($filename);
    # The filename is now a series of raw bytes, but the url is
    # encoded as utf8 (i.e. with en-dashes).  For utf-8 systems, we
    # can just use the octets as such without further ado, but on
    # Windows we have to convert to the local 8-bit codepage (unless
    # we want to install a special Win32 module to use the Windows
    # Unicode file API). Hopefully the local codepage includes the
    # en-dash (cp1252 is OK).  There will be problems if not.  The
    # terminal output will be wrong on Windows, as the terminal uses a
    # different codepage.
    if ($Diogenes::Base::OS eq 'windows') {
        Encode::from_to($filename, 'utf8', $Diogenes::Base::code_page);
    }
    if (-e $filename) {
        print "Skipping existing file: $filename\n";
        next FILE;
    }
    open my $fh, ">", $filename or die "Could not open $filename for writing: $!\n";
    binmode($fh); # essential for Windows
    print "\nDownloading $filename ...\n";
    download($url, $fh, $filename);
    die "Shutting down.\n" if $interrupted;
    close $fh or die "Could not close $filename: $!\n";
}

print "Finished: all files downloaded.  You can now close this window.";

sub download {
    my ($url, $fh, $filename) = @_;
    my $length;    # total number of bytes to download
    $flength = 0;
    $size = 0;
    $last_dur = 0;
    $start_t = time;
    my $callback = sub {
        # Test if output window is still open
        $interrupted = 1 unless print ("\0");
        return if $interrupted;
        my $data =  $_[0];
        my $resp = $_[1];
        unless (defined $length) {
            $length = $resp->content_length;
            $flength = fbytes($length) if defined $length;
        }
        print $fh $data or die "Can't write to $filename: $!\n";
        $size += length($_[0]);
        
        if ($length) {
            my $dur  = time - $start_t;
            if ($dur > $last_dur + 3) {  # don't update too often
                $last_dur = $dur;
                my $perc = $size / $length;
                my $speed;
                $speed = fbytes($size/$dur) . "/sec" if $dur > 3;
                my $secs_left = fduration($dur/$perc - $dur);
                $perc = int($perc*100);
                my $show = "$perc% of $flength";
                $show .= " (at $speed, $secs_left remaining)" if $speed;
                print $show . ".\n";
            }
        }
        else {
            print fbytes($size) . " received.\n";
        }
    };
    my $res = $ua->request(HTTP::Request->new(GET => $url), $callback);

    print "\n";
    print fbytes($size);
    print " of ", fbytes($length) if defined($length) && $length != $size;
    print " received";
    my $dur = time - $start_t;
    if ($dur) {
	my $speed = fbytes($size/$dur) . "/sec";
	print " in ", fduration($dur), " ($speed)";
    }
    print "\n";

    if (my $mtime = $res->last_modified) {
	utime time, $mtime, $filename;
    }

    if ($res->header("X-Died") || !$res->is_success) {
	if (my $died = $res->header("X-Died")) {
	    print "$died\n";
	}
        print "Transfer aborted, $filename kept\n";
    }
}

sub fbytes
{
    my $n = int(shift);
    if ($n >= 1024 * 1024) {
	return sprintf "%.3g MB", $n / (1024.0 * 1024);
    }
    elsif ($n >= 1024) {
	return sprintf "%.3g KB", $n / 1024.0;
    }
    else {
	return "$n bytes";
    }
}

sub fduration
{
    use integer;
    my $secs = int(shift);
    my $hours = $secs / (60*60);
    $secs -= $hours * 60*60;
    my $mins = $secs / 60;
    $secs %= 60;
    if ($hours) {
	return "$hours hours $mins minutes";
    }
    elsif ($mins >= 2) {
	return "$mins minutes";
    }
    else {
	$secs += $mins * 60;
	return "$secs seconds";
    }
}

# The files have been moved to new URLs and the filenames have been
# changed.  So we keep the old names and split them from the new URLs.

sub tll_file_names {
    return (
"000924304%7BThLL%20vol.%2001%20col.%200001%E2%80%930724%20%28a%E2%80%93adli%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924304%7BThLL%20vol.%2001%20col.%200725%E2%80%931410%20%28adluc%E2%80%93agoge%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924304%7BThLL%20vol.%2001%20col.%201411%E2%80%932032%20%28agogima%E2%80%93Amyzon%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914810%7BThLL%20vol.%2002%20col.%200001%E2%80%930706%20%28an%E2%80%93Artigi%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914810%7BThLL%20vol.%2002%20col.%200707%E2%80%931324%20%28artigraphia%E2%80%93Aves%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914810%7BThLL%20vol.%2002%20col.%201325%E2%80%931646%20%28Avesica%E2%80%93Azzi%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914810%7BThLL%20vol.%2002%20col.%201647%E2%80%932270%20%28b%E2%80%93Byzeres%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924306%7BThLL%20vol.%2003%20col.%200001%E2%80%930748%20%28c%E2%80%93celebro%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924306%7BThLL%20vol.%2003%20col.%200749%E2%80%931444%20%28celebrum%E2%80%93coevangelista%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924306%7BThLL%20vol.%2003%20col.%201445%E2%80%932186%20%28coeuntia%E2%80%93comus%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924307%7BThLL%20vol.%2004%20col.%200001%E2%80%930788%20%28con%E2%80%93controversus%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924307%7BThLL%20vol.%2004%20col.%200789%E2%80%931594%20%28controverto%E2%80%93cyulus%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924308%7BThLL%20vol.%2005.1%20col.%200001%E2%80%930558%20%28d%E2%80%93deopto%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924308%7BThLL%20vol.%2005.1%20col.%200559%E2%80%931102%20%28deorata%E2%80%93diffidus%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924308%7BThLL%20vol.%2005.1%20col.%201103%E2%80%931812%20%28diffindentia%E2%80%93dogarius%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924308%7BThLL%20vol.%2005.1%20col.%201813%E2%80%932334%20%28dogma%E2%80%93dze%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924309%7BThLL%20vol.%2005.2%20col.%200001%E2%80%930758%20%28e%E2%80%93ergenna%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924309%7BThLL%20vol.%2005.2%20col.%200759%E2%80%931276%20%28erginario%E2%80%93excolligo%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924309%7BThLL%20vol.%2005.2%20col.%201277%E2%80%931822%20%28excolo%E2%80%93exquiro%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924309%7BThLL%20vol.%2005.2%20col.%201823%E2%80%932134%20%28exquisitim%E2%80%93eozani%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924310%7BThLL%20vol.%2006.1%20col.%200001%E2%80%930808%20%28f%E2%80%93firmitas%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924310%7BThLL%20vol.%2006.1%20col.%200809%E2%80%931664%20%28firmiter%E2%80%93fysis%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924311%7BThLL%20vol.%2006.2%20col.%201665%E2%80%932388%20%28g%E2%80%93gytus%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924312%7BThLL%20vol.%2006.3%20col.%202389%E2%80%932780%20%28h%E2%80%93hieranthemis%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000924312%7BThLL%20vol.%2006.3%20col.%202781%E2%80%933166%20%28hierarchia%E2%80%93hystrix%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914816%7BThLL%20vol.%2007.1%20col.%200001%E2%80%930840%20%28i%E2%80%93inaures%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914816%7BThLL%20vol.%2007.1%20col.%200841%E2%80%931596%20%28inauricula%E2%80%93inhonestitas%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914816%7BThLL%20vol.%2007.1%20col.%201597%E2%80%932304%20%28inhonesto%E2%80%93intervulsus%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914817%7BThLL%20vol.%2007.2.1%20col.%200001%E2%80%930760%20%28intestabilis%E2%80%93kyrie%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914817%7BThLL%20vol.%2007.2.2%20col.%200761%E2%80%931346%20%28l%E2%80%93librariolus%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914817%7BThLL%20vol.%2007.2.2%20col.%201347%E2%80%931952%20%28librarium%E2%80%93lyxipyretos%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914818%7BThLL%20vol.%2008%20col.%200001%E2%80%930786%20%28m%E2%80%93meocarius%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914818%7BThLL%20vol.%2008%20col.%200787%E2%80%931332%20%28meoculos%E2%80%93mogilalus%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914818%7BThLL%20vol.%2008%20col.%201333%E2%80%931764%20%28moincipium%E2%80%93myzon%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914819%7BThLL%20vol.%2009.2%20col.%200001%E2%80%930624%20%28o%E2%80%93omnividens%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000914819%7BThLL%20vol.%2009.2%20col.%200625%E2%80%931214%20%28omnividentia%E2%80%93ozynosus%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000094372%7BThLL%20vol.%2010.1.1%20col.%200001%E2%80%930694%20%28p%E2%80%93paternaliter%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000094372%7BThLL%20vol.%2010.1.1%20col.%200695%E2%80%931472%20%28paterne%E2%80%93perimelides%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000094372%7BThLL%20vol.%2010.1.2%20col.%201473%E2%80%932074%20%28perimetros%E2%80%93piceno%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000094372%7BThLL%20vol.%2010.1.2%20col.%202075%E2%80%932780%20%28picercula%E2%80%93porrus%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000094373%7BThLL%20vol.%2010.2.1%20col.%200001%E2%80%930644%20%28porta%E2%80%93praefinitivus%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000094373%7BThLL%20vol.%2010.2.1%20col.%200645%E2%80%931232%20%28praefinitus%E2%80%93primaevitas%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000094373%7BThLL%20vol.%2010.2.2%20col.%201233%E2%80%931970%20%28primaevus%E2%80%93propello%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"000094373%7BThLL%20vol.%2010.2.2%20col.%201971%E2%80%932798%20%28propemodum%E2%80%93pyxodes%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"036397929%7BThLL%20vol.%20onom.2%20col.%200001%E2%80%930814%20%28c%E2%80%93cyzistra%29%7D%5BCC%20BY-NC-ND%5D.pdf",
"036397930%7BThLL%20vol.%20onom.3%20col.%200001%E2%80%930280%20%28d%E2%80%93dzoni%29%7D%5BCC%20BY-NC-ND%5D.pdf",

# New fascicles
"ThLL%20vol.%209.1.1%20col.%200001%E2%80%930208%20%28n%E2%80%93navalis%29.pdf",
"ThLL%20vol.%209.1.2%20col.%200209%E2%80%930336%20%28navalis-nebel%29.pdf",
"ThLL%20vol.%209.1.3%20col.%200337%E2%80%930516%20(nebel-nemo)%7D.pdf",
"ThLL_IX_1__3_UEberhang_nemo_nemus.pdf",
"ThLL%20vol.%2011.2.1%20col.%200001%E2%80%930144%20%28r-rarus%29.pdf",
"ThLL%20vol.%2011.2.2%20col.%200145%E2%80%930320%20%28rarus-recido%29.pdf",
"ThLL%20vol.%2011.2.3%20col.%200321%E2%80%930496%20%28recido-reddo%29.pdf",
"ThLL%20vol.%2011.2.4%20col.%200497%E2%80%930656%20%28reddo-refocilo%29.pdf",
"ThLL%20vol.%2011.2.5%20col.%200657%E2%80%930784%20%28refodio-regnum%29.pdf"
        )
};

sub tll_urls {
    return (
"http://publikationen.badw.de/de/000924304/pdf/CC%20BY-NC-ND/ThLL%20vol.%2001%20col.%200001%E2%80%930724%20%28a%E2%80%93adli%29",
"http://publikationen.badw.de/de/000924304/pdf/CC%20BY-NC-ND/ThLL%20vol.%2001%20col.%200725%E2%80%931410%20%28adluc%E2%80%93agoge%29",
"http://publikationen.badw.de/de/000924304/pdf/CC%20BY-NC-ND/ThLL%20vol.%2001%20col.%201411%E2%80%932032%20%28agogima%E2%80%93Amyzon%29",
"http://publikationen.badw.de/de/000914810/pdf/CC%20BY-NC-ND/ThLL%20vol.%2002%20col.%200001%E2%80%930706%20%28an%E2%80%93Artigi%29",
"http://publikationen.badw.de/de/000914810/pdf/CC%20BY-NC-ND/ThLL%20vol.%2002%20col.%200707%E2%80%931324%20%28artigraphia%E2%80%93Aves%29",
"http://publikationen.badw.de/de/000914810/pdf/CC%20BY-NC-ND/ThLL%20vol.%2002%20col.%201325%E2%80%931646%20%28Avesica%E2%80%93Azzi%29",
"http://publikationen.badw.de/de/000914810/pdf/CC%20BY-NC-ND/ThLL%20vol.%2002%20col.%201647%E2%80%932270%20%28b%E2%80%93Byzeres%29",
"http://publikationen.badw.de/de/000924306/pdf/CC%20BY-NC-ND/ThLL%20vol.%2003%20col.%200001%E2%80%930748%20%28c%E2%80%93celebro%29",
"http://publikationen.badw.de/de/000924306/pdf/CC%20BY-NC-ND/ThLL%20vol.%2003%20col.%200749%E2%80%931444%20%28celebrum%E2%80%93coevangelista%29",
"http://publikationen.badw.de/de/000924306/pdf/CC%20BY-NC-ND/ThLL%20vol.%2003%20col.%201445%E2%80%932186%20%28coeuntia%E2%80%93comus%29",
"http://publikationen.badw.de/de/000924307/pdf/CC%20BY-NC-ND/ThLL%20vol.%2004%20col.%200001%E2%80%930788%20%28con%E2%80%93controversus%29",
"http://publikationen.badw.de/de/000924307/pdf/CC%20BY-NC-ND/ThLL%20vol.%2004%20col.%200789%E2%80%931594%20%28controverto%E2%80%93cyulus%29",
"http://publikationen.badw.de/de/000924308/pdf/CC%20BY-NC-ND/ThLL%20vol.%2005.1%20col.%200001%E2%80%930558%20%28d%E2%80%93deopto%29",
"http://publikationen.badw.de/de/000924308/pdf/CC%20BY-NC-ND/ThLL%20vol.%2005.1%20col.%200559%E2%80%931102%20%28deorata%E2%80%93diffidus%29",
"http://publikationen.badw.de/de/000924308/pdf/CC%20BY-NC-ND/ThLL%20vol.%2005.1%20col.%201103%E2%80%931812%20%28diffindentia%E2%80%93dogarius%29",
"http://publikationen.badw.de/de/000924308/pdf/CC%20BY-NC-ND/ThLL%20vol.%2005.1%20col.%201813%E2%80%932334%20%28dogma%E2%80%93dze%29",
"http://publikationen.badw.de/de/000924309/pdf/CC%20BY-NC-ND/ThLL%20vol.%2005.2%20col.%200001%E2%80%930758%20%28e%E2%80%93ergenna%29",
"http://publikationen.badw.de/de/000924309/pdf/CC%20BY-NC-ND/ThLL%20vol.%2005.2%20col.%200759%E2%80%931276%20%28erginario%E2%80%93excolligo%29",
"http://publikationen.badw.de/de/000924309/pdf/CC%20BY-NC-ND/ThLL%20vol.%2005.2%20col.%201277%E2%80%931822%20%28excolo%E2%80%93exquiro%29",
"http://publikationen.badw.de/de/000924309/pdf/CC%20BY-NC-ND/ThLL%20vol.%2005.2%20col.%201823%E2%80%932134%20%28exquisitim%E2%80%93eozani%29",
"http://publikationen.badw.de/de/000924310/pdf/CC%20BY-NC-ND/ThLL%20vol.%2006.1%20col.%200001%E2%80%930808%20%28f%E2%80%93firmitas%29",
"http://publikationen.badw.de/de/000924310/pdf/CC%20BY-NC-ND/ThLL%20vol.%2006.1%20col.%200809%E2%80%931664%20%28firmiter%E2%80%93fysis%29",
"http://publikationen.badw.de/de/000924311/pdf/CC%20BY-NC-ND/ThLL%20vol.%2006.2%20col.%201665%E2%80%932388%20%28g%E2%80%93gytus%29",
"http://publikationen.badw.de/de/000924312/pdf/CC%20BY-NC-ND/ThLL%20vol.%2006.3%20col.%202389%E2%80%932780%20%28h%E2%80%93hieranthemis%29",
"http://publikationen.badw.de/de/000924312/pdf/CC%20BY-NC-ND/ThLL%20vol.%2006.3%20col.%202781%E2%80%933166%20%28hierarchia%E2%80%93hystrix%29",
"http://publikationen.badw.de/de/000914816/pdf/CC%20BY-NC-ND/ThLL%20vol.%2007.1%20col.%200001%E2%80%930840%20%28i%E2%80%93inaures%29",
"http://publikationen.badw.de/de/000914816/pdf/CC%20BY-NC-ND/ThLL%20vol.%2007.1%20col.%200841%E2%80%931596%20%28inauricula%E2%80%93inhonestitas%29",
"http://publikationen.badw.de/de/000914816/pdf/CC%20BY-NC-ND/ThLL%20vol.%2007.1%20col.%201597%E2%80%932304%20%28inhonesto%E2%80%93intervulsus%29",
"http://publikationen.badw.de/de/000914817/pdf/CC%20BY-NC-ND/ThLL%20vol.%2007.2.1%20col.%200001%E2%80%930760%20%28intestabilis%E2%80%93kyrie%29",
"http://publikationen.badw.de/de/000914817/pdf/CC%20BY-NC-ND/ThLL%20vol.%2007.2.2%20col.%200761%E2%80%931346%20%28l%E2%80%93librariolus%29",
"http://publikationen.badw.de/de/000914817/pdf/CC%20BY-NC-ND/ThLL%20vol.%2007.2.2%20col.%201347%E2%80%931952%20%28librarium%E2%80%93lyxipyretos%29",
"http://publikationen.badw.de/de/000914818/pdf/CC%20BY-NC-ND/ThLL%20vol.%2008%20col.%200001%E2%80%930786%20%28m%E2%80%93meocarius%29",
"http://publikationen.badw.de/de/000914818/pdf/CC%20BY-NC-ND/ThLL%20vol.%2008%20col.%200787%E2%80%931332%20%28meoculos%E2%80%93mogilalus%29",
"http://publikationen.badw.de/de/000914818/pdf/CC%20BY-NC-ND/ThLL%20vol.%2008%20col.%201333%E2%80%931764%20%28moincipium%E2%80%93myzon%29",
"http://publikationen.badw.de/de/000914819/pdf/CC%20BY-NC-ND/ThLL%20vol.%2009.2%20col.%200001%E2%80%930624%20%28o%E2%80%93omnividens%29",
"http://publikationen.badw.de/de/000914819/pdf/CC%20BY-NC-ND/ThLL%20vol.%2009.2%20col.%200625%E2%80%931214%20%28omnividentia%E2%80%93ozynosus%29",
"http://publikationen.badw.de/de/000094372/pdf/CC%20BY-NC-ND/ThLL%20vol.%2010.1.1%20col.%200001%E2%80%930694%20%28p%E2%80%93paternaliter%29",
"http://publikationen.badw.de/de/000094372/pdf/CC%20BY-NC-ND/ThLL%20vol.%2010.1.1%20col.%200695%E2%80%931472%20%28paterne%E2%80%93perimelides%29",
"http://publikationen.badw.de/de/000094372/pdf/CC%20BY-NC-ND/ThLL%20vol.%2010.1.2%20col.%201473%E2%80%932074%20%28perimetros%E2%80%93piceno%29",
"http://publikationen.badw.de/de/000094372/pdf/CC%20BY-NC-ND/ThLL%20vol.%2010.1.2%20col.%202075%E2%80%932780%20%28picercula%E2%80%93porrus%29",
"http://publikationen.badw.de/de/000094373/pdf/CC%20BY-NC-ND/ThLL%20vol.%2010.2.1%20col.%200001%E2%80%930644%20%28porta%E2%80%93praefinitivus%29",
"http://publikationen.badw.de/de/000094373/pdf/CC%20BY-NC-ND/ThLL%20vol.%2010.2.1%20col.%200645%E2%80%931232%20%28praefinitus%E2%80%93primaevitas%29",
"http://publikationen.badw.de/de/000094373/pdf/CC%20BY-NC-ND/ThLL%20vol.%2010.2.2%20col.%201233%E2%80%931970%20%28primaevus%E2%80%93propello%29",
"http://publikationen.badw.de/de/000094373/pdf/CC%20BY-NC-ND/ThLL%20vol.%2010.2.2%20col.%201971%E2%80%932798%20%28propemodum%E2%80%93pyxodes%29",
"http://publikationen.badw.de/de/036397929/pdf/CC%20BY-NC-ND/ThLL%20vol.%20onom.2%20col.%200001%E2%80%930814%20%28c%E2%80%93cyzistra%29",
"http://publikationen.badw.de/de/036397930/pdf/CC%20BY-NC-ND/ThLL%20vol.%20onom.3%20col.%200001%E2%80%930280%20%28d%E2%80%93dzoni%29",

# These are new fascicles, as of Dec. 2020

"http://publikationen.badw.de/de/039602104/pdf/CC%20BY-NC-ND/ThLL%20vol.%209.1.1%20col.%200001%E2%80%930208%20%28n%E2%80%93navalis%29",
"http://publikationen.badw.de/de/039602104/pdf/CC%20BY-NC-ND/ThLL%20vol.%209.1.2%20col.%200209%E2%80%930336%20%28navalis-nebel%29", "http://publikationen.badw.de/de/039602104/pdf/CC%20BY-NC-ND/ThLL%20vol.%209.1.3%20col.%200337%E2%80%930516%20%28nebel-nemo%29",
"http://www.thesaurus.badw.de/fileadmin/user_upload/Files/TLL/ThLL_IX_1__3_UEberhang_nemo_nemus.pdf",
"http://publikationen.badw.de/de/040453075/pdf/CC%20BY-NC-ND/ThLL%20vol.%2011.2.1%20col.%200001%E2%80%930144%20%28r-rarus%29",
"http://publikationen.badw.de/de/040453075/pdf/CC%20BY-NC-ND/ThLL%20vol.%2011.2.2%20col.%200145%E2%80%930320%20%28rarus-recido%29",
"http://publikationen.badw.de/de/040453075/pdf/CC%20BY-NC-ND/ThLL%20vol.%2011.2.3%20col.%200321%E2%80%930496%20%28recido-reddo%29",
"http://publikationen.badw.de/de/040453075/pdf/CC%20BY-NC-ND/ThLL%20vol.%2011.2.4%20col.%200497%E2%80%930656%20%28reddo-refocilo%29",
"http://publikationen.badw.de/de/040453075/pdf/CC%20BY-NC-ND/ThLL%20vol.%2011.2.5%20col.%200657%E2%80%930784%20%28refodio-regnum%29"
        )
};

