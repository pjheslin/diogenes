#!/usr/bin/env perl

###################################################################################
#                                                                                 #
# Diogenes is a set of programs including this script which provides              #
# a command-line interface to the CD-Rom databases published by the               #
# Thesaurus Linguae Graecae and the Packard Humanities Institute.                 #
#                                                                                 #
# Send your feedback, suggestions, and cases of fine wine to                      #
# P.J.Heslin@durham.ac.uk                                                         #
#                                                                                 #
# Copyright P.J. Heslin 1999-2000.  All Rights Reserved.                          #
#                                                                                 #
#   This module is free software.  It may be used, redistributed, and/or modified #
#   under the terms of the GNU General Public License, either version 2 of the    #
#   license, or (at your option) any later version.  For a copy of the license,   #
#   write to:                                                                     #
#                                                                                 #
#           The Free Software Foundation, Inc.                                    #
#           675 Massachussets Avenue                                              #
#           Cambridge, MA 02139                                                   #
#           USA                                                                   #
#                                                                                 #
#   This program is distributed in the hope that they will be useful, but WITHOUT #
#   ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS #
#   FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more        #
#   details.                                                                      #
#                                                                                 #
###################################################################################

push @INC, '.';
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
use lib ($Bin, catdir($Bin, '..', 'dependencies', 'CPAN') );

use Diogenes::Base qw(%encoding %context @contexts %choices %work %author);
use Diogenes::Search;
use Diogenes::Indexed;
use Diogenes::Browser;


#use Data::Dumper;
#use Coy;
#use diagnostics;
#use re 'debugcolor';

use integer;
use Getopt::Std;
use strict;
use warnings;

use Encode;

use vars qw($opt_l $opt_w $opt_g $opt_b $opt_r $opt_p $opt_O $opt_R
			$opt_c $opt_d $opt_s $opt_v $opt_x $opt_f
			$opt_n $opt_a $opt_z $opt_i $opt_I $opt_M
			$opt_B $opt_e $opt_h $opt_m $opt_N $opt_C
			$opt_u $opt_U $opt_W $opt_o $opt_D $opt_P
			$opt_F $opt_8 $opt_7 $opt_3 $opt_k $opt_j
			$opt_t $opt_Z $opt_X $opt_1);

delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};   # Make %ENV safer
$ENV{'PATH'} = "/bin/:/usr/bin/";
my ($inp, @wlist); 
my %args;

my ($a, $aw, $b, $bw, $c, $cw, $d) = ('', '', '', '', '', '', '');
format COLS =
@<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<  @<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$a, $b, $c, $d
.
format AUTHS =
@<<<<< ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$a,     $b
~        ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        $b
.
format WORDS =
@<<< @<<<<<<<<<<<<<<<<<< @<<< @<<<<<<<<<<<<<<<<< @<<< @<<<<<<<<<<<<<<<<<<
$a, $aw,           $b, $bw,          $c, $cw
.
my $mode = '';

&display_help unless @ARGV;
&display_help unless 
getopts('FWwlgbriIpORdsvMCxfazBehu873tZP1N:n:c:m:U:o:D:k:j:X:');

$args{type} = 'tlg' if $opt_g;
$args{type} = 'tlg' if $opt_t;
$args{type} = 'tlg' if $opt_w;
$args{type} = 'phi' if $opt_l;
$args{type} = 'ddp' if $opt_p;
$args{type} = 'ins' if $opt_i;
$args{type} = 'chr' if $opt_I;
$args{type} = 'misc' if $opt_M;
$args{type} = 'bib' if $opt_B;
$args{type} = 'cop' if $opt_C;

$args{input_encoding} = 'Unicode';
$args{input_encoding} = 'Perseus-style' if $opt_P;
$args{input_encoding} = 'BETA code' if $opt_t or $opt_r or $opt_z;
$args{input_lang} = 'g' if ($opt_g or $opt_w);
$args{input_raw} = 1 if $opt_r;
$args{input_pure} = 1 if $opt_z;

$args{output_format} = 'ascii'; # default
$args{output_format} = 'repaging' if $opt_R;
$args{output_format} = 'beta' if $opt_O;
$args{output_format} = 'latex', $args{printer} = 1 if $opt_x;
$args{output_format} = 'html' if $opt_h;

$args{fast} = 0 if $opt_s;
$args{debug} = 1 if $opt_d;
$args{bib_info} = 1 if $opt_e;
$args{context} = $opt_c if ($opt_c and not $opt_b);
$args{min_matches} = $opt_m if $opt_m;
$args{min_matches} ||= 'all';
$args{encoding} = $opt_U if $opt_U;
$args{encoding} = 'Unicode_Entities' if $opt_u;
$args{encoding} = 'UTF-8' if $opt_8;
$args{encoding} = 'ISO_8859_7' if $opt_7;
$args{encoding} = 'DOS_CP_737' if $opt_3;
$args{encoding} = 'WinGreek' if $opt_W;
$args{tlg_dir} = $args{phi_dir} = $args{ddp_dir} = $opt_D if $opt_D;
$args{encoding} = 'UTF-8' if $opt_h and not $args{encoding};
$args{blacklist_file} = $opt_k if $opt_k;
$args{reject_pattern} = $opt_j if $opt_j;
$args{quiet} = 1 if $opt_Z;
if (not $opt_b and ($opt_i or $opt_I or $opt_M))
{
	if    ($opt_g or $opt_t)	{ $args{input_lang} = 'g'; }
	elsif ($opt_l)	            { $args{input_lang} = 'l'; }
	else
	{
		print "\nYou should specify whether your pattern is to be interpreted\n"
			. "as Greek or as Latin (the -l or -g flag) [g]/l: ";
		$args{input_lang} = <STDIN> =~ /[lat]/ ? 'l' : 'g';
	}
}
# Output with formatting codes stripped and hits highlighted, as default.
$args{highlight} = 1 unless $opt_O;
$Diogenes::Base::cgi_flag = 1 if $opt_1;

die "You must specify a pattern. \n" unless @ARGV or $opt_b or $opt_Z or $opt_U;
my @patterns = @ARGV;
if ($args{input_encoding} eq 'Unicode') {
    @patterns = map {Encode::decode(utf8=>$_) } @patterns;
}

$args{pattern_list} = [@patterns] unless $opt_b;
undef @ARGV;

die "Edition info only available for the TLG. \n" if $opt_e and 
										not ($opt_g or $opt_w);

if ($opt_v) 
{
	print "Diogenes version is: $Diogenes::Base::Version\n";
	exit;
}

my ($query, $old_fh);

if ($opt_o)
{
	open OUT_FILE, ">$opt_o" or die "Could not open $opt_o: $!";
	$old_fh = select STDERR;
}

if ($opt_b or $opt_Z) 
{ 
	$query = new Diogenes::Browser(%args);
    die "Database not found!\n" unless ref $query;
	&browser;
	exit;
}
elsif ($opt_w) 
{ 
	$query = new Diogenes::Indexed(%args);
    die "Database not found!\n" unless ref $query;
}
else		   
{ 
    $query = new Diogenes::Search(%args);
    die "Database not found!\n" unless ref $query;
}

die "Cannot find database for $args{type}\n"
    if not $query->check_db;
 

my %req;
if ($opt_F) 
{
	my %labels = %{ $query->select_authors(get_tlg_categories => 1) };
	
	my ($num, @inputs);
	$/ = "\n";
INP: foreach my $label (keys %labels) 
	 {
		next if $label eq 'auths';
		print "\nHere are the choices for $label:\n\n";
		print "Cross-indexed genre listing (somewhat more broadly 
inclusive than the genre listings)\n\n"if $label eq 'genre_clx';
		my $last = $#{ $labels{$label } };
		my $half = int( $last / 2 );
		local $~ = 'COLS';
		($a, $b, $c, $d) = (0, '', '', '');
		my $n = 0;
		while ($n <= $half and $last > 0) 
		{
			$a = "$n)";
			$b = @{ $labels{$label} }[$n];
			$c = $n + $half.')';
			$d = @{ $labels{$label} }[$n + $half];
			write;
			$n++;
		}
		if ($last % 2 or $last == 0) 
		{
			$a = "$last)";
			$b = @{ $labels{$label} }[$last];
			($c, $d) = ('', '');
			write;
		}
		if ($label eq 'date')
		{
			my ($varia, $incertum, $begin, @dates);
			foreach (0 .. $#{ $labels{date} }) 
			{
				$varia    = $_ if @{ $labels{date} }[$_] eq 'Varia';
				# Note the space at the end of Incertum
				$incertum = $_ if @{ $labels{date} }[$_] eq 'Incertum ';
			}
			$inp = '';
			print "Beginning of (inclusive) date range: ";
			chomp ($inp = <STDIN>);	
			if (($begin = $inp) ne '') 
			{
				print "End of (inclusive) date range: ";
				chomp ($inp = <STDIN>);	
				$inp ||= $begin;
				@dates = ($labels{date}[$begin], $labels{date}[$inp]);
				unless ($inp eq '' or $inp == $varia or $inp == $incertum) 
				{
					print "Include Varia and Incerta? [n] ";
					chomp ($inp = <STDIN>);
					push @dates, 1, 1 if $inp =~ /y/i;
				}
			}
			@{ $req{date} } = @dates if $begin ne '';
		}
		else
		{
			print "Enter the corresponding number(s) for $label (Enter to ignore): ";
	       	chomp ($inp = <STDIN>);
	       	if ($inp ne '') 
			{
				# validate input, multiple
				@inputs = ();
				foreach $num (split /[\s,]+/, $inp) 
				{
					if (@{ $labels{$label} }[$num]) 
					{
						push @{ $req{$label} }, @{ $labels{$label} }[$num];
					}
					else 
					{
						print "What?\n";
						redo INP;
					}
				}
			}
		}
	}
	print "author regexp to match: ";
	chomp ($inp = <STDIN>);	
	$req{author_regex} = $inp if $inp ne ''; 
	
	print "author nums (whitespace separated): ";
	chomp ($inp = <STDIN>);	
	$req{author_nums} = [split /[\s,]+/, $inp] if $inp ne '';	
	
	print "criteria to match [any]: ";
	chomp ($inp = <STDIN>);	
	$req{criteria} = ($inp eq '') ? 1: ($inp =~ m/any/i) ? 'any': ($inp =~ m/all/i) ? 'all' : $inp;	
	
	if ((not %req) or (exists $req{criteria} and $req{criteria} eq '0'))
	{
		print "No criteria given; searching entire corpus. \n"
	}
	else
	{
		# print Data::Dumper->Dump ([\%req], ['*req']);
		print "\nHere are the matching authors and works:\n\n";
		my @auths = $query->select_authors(%req);
		# print Data::Dumper->Dump ([\@auths], ['*auths']) if %req;
		local $~ = 'AUTHS';
		#print "$_)\t$auths[$_] \n" for (0 .. $#auths);
		for (0 .. $#auths) 
		{
			$a = "$_)";
			$b = "$auths[$_]";
			write;
		}
		print "Which of these texts should be searched? [Return for all]: ";
		chomp ($inp = <STDIN>);	
		if ($inp ne '')
		{
			undef %req;
			$req{previous_list} = [split /[\s,]+/, $inp]; 
			@auths = $query->select_authors(%req);
			print "\nSearching within the following texts: \n\n";
			print "$auths[$_] \n" for (0 .. $#auths);
			print "\n";
			# print Data::Dumper->Dump ([\@auths], ['*auths']);
		}
	}
}
elsif ($opt_f) 
{
	my (%auths, @auths);
	if ($opt_n)
	{
		@auths = $query->select_authors(author_regex => $opt_n);
	}
	else
	{
		%auths = %{ $query->select_authors('select_all' => 1) };
		local $~ = 'AUTHS';
		print "\n";
		for (sort keys %auths) 
		{
			$a = "$_)";
			$b = "$auths{$_}";
			write;
		}
		print "Which of these texts should be searched? [Return for all]: ";
		chomp ($inp = <STDIN>);	
		if ($inp ne '')
		{
			undef %req;
			$req{author_nums} = [split /[\s,]+/, $inp]; 
			@auths = $query->select_authors(%req);
		}
	}
	print "\nSearching within the following texts: \n\n";
	print "$auths[$_] \n" for (0 .. $#auths);
	print "\n";
}
elsif ($opt_n) 
{
	if ($opt_n =~ m/\d/)
	{
		my @nums = split /[\s,]+/, $opt_n;
		$req{author_nums} = \@nums;
	}
	else
	{
		$req{author_regex} = $opt_n;
	}
	my @auths = $query->select_authors(%req);
	{
		print "\nSearching within the following texts: \n\n";
		print "$auths[$_] \n" for (0 .. $#auths);
		print "\n";
	}
}
elsif ($opt_N)
{
    # We use a temp browser to find the works
	my $browser = new Diogenes::Browser(%args);
    die "Database not found!\n" unless ref $query;
	my %auths;
	if ($opt_N =~ m/\d/)
   	{ 
		%auths = (%auths, $browser->browse_authors($_)) for split /[\s,]+/, $opt_N;
	}
	else
    { 
		%auths = $browser->browse_authors($opt_N);
	}
	#print Data::Dumper->Dump ([\%auths], ['auths']);
    if (%auths)
    {
		print "
For each author, enter the number(s) of the work(s) to be searched: \n";
    }
		my %works;
		foreach my $auth (sort keys %auths)
		{
    		print "\n$auths{$auth}:\n";
    		my %all_works = $browser->browse_works ($auth);
        	print "  $_: $all_works{$_}\n" foreach (sort keys %all_works);
			print "\n  Work? (Return for all, 0 for none) ";
            $/ = "\n";
			chomp ($inp = <STDIN>);
            unless ($inp eq "0")
            {
			    $works{$auth} = ($inp eq '') ? 'all' : [split /[\s,]+/, $inp];
            }
		}
	print "\n";
	#print Data::Dumper->Dump ([\%works], ['works']);
	my @auths = $query->select_authors(author_nums=>\%works);
	{
		print "\nSearching within the following texts: \n\n";
		print "$auths[$_] \n" for (0 .. $#auths);
		print "\n";
	}
}

if ($opt_w)
{
	my @word_lists;
	foreach my $pattern (@patterns)
	{
		my ($wref, @wlist) = $query->read_index($pattern);
		die "Sorry, I didn't find anything in the word list!\n" unless @wlist;
		
		unless ($opt_a)
		{
			print 	"\nHere are the words from the word list that match \n".
				"the word-beginning you gave:\n\n";
			my $n;
			if (@wlist > 10000) # Max in 4 col. num. column 
			{
				print "\n";
				print "$_] $wlist[$_] ($wref->{$wlist[$_]})\n" for (0 .. $#wlist) 

			}
			else
			{
				local $~ = 'WORDS';
				for ( $n = 0; $n < @wlist; $n++ ) 
				{
	    			$aw = $wlist[$n] . " ($wref->{$wlist[$n]})";
	    			$a  = "$n]";
					last if ++$n >= @wlist;
	    		    $bw = $wlist[$n] . " ($wref->{$wlist[$n]})";   
	    		    $b  = $n . ']';   
					last if ++$n >= @wlist;
	    		    $cw = $wlist[$n] . " ($wref->{$wlist[$n]})";   
	    		    $c =  $n . ']';   
					write;
				 	($a, $aw, $b, $bw, $c, $cw) = ('', '', '', '', '', '');
				}
				write;
			}
			
			print "\nEnter a list of desired words (or Return for all): ";
			chomp ($inp = <STDIN>);	
			print "\n";
			@wlist = @wlist[split /[\s,]+/, $inp] unless ($inp eq '');	
		}
		push @word_lists, \@wlist;
	}
	print "Sending output to $opt_o.\n" if $old_fh;
	if ($old_fh) {select OUT_FILE; $| = 1;} 
	$query->do_search(@word_lists);
}
else
{
	print "Sending output to $opt_o.\n" if $old_fh;
	if ($old_fh) {select OUT_FILE; $| = 1;} 
	$query->do_search;
}


print "done.\n\n";	
exit;

sub browser 
{
    my (%auths, $auth, %works, $work, @labels, $j, $lev,  @target); 
    $query->{browse_lines} = $opt_c if $opt_c;
    $query->{browse_multiple} = $opt_X if $opt_X;
	$| = 1 if $opt_h; # Flush buffer if we are viewing this output
	my $fh = select STDERR if ($opt_x) ;

	# prompt for choice of author
    print "\n";
	my $browse_pattern = (shift @patterns) || ''; 
    $browse_pattern = $opt_n if $opt_n;
	%auths = $query->browse_authors($browse_pattern);
	die "Sorry. No matching authors. \n" unless %auths; 
	print "Please select one:\n\n" if keys %auths > 1;
	foreach $auth (sort keys %auths) 
	{
        print "$auth: $auths{$auth}\n" ;
    }

    print "\n";
    if (keys %auths == 1) 
	{
        $auth = (keys %auths)[0];
    }
    else 
	{
		print $args{type} eq 'bib' ? 'Bibliography? ' : 'Author? ';
        $/ = "\n";
        $auth = <>;
        chomp $auth;
        $auth = sprintf '%04d', $auth =~ /(\d+)/ unless $auth =~ /\D/ or $args{type} eq 'bib';
    }

    # prompt for choice of work
    %works = $query->browse_works ($auth);
    die "Sorry. No matching works. \n" unless %works;
    print "Please select one:\n\n" if keys %works > 1;

    foreach $work (sort keys %works) 
	{
        print "$work: $works{$work}\n";
    }

    print "\n";
    if (keys %works == 1) 
	{
        $work = (keys %works)[0];
    }
    else 
	{
        print "Work? ";
        $/ = "\n";
        $work = <>;
        chomp $work;
        $work = sprintf '%03d', $work =~ /(\d+)/ unless $work =~ /\D/;
    }
    print "\n";

    if ($opt_Z)
    {
        $query->{browser_multiple} = 100000000;
        @target = (0) x 100;
    }
    else
    {
        # prompt for location in the text
        @labels = $query->browse_location ($auth, $work);
        $j = (scalar @labels) - 1;
        print "Enter the number of any TLG author: \n" if $args{type} eq 'bib';
        foreach $lev (@labels) 
	    {
            next if $lev =~ m#^\*#;
            print "$lev? ";
            $/ = "\n";
            $inp = <>;
            chomp $inp;
            push @target, $inp;
            $j--;
        }
        print "\n";
    }
    # show the desired text
	print "Sending output to $opt_o.\n" if $old_fh;
	if ($old_fh) {select OUT_FILE; $| = 1;} 
        $query->seek_passage ($auth, $work, @target);
        $query->begin_boilerplate;
        if (grep {m/^0$/ or m/^$/} @target) {
            $query->browse_forward;
        } else {
            $query->browse_half_backward;
        }
	print "<p>\n" if $opt_h;
#	select STDERR if $old_fh;

    # prompt reader to move back or forth in the text
    $inp = "";
    $inp = "Q" if $opt_Z;
            
    until ($inp =~ /[qQ]/) 
	{
		select STDERR if $old_fh;
      	print "\n[more], [b]ack, [q]uit? ";
        local $/ = "\n";
        $inp = <>;
        print "\n";
        if ($inp =~ /[Bb]/) 
		{
			print "Sending output to $opt_o.\n" if $old_fh;
			if ($old_fh) {select OUT_FILE; seek OUT_FILE, 0, 0; truncate OUT_FILE, 0; $| = 1;} 
       		$query->browse_backward;
        }
        else 
		{
			print "Sending output to $opt_o.\n" if $old_fh and $inp !~ /[qQ]/;
			if ($old_fh) {select OUT_FILE; $| = 1;} 
        	$query->browse_forward unless ($inp =~ /[qQ]/);
        }
    	print "\n";
		print "<p>\n" if $opt_h;
    }
    print "\n";
    $query->end_boilerplate;
}

sub numerically { $a <=> $b; }

sub display_help 
{
	my $help = <<"EOB";

This is Diogenes, a search tool for the databases of Latin
and Greek published on CD-Rom by the Packard Humanities
Institute and the Thesaurus Linguae Graecae.

NB. All searches are now case-insensitive, and thus the -i switch
is no longer implemented.

Usage:

diogenes [options] pattern [pattern [pattern ... ]]

Options:

  -l   Interpret the pattern according to the Latin alphabet.
       If no other corpus is specified, search the PHI Latin
       corpus. Your search pattern is turned into a case-insensitive
       regular expression that treats w and v and i and j as equivalent,
       and permits hyphenation and indexing codes to intervene.  Spaces
       are significant and may be used to indicate the beginning
       or end of a word. This option should be able handle without
       mangling some simple pattern-matching constructs, such as
       character classes, parentheses, alternation and the ? + *
       modifiers.  Thus, for example: ./diogenes -ln Vergil ' rex |
       reg(is?(bus)?|e[ms]?|um) ' This pattern finds the cases of
       "rex" in Virgil and the Appendix Virgiliana, even if hyphenated
       (unlikely in verse, but common in prose) while ignoring other,
       related words (regnum, regina, etc.).
  
  -w   Greek (TLG) word list search. The search pattern should
       be input in the format used by the Perseus project, and should
       not contain diacritics except to mark long vowels: eg. ./diogenes
       -w Athe^ne^ or Athênê.  Words are given with their frequency in
       the texts you have selected (or in the entire TLG).  You are
       prompted to choose among the words found in the word list, unless
       you also specify the following.

  -a   Used with the -w switch to search for all words in the word list
       that match the pattern, without prompting for the user to make a
       selection.

  -g   Do a brute force search of the TLG (the scope may be narrowed
       down with -f or -n).  This is the default.

(NB. As of version 3.1, default input encoding is Unicode.  Use the -P
switch to revert to the Perseus transliteration.  With Unicode, either
indicate all accents for strict matching, or none at all for loose
matching.)
 
  -P   Interpret the pattern according to the Latin transliteration of
       the Greek alphabet as used by the Perseus project: eg. diogenes
       -g " phoib(['e]|o[snu]|ôi?) ".  This input pattern is
       transformed into a Perl regular expression as above, such that
       analphabetic characters and non-ascii bytes may follow any
       letter in the pattern.  A similar range of pattern-matching
       metacharacters may be used in the input.

  -t   As above, but interpret Greek input as BETA code. In this scheme, you
       must indicate accents and breathings in the normalized form used by
       the <i>TLG</i> word list: do not indicate upper-case letters, and do
       not use barytone accents.  You may use lower-case Latin letters.  You
       may not use Perl regular expression metacharacters, because many of
       them are significant in Beta code; your pattern will be turned
       into a regular expression that allows hyphenation to intervene.

  -e   Add some info about the edition of each text to the citations: 
       (TLG only, but there is some bibliographical info on the papyri, 
       inscriptions and Latin canon that can be accessed using the 
       browser). 

  -b   Run the text browser.  Should be used in conjunction
       with the -l, -g, -p, -i, -I, -m or -B option to specify the
       corpus in which you wish to browse.  You may supply a pattern, to
       narrow the options down to a particular text; you will be asked
       to choose from a list of authors, and then for a particular work
       and the location within the text you choose.

  -i   Search the corpus of classical inscriptions; use the -g or -l  
       flag to indicate whether your search pattern should be treated
       as Latin or as Perseus-style Greek transliteration.  Can be used
       with the -b flag to browse the database.

  -I   As above, but search (or browse) the corpus of Christian 
       inscriptions.

  -p   As above, but search (or browse) the Duke documentary papyri.

  -M   As above, but search (or browse) the miscellaneous texts on later
       versions of the PHI disk (Hebrew bible, Vulgate, Milton, etc.).

  -C   As above, but search (or browse) the Coptic texts on the PHI disk.

  -B   As above, but search (or browse) the TLG bibliographical data.

  -f   Interactively filter the texts in which to search.  
  
  -F   As above, but you will be prompted to choose the
       genre, range of dates, etc.; the TLG alone provides this
       type of information.

  -n (Num or Pattern)  Filter texts (not interactively) by author name 
       or number. This option provides a handy way to restrict your
       search to one author (or a few); it works for any of the
       databases. Thus, diogenes -gn Homer Phoibos would search only
       in those authors whose names match the pattern "Homer", which
       includes the Hymns, Homeric scholia and a few other related
       texts.  To further restrict the search, you could specify
       the pattern "Homerus", which would only match Homer and some
       pseudhomerica.  To be more precise, use a number instead of
       letters with this option, and it will be interpreted as an author
       number or list of author numbers.  The number of Homer himself is
       0012, while the Homeric Hymns are 0013, and so diogenes -gn 12,13
       Phoibos will search only those two files.

  -N (Num or Pattern)  As above, but you will be prompted to indicate
       which works of the specified author(s) to search in.

  -O   Causes Greek to be output as raw beta code with formatting
       codes intact. By contrast, the default is is to print the text in
       ibycus code, which has very similar conventions to the TLG but is
       much easier to read, and to strip the page formatting codes from
       the output.

  -x   Causes a (messy and unreadable) LaTeX file to be dumped to
       STDOUT.  This attempts to preserve and correctly represent many
       of the font, special character and layout formatting codes
       recorded with the texts. Example usage: ./diogenes -wax foo
       >myfile.tex; latex myfile; xdvi myfile
       
       The file produced by -x will use Ibycus as its Greek encoding,
       not Babel. For Babel output, use eg. the -UBabel_7 option and
       paste the output into a LaTex file that declares:
       \\usepackage[iso-8859-7]{inputenc}
       \\usepackage[polutonikogreek]{babel}
       The result should represent the text accurately, but will not attempt 
       to preserve all of the formatting detail that -x gives you.

  -c Val This is the amount of context to display before and after each
       match.  If Val is a number, it is the number of lines to display 
       before and after each match; this is also the maximum distance apart
       of patterns that are guaranteed to be matched in multiple matching 
       mode (it may be that some patterns even farther apart may also be
       caught).  Otherwise, Val should be either sent, clause, phrase or
       para.  The default is sentence mode, where an attempt is made to
       determine the appropriate scope from the punctuation.
       With the -b option this specifies instead the number of lines
       (approx.) printed by the browser.

   -o (filename)  A file to dump the output to.  Interactive queries
       go to STDERR instead of this file.

   -D (drive or mount point)  Use CD-Rom found here, overriding the values
       found in the configuration files.

   -U (encoding) For Greek output use the named encoding, which should be 
       defined in a Diogenes.map file somewhere in the path Perl searches.
   
   -W  Use the WinGreek encoding for Greek output.
   
   -8  Use the UTF-8 Unicode encoding for Greek output. 

   -7  Use the ISO-8859-7 Modern (monotonic) Greek encoding for output.

   -3  Use the MS-DOS/Windows Modern (monotonic) Greek code page 737 for
       output.
   
   -u  Use the Unicode html entities encoding for Greek output.  This will 
       normally be used in conjunction with the -h option.

   -h  Format the output using html.  The default Greek encoding is
       UTF-8, unless another is specified. Example usage:
       ./diogenes -whu -o "output.htm" poikilothron

   -k (filename)  A file containing a blacklist of authors not to be
       searched through. Syntax of the file is: "tlg2062 lat0474" to
           block out John Chrysostom and Cicero.

   -j (pattern)  A pattern which, if it is found in the context of a hit, will
       cause that hit not to be reported.  For Greek searches, this should be
       a Perseus-style transliterated word or fragment thereof, without
       accents, etc.  In this way you can specify what must not be found in
       the neighborhood of your search target.

   -X (number)  The number of times to redo the browser output.  In combination 
      with a small value for the -c option, a large value will give you a large part
      of the text, but with the citation information repeated frequently.
       
   -Z  Output a work in its entirety (effectively the -X option with a large value).  
       See the -c option above for periodic repetition of the citation information.
       
Debugging Options:

  -d   Causes copious debugging information to be printed.
  
  -r   Raw beta code as Greek input.  The pattern is passed to
       the search engine unmodified (except that Perl metacharacters
       are escaped), eg. diogenes -r '*)AQH/NH' or diogenes -r
       '*FOI=BOS'.  Make sure to put your pattern in quotes to protect
       its analphabetics from interpretation by your shell.  (This will
       not automatically allow for hyphenation.)

  -z   Perl code as Greek or Latin input.  The program does
       not even protect Perl metacharacters, so you must escape them
       yourself.  You may use the full range of Perl regular expressions in
       your pattern this way, but it is very cumbersome (e.g.  ./diogenes -p
       '\\*\\)AQH\/NH[SN]? '). This option is nearly obsolete now that many
       pattern-matching metacharacters may be introduced into normal Greek
       search patterns, and another disadvantage is that this option will not
       automatically catch hyphenated instances).

  -v   Prints the version number and exits.

EOB
        
        if ($^O !~ /MSWin|dos/)
        {
                local *STDOUT;
                open            STDOUT, "|less -P 'Return for more, q to quit'" 
                        or open STDOUT, "|more -d";
                print $help;
        }
        else
        {
                print $help;
        }

exit;
}

# ex: set shiftwidth=4 tw=78 nowrap ts=4 si sta expandtab: #:w
