package Diogenes::Search;
use Diogenes::Base qw(%work %author %work_start_block %level_label %context);
@Diogenes::Search::ISA = ('Diogenes::Base');

sub do_search 
{
    my $self = shift;
    $self->{current_chunk} = 0;
    # Do the search (brute force).
    $self->begin_boilerplate;
    my $retval = $self->pgrep;
    $self->print_totals($retval);
    $self->end_boilerplate;
    return $retval;
}

###############################################################
#                                                             #
# Method that actually does the brute-force searches.         #
# For an explanation of the approach using @ARGV, see p. 226  #
# of /Programming Perl/, 2nd edition.                         #
#                                                             #
# It takes a pattern and returns a hash of filenames, each    #
# pointing to an array containing the offsets of the matches. #
#                                                             #
###############################################################

sub pgrep 
{
    my $self = shift;
    chdir "$self->{cdrom_dir}" or 
        $self->barf ("cannot chdir to $self->{cdrom_dir} ($!)");
    print STDERR "\nCurrent dir: ",`pwd`, 
    "Prefix: $self->{file_prefix}\n\n" if $self->{debug};
    
    unless ($self->{filtered}) 
    {
        if ($self->{tlg_use_chronology} and $self->{type} eq 'tlg') {
            @ARGV = @{ $self->{tlg_ordered_filenames} };
        }
        else {
            # In theory, the following code is platform independent for
            # achitectures (ie. Mac) that don't like unix-shell style globbing.
            opendir (INP_DIR, "$self->{cdrom_dir}") or
                $self->barf ("Cannot open $self->{cdrom_dir} ($!)");
            @ARGV = sort grep {/$self->{file_prefix}.+$self->{txt_suffix}/i} readdir INP_DIR;
            closedir INP_DIR;
        }
    }
    
    $self->barf ("I can't find any data files!") 
        unless @ARGV or $self->{req_auth_wk};
    local $/;
    undef $/;
    
    my $final_pass;
    if ($self->{repeat_matches}) {
        # min_matches is irrelevant for passes in this case
        $final_pass = @{ $self->{pattern_list} } - 1
    }
    else {
        $final_pass = $self->{numeric_context} ?
            @{ $self->{pattern_list} } - 1
            : @{ $self->{pattern_list} } - $self->{min_matches_int};
    }
    print STDERR "FP: $final_pass\n" if $self->{debug};
    my ($buf, $i);
    $self->{buf} = \$buf;
    $self->read_blacklist if $self->{blacklist_file};
    $self->read_works_blacklist if $self->{blacklisted_works_file};
    my %already_seen = map { $_ => 1 } @{ $self->{seen_author_list} };

    if (@ARGV)
    {
        # Do the (full-file) search.  
        #print Data::Dumper->Dump(\@ARGV);
        while ($buf = <>) 
        {
            my $auth_num = $ARGV;
            $auth_num =~ tr/0-9//cds;
            next if $already_seen{$auth_num};

            # Search for the minimum necessary number of patterns
            for (   my $pass = 0; $pass <= $final_pass; $pass++  )
            {
                # Before each pass, make sure that the browser is still listening;
                # SIGPIPE does not work under MS Windows
                my $success = print ("\0");
                if (not $success) {
                    print STDERR "Test print failed! $!\n";
                    # die does not exit server, but halts eval of cgi script
                    die if $Diogenes_Daemon::flag;
                } else {
                    # print STDERR "OK!\n" if $self->{debug};
                }
                my $pattern = @{ $self->{pattern_list} }[$pass];
                # clear the last search
                undef $self->{seen}{$ARGV};
                undef $self->{match_start}{$ARGV};
                while ($buf =~ m#$pattern#g) {
                    push @{ $self->{seen}{$ARGV} }, pos $buf;
                    push @{ $self->{match_start}{$ARGV} }, $-[0];
                }
                if ($self->{seen}{$ARGV})
                {
                    $self->parse_idt($auth_num);
                    $self->extract_hits($ARGV);
                }
            }
            push @{$self->{seen_author_list}}, $auth_num;
            return $self->{seen_author_list} if $self->{current_chunk} > $self->{chunk_size};
        } 
    }
    
    # Now search in any files that are to be read only in part.
    
    my @ordered_authors = ();
    if ($self->{tlg_use_chronology} and $self->{type} eq 'tlg') {
        # Do chronological sort of authors for TLG
        foreach my $num (@{ $self->{tlg_ordered_authnums} }) {
            my $short_num = $num;
            $short_num =~ s/^0+//g;
            if (exists $self->{req_auth_wk}{$num}) {
                push @ordered_authors, $num;
            }
            elsif (exists $self->{req_auth_wk}{$short_num}) {
                push @ordered_authors, $short_num;
            }
        }
    }
    else {
        # Just do ordinary sort
        @ordered_authors = sort numerically (keys %{ $self->{req_auth_wk} });
    }

    # Read in only the desired blocks from files for which only certain works 
    # were requested.

    my ($filename, $offset, $start_block, $end_block, $auth_num);
    foreach my $author (@ordered_authors)
    {
        # pad with leading zeroes 
        $auth_num = sprintf '%04d', $author;
        next if $already_seen{$auth_num};
        
        # parse .idt file
        my $real_num = $self->parse_idt($auth_num);
        
        $filename = $self->{file_prefix} . $auth_num;
                
        # open the .txt file 
        $filename .= $self->{txt_suffix};
        open INP, "$self->{cdrom_dir}$filename" or $self->barf("Couln't open $filename!");
        binmode INP;
                
        # loop through each requested work
        foreach my $work (sort keys %{ $self->{req_auth_wk}{$author} }) 
        {
            # get only those blocks of the file containing the work in question
            $start_block = $work_start_block{$self->{type}}{$real_num}{$work};
            $offset = $start_block << 13;
            seek INP, $offset, 0;
            my $next = $work;
            $next++;
            if (defined ($work_start_block{$self->{type}}{$author}{$next})) 
            {
                $end_block = $work_start_block{$self->{type}}{$author}{$next};
                read INP, $buf, (($end_block - $start_block + 1) << 13) or
                    $self->barf ("Couln't read from $filename");
            }
            else 
            {
                $buf = <INP>;
                $self->barf ("Couln't read the rest of $filename!") unless
                    defined $buf;
            }
            $self->{current_work} = $work;  
            
            # This does the search, storing the locations in %seen
            # Search for the minimum necessary number of patterns
            for (   my $pass = 0; $pass <= $final_pass; $pass++  )
              {
                my $success = print ("\0");
                if (not $success) {
                    print STDERR "Test print failed! $!\n";
                    die if $Diogenes_Daemon::flag;
                }
                my $pattern = @{ $self->{pattern_list} }[$pass];
                # clear the last search
                undef $self->{seen}{$author};
                undef $self->{match_start}{$author};
                while ($buf =~ m#$pattern#g) {
                    push @{ $self->{seen}{$author} }, (pos $buf);
                    push @{ $self->{match_start}{$author} }, $-[0];
                }
                $self->extract_hits($author);

            }
        }
        close INP or $self->barf("Couln't close $filename!");
        push @{$self->{seen_authors}}, $auth_num;
        return $self->{seen_authors} if $self->{current_chunk} > $self->{chunk_size};
    }
    
    return 'done';
}


###########################################################
#                                                         #
# Method to print the total hits in a brute force search. #
#                                                         #
###########################################################

sub print_totals 
{
    my $self = shift;
    my $message = shift;
    $chunk_message = '' if $message ne 'done';
    my $out = '';
    $out .= '\nrm{}' if $self->{output_format} eq 'latex';
    if ($message eq 'done') {
        $out .= "\n\&Passages found: " . ($self->{hits} || 0) ."\n";
    }
    else {
        $out .= "\n\&Cumulative total of passages found so far: " . ($self->{hits} || 0) ."\n";
    }
    $out .= '(' . $self->{blacklisted_hits} .
        " passages suppressed from blacklisted works)\n" 
        if $self->{blacklisted_hits};
    $out .= '(' . $self->{blacklisted_files} .
        " blacklisted authors were not searched at all)\n" 
        if $self->{blacklisted_files};
    if ($self->{tlg_files_missing}) {
        $out .= "Number of files missing from TLG database (version E): " .
            $self->{tlg_files_missing} . "\n"
    }
    if ($self->{phi_files_missing}) {
        $out .= "Number of files missing from PHI database: " .
            $self->{phi_files_missing} . "\n"
    }
    if ($self->{phi_files_damaged}) {
        $out .= "Number of files damaged in PHI database: " .
            $self->{phi_files_damaged} . "\n"
    }
    $out .= "\n";
    $self->print_output(\$out);
}

# Non-unicode, various Latin transliterations

sub make_greek_patterns_translit {
    my $self = shift;
    $self->{reject_pattern} =
        $self->make_greek_pattern_from_translit($self->{reject_pattern});
    foreach my $pat (@{ $self->{pattern_list} }) {
        $pat = $self->make_greek_pattern_from_translit($pat);
    }
}

sub make_greek_pattern_from_translit { 
    my ($self, $pat) = @_;
    if ($self->{input_pure}) {
        return $pat;
    }
    elsif ($self->{input_raw}) {
        return quotemeta $pat;
    }
    elsif ($self->{input_beta}) {
        return $self->make_strict_greek_pattern ($pat);
    }
    else {
        # Fall back to Perseus transliteration
        return $self->perseus_to_beta($pat);
    }
}

# Construct a regexp to search for Greek, with accents and breathings
# significant.  Input is Beta code with diacritics.  Uses the code for
# word-list searches.

sub make_strict_greek_pattern
{
    my ($self, $pat) = @_;
    $pat =~ tr/a-z/A-Z/;                    # upcap all letters
    $pat =~ s#\\#/#g;                       # normalize barytone accents
    $pat =~ s#\s+# #g;                      # normalize spacing
    
    # We remove all diaereses specified in the input, because the TLG
    # word list strips out diaereses and thus our patterns must permit
    # a diaeresis to appear after any letter. Explicit diaereses get
    # in the way of matching, esp in cases of hyphenation.
    $pat =~ s#\+##g;
    
    my @pats;
    my $pattern;
    if ($pat =~ m/\s/) {
        my @parts = split /\s+/, $pat;
        foreach my $part (@parts) {
            my ($part_pat, undef) =
                Diogenes::Indexed::make_tlg_regexp($self, $part, (not $begin), (not $end));
            push @pats, $part_pat;
        }
        $pattern = join '\s+[^A-Z]*', @pats;
    }
    else {
        ($pattern, undef) =
            Diogenes::Indexed::make_tlg_regexp($self, $pat, (not $begin), (not $end));
    }

    s/\x073(?!\?)/(?:/g; # turn ( into (?: for speed
    s/\x074/)/g;
    return $pattern;
}

sub make_latin_pattern
{
    my $self = shift;
        
    $self->{reject_pattern} = $self->latin_pattern($self->{reject_pattern});
    foreach my $pat (@{ $self->{pattern_list} })
    {
        if ($self->{input_pure}) 
        { 
            $pat = $pat;
        }
        elsif ($self->{input_raw}) 
        { 
            $pat = quotemeta $pat;
            $pat = $pat;
        }
        else 
        {
            $pat = $self->latin_pattern($pat);
        }
    }
}

sub latin_pattern
{
    my $self = shift;
    my $pat = shift;
    return $pat unless $pat;
    
    # We get (in Cicero) both auctio- @1 .nem and auctio- @1.nem
    my $non_alpha = '\\x00-\\x1f\\x21-\\x40\\x5b-\\x60\\x7b-\\xff';
    my $non_alpha_with_space = '\\x00-\\x40\\x5b-\\x60\\x7b-\\xff';
    # This code has been designed so that it will not disturb certain
    # Perl regexp constructs, such as char classes, and parens and | 
    # (alternation).  But many other types of input it may well mangle.
    
    # Turn every letter and every char class into a case insensitive
    # char class.
    $pat =~ s#([a-zA-Z]|\[[^\]]*\])#
                my $rep = $1;
                $rep =~ tr/\[\]//d;
                $rep =~ s/[ij]/ij/;
                $rep =~ s/[IJ]/IJ/;
                $rep =~ s/[uv]/uv/;
                $rep =~ s/[UV]/UV/;
                '['."\L$rep\E\U$rep\E".']'#gex; 
    
    print STDERR "Char classes: $pat\n" if $self->{debug};
                                
    # Add non-alphabetics
    # We have to allow spaces after hyphens and where there's a space
    # in the input pattern, because of e.g. page-breaks that intervene
    # like so: auctio- @1 .nem 
    $pat =~ 
        s/(\[[^\]]*\][*+?]?)(?!$)/$1(?:-\[$non_alpha_with_space\]\*|\[$non_alpha\]\*)/g;
    # spaces at the start + some lookbehind
    $pat =~ s/^\s+/(?<![A-Za-z])(?<!\-[\\x80-\\xff])(?<!\-[\\x80-\\xff][\\x80-\\xff])/g; 
    $pat =~ s/\s+$/(?![A-Za-z])/g;                     # spaces at the end
    $pat =~ s/(?<!^)(?<!-)\s+/\\s+\[$non_alpha_with_space\]\*/g;  # other spaces (not at start or end)
    $pat =~ s/\((?!\?)/(?:/g;                          # turn ( into (?: for speed
    return $pat;
}
                        

#####################################################################
#                                                                   #
# Subroutine to convert latinized greek to a useful search pattern. #
# Input is in Perseus format, output is TLG BETA code regexp.       #
#                                                                   #
#####################################################################

sub perseus_to_beta 
{
    my $self = shift;
    $_ = shift;
    return $_ unless $_;

    s#\(#\x073#g;                                                       # protect parens
    s#\)#\x074#g;

    die "Invalid letter $1 used in Perseus-style transliteration\n" if m/([wyjqv])/;
    die "Invalid letter c used in Perseus-style transliteration\n" if m/c(?!h)/;
    # This is now entirely case-insensitive (and ignorant of accent).
    # The business of having accents and breathings before caps
    # made it nearly impossible to do case- sensitive searches reliably, and
    # the best candidate regeps were an order of magnitude slower.
        
    s/\b([aeêioôu\xea\xf4])/\x071$1/gi;         # mark where non-rough breathing goes
    s/(?<!\w)h/\x072/gi;                        # mark where rough breathing goes

#       #s#\b([aeêioôu^]+)(?!\+)#(?:\\\)[\\/|+=]*$1|$1\\\))#gi;         # initial vowel(s), smooth
#
#       s#^h# h#; # If there's a rough breathing at the start of the pattern, then we assume it's the start of a word
#   s#(\s)([aeêioôu^]+)(?!\+)#$1(?:(?<!\\\([\\/|+=][\\/|+=])(?<!\\\([\\/|+=])(?<!\\\()$2(?!\\\())#gi;           # initial vowel(s), smooth
#       s#(\s)h([aeiou^]+)(?!\+)#$1(?:\\\([\\/|+=]*$2|$2\\\()#gi;             # initial vowel(s), rough breathing
#   s#\bh##; # Ignore breathings
    
    s/[eE]\^/H/g;                                           # eta
    s/[êÊ\xea\xca]/H/g;                                             # ditto
    s/[tT]h/Q/g;                                            # theta
    s/x/C/g;                                                # xi
    s/[pP]h/F/g;                                            # phi
    s/[cC]h/X/g;                                            # chi
    s/[pP]s/Y/g;                                            # psi
    s/[oO]\^/W/g;                                           # omega
    s/[ôÔ\xf4\xd4]/W/g;                                             # ditto
        
    return $self->make_loose_greek_pattern($_);              
}

# Make a regexp for searching greek, not sensitive to accents and
# case.  Input is beta-code, with diacrits removed.  Smooth and rough
# breathing should be marked with \x071 and \x072 respectively at the
# start of the word, and parens by \x073 and \x074.

# h looks ahead for a rough breathing somewhere in the following group
# of vowels, or before it as capitalized words or in the word (EA`N.
# In lookbehind, allow for other diacrits to intervene

my $rough_breathing =  q{(?:(?<=\()|(?<=\([^A-Z])|(?<=\([^A-Z][^A-Z])|(?=[AEHIOWU/\\\\)=+?!|']+\())};    
my $smooth_breathing =  q{(?:(?<=\))|(?<=\)[^A-Z])|(?<=\)[^A-Z][^A-Z])|(?=[AEHIOWU/\\\\)=+?!|']+\)))};    

# smooth is lack of rough
# my $smooth_breathing = q{(?:(?<!\()(?<!\([^A-Z])(?<!\([^A-Z][^A-Z])(?![AEHIOWU/\\\\)=+?!|']+\())}; 

sub make_loose_greek_pattern {
    my $self = shift;
    $_ = shift;
    tr/a-z/A-Z/;                                            # upcap all 

    my $non_alpha = '\\x00-\\x1f\\x21-\\x40\\x5b-\\x5e\\x60\\x7b-\\xff';
    my $non_alpha_and_space = '\\x00-\\x40\\x5b-\\x5e\\x60\\x7b-\\xff';
    my $non_alpha_nor_asterisk = '\\x00-\\x1f\\x21-\\x29\\x2b-\\x40\\x5b-\\x5e\\x60\\x7b-\\xff';
    # The following allows trailing accents, hyphens, markup, etc. after letters, char classes and rough breathing
#s/(\[[^\]]*\][*+?]?|\(\?:(?:[^\\)]|\\\)|\\)*\)|[A-Z])/$1\[\\x00-\\x1f\\x21-\\x40\\x5b-\\x60\\x7b-\\xff\]\*/g;
#s/([^A-Z ]*[A-Z ][^A-Z ]*)/$1\[\\x00-\\x1f\\x21-\\x40\\x5b-\\x60\\x7b-\\xff\]\*/g;

# Put non-alpha after all chars.  Allow spaces where there is a hyphenation (page-break markup)

#     s/([^A-Z ]*[A-Z][^A-Z ]*)/$1\[$non_alpha\]\*/g;
      s/([^A-Z ]*[A-Z][^A-Z ]*)/$1(?:-\[$non_alpha_and_space\]\*|\[$non_alpha\]\*)/g;

# A space in the middle can gobble extra spaces for things like " @1 "
s/([^A-Z ]*[ ][^A-Z ]*)(?!$)/$1\[$non_alpha_and_space\]\*/g;
s/([^A-Z ]*[ ][^A-Z ]*)(?=$)/$1\[$non_alpha_nor_asterisk\]\*/g;
#s/(?<!^)\s+(?!$)/\[^A-Z\]/g;           # other spaces (not at start or end)
    # spaces at the start (the lookbehind tries to reject hyphenation fragments and
    # mid-word matches after accents, but we can't just reject on preceding accents,
    # since capitalized words do have accents preceding, and *must* not be rejected).
        s#^\s+#(?<![A-Z])(?<!\-[\\x80-\\xff])(?<![A-Z][)(\\/|+=])(?<![A-Z][)(\\/|+=][)(\\/|+=])(?<!\-[\\x80-\\xff][\\x80-\\xff])#g; 
#       s/\s+$/(?=[^A-Z])/g;            # spaces at the end -- this doesn't work -- previous glob backtracks off
#        s/\s+$/[ \\]}&\$\%"#\@>]/g;     # spaces at the end -- doesn't match
   
    #my $diacrits = '\/\\\\\=\+\?\!\)\(\|\'';
    
    s#\x072#$rough_breathing#g;    
    s#\x071#$smooth_breathing#g;

    s/\x073(?!\?)/(?:/g;                                # turn ( into (?: for speed
    s/\x074/)/g;                

    return $_;
}


# Latin transliteration input, except without turning the greek into a
# regexp (Used on input destined for the word list.)

sub simple_latin_to_beta 
{
    my $self = shift;
    $_ = shift;
    return quotemeta $_ if $self->{input_raw} or $self->{input_pure};
    if ($self->{input_beta})
    {
        tr/a-z/A-Z/;                                            # upcap all letters
        s#\\#/#g;
        $_ = quotemeta $_;
        s#\\\s+# #g;
        return $_;
    }

    # Fall back to Perseus-style transliteration
    
    tr/A-Z/a-z/;
    my $start;
    $start++ if s#^\s+##;
    
    s/\b([aeêioôu\xea\xf4])/\x071$1/g;     # mark where non-rough breathing goes
    s#^h#\x072#i;                  # protect h for rough breathing later
    
    s/[eE]\^/H/g;                                           # eta
    s/[êÊ\xea\xca]/H/g;
    s/[tT]h/Q/g;                                            # theta
    s/x/C/g;                                                # xi
    s/[pP]h/F/g;                                            # phi
    s/[cC]h/X/g;                                            # chi
    s/[pP]s/Y/g;                                            # psi
    s/[oO]\^/W/g;                                           # omega
    s/[ôÔ\xf4\xd4]/W/g;
#   if (/h/) { $self->barf("I found an \`h\' I didn't understand in $_")};
    tr/a-z/A-Z/;                                            # upcap all other letters

    s#\x072#$rough_breathing#g;    
    s#\x071#$smooth_breathing#g;
    
    s#^# # if $start; # put the space back in front
    return $_;              
}


##################################################################
#                                                                #
# Method to remove from @ARGV any files that match the blacklist #
# of files that we never want to search through.                 #
#                                                                #
##################################################################

sub read_blacklist
{
    my $self = shift;
    my $bl;
    open BL, "<$self->{blacklist_file}" or 
        die "Couldn't open blacklist file: $self->{blacklist_file}: $!\n";
    {
        local $/;
        undef $/;
        $bl = <BL>;
    }
    print STDERR "Files originally in ARGV: ".scalar @ARGV."\n" if $self->{debug};
    my @files;
    $self->{blacklisted_files} = 0;
    foreach my $file (@ARGV)
    {
        $file =~ m/($self->{file_prefix}\d\d\d\d)/;
        my $pat  = $1;
        if ($bl =~ m/$pat/i)
        {
            print STDERR "Removing blacklisted file: $file\n" if $self->{debug};
            $self->{blacklisted_files}++;
        }
        else
        {
            push @files, $file;
        }
    }
    @ARGV = ();
    @ARGV = @files;
    print STDERR "Files remaining in ARGV: ".scalar @ARGV."\n" if $self->{debug};
}

sub read_works_blacklist
{
    my $self = shift;
    open BL, "<$self->{blacklisted_works_file}" or 
        die "Couldn't open blacklisted works file: $self->{blacklisted_works_file}: $!\n";
    {
        local $/;
        $/="\n";
        
	while (my $entry = <BL>)
	{
            chomp $entry;
            next if $entry =~ m/^\s*$/;
            next if $entry =~ m/^#/;
            my ($auth, @works) = split ' ', $entry;
            die "Bad blacklisted works auth ($self->{blacklisted_works_file}): $auth\n" 
                unless $auth =~ m/^\D\D\D\d+$/;
            my ($type, $auth_num) = $auth =~ m/^(\D\D\D)(\d+)$/;
            $type = lc $type;             
            $auth_num = sprintf '%04d', $auth_num;
            
            for (@works)
            {
                die "Bad blacklisted work ($self->{blacklisted_works_file}): $_\n" 
                    unless $_ =~ m/^\d+$/;
                $_ = sprintf '%03d', $_;
                warn "Blacklisting $type$auth_num: $_\n" if $self->{debug};
                $self->{blacklisted_works}{$type}{$auth_num}{$_} = 1;
            }
        }
    }
    $self->{blacklisted_hits} = 0;
    close BL or 
        die "Couldn't close blacklisted works file: $self->{blacklist_file}: $!\n";
}


##################################################################################
#                                                                                #
# Subroutine to seek to the position of each hit in a search and for each one to #
# extract the location info and surrounding context.                             #
#                                                                                #
##################################################################################

sub extract_hits 
{
    my ($self, $auth) = @_;
    my ($match, $block_start, $location);
    my ($code, $start, $end, $lines, $result, $this_work, $pos);
    my $current_block_start = -1;
    my $buf = $self->{buf};
    
    # load up the author, work and label info for that file (from the
    # corresponding .idt file, but only for full-file searches -- word 
    # list searches and partial files will have parsed the idt file aleady, 
    # in order to see what blocks the work in question lies in.
    
    # Get context regexps for the current language
    my $numeric = $1 if $self->{context} =~ m/(\d+)/;
    my $context;
    $context = $context{$self->{current_lang}}{$self->{context}} 
        || $numeric;
    $context = $self->{context} unless $context;
    my $overflow  = $self->{overflow}->{$self->{context}} || $self->{max_context};

    # This is used to reject candidates for sentence, etc. ending; matches against: (..X..)
    my $reject = ($self->{current_lang} eq 'g') ?
        qr /^\.\ |^.\.\.|^[ &][A-Za-z]|^[a-z][a-z]\.|^.\$|^..@\d|^...[&\$]|^..._|^..\.[ \]]\d/ :
        qr /^\.\ |^.\.\.|^\ [A-Za-z]|^fr\.|^cf\.|^eg\.|^.\$|^..@\d|^...[&\$]|^..._|^..\.[ \]]\d|^[A-Z]|^.[A-Z]/;
        
    my ($offset, $last_offset, $parsed_block) = (-1, -1, 0);
    my $matching_sets;
    HIT: foreach $match ( 0 .. $#{ $self->{seen}{$auth} } ) 
    {
        # The blocks containing the work in
        # question have been read into memory, so all we need to do
        # is to start at the beginning of the correct block
        $last_offset = $offset;
        $offset = $self->{seen}{$auth}[$match];
        print STDERR "Match num: $match; offset: $offset\n" if $self->{debug};
        my $buf_start  = (($offset >> 13) << 13);
        
        # Optimize case where one hit comes close after the previous,
        # so as not to go back to parse once again unneccessarily from
        # the beginning of the same block.  But watch out for cases
        # where a failed multiple match (next HIT) has skipped that
        # parsing
        if ($parsed_block and $last_offset != -1 and 
            ($offset - $last_offset < $offset - $buf_start))
        {
            $buf_start = $last_offset;
        }
        $parsed_block = 0; # set flag false
        
        if ($self->{check_word_stats})
        {
            # We have to scan for the location of this hit in the case of
            # indexed searches, even when it will not be displayed, in order 
            # to maintain proper statistics for the number of hits per work. 
            for (my $i = $buf_start; $i < $offset; $i++ ) 
            {
                # parse all of the data in this block from its beginning to our match
                $code = ord (substr ($$buf, $i, 1));
                next unless ($code >> 7); # high bit set
                $self->parse_non_ascii ($buf, \$i);             
            }
            $parsed_block = 1;
            
            print STDERR "$self->{work_num} ... $self->{current_work}\n" if
                $self->{debug};
            # for word-list searches, discard any hits that are not in the right
            # work (i.e. there might be other hits in this set of blocks too)
            next HIT if ($self->{current_work} and 
                         ($self->{work_num}) != $self->{current_work});  
            
        }
        $start = $self->{match_start}{$auth}[$match] - 2;
                
        # Get context block
        if ($self->{numeric_context}) 
        {
            $start++;
            # Get a number of lines of context before the match -- the concept of
            # `line' here is very unsophisticated.
            for ($lines = 0; $lines <= $context and 
                 ($start > 0); $start--) 
            {
                $lines++ if (((ord (substr ($$buf, $start, 1))) >> 7) and not
                             (ord (substr ($$buf, $start - 1, 1)) >> 7) and not
                             (substr ($$buf, $start - 1, 1) eq "\x00"));
            }
            $start+=2;
        }
        elsif ($context eq 'level') {
            # Do nothing: $start stays the same
            $start+=2;
        }
        else
        {       
            # Find the start of the word pattern -- our pattern might have 
            # punctuation inside, or may simply have picked some up along the way.
            for ($start--; $start > 0; $start--)
            {
                last if substr ($$buf, $start, 2) =~ /[a-zA-Z)(=\\\/+][\s.,;:]/;
            }
            
            $start++; # This is to compensate for the $start-- on the first pass below
            # Get a regexp-delimited context
            for ($lines = 0; $start > 0; $start--)
            {
                # Lookahead so as to avoid ?_, @1, $., .&, Q. Horatius usw.
                last if substr ($$buf, $start, 1) =~ /$context/
                    and not substr ($$buf, $start - 2, 5) =~ $reject;
                # Failsafe
                $lines++ if (((ord (substr ($$buf, $start, 1))) >> 7) and not
                             (ord (substr ($$buf, $start - 1, 1)) >> 7) and not
                             (substr ($$buf, $start - 1, 1) eq "\x00"));
                last if $lines >= $overflow; 
            }
            # Try to eliminate stray chars and wasteful whitespace
            #while (substr ($$buf, ++$start, 1) =~ /[\s\d'"@}\])&\$\x80-\xff]/) {};
            while (substr ($$buf, ++$start, 1) =~ /[\s\d'"@}\])\x80-\xff]/) {};
        }
        
        next HIT if $self->{already_reported}{$auth}{$start} and 
            not $self->{check_word_stats};
        
        if ($self->{numeric_context}) 
        {
            # Get lines of context after the match.
            for ($end = $offset, $lines = 0; ($lines <= $context) and 
                 ($end < length $$buf ) ; $end++) 
            {
                $lines++ if (((ord (substr ($$buf, $end, 1))) >> 7) and not 
                             (ord (substr ($$buf, $end + 1, 1)) >> 7) and not
                             (substr ($$buf, $end + 1, 1) eq "\x00"));
            }
            $end-=2;
        }
        elsif ($context eq 'level') {
            # Grab to the end of the current section (e.g. lexicon
            # entry).  Crude solution, but Photius lex entries are not
            # separated by level.
            for ($end = $offset, $lines = 0; $end < length $$buf; $end++) {
                last if substr ($$buf, $end, 2) =~ m/[\x80-\xff]</;
                # Failsafe
                $lines++ if (((ord (substr ($$buf, $end, 1))) >> 7) and not
                             (ord (substr ($$buf, $end + 1, 1)) >> 7) and not
                             (substr ($$buf, $end + 1, 1) eq "\x00"));
                last if $lines >= 100;
            }
        }
        else
        {
            # Get a regexp-delimited context
            for ($end = $offset, $lines = 0; $end < length $$buf; $end++)
            {
                # Lookahead so as to avoid ?_, @1, $. usw.
                last if substr ($$buf, $end, 1) =~ /$context/
                    and not substr ($$buf, $end - 2, 5) =~ $reject;
                # Failsafe
                $lines++ if (((ord (substr ($$buf, $end, 1))) >> 7) and not
                             (ord (substr ($$buf, $end + 1, 1)) >> 7) and not
                             (substr ($$buf, $end + 1, 1) eq "\x00"));
                last if $lines >= $overflow; 
            }
            $end++; # Take one more
        }
        
        $result = substr ($$buf, $start, ($end - $start));
        
        # We want to highlight all matching patterns, and yet accept only those
        # passages where there are matches across a mimimum number of distinct
        # patterns from the list
        my %matches = ();
        if ($self->{output_format} eq 'beta' or not $self->{highlight})
        {
            my $n = 0;
            map {$matches{$n}++ if $result =~ /$_/; $n++;}(@{ $self->{pattern_list} });
            $matching_sets = 0;
            if ($self->{repeat_matches}) {
                # Count total number of matches for all patterns
                $matching_sets += $_ for values %matches;
            }
            else {
                # Count number of individual patterns that match
                $matching_sets = values %matches;
            }
            print STDERR "+ $result\n" if $self->{debug};
            print STDERR "+ $matching_sets: $auth, $offset\n" if $self->{debug};
            warn "ERROR: Disappearing Match!\n" unless $matching_sets;
            next HIT unless $matching_sets >= $self->{min_matches_int};
            next HIT if $self->{reject_pattern} and $result =~ m/$self->{reject_pattern}/;
        }
        else
        {
            my $n = 0;
            map     {$result =~ s#(~hit~[^~]*~)|((?:\*[)(/\\\\=+|']*)?$_[)(/\\\\=+|']*)#
                                                                        if ($2) {$matches{$n}++; '~hit~'.$2.'~'}
                                                                        else    {$1}
                                                                        #ge;
                     $n++;}
                (@{ $self->{pattern_list} });


            if ($self->{repeat_matches}) {
                # Count total number of matches for all patterns
                $matching_sets = 0;
                $matching_sets += $_ for values %matches;
            }
            else {
                # Count number of individual patterns that match
                $matching_sets = scalar keys %matches;
            }
            print STDERR "+ $result\n" if $self->{debug};
            # print STDERR "+ ".$self->{pattern_list}[0]."\n" if $self->{debug};
            print STDERR "+ $matching_sets: $auth, $offset\n" if $self->{debug};
#            my $seens = join ':', @{ $self->{seen}{$auth} };
#            print STDERR  "$seens\n";

            warn "ERROR: Disappearing Match!!\n" unless $matching_sets;
            next HIT unless $matching_sets >= $self->{min_matches_int};
            next HIT if $self->{reject_pattern} and $result =~ m/$self->{reject_pattern}/;
        }
                
        if ($self->{check_word_stats})
        {
            # keep a running total of hits
            $self->{hits_hash}{$self->{auth_num}}
            {$self->{work_num}}{$self->{word_key}}++;
            print STDERR $self->{auth_num}, "; ", 
            $self->{work_num}, "; ", 
            $self->{word_key},   "; ", 
            $self->{hits_hash}{$self->{auth_num}}{$self->{work_num}}
            {$self->{word_key}}, 
            "\n" if $self->{debug};
            next HIT if $self->{already_reported}{$auth}{$start};
        }
        else
        {
            # Only now do we belatedly find the location for searches that
            # ignore statistics (ie. all but indexed searches of the TLG), since
            # we are sure we want to output this block.
            for (my $i = $buf_start; $i < $offset; $i++ ) 
            {
                # parse all of the data in this block from its beginning to our match
                $code = ord (substr ($$buf, $i, 1));
                next unless ($code >> 7); # high bit set
                $self->parse_non_ascii ($buf, \$i);             
            }
        }
        # Set flag to true, since we have passed by all of the next
        # HIT statements, and we have definitely parsed the location
        # info for this hit, meaning we can use it as the basis for
        # the location info for the next hit in this block
        $parsed_block = 1;
        
        $self->{hits}++;
            
        if (exists $self->{blacklisted_works} 
            and $self->{blacklisted_works}{$self->{file_prefix}}{$self->{auth_num}}{$self->{work_num}})
        {
            warn "Warning: supressing hit in blacklisted work ($self->{auth_num}: $self->{work_num})\n";
            $self->{blacklisted_hits}++;
            next HIT;
        }

        # Add spaces to start of line for proper indent
        my $spaces = -1;
        for (my $pre_start = $start; not (ord (substr ($$buf, $pre_start--, 1)) >> 7); 
             $spaces++)     {}
        $result = ' ' x $spaces . $result;
        
        $location = "\n\&";
        # extract and print the author, work and location of the match
        #print STDERR ">>".$self->{type}.$self->{auth_num}."||\n";

        $this_work = "$author{$self->{type}}{$self->{auth_num}}, ";
        $this_work .= 
            "$work{$self->{type}}{$self->{auth_num}}{$self->{work_num}} ";
        $location .= ($self->{print_bib_info} and not  $self->{bib_info_printed}{$self->{auth_num}}{$self->{work_num}})
            ? $self->get_biblio_info($self->{type}, $self->{auth_num}, $self->{work_num})
            : $this_work;
        $self->{bib_info_printed}{$self->{auth_num}}{$self->{work_num}} = 'yes' if $self->{print_bib_info};

        $location .="\&\n";

        my $jumpto = $self->{type}.','.$self->{auth_num}.','.$self->{work_num};
            
        foreach (reverse sort keys %{ $self->{level} }) 
        {
            if 
                ($level_label{$self->{type}}{$self->{auth_num}}{$self->{work_num}}{$_})
            {
                $location .=
                    "$level_label{$self->{type}}{$self->{auth_num}}{$self->{work_num}}{$_}".
                    " $self->{level}{$_}, ";
                $jumpto .= ':'.$self->{level}{$_};
            }
            elsif ($self->{level}{$_} ne '1') 
            {       # The Theognis exception & ddp
                $location .= "$self->{level}{$_}, ";
                $jumpto .= ':'.$self->{level}{$_};
            }
        }
        chop ($location); chop ($location);
        if ($self->{special_note}) 
        {
            $location .= "\nNB. $self->{special_note}";
            undef $self->{special_note};
        }

        $location .= "\n\n";
        if ($Diogenes::Base::cgi_flag and $self->{cgi_buttons})
        {
            # Leading space keeps it out of the perseus links
            $result .= " \n~~~$jumpto~~~\n";
        }
        else
        {
            $result .= "\n\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n";
        }
        my $base = ($self->{current_lang} eq 'g')
            ? '$'
            : '&';
        my $output = '& ' . $location . $base . $result;
        
        $self->print_output(\$output);
        
        $self->{already_reported}{$auth}{$start}++;
        
    } # end of foreach.
} # end of sub extract_hits.

sub numerically { $a <=> $b; }

1;
