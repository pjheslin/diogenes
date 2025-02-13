#!/usr/bin/env perl

# Lightly reformat the quasi-XML of Gcide, as cloned from
# https://git.savannah.gnu.org/git/gcide.git

# Decided to bin this.  The XML version is a total mess.  Much better
# to use the old Dict formatted version.

use strict;
use warnings;
# utf8 in and out.
binmode STDOUT, ':utf8';
binmode STDIN, ':utf8';
use open ':utf8';
my $path = shift @ARGV;

local $/ = "";
my $start = 1;

foreach my $letter ("A" .. "Z") {
    my $file = $path."CIDE.$letter";
    print "$file\n";
    my $last_entry = '';

    open my $fh, "<$file" or die $!;
    while ( <$fh> ) {

        my ($entry, $pos, $def, $subentry);
        if (m#<ent>(.*?)</ent>#s) {
            $entry = $1;
        }
        if (m#<pos>(.*?)</pos>#s) {
            $pos = $1;
        }
        if (m#<def>(.*?)</def>#s) {
            $def = $1 || '';            
        }
        # print "\n\n>>>>> $entry, $pos, $def\n<<<<\n";
        if (defined $entry and $entry ne $last_entry) {
            print "</ul></entryFree>" unless $start;
            print "\n\n<entryFree key=$entry><hr/><ul>";
            $start = 0;
        }
        if ($entry or $pos) {
            my $this_entry = $entry || $last_entry;
            my $this_pos;
            if ($pos) {
                $this_pos = ', '.$pos;
            }
            else {
                $this_pos = '';
            };
            print "\n<h2>$this_entry$this_pos</h2>";
        }
        if ($def) {
            print "<li>$def</li>";
        }
        $last_entry = $entry if $entry;
    }
}
