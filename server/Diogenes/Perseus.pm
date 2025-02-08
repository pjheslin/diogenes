#!/usr/bin/env perl
# Interface to Perseus morphological data and dictionaries.

# This cgi script has been recast as a module, so that we can require
# it once and not reparse the file for each query that comes to the
# server.
package Diogenes::Perseus;

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
# Use local CPAN
use lib ($Bin, catdir($Bin, '..', 'dependencies', 'CPAN') );
my $perseus_dir = catdir($Bin, '..', 'dependencies', 'data');

use Diogenes::Base qw(%encoding %context @contexts %choices %work %author %database @databases @filters);
use Diogenes::EntityTable;
use FileHandle;
use Encode;
use Unicode::Normalize;
use URI::Escape;

# The lexica are now utf8, but we need to read the files in as bytes,
# as we want to jump into the middle and read backwards.  We then
# convert entries to utf8 by hand.
use open IN  => ":bytes", OUT => ":utf8";

use XML::Tiny;
use CGI qw(:standard);

my $debug = 0;

# This is the directory whence the decorative images that come with
# the script are served.  Overridden later for DiogenesWeb
my $picture_dir = 'images/';

my %dicts = (
    grk => ['grc.lsj.xml', 'LSJ', 'xml'],
    lat => ['lat.ls.perseus-eng1.xml', 'Lewis-Short', 'xml'],
    eng => ['gcide.txt', 'Gcide (based on 1913 Webster)', 'dict']
    );
my %format_fn;

use vars '$translate_abo';
do "perseus-abo.pl" or die ($! or $@);

# For searching LSJ
# v is digammma, 0 is for prefatory material
my @alphabet = qw(0 a b g d e v z h q i k l m n c o p r s t u f x y w);
my %alph;
my $i = 1;
for (@alphabet) {
    $alph{$_} = $i;
    $i++;
}
# For English
my @suffixes = qw{s es d ed n en ing};

# Needed by setup().
my $beta_to_utf8 = sub {
    my $text = shift;
    if ($text !~ m/^[\x00-\x7f]*$/) {
        # In Logeion LSJ, the Greek (apart from keys) is already utf8
        return $text;
    }
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

my ($f, $request, $query, $qquery, $lang, $xml_out, $inp_enc);
my $footer = sub {
    if ($f->param('popup')) {
        print '</div>'; # font div
        print $f->end_form;
        print $f->end_html;
    }
};

our (%index_start, %index_end, $index_max);
my ($dict_file, $dict_name, $dict_format, $idt_fh, $search_fh);
my ($size, $idt_file, $txt_file, $dict_offset);
my ($comp_fn, $key_fn, $format_sub);
my ($lem_num, $logeion_link);
my ($dweb, $external_dict);

my $setup = sub {

    my $parameters = shift;
    binmode ((select), ':utf8');
    $| = 1;

    if ($parameters) {
        $f = new CGI($parameters);
    }
    elsif ($Diogenes_Daemon::params) {
        $f = new CGI($Diogenes_Daemon::params)
    }
    else {
        $f = new CGI;
    }

    $request = $f->param('do') or warn "Bad Perseus request (a)";
    $query = $f->param('q') or warn "Bad Perseus request (b)";
    $lang = $f->param('lang') or warn "Bad Perseus request (c)";
    $xml_out = 1 if $f->param('xml');
    $inp_enc = $f->param('inp_enc') || '';
    $qquery = ($lang eq "grk" and $inp_enc ne 'utf8') ? $beta_to_utf8->($query) : $query;
    # Convert to utf8 unless already converted
    $qquery = Encode::decode(utf8=>$qquery) unless $qquery =~ /[^\x00-\xFF]/;
    $external_dict = $f->param('dict');

    print STDERR "Perseus: >$request, $lang, $query, $qquery, $inp_enc, $external_dict<\n" if $debug;

    # DiogenesWeb version number
    $dweb = $f->param('dweb');
    if ($dweb) {
        $picture_dir = "../static/images/";
    }

    $dict_file = File::Spec->catfile($perseus_dir, $dicts{$lang}->[0]);
    $dict_name = $dicts{$lang}->[1];
    $dict_format = $dicts{$lang}->[2];
    $idt_fh = new FileHandle;
    $search_fh = new FileHandle;

    unless ($f->param('noheader')) {
        print $f->header(
            -charset=>'utf-8',
            -'Access-Control-Allow-Origin' => '*');
    }
    if ($f->param('popup')) {
        if ($dweb) {
            print $f->start_html(-title=>'Perseus Data',
                                 -meta=>{'content' => 'text/html;charset=utf-8'},
                                 -encoding=>"utf-8",
                                 -script=>[
                                      {-type=>'text/javascript',
                                       -src=>"../static/ver/$dweb/js/version.js"},
                                      {-type=>'text/javascript',
                                       -src=>"../static/ver/$dweb/js/file-sidebar.js"},
                                 ],
                                 -style=>{ -type=>'text/css',
                                -src=>"../static/ver/$dweb/css/DiogenesWeb.css"});
            print qq{<span hidden>$Diogenes::Base::Version</span>};
        }
        else {
            print $f->start_html(-title=>'Perseus Data',
                                 -meta=>{'content' => 'text/html;charset=utf-8'},
                                 -encoding=>"utf-8",
                                 -script=>{-type=>'text/javascript',
                                               -src=>'diogenes-cgi.js'},
                                 -style=>{ -type=>'text/css',
                                               -src=>'diogenes.css'});
        }
        # For jumpTo
        print $f->start_form(-name=>'form',
                             -id=>'form',
                             -action=>"Diogenes.cgi");
        print $f->hidden( -name => 'JumpTo',
                          -default => "",
                          -override => 1 );
        print $f->hidden( -name => 'JumpFromQuery',
                          -default => $f->param('q'),
                          -override => 1 );
        print $f->hidden( -name => 'JumpFromLang',
                          -default => $f->param('lang'),
                          -override => 1 );
        print $f->hidden( -name => 'JumpFromAction',
                          -default => $f->param('do'),
                          -override => 1 );
        if ($dweb) {
            # Says not to create the sidebar controls
            print $f->hidden( -name => 'popupParse',
                              -default => 1,
                              -id => 'popupParse' );
        }

        print qq{<div>};

        # Subsequent pages should use this same pop-up
        print qq{<div id="sidebar" class="sidebar-newpage"></div>}
    }
    else {
        print qq{<div id="sidebar-control"></div>};
        print qq{<span hidden>Version $Diogenes::Base::Version</span>};
    }

    if ($lang ne 'grk') {
        # Latin -- do nothing.
    }
    elsif ($inp_enc eq 'Unicode') {
        # Already decoded utf8
        my $c = new Diogenes::UnicodeInput;
        $query = $c->unicode_greek_to_beta($query);
    }
    elsif ($inp_enc eq 'utf8' or
           $query =~ m/[\x80-\xff]/) {
        # print STDERR "Q1: $query\n";
        # Raw bytes that need to be decoded
        $query = Encode::decode('utf8', $query);
        my $c = new Diogenes::UnicodeInput;
        $query = $c->unicode_greek_to_beta($query);
        $query = lc $query;
        # print STDERR "Q2: $query\n";
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
    #$query =~ tr/A-Z/a-z/;
    # print STDERR "Q3: $query\n";

    warn "I don't know about language $lang!\n" unless exists $dicts{$lang};

    if (not -e $perseus_dir) {
        $perseus_dir = $ENV{Diogenes_Perseus_Dir} if $ENV{Diogenes_Perseus_Dir};
        if (not -e $perseus_dir) {
            print "<b>Sorry -- Perseus Data not installed!</b>";
            $footer->();
            die("No Perseus data!");
        }
    }
    $lem_num = 0;
    # When back and forth surfing through the lexica, $query is a
    # numerical offset, so we will have to work harder to figure out
    # the word.  Until then, we switch the feature off.  FIXME
    if ($qquery =~ /^[0-9\s]+$/ or $lang eq 'eng' or $f->param('noheader')) {
        $logeion_link = ''
    }
    else {
        $logeion_link = qq{<a href="https://logeion.uchicago.edu/$qquery" class="logeion-link" target="logeion">Logeion</a>};
    }
};

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
    if ($line =~ m/<(?:entryFree|div2|div1)[^>]*key\s*=\s*\"([^"]*)\"/)
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
    $comp_fn = $beta_comp_fn;
    $key_fn = $xml_key_fn;
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

my $tll_parse_setup = sub {
    $idt_file = File::Spec->catfile($perseus_dir, 'tll-bookmarks.idt');
    $txt_file = File::Spec->catfile($perseus_dir, 'tll-bookmarks.txt');
    $comp_fn = $ascii_comp_fn;
    $key_fn = $tab_key_fn;
};

my $parse_prelims = sub {
    open $idt_fh, "<$idt_file" or die $!;
    local $/ = undef;
    my $code = <$idt_fh>;
    eval $code;
    warn "Error eval'ing $idt_file: $@" if $@;
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
our $binary_search = sub {
    # "local" fails and becomes slurping on versions of Windows
    # local $/ = "\n";
    $/ = "\n";
    my $word = shift;
    my $start = shift;
    my $stop = shift;
    my $mid = int(($start + $stop) / 2);
    return undef if $start == $mid or $stop == $mid;
    # This may land in the middle of a utf8 char, but that should not matter.
    seek $search_fh, $mid, 0;
    <$search_fh> unless $mid == 0;
    $dict_offset = tell $search_fh;
    my $line = <$search_fh>;
    chomp $line;
    (my $key, my $value) = $key_fn->($line);
    my $cmp = $comp_fn->($word, $key);
    # print STDERR "debug: $start -> $mid -> $stop  cmp: $cmp; $word vs $key\n";
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

my $normalize_latin_lemma = sub {
    my $lemma = shift;

    # Remove accents from utf8 text
    $lemma = NFKD( $lemma );
    $lemma =~ s/\p{NonspacingMark}//g;
    # Remove macrons and breves from ascii text
    $lemma =~ s/[_^]//g;

    if ($lemma =~ m/-/) {
        $lemma =~ s/(.*)-(.*)/$1$2/;
    }
    $lemma =~ s/\d$//;
    return $lemma;
};

my $normalize_greek_lemma = sub {
    my $lemma = shift;
    $lemma = lc $lemma;
    # We strip breathings, too, because that surprises less
    $lemma =~ s/[_^,-\\\/=+\d)(]//g;
    return $lemma;
};

my $text_with_links = sub {
    my $text =  shift;
    my $text_lang = shift;
    my $inhibit_conversion = shift;
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
        $word = $beta_to_utf8->($word) if $text_lang eq "grk"
            and not $inhibit_conversion;
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

my $munge_ls_lemma = sub {
    my $text = shift;
    $text =~ s/&lt;/</g;
    $text =~ s/&gt;/>/g;
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
    # Tiny.pm will complain if not well-formed -- get rid of stray
    # divs and milestones before and after entry
    $text =~ s/^.*?(<(?:entryFree|div1|div2) )/$1/;
    $text =~ s/(<\/(?:entryFree|div1|div2)>).*$/$1/;
    # Tiny needs a space before close of empty tag
    $text =~ s#<([^>]*\S)/>#<$1 />#g;
    return $text if $xml_out;
    $out = '';
    local $xml_lang = '' ; # dynamically scoped
    local $xml_ital = 0  ;
    # print STDERR ">>$text\n";
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

our $munge_tree = sub {
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
        elsif ($lang eq 'lat' and $text =~ m/^, (?:v\.|=) /) {
           # Hack for L-S cross refs (not identified as Latin).
           $text = $text_with_links->($text, 'lat');
        }
        elsif ($lang eq 'lat' and not $xml_ital) {
           # Hack to make all non-italicized L-S text Latin
           $text = $text_with_links->($text, 'lat');
        }
        elsif ($lang eq 'grk' and $text =~ m/\p{Greek}/) {
           # Hack to catch any Unicode greek (as in Logeion LSJ);
           # inhibit conversion again to Unicode.
            $text = $text_with_links->($text, 'grk', 1);
        }
        else {
            $text = $text_with_links->($text, 'eng');
        }
    }
    $out .= $text;
};

our $munge_content = sub {
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
            my $factor = $dweb ? 1 : 2;
            my $padding = $level * $factor;
            my $heading = $e->{attrib}->{n};
            if ($heading) {
                # Some entries wrongly begin with a dot, which makes this look bad, unfortunately
                $heading .= '. ';
                $out .= qq{<div id="sense" style="padding-left: $padding}.qq{em; padding-bottom: 0.5em; text-indent: -1em"><b>$heading</b>};
            }
            else {
                $out .= qq{<div id="sense" style="padding-left: $padding}.qq{em; padding-bottom: 0.5em">};
            }
        }
    }
    # Try to emphasize English words in lexica
    if ($lang eq 'grk' and $e->{name} =~ m/^tr|orth$/) {
        $out .= $close ? '</i></b>' : '<b><i>';
    }
    if (($e->{attrib}->{rend} and $e->{attrib}->{rend} eq 'ital')
        or $e->{name} eq 'i') {
        if ($close) {
            $out .= '</i></b>';
            $xml_ital = 0;
        } else {
            $out .= '<b><i>';
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
            $out .= qq{<a class="origjump $e->{attrib}->{n}" onClick="jumpTo('$jump');">};
            #$out .= qq{<a onClick="jumpTo('$jump');">};
            $in_link = 1;
        }
    }

};

my $tll_pdf_link = sub {
    return '' if $dweb;
    return '' unless $lang eq 'lat';
    my $word = shift;
    # print STDERR "Before lemma: $word\n";
    # Remove numbered entries, since there is no reason to believe
    # that the numbers used by L-S and TLL will correspond.
    $word =~ s/\s*\d+$//;
    $word = $normalize_latin_lemma->($word);
    # Remove numeric entities for accents, macrons, etc.
    $word =~ s/&[^;]+;//g;
    $word =~ s/[^A-Za-z]//g;
    # Bookmarks in the PDFs have consonant u; index.json has v
    # $word =~ tr/vj/ui/;
    $word =~ tr/j/i/;
    # print STDERR "TLL lemma: $word\n";
    $tll_parse_setup->();
    $parse_prelims->();
    my $bookmark = $try_parse->($word);
    return '' unless $bookmark;

    $bookmark =~ m/^([\.\do]+)\t(\d+)$/ or die "No match for $bookmark\n";
    my $tll_file = $1;
    my $page = $2;
    # print STDERR "!!$word->$bookmark->$tll_file->$page\n";
    my $href = "tll-pdf/$tll_file.pdf#page=$page";
    return qq{<a onClick="openPDF('$href')" href="#"><i>TLL</i></a>};
};

my $old_pdf_link = sub {
    return '' if $dweb;
    return '' unless $lang eq 'lat';
    # Short file with only running heads, linear search, stop when
    # past target.
    my $word = shift;
    $word =~ s/\s*\d+$//;
    $word = $normalize_latin_lemma->($word);
    $word =~ tr/A-Z/a-z/;
    $word =~ tr/vj/ui/;
    # Remove numeric entities for accents, macrons, etc.
    $word =~ s/&[^;]+;//g;
    $word =~ s/[^a-z]//g;
    # print STDERR "OLD lemma: $word\n";
    my $old_file = File::Spec->catfile($perseus_dir, 'old-bookmarks.txt');
    return '<br/>' unless -e $old_file;
    open my $old_fh, "<$old_file" or warn "Could not open $old_file!\n";
    my $page = 1;
    local $/ = "\n";
    while (my $line = <$old_fh>) {
        $line =~ m/(\w+)\t(\d+)/;
        my $headword = $1;
        $page = $2;
        next unless $headword and $page;
        # print STDERR "$word, $headword, $page, ".($word cmp $headword)."\n";
        last if (($word cmp $headword) <= 0);
    }
    my $href = "ox-lat-dict.pdf#page=$page";
    return qq{ <a onClick="openPDF('$href')" href="#"><i>OLD</i></a>};
};

my $silverdict_link = sub {
    my $word = shift;
    my $href = "http://localhost:2628/?group=Diogenes&key=$word";
    # We'll use a popup window to view the definition
    return qq{ <a onClick="window.open('$href', 'SilverDict', 'width=500,height=600,left='+ (window.screen.width - 500) +',top='+ (window.screen.height - 600)); return false;" href="#"><i>SilverDict</i></a>};
};

our $munge_element = sub {
    my $e = shift;
    $swap_element->($e, 0); # open it
    if ($e->{name} eq 'entryFree' or $e->{name} eq 'div2' or $e->{name} eq 'div1') {
        my $key;
        if ($e->{content}->[0]->{name} eq 'head' and
            $e->{content}->[0]->{attrib}->{orth_orig}) {
            # Only present in Logeion LSJ
            $key = $e->{content}->[0]->{attrib}->{orth_orig};
        }
        else {
            $key = $e->{attrib}->{key};
        }
        $key = $munge_ls_lemma->($key) if $lang eq 'lat';
        $key = $beta_to_utf8->($key) if $lang eq 'grk';
        $out .= '<h2><span style="display:block;float:left">' . $key . '</span>';
        $out .= '<span style="display:block;text-align:right;">&nbsp;';
        $out .= $tll_pdf_link->($key);
        $out .= $old_pdf_link->($key);
        $out .= $silverdict_link->($key);
        $out .= '</span></h2>';
        # $out .= '<h2>' . $key . '</h2>';
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
    print qq{<hr /><div>};
    print qq{<a onClick="prevEntry$lang($dict_offset)"><img class="prev" src="${picture_dir}go-previous.png" srcset="${picture_dir}go-previous.hidpi.png 2x" alt="Previous Entry" /></a> };
    # print "TLL Link";
    print qq{<a onClick="nextEntry$lang($dict_offset)"><img class="next" src="${picture_dir}go-next.png" srcset="${picture_dir}go-next.hidpi.png 2x" alt="Next Entry" /></a>};
    print "</div><br/>";
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
    $text = Encode::decode('utf-8', $text);
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
    my $pretty_word = ($lang eq "grk") ? $beta_to_utf8->($word) : $word;

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
    $query = $beta_to_utf8->($query) if $lang eq 'grk';
    my (@out, @suppl);
#     print "\n\n$anl\n\n";
    while ($anl =~ m/{([^\}]+)}((?:\[\d+\])*)/g) {
#     while ($anl =~ m/{([^\}]+)}/g) {
        my $entry = $1;
        my $suppl = $2;
        if ($entry =~ m/^(\d+) (\d) (.*?)\t(.*?)\t(.*?)$/) {
            my ($dict, $conf, $lemma, $trans, $info) = ($1, $2, $3, $4, $5);
            $lemma = $beta_to_utf8->($lemma) if $lang eq 'grk';
            $lemma = $munge_ls_lemma->($lemma) if $lang eq 'lat';
            # The greek-analyses.txt file is subtly utf8, as the short defs include some Unicode punctuation.
            $trans = Encode::decode('utf-8', $trans);
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
#        print STDERR "\n\n== $entry\n\n";
        $format_dict->($entry);
    }
};

my $format_inflect = sub {
    $lem_num++;
    my ($lem, $out) = @_;
    my @out = split /\t/, $out;
    my $dict = shift @out;
    my $link = qq{<a onClick="getEntry$lang('$dict');">}.
        ($lang eq "grk" ? $beta_to_utf8->($lem) : $lem).
        qq{</a>};
    print qq{<h2><a onClick="toggleLemma('$lem_num');"><img src="${picture_dir}opened.png" srcset="${picture_dir}opened.hidpi.png 2x"
align="bottom" id="lemma_$lem_num" /></a>&nbsp;$link</h2>};

    print qq{<span class="lemma_span_visible" id="lemma_span_$lem_num">};
    for (@out) {
        m/^(\S+)(.*)$/;
        my ($form, $infl) = ($1, $2);
        my $label = ($lang eq "grk" ? $beta_to_utf8->($form) : $form) . ": $infl";
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
    my @lemmata = split /{}/, $query;
    for (@lemmata) {
        next if m/^\s*$/;
        $do_inflect->($_);
    }
};

my $find_lemma = sub {
    my $filename = ($lang eq 'grk' ? 'greek' : 'latin') . '-lemmata.txt';
    my $norm_func = ($lang eq 'grk') ? $normalize_greek_lemma : $normalize_latin_lemma;
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
    my $qq = $f->param('q');
    if (@results) {
        my %labels;
        $labels{$_} = qq{<a onClick="getEntry$lang('$dicts{$_}');">}.
            ($lang eq "grk" ? $beta_to_utf8->($_) : $_).
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
    # remove leading & trailing spaces
    $query =~ s/^\s+//g;
    $query =~ s/\s+$//g;
    # Do not remove apostrophes from Greek! (Morpheus knows about elided forms) ...
    $query =~ s/[~,.;:?!"]//g;
    # ... but do change Unicode koronis or curly quote into an
    # apostrophe when it shows elision, or Morpheus won't understand.
    $query =~ s/[᾽’]$/'/g;
    # In Latin, however, apostrophes are just single quotation marks and need to be removed.
    $query =~ s/[']//g if $lang eq 'lat';
    my $word = $query;
    # remove diareses
    $word =~ s/\+//g;
    # print STDERR "\n\n-$word-$query-\n";
    # Accent thrown back from enclitic?
    $word =~ s/^(.*[\\\/=].*)[\\\/=]/$1/;
    my $analysis = $try_parse->($word);
    if (not defined $analysis) {
        # Try lower-case if upper
        if ($lang eq 'lat' and $word =~ m/^[A-Z]/) {
            $word =~ tr/A-Z/a-z/;
            $analysis = $try_parse->($word);
        }
        elsif ($lang eq 'grk' and $word =~ m/^\*/) {
            $word =~ s/\*//g;
            $word =~ s/^([\\\/=|)(]+)([aeiouhw])/$2$1/;
            $analysis = $try_parse->($word);
            if (not defined $analysis) {
                if ($word =~ s/^([aeiouhw])([\\\/=|)(]+)([aeiouhw])/$1$3$2/) {
                    # print STDERR "Try-$word-$query-\n";
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

my $dispatch = sub {
    if ($logeion_link) {
        print $logeion_link.'<br/>';
    }
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
};

$Diogenes::Perseus::go = sub {
    my $parameters = shift;
    $setup->($parameters);
    $dispatch->();
    $footer->();
};

1;
