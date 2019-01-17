#!/usr/bin/perl -w

# Interface to Perseus morphological data and dictionaries.
package Diogenes::Perseus;
use strict;
use Diogenes::Base qw(%encoding %context @contexts %choices %work %author %database @databases @filters $logeion);
use Diogenes::EntityTable;
use FileHandle;
use Encode;
use open qw(:utf8);

use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);

# Use local CPAN
use lib ($Bin, catdir($Bin, '..', 'dependencies', 'CPAN') );

use XML::Tiny;
use CGI qw(:standard);

my $debug = 0;

#binmode STDOUT, ':utf8';
binmode ((select), ':utf8');

my $f = $Diogenes_Daemon::params ? new CGI($Diogenes_Daemon::params) : new CGI;
print STDERR "$Diogenes_Daemon::params\n" if $debug;

# This is the directory whence the decorative images that come with
# the script are served.
my $picture_dir = 'images/';

unless ($f->param('noheader')) {
    print $f->header(-charset=>'utf-8');
}
if ($f->param('popup')) {
    print $f->start_html(-title=>'Perseus Data',
                         -meta=>{'content' => 'text/html;charset=utf-8'},
                         -encoding=>"utf-8",
                         -script=>{-type=>'text/javascript',
                                   -src=>'diogenes-cgi.js'},
                         -style=>{ -type=>'text/css',
                                   -src=>'diogenes.css'});
    # For jumpTo
    print $f->start_form(-name=>'form',
                         -id=>'form',
                         -action=>"Diogenes.cgi");
    print $f->hidden( -name => 'JumpTo',
                      -default => "",
                      -override => 1 );
    print qq{<div>};

    # Subsequent pages should use this same pop-up
    print qq{<div id="sidebar" class="sidebar-newpage"></div>}
} else {
    print qq{<div id="sidebar-control"></div>};
}

my $footer = sub {
    if ($f->param('popup')) {
        print '</div>'; # font div
        print $f->end_form;
        print $f->end_html;
    }
};

my $request = $f->param('do') or warn "Bad Perseus request (a)";
my $query = $f->param('q') or warn "Bad Perseus request (b)";
my $lang = $f->param('lang') or warn "Bad Perseus request (c)";
my $xml_out = 1 if $f->param('xml');
my $inp_enc = $f->param('inp_enc') || '';

if ($lang ne 'grk') {
    # Latin -- do nothing.
}
elsif ($inp_enc eq 'Unicode') {
    # Already decoded utf8
    my $c = new Diogenes::UnicodeInput;
    $query = $c->unicode_greek_to_beta($query);
}
elsif ($inp_enc eq 'utf8') {
    # Bytes that need to be 
    $query = Encode::decode(utf8=>$query);
    my $c = new Diogenes::UnicodeInput;
    $query = $c->unicode_greek_to_beta($query);
}
elsif ($inp_enc eq 'Perseus-style') {
    eval "require Diogenes::Search; 1;";
    $query = Diogenes::Search::simple_latin_to_beta({}, $query);
}
elsif ($inp_enc eq 'BETA code') {
    $query =~ s#\\#/#g;                       # normalize accents
}
elsif ($inp_enc) {
    warn "I don't understand encoding $inp_enc!\n";
}
$query =~ tr/A-Z/a-z/;

my %dicts = (
    grk => ['grc.lsj.perseus-eng0.xml', 'LSJ', 'xml'],
    lat => ['lat.ls.perseus-eng1.xml', 'Lewis-Short', 'xml'],
    eng => ['gcide.txt', 'Gcide (based on 1913 Webster)', 'dict']
    );
if ($logeion) {
    $dicts{grk} = ['grc.lsj.logeion.xml', 'LSJ', 'xml']
}
my %format_fn;

warn "I don't know about language $lang!\n" unless exists $dicts{$lang};

use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
my $perseus_dir = catdir($Bin, '..', 'dependencies', 'data');
if (not -e $perseus_dir) {
    $perseus_dir = $ENV{Diogenes_Perseus_Dir} if $ENV{Diogenes_Perseus_Dir};
    if (not -e $perseus_dir) {
        print "<b>Sorry -- Perseus Data not installed!</b>";
        $footer->();
        exit;
    }
}
    
my $dict_file = File::Spec->catfile($perseus_dir, $dicts{$lang}->[0]);
my $dict_name = $dicts{$lang}->[1];
my $dict_format = $dicts{$lang}->[2];
my (%index_start, %index_end, $index_max, $size);
my ($idt_file, $txt_file, $dict_offset);
my $idt_fh = new FileHandle;
my $search_fh = new FileHandle;
my $format_sub;

use vars '$translate_abo';
do "perseus-abo.pl" or die ($! or $@);

my ($comp_fn, $key_fn);
# For ascii-sorted files.
my $ascii_comp_fn = sub {
    my ($a, $b) = @_;
    $a =~ tr /A-Z/a-z/;
    $b =~ tr /A-Z/a-z/;
    return $a cmp $b;
};
# For tab-separated files.
my $tab_key_fn = sub {
    my $line = shift;
    return split /\t/, $line, 2;
};
# For space-separated files.
my $space_key_fn = sub {
    my $line = shift;
    $line =~ m/^(\S+)/;
    return ($1, $line);
};

# For searching LSJ
# v is digammma, 0 is for prefatory material
my @alphabet = qw(0 a b g d e v z h q i k l m n c o p r s t u f x y w);
my %alph;
my $i = 1;
for (@alphabet) {
    $alph{$_} = $i;
    $i++;
}
my $beta_comp_fn = sub {
    my ($a, $b) = @_;
#     print "$a|$b|\n";
    my $min = (length $a < length $b) ? length $a : length $b;
    for ($i = 0; $i < $min; $i++) {
        my $aa = substr $a, $i, 1;
        my $bb = substr $b, $i, 1;
        die "Diogenes error: $aa, $bb" unless (exists $alph{$aa} and exists $alph{$bb});
#         print "$aa, $bb, $alph{$aa}, $alph{$bb}\n";
        return 1  if $alph{$aa} > $alph{$bb};
        return -1 if $alph{$aa} < $alph{$bb};
    }
    return 1  if length $a > length $b;
    return -1 if length $a < length $b;
    return 0;
};

my $xml_key_fn = sub {
    my $line = shift;
    my $key;
    if ($line =~ m/<entryFree[^>]*key\s*=\s*\"([^"]*)\"/)
    {
        $key = $1;
        $key =~ s/[^a-zA-Z]//g;
#         print "!$line\n";
    }
    else {
        # We have hit prefatory material
        return (0, '');
    }
    return ($key, $line);
};

my $lsj_search_setup = sub {
    open $search_fh, "<$dict_file" or die $!;
    $size = -s $dict_file;
    $key_fn = $xml_key_fn;
    if ($logeion) {
        $comp_fn = $ascii_comp_fn;
    }
    else {
        $comp_fn = $beta_comp_fn;
    }
};

my $lewis_search_setup = sub {
    open $search_fh, "<$dict_file" or die $!;
    $size = -s $dict_file;
    $comp_fn = $ascii_comp_fn;
    $key_fn = $xml_key_fn;
};

my $gcide_search_setup = sub {
    open $search_fh, "<$dict_file" or die $!;
    $size = -s $dict_file;
    $comp_fn = $ascii_comp_fn;
    $key_fn = $space_key_fn;
};

my $greek_parse_setup = sub {
    $idt_file = File::Spec->catfile($perseus_dir, 'greek-analyses.idt');
    $txt_file = File::Spec->catfile($perseus_dir, 'greek-analyses.txt');
    $comp_fn = $ascii_comp_fn;
    $key_fn = $tab_key_fn;
};

my $latin_parse_setup = sub {
    $idt_file = File::Spec->catfile($perseus_dir, 'latin-analyses.idt');
    $txt_file = File::Spec->catfile($perseus_dir, 'latin-analyses.txt');
    $comp_fn = $ascii_comp_fn;
    $key_fn = $tab_key_fn;
};

my $parse_prelims = sub {
    open $idt_fh, "<$idt_file" or die $!;
    local $/ = undef;
    my $code = <$idt_fh>;
    eval $code;
    warn "Error reading in saved corpora: $@" if $@;
    open $search_fh, "<$txt_file" or die $!;
};

# Recursive, line-wise binary search

# NB. This search is sloppy, since we don't know record boundaries.
# Results in lots of extra comparisons in failure case, but fast when
# successful.  The initial lower bound ($start) must be two less than
# the true bound, or the first record will never be found (not an
# issue when it's 0, i.e starting from the beginning of the file, as
# this is dealt with as a special case).

# $dict_offset tells us where the successful match began (for passing
# to next and prev entry), or in the case of an unsuccessful search,
# where the nearest-miss entry begins.

# We use global var to avoid leaking memory with recursive anon subs.
use vars '$binary_search';
$/ = "\n";
local $binary_search = sub {
    my $word = shift;
    my $start = shift;
    my $stop = shift;
    my $mid = int(($start + $stop) / 2);
    return undef if $start == $mid or $stop == $mid;
    seek $search_fh, $mid, 0;
    <$search_fh> unless $mid == 0;
    $dict_offset = tell $search_fh;
    my $line = <$search_fh>;
    chomp $line;
    (my $key, my $value) = $key_fn->($line);
    my $cmp = $comp_fn->($word, $key);
#       print "debug: $start -> $mid -> $stop  cmp: $cmp; $word vs $key\n";
    return $binary_search->($word, $start, $mid) if ($cmp == -1);
    return $binary_search->($word, $mid, $stop) if ($cmp == 1);
    return $value;
};

my $try_parse = sub {
    my $word = shift;
    my $key = substr($word, 0, 3);
    my $start = defined $index_start{$key} ? $index_start{$key} - 2 : 0;
    my $stop = $index_end{$key} || $index_max;
    return $binary_search->($word, $start, $stop);
};

my $beta_to_utf8 = sub {
    my $text = shift;
    $text =~ s/#?(\d)$/ $1/g;
    my %fake_obj;    # Dreadful hack
    $fake_obj{encoding} = 'UTF-8';
    $text =~ tr/a-z/A-Z/;
    Diogenes::Base::beta_encoding_to_external(\%fake_obj, \$text);
    $text =~ s/([\x80-\xff])\_/$1&#x304;/g; # combining macron
    $text =~ s/_/&nbsp;&#x304;/g;
    $text =~ s/([\x80-\xff])\^/$1&#x306;/g; # combining breve
    $text =~ s/\^/&nbsp;&#x306;/g; 
    # Decode from a 'binary string' to a UTF-8 'text string' so the
    # UTF-8 strings from Diogenes::EntityTable can be mixed freely
    return Encode::decode('utf-8', $text);
};

my $text_with_links = sub {
    my $text =  shift;
    my $text_lang = shift;
    $text_lang = "lat" if $text_lang eq "la";
    $text_lang = "grk" if $text_lang eq "greek";
    my $out = '';
    $out .= " " if $text =~ m/^(\s+)/;
    # skip spaces 
    while ($text=~m/([^\s]+)(\s*)/g) {
        my $word = $1;
        my $space = $2 || '';
        my $form = $word;
        $form =~ s/\-//g;
        $form =~ s/[^A-Za-z]//g if $text_lang eq 'eng';
        $word = $beta_to_utf8->($word) if $text_lang eq "grk" and not $logeion;
        # We use a new page, since otherwise the back button won't get
        # us back where we came from. -- Changed to workaround FF bug.
        if ($form) {
            # Escape backslashes for Javascript
            $form =~ s/\\/\\\\/g;
            $out .= qq{<a onClick="parse_$text_lang}.qq{('$form');">$word</a>};
        }
        else {
            $out .= $word;
        }
        $out .= $space;
    }

    return $out;
};

my $qquery = ($lang eq "grk" and not $logeion) ? $beta_to_utf8->($query) : $query;

my $munge_ls_lemma = sub {
    my $text =shift;
    $text =~ s/\_/&#x304;/g;
    $text =~ s/\^/&#x306;/g;
    $text =~ s/#?(\d)$/ $1/g;
    return $text;
};

my $format_latin_analysis = sub {
    my $a = shift;
    print $a;
};

# Use global vars to avoid leaking memory with recursive anon subs
use vars '$xml_lang', '$munge_tree', '$munge_content', '$munge_element', '$xml_ital';
my ($out, $in_link);
my $munge_xml = sub {
    my $text = shift;
    # Tiny.pm will complain if not well-formed -- get rid of stray divs and milestones
    $text =~ s/^.*?<entryFree /<entryFree /;
    $text =~ s/<\/entryFree>.*$/<\/entryFree>/;
    return $text if $xml_out;
    $out = '';
    local $xml_lang = '' ; # dynamically scoped
    local $xml_ital = 0  ; 
    my $tree = XML::Tiny::parsefile($text,
                                    'no_entity_parsing' => 1,
                                    'input_is_string' => 1,
                                    'preserve_whitespace' => 1);
    $munge_tree->($tree);
    
    my $entity;
    foreach $entity (%Diogenes::EntityTable::table) {
        $out =~ s/&$entity;/$Diogenes::EntityTable::table{$entity}/g;
    }
    return $out;
};

local $munge_tree = sub {
    my $array_ref = shift;
    foreach my $item (@{ $array_ref }) {
        $munge_content->($item);
    }
};

my $munge_text = sub {
    my $e = shift;
    my $text = $e->{content};
    if (not $in_link) {
        if ($xml_lang eq 'greek' or $xml_lang eq 'la') {
            $text = $text_with_links->($text, $xml_lang);
        }
        # BUG: These hacks cause much that is English to be misidentified
        #      as Latin. Not sure yet what cases it's needed for.
        #elsif ($lang eq 'lat' and $text =~ m/^, (?:v\.|=) /) {
        #    # Hack for L-S cross refs (not identified as Latin).
        #    $text = $text_with_links->($text, 'lat');
        #}
        #elsif ($lang eq 'lat' and not $xml_ital) {
        #    # Hack to make all non-italicized L-S text Latin
        #    $text = $text_with_links->($text, 'lat');
        #}
        else {
            $text = $text_with_links->($text, 'eng');
        }
    }
    $out .= $text;
};

local $munge_content = sub {
    my $item = shift;
    if ($item->{type} eq 'e') {
        $munge_element->($item);
    }
    elsif ($item->{type} eq 't') {
        $munge_text->($item);
    }
    else {
        warn("Bad tree");
    }
};

my $swap_element = sub {
    my $e = shift;
    my $close = shift;
    if ($e->{name} eq 'sense') {
        if ($close) {
            $out .= '</div>';
        } else {
            my $level = $e->{attrib}->{level};
            my $padding = $level * 2;
            $out .= qq{<div id="sense" style="padding-left: $padding}.qq{em; padding-bottom: 0.5em">};
        }
    }
    if ($lang eq 'grk' and $e->{name} =~ m/^tr|orth$/) {
        $out .= $close ? '</b>' : '<b>';
    }
    if ($e->{attrib}->{rend} and $e->{attrib}->{rend} eq 'ital') {
        if ($close) {
            $out .= '</i>';
            $xml_ital = 0;
        } else {
            $out .= '<i>';
            $xml_ital = 1;
        }
    }
    if ($e->{name} eq "bibl" and exists $e->{attrib}->{n}
        and $e->{attrib}->{n} =~ m/^(?:Perseus:abo:|urn:cts:latinLit:|urn:cts:greekLit:)(.+)$/) {
        if ($close) {
            $out .= '</a>';
            $in_link = 0;
        }
        else {
            my $jump = $1;
            $jump = $translate_abo->($jump);
            # DEBUGGING
            $out .= qq{<a class="origjump $e->{attrib}->{n}" onClick="jumpTo('$jump');">};
            #$out .= qq{<a onClick="jumpTo('$jump');">};
            $in_link = 1;
        }
    }

};

local $munge_element = sub {
    my $e = shift;
    $swap_element->($e, 0); # open it
    if ($e->{name} eq 'entryFree') {
        my $key = $e->{attrib}->{key};
        $key = $munge_ls_lemma->($key) if $lang eq 'lat';
        $key = $beta_to_utf8->($key) if $lang eq 'grk';
        $out .= '<h2>' . $key . '</h2>';
    }
    if ($e->{attrib}->{lang} ) {
        local $xml_lang = $e->{attrib}->{lang};
        $munge_tree->($e->{content});
    } else {
        $munge_tree->($e->{content});
    }
    $swap_element->($e, 1); # close it
};

$format_fn{xml} = sub {
    my $text = shift;
#      print STDERR "\n\n$text\n\n";
    print "<div>";
    print qq{<a onClick="prevEntry$lang($dict_offset)"><img class="prev" src="${picture_dir}go-previous.png" srcset="${picture_dir}go-previous.hidpi.png 2x" alt="Previous Entry" /></a> };
    print qq{<a onClick="nextEntry$lang($dict_offset)"><img class="next" src="${picture_dir}go-next.png" srcset="${picture_dir}go-next.hidpi.png 2x" alt="Next Entry" /></a>};
    print "</div><hr />";
    print $munge_xml->($text);
};

$format_fn{dict} = sub {
    my $text = shift;
    $text =~ s#(\S+)(\s*)#$text_with_links->($1, $lang).($2||'')#ge;
    $text =~ s#\t#\n#g;
    $text =~ s#^(<[^>]+>)([A-Za-z]+)(</[^>]>)#$1<b>$2</b>$3#g;
    $text =~ s#\n(<[^>]+>)([A-Za-z]+)(</[^>]>)#\n<hr padding=2>$1<b>$2</b>$3#g;
    $text =~ s#\n(\s+)#'<br>'.('&nbsp;' x length $1)#ge;

    print $text;
     print qq{<hr><a onClick="prevEntry$lang($dict_offset)">Previous Entry</a>&nbsp;&nbsp;&nbsp;<a onClick="nextEntry$lang($dict_offset)">Next Entry</a><hr>};

};
    
my $format_dict = sub {
    my $text = shift;
    $format_fn{$dict_format}->($text);
};
        
my $do_lookup = sub {
    my $word = shift;
    my $exact = shift;
    if ($lang eq 'grk' ) {
        $lsj_search_setup->();
    }
    elsif ($lang eq 'lat' ) {
        $lewis_search_setup->();
    }
    elsif ($lang eq 'eng' ) {
        $gcide_search_setup->();
    }
    else {
        warn "Bad Perseus request (e)";
    }
    my $pretty_word = ($lang eq "grk") ?
        $beta_to_utf8->($word) : $word;

    $word =~ tr/A-Z/a-z/;
    $word =~ s/[^a-z]//g;
    my $output = $binary_search->($word, 0, $size);
    if ($output) {
        $format_dict->($output);
        return 1;
    }
    elsif (not $exact) {
        print "<p>Could not find dictionary headword for $pretty_word.  Showing nearest entry.</p>";
        seek $search_fh, $dict_offset, 0;
        my $entry = <$search_fh>;
        $format_dict->($entry);
    }
    else {
        return undef;
    }
};

my $format_analysis = sub {
    my $anl = shift;
    $query = $beta_to_utf8->($query) if $lang eq 'grk' and not $logeion;
    my (@out, @suppl);
#     print "\n\n$anl\n\n";
    while ($anl =~ m/{([^\}]+)}((?:\[\d+\])*)/g) {
#     while ($anl =~ m/{([^\}]+)}/g) {
        my $entry = $1;
        my $suppl = $2;
        if ($entry =~ m/^(\d+) (\d) (.*?)\t(.*?)\t(.*?)$/) {
            my ($dict, $conf, $lemma, $trans, $info) = ($1, $2, $3, $4, $5);
            $lemma = $beta_to_utf8->($lemma)
                if $lang eq 'grk' and not $logeion;
            $lemma = $munge_ls_lemma->($lemma) if $lang eq 'lat';
            $lemma .= " ($trans)" if $trans =~ m/\S/;
            $lemma .= ": $info";
            push @out, [$dict, $conf, $lemma];
        }
        else {
            warn "Bad analysis: $entry";
        }
        if ($suppl) {
            while ($suppl =~ m/\[(\d+)\]/g) {
                push @suppl, $1;
            }
        }
    }
    my (@dicts, %conf);
    if (scalar @out == 1) {
        my ($dict, $conf, $lemma) = @{ $out[0] };
        print $f->h1("Perseus analysis of $query:");
        print $f->p($lemma);
        @dicts = ($dict);
        $conf{$dict} = $conf;
    }
    else {
        print $f->h1("Perseus analyses of $query:");
        print "<ol>\n";
        for (@out) {
            my ($dict, $conf, $lemma) = @{ $_ };
            print $f->li($lemma);
            push @dicts, $dict unless exists $conf{$dict};
            $conf{$dict} += $conf;
        }
        print "</ol>";
    }
    if (@suppl) {
        for (@suppl) {
            unless (exists $conf{$_}) {
                $conf{$_} = -1;
                push @dicts, $_;
            }
        }
    }
    print "\n";
    if (scalar @dicts == 1) {
        print $f->h1("$dict_name entry");
    } else {
        print $f->h1("$dict_name entries");
    }
    for my $dict (@dicts) {
        if ($conf{$dict} == -1) {
            print $f->p("Supplementary prefix entry:");
        } elsif ($conf{$dict} == 0) {
            print $f->p("(NB. Could not find dictionary headword; this is around
the spot it should appear.)");
        } elsif ($conf{$dict} <= 2) {
            print $f->p("(NB. This dictionary headword is a guess.)");
        }
        open my $dict_fh, "<$dict_file" or die $!;
        seek $dict_fh, $dict, 0;
        $dict_offset = $dict;
        my $entry = <$dict_fh>;
#          print "\n\n$entry\n\n";
        $format_dict->($entry);
    }
};

my $lem_num = 0;

my $format_inflect = sub {
    $lem_num++;
    my ($lem, $out) = @_;
    my @out = split /\t/, $out;
    my $dict = shift @out;
    my $link = qq{<a onClick="getEntry$lang('$dict');">}.
        (($lang eq "grk" and not $logeion) ? $beta_to_utf8->($lem) : $lem).
        qq{</a>};
    print qq{<h2><a onClick="toggleLemma('$lem_num');"><img src="${picture_dir}opened.png" srcset="${picture_dir}opened.hidpi.png 2x"
align="bottom" id="lemma_$lem_num" /></a>&nbsp;$link</h2>};

    print qq{<span class="lemma_span_visible" id="lemma_span_$lem_num">};
    for (@out) {
        m/^(\S+)(.*)$/;
        my ($form, $infl) = ($1, $2);
        my $label = (($lang eq "grk" and not $logeion) ?
                     $beta_to_utf8->($form) : $form) . ": $infl";
        print qq{<span class="form_span_visible" infl="$infl"><input type="checkbox" name="lemma_list" value="$form">$label</input><br/></span>};
    }
    print '</span>';
};

my $failed_inflect = sub {
    print "Could not find lemma for $qquery\n";
};


my $do_inflect = sub {
    my $lemma = shift;
    my $filename = ($lang eq 'grk' ? 'greek' : 'latin') . '-lemmata.txt';
    $txt_file = File::Spec->catfile($perseus_dir, $filename);
    $size = -s $txt_file;
    $comp_fn = $ascii_comp_fn;
    $key_fn = $tab_key_fn;
    open $search_fh, "<$txt_file" or die $!;
    my $output = $binary_search->($lemma, 0, $size);
    if ($output) {
        $format_inflect->($lemma, $output);
    }
    else {
        $failed_inflect->();
    }
};

my $do_inflects = sub {
    my @lemmata = split /[,\s]+/, $query;
    for (@lemmata) {
        next if m/^\s*$/;
        $do_inflect->($_);
    }
};

my $normalize_latin_lemma = sub {
    my $lemma = shift;
    $lemma =~ s/[_^]//g;

    if ($lemma =~ m/-/) {
        $lemma =~ s/(.*)-(.*)/$1$2/;
    }
    $lemma =~ s/\d$//;
    return $lemma;
};

my $normalize_greek_lemma = sub {
    my $lemma = shift;
    # We strip breathings, too, because that surprises less
    $lemma =~ s/[_^,-\\\/=+\d)(]//g;
    return $lemma;
};


my $find_lemma = sub {
    my $filename = ($lang eq 'grk' ? 'greek' : 'latin') . '-lemmata.txt';
    my $norm_func = ($lang eq 'grk' and not $logeion) ?
        $normalize_greek_lemma : $normalize_latin_lemma;
    $txt_file = File::Spec->catfile($perseus_dir, $filename);
    my $target = $norm_func->($query);
    $target =~ s/[,\s]+/ /g;
    $target = quotemeta $target;
    $target =~ s/\\ /\\b/g;
    open my $fh, "<$txt_file" or die $!;
    my (@results, %dicts);
    $/ = "\n";
    # Linear search, since we are looking for any partial match
    while (<$fh>) {
        m/^(.*?)\t(.*?)\t/;
        my $key = $1;
        my $dict = $2;
        my $norm_key = $norm_func->($1);
        if ($norm_key =~ /$target/) {
            push @results, $key;
            $dicts{$key} = $dict;
        }
    }
    my $qq = $lang eq "grk" ? $beta_to_utf8->($query) : $query;
    if (@results) {
        my %labels;
        $labels{$_} = qq{<a onClick="getEntry$lang('$dicts{$_}');">}.
            (($lang eq "grk" and not $logeion) ? $beta_to_utf8->($_) : $_).
            qq{</a>} for @results;
        print $f->h2("Lemma matches for $qq:");
        $f->autoEscape(0);
        print $f->checkbox_group(-name=> "lemma_list",
                                 -values=>\@results,
                                 -labels=>\%labels,
                                 -linebreak=>1);
        $f->autoEscape(1);
    } else {
        print "Sorry, no lemma matches were found for $qq (language = $lang)\n";
    }
    
};

my $get_entry = sub {
    my $direction = shift;
    die "Bad seek parameter for query" unless $query =~ m/^\d+$/;
    open my $fh, "<$dict_file" or die $!;
    seek $fh, $query, 0 or die $!;
    my $entry;
    if ($direction eq 'next') {
        $entry = <$fh>;
    } elsif ($direction eq 'prev') {
        my $char = '';
        while ($char ne "\n") {
#             print STDERR "$char";
            seek $fh, -2, 1;
            read $fh, $char, 1;
        }
    }
    $dict_offset = tell $fh;
    $entry = <$fh>;
#     print STDERR "\n\n$entry\n\n";
    $format_dict->($entry);
    close $fh or die $!;
};

my $do_parse = sub {
    if ($lang eq 'grk' ) {
        $greek_parse_setup->();
    }
    elsif ($lang eq 'lat' ) {
        $latin_parse_setup->();
    }
    else {
        warn "Bad Perseus request (e)";
    }
    $parse_prelims->();

    # Normalize barytone
    $query =~ s#\\#/#g;
    # Remove ~hit~ and punctuation
    $query =~ s/~hit~//;
    $query =~ s/[~,.;:?!"']//g;
    my $word = $query;
    # remove leading & trailing spaces
    $word =~ s/^\s+//g;
    $word =~ s/\s+$//g;
    # remove diareses
    $word =~ s/\+//g;
#     print "\n\n-$word-$query-\n";
    # Accent thrown back from enclitic?
    $word =~ s/^(.*[\\\/=].*)[\\\/=]/$1/;
    my $analysis = $try_parse->($word);
    if (not defined $analysis) {
        # Try lower-case if upper
        if (($lang eq 'lat' or $logeion) and $word =~ m/^[A-Z]/) {
            $word =~ tr/A-Z/a-z/;
            $analysis = $try_parse->($word);
        }
        elsif ($lang eq 'grk' and not $logeion and $word =~ m/^\*/) {
            $word =~ s/\*//g;
            $word =~ s/^([\\\/=|)(]+)([aeiouhw])/$2$1/;
            $analysis = $try_parse->($word);
            if (not defined $analysis) {
                if ($word =~ s/^([aeiouhw])([\\\/=|)(]+)([aeiouhw])/$1$3$2/) {
                    $analysis = $try_parse->($word);
                }
            }
        }
    }
    
    if (defined $analysis) {
        $format_analysis->($analysis);
    }
    else {
        print "<p>Could not parse $qquery.  Looking in dictionary.</p>";
        # do search in dict
        $do_lookup->($query);
    }
};

my $try_english = sub {
    my $lemma = shift;
    my $entry = $do_lookup->($lemma, 1);
};

my @suffixes = qw{s es d ed n en ing};

my $parse_english = sub {
    return if  $try_english->($query);
    eval "require PorterStemmer;";
    my $lemma = PorterStemmer::stem($query);
    return if $try_english->($lemma);
    for my $s (@suffixes) {
        $lemma = $query;
        if ($lemma =~ s/$s$//) {
            return if $try_english->($lemma);
        }
    }
    print "<p>Could not find $query in the $dict_name English dictionary.</p>";

};

print STDERR "Perseus: >$request, $lang, $query<\n" if $debug;

if ($request eq 'parse') {
    if ($lang eq 'eng') {
        $parse_english->();
    }
    else {
        $do_parse->();
    }
}
elsif ($request eq 'lookup') {
    $do_lookup->($query);
}
elsif ($request eq 'inflect') {
    $do_inflect->($query);
}
elsif ($request eq 'inflects') {
    $do_inflects->();
}
elsif ($request eq 'lemma') {
    $find_lemma->();
}
elsif ($request eq 'get_entry') {
    $get_entry->();
}
elsif ($request eq 'prev_entry') {
    $get_entry->('prev');
}
elsif ($request eq 'next_entry') {
    $get_entry->('next');
}
else {
    warn "Bad Perseus request (d)";
}

$footer->();

1;
