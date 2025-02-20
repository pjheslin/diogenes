#!/usr/bin/env perl
use strict;
use warnings;
use 5.012;
use autodie;
use File::Spec::Functions qw(:ALL);
use Getopt::Std;
use JSON;

# New script to get the TLL info from the JSON file they have provided.

getopts ('t:l:i:');
our ($opt_i, $opt_l, $opt_t);

sub HELP_MESSAGE { print qq{

This script uses data from the TLL to figure out the headwords of the
pages in the PDFs

-i PATH The path to the index.json file from the TLL website.

-l PATH Directory in which to put the file tll-pdf-list.txt, which
        contains the PDF filenames, indexed for easier use.

-t PATH The path to the directory containing the TLL PDFs.
    }
}

my ($path, $list, $list_fh);
unless ($opt_t and $opt_l and $opt_i) {
    die "Error. Options -t, -l and -i are all required.\n";
}
my $json_file = $opt_i;
$path = $opt_t;
$list = $opt_l;

$list = File::Spec->catfile($list, 'tll-pdf-list.txt');
open $list_fh, ">$list" or die "Could not open $list for writing: $!";
print STDERR "Writing file list to $list\n";

my @pdfs;
opendir(my $dh, $path);
while (my $file = readdir $dh) {
    next if $file =~ m/^\./;
    next unless $file =~ m/\.pdf$/i;
    next unless $file =~ m/ThLL/;
    my ($vol, $cs, $ce) = get_vol_and_col($file);
    my $key = "$vol.$cs";
    # print STDERR "$vol, $cs, $ce, $key\n";
    push @pdfs, [$vol, $cs, $ce, $key];
    print $list_fh "$key\t$file\n"; 
}
closedir $dh;
close $list_fh;

my %bookmarks;
my %start_page = %{ start_pages() };
# Index for TLL pageview on website; hopeless to parse as JSON 
open(my $json_fh, "<:encoding(UTF-8)", $json_file)
    or die("Can't open $json_file: $!\n");
my $junk = <$json_fh>; # throw away first line
my @lines = <$json_fh>;
print STDERR "Processing index.json\n";

# We take the lines in reverse order so that, when there are multiple
# numbered entries for the same lemma, the first one at the start of
# all the entries takes precedence.
for (my $i = $#lines; $i >= 0; $i--) {
    my $line = $lines[$i];
    $line =~ m#\{"0":\{"_":"(.*?)\s+<a onclick=\\"rI\(event,'-/(.*?)\.(jpg|pdf)#;
    my $word = $1;
    my $vol_col = $2;
    next if $line =~ m/\"DT_RowId\":83061\}/; # Bad entry
    warn "BAD: $line" unless $word and $vol_col;
    $word =~ s#</?small>##g;
    $word =~ s#&[lg]t;##g;
    $word =~ s#^\d\.\s*##g;
    $word =~ s#<x->.*$##g;
    $word =~ s#,.*$##g;
    $word =~ s#[()?.-]##g;
    $word =~ s#\s.*$##g;
    next unless $word;
    $vol_col =~ m/(.*)\.(\d+)$/;
    my $vol = $1;
    my $col = $2;
    $vol =~ s/,/./g;
    my ($key, $start_col);
    # print STDERR "v: $vol; c: $col\n";
    foreach my $pdf (@pdfs) {
        if ($vol eq @{$pdf}[0] and $col >= @{$pdf}[1] and $col <= @{$pdf}[2]) {
            $key = @{$pdf}[3];
            $start_col = @{$pdf}[1];
            last;
        }
    }
    if ($key) {
        my $page = (($col - $start_col) / 2) + $start_page{$key};
        $bookmarks{$word} = "$key\t$page";
        # print STDERR "$word -> $vol -> $col -> $key -> $page\n";
    }
    else {
        print STDERR "Error processing $word; $vol_col; $vol; $col \n";
    }

}

foreach my $k (sort keys %bookmarks) {
    print $k."\t".$bookmarks{$k}."\n";
}

sub get_vol_and_col {
    my $filename = shift;
    # Volume number in the json index is either one part or two.  We don't care about the third part of the volume number, since the json index does not use it and in any case it is not used consistently in filenames to denote the fascicle.

    # Filenames have been tidied up and made consistent, including replacing en-dashes with hyphens.
    
    die $! unless $filename =~ m/ThLL vol\. ((?:onom|\d+)(?:\.\d+)?)/;
    my $vol = $1;
    $vol =~ s/onom\./o/;
    $vol =~ s/^0+//;
    die $! unless
        $filename =~ m/ThLL vol\. (?:onom|\d+)(?:[\.\d]+)* col\. (\d+)-(\d+)/;
    my $col_start = $1;
    my $col_end = $2;
    $col_start =~ s/^0+//;
    $col_end =~ s/^0+//;

    # Errors in these filename: they forgot the addenda/corrigenda
    $col_end = "1956" if $vol eq '7.2' and $col_start eq '1347';
    $col_end = "1916" if $vol eq '9.2' and $col_start eq '625';
    $col_end = "2788" if $vol eq '10.1' and $col_start eq '2075';
    $col_end = "2804" if $vol eq '10.2' and $col_start eq '1971';
    $col_end = "816" if $vol eq 'o2';
    $col_end = "284" if $vol eq 'o3';
    return $vol, $col_start, $col_end;
}

# We need to have a list telling us on what page of the PDF the first
# column appears (the number of the first column is given in the
# filename).  This could be extracted from some the new PDFs, but not
# the ones that start at column 1 or for the old PDFs.  So we do it
# manually.

sub start_pages {
    return
    { '1.1' => 16,
      '1.725' => 3,
      '1.1411' => 3,
      '2.1' => 3,
      '2.707' => 3,
      '2.1325' => 3,
      '2.1647' => 3,
      '3.1' => 9,
      '3.749' => 3,
      '3.1445' => 3,
      '4.1' => 3,
      '4.789' => 3,
      '5.1.1' => 13,
      '5.1.559' => 3,
      '5.1.1103' => 3,
      '5.1.1813' => 3,
      '5.2.1' => 6,
      '5.2.759' => 3,
      '5.2.1277' => 3,
      '5.2.1823' => 3,
      '6.1.1' => 6,
      '6.1.809' => 3,
      '6.2.1665' => 6,
      '6.3.2389' => 4,
      '6.3.2781' => 3,
      '7.1.1' => 6,
      '7.1.841' => 3,
      '7.1.1597' => 3,
      '7.2.1' => 8,
      '7.2.761' => 4,
      '7.2.1347' => 3,
      '8.1' => 6,
      '8.787' => 3,
      '8.1333' => 3,
      '9.1.1' => 1,
      '9.1.209' => 1,
      '9.1.337' => 1,
      '9.1.513' => 1,
      '9.2.1' => 8,
      '9.2.625' => 3,
      '10.1.1' => 6,
      '10.1.695' => 3,
      '10.1.1473' => 4,
      '10.1.2075' => 3,
      '10.2.1' => 6,
      '10.2.645' => 3,
      '10.2.1233' => 4,
      '10.2.1971' => 3,
      '11.2.1' => 1,
      '11.2.145' => 1,
      '11.2.321' => 1,
      '11.2.497' => 1,
      '11.2.657' => 1,
      '11.2.785' => 1,
      '11.2.961' => 1,
      '11.2.1121' => 1,
      'o2.1' => 4,
      'o3.1' => 3
    }
}
