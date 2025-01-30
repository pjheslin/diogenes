#!/usr/bin/env perl
use strict;
use warnings;
use v5.12;

my $dir = shift @ARGV or die "No directory specified";

opendir(my $dh, $dir) || die "Can't open $dir: $!";
my @files = sort readdir($dh);

while ( my $name = shift @files ) {
    if ($name =~ m/(?:phi|lat)(\d\d\d\d)\.txt/i) {
        my $size = -s "$dir/$name";
        print "$1\t$size\n";
    }
}
closedir $dh;
