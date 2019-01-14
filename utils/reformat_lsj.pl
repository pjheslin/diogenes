#!/usr/bin/perl -w
use strict;

# Unfortunately Perseus updated the formatting of their XML files to be more usable, which broke our naive XML parsing. This script returns the XML to its less readable form, as that is easier than converting all of Diogenes to do proper XML parsing.

# The -l option is to process the forked version of the Perseus LSJ of the Logeion project.  Helma Dik has corrected many errors in the original Perseus XML translation of the LSJ.  Some of the tags have been changed and the beta code has been converted into Unicode.  Many of the corrections involve splitting entries that were wrongly compressed into one when the XML was created, but Morpheus would need to be rebuilt to take advantage of that.

my $logeion;
$logeion = 1 if @ARGV and $ARGV[0] eq '-l';

use XML::Parser;
use XML::Parser::EasyTree;
my $parser = new XML::Parser(Style=>'EasyTree');
binmode STDOUT, ':utf8';

sub attribs_str {
    my $s = '';
    my $attrib = shift;
    for my $key (sort(keys(%$attrib))) {
        # The TEIform attribs just take up an enormous amount of space.
        next if $key eq 'TEIform';
        $s .= ' ' . $key . '="' . $attrib->{$key} . '"';
    }
    return $s;
}

my $inentry = 0;
sub print_contents {
    for my $item (@_) {
        if(ref($item) eq 'ARRAY') {
            print_contents(@$item);
            next;
        }
        if($item->{'type'} eq 't') {
            if ($inentry) {
                my $content = $item->{'content'};
                # Consolidate whitespace.
                $content =~ s/\s+/ /gs;
                printf("%s", $content);
            }
        } else {
            if ($logeion and $item->{'name'} eq 'div2') {
                $item->{'name'} = 'entryFree';
            }
            if($item->{'name'} eq 'entryFree') {
                $inentry = 1;
            }
            if($inentry) {
                if (scalar keys %{$item->{'attrib'}}) {
                    printf("<%s%s>", $item->{'name'},
                           attribs_str($item->{'attrib'}));
                } else {
                    printf("<%s>", $item->{'name'});
                }
            }
            print_contents($item->{'content'});
            if($inentry) {
                printf("</%s>", $item->{'name'});
            }
            if($item->{'name'} eq 'entryFree') {
                $inentry = 0;
                printf("\n");
            }
        }
    }
}

my @x = $parser->parse(\*STDIN);

for my $i (@x) {
	print_contents($i);
}
