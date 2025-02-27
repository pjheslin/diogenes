#############################################
#-------------------------------------------#
#---------------File Browser----------------#
#-------------------------------------------#
#############################################
package Diogenes::Browser;
use Diogenes::Base qw(%work %author %work_start_block %level_label %top_levels %last_citation);
@Diogenes::Browser::ISA = qw( Diogenes::Base );

# Method to print the authors whose names match the pattern passed as an    #
# argument.                                                                 #

sub browse_authors 
{
    my ($self, $pattern) = @_;
    $self->{latex_counter} = 0;
    return (1 => 'doccan1', 2 => 'doccan2') if $self->{type} eq 'bib';
    # For authors without numbers
#     return %{ $self->match_authtab($pattern) };
    my $rv = $self->match_authtab($pattern);
    # Add numbers (because some author names are identical)
    foreach (keys %{ $rv }) {
        $rv->{$_} .= " ($_)";
    }
    return %{ $rv };
}

# Method to print the works belonging to the specified author (number).     #

sub browse_works 
{
    my $self = shift;
    my $auth_num = shift;
    my $work_num;
    # The real auth num is actually not a number for civ texts, so
    # we get it here (conversely, tlg bibliography files have a real author
    # number, such as 9999, that is not reflected in the file name)
    my $real_num = $self->parse_idt ($auth_num);
    #return %{ $work{$self->{type}}{$real_num} };
    my %ret =  %{ $work{$self->{type}}{$real_num} };
    $self->format_output(\$_, 'l') for values %ret;
    return %ret;
}

# Method to get the labels belonging to the specified work. 

sub browse_location 
{
    my $self = shift;
    my ($auth, $work) = @_;
    my ($lev, @levels);

    my $real_num = $self->parse_idt ($auth);
    $work = sprintf '%03d', $work;

    foreach $lev (sort numerically keys 
                  %{ $level_label{$self->{type}}{$real_num}{$work} }) 
    {
        push @levels, $level_label{$self->{type}}{$real_num}{$work}{$lev};
    }
    my @ret = reverse @levels;
    $self->format_output(\$_, 'l') for @ret;
    return @ret;
}

# Method to read the selected work and to seek to the specified point 
# within it (eg. Book x, Chapter y, line z). 

sub seek_passage 
{
    my $self = shift;
    my ($auth, $work, @array_target) = @_;
    my ($start_block, $end_block, $code, $lev, $top_level, $look_ahead);
    my ($top_num, $target_num, $level_num, $i);
    
    # We turn the passed array into a hash, to match the data gleaned
    # from the .idt file.
    my $index = $#array_target;
    my %target = map {$index-- => $_} @array_target;
    die "Ooops! $index" if $index != -1; 
    $self->{target_levels} = scalar @array_target;
    # If we aim for Book 0, Line 90, we really want Book 1, Line 90.
    my @modified_target = @array_target;
    for (my $j = 0; $j < $self->{target_levels}; $j++) {
        if ($modified_target[$j] eq "0") {
            $modified_target[$j] = 1;
        }
    }
    $self->{target_citation} = join '.', @modified_target;
        
    my $orig_auth_num = $auth;
    my $real_num = $self->parse_idt ($auth);
    $work = sprintf '%03d', $work;
        
    # Hack for ddp etc. disk -- .idt files only list `document', which
    # is really the label for level 5, not level 0.
    if ($self->{documentary})
    {
        $target{5} = delete $target{0};
        $target{5} =~ s#([\[\]])#\`$1\`#g; #These are BETA null chars (see above).
    }

    $self->{current_lang} = 'g' unless $self->{type} =~ m/phi|civ/;
    
    my $filename = "$self->{cdrom_dir}$self->{file_prefix}$auth$self->{txt_suffix}";
    $auth = $real_num if defined $real_num;

    # open the file and seek to the beginning of the first block containing
    # our work
    open INP, $filename or $self->barf("Couldn't open $filename");
    binmode INP;
    
    $start_block = $work_start_block{$self->{type}}{$auth}{$work};
    my $next = $work;
    $next++;
    $end_block = $work_start_block{$self->{type}}{$auth}{$next};
    
    print STDERR "Start: $start_block" if $self->{debug}; 
    print STDERR ", End: $end_block\n" if $self->{debug} and $end_block; 

    my $offset = $start_block << 13;
    seek INP, $offset, 0;

    # read the several 8k blocks containing our work
    # Should one have the option to read in only a subsection?
    my $buf;
    $self->{buf} = \$buf;
    if (defined $end_block) 
    {
        read INP, $buf, (($end_block - $start_block + 1) << 13) or
            $self->barf ("Couln't read from $filename!");
    }
    else 
    {
        local $/;
        undef $/;
        $buf = <INP>;
        $self->barf ("Couln't read the rest of $filename!") unless
            defined $buf;
        $end_block = (length $buf) >> 13;
    }
    close INP or $self->barf("Couldn't close $filename");
    
    $self->{work_num} = 0;
    $self->{auth_num} = 0;
    $self->{browse_auth} = $orig_auth_num;
    $self->{browse_work} = $work;
    $self->{current_work} = $work;
        
    # First, we look in the table of contents for starting point
    $top_level = (keys %{ $level_label{$self->{type}}{$auth}{$work} }) - 1;
    my ($block, $old_block);

    my $typeauth = $self->{type}.$auth;
    my $typeauthwork = $typeauth.$work;

    # There are very many short texts (esp fragmentary) where using
    # the ToC causes us to miss the work entirely.  Not sure if this
    # is a bug in the code below or in the idt files.  But computers
    # are so fast now, even searching through the entirety of a long
    # work is fast, so let's try defaulting to switching it off.
    
    # if ($typeauth =~ m/^(tlg5034|phi1348|phi0588|phi2349|tlg0031|phi0474|phi1002|tlg0096|phi0631|tlg5035)$/)
    if (not $self->{use_idt_browsing})
    {
        print STDERR "Skipping ToC from idt file.\n" if $self->{debug};
    }
    else
    {
        # We have to iterate through these levels, since for alphabetic entries, they
        # may not be in any order.
      SECTION:
        for (@{ $top_levels{$self->{type}}{$auth}{$work} })
        {
            $block = @{ $_ }[1];
            my $comp = compare(@{ $_ }[0], $target{$top_level});
            if ($comp >= 0)
            {
                # We've gone too far, so use previous chunk
                print STDERR 
                    ">>>@{ $_ }[0] => $target{$top_level} (using block $old_block)\n" if 
                    $self->{debug} and $old_block;
                $block = $old_block;
                last SECTION;
            }
            $old_block = $block;
        }
        # No match, so we try another trick
        print STDERR "No match in table of contents.\n" if 
            $self->{debug} and not defined $block;
    
        # We now look in the table of last citations per block
        my $cite_block = $block || 0;
      CITE_BLOCK:
        while ($cite_block <= $end_block)
        {
            my $level = $last_citation{$self->{type}}{$auth}{$work}{$cite_block};
            
            unless (defined $level)
            {
                # In case we are in an earlier work
                $cite_block++;
                next CITE_BLOCK;
            }
          LEVEL:
            foreach $lev (reverse sort numerically keys 
                          %{ $level_label{$self->{type}}{$auth}{$work} }) 
            {   
                # See below
                next LEVEL if 
                    $level_label{$self->{type}}{$auth}{$work}{$lev} =~ m#^\*#;
                next LEVEL unless $target{$lev};
                my $result = compare($level->{$lev}, $target{$lev});
                print STDERR 
                    ">>>$level->{$lev} <=> $target{$lev}: res = $result ($lev, $cite_block)\n"
                    if $self->{debug};
                if ($result == 0)
                {
                    next LEVEL;
                }
                elsif ($result == -1)
                {
                    $cite_block++;
                    next CITE_BLOCK;
                }
                else
                {
                    $block = $cite_block;
                    last CITE_BLOCK;
                }
            }
            $block = $cite_block;
            last CITE_BLOCK;
        }
    
        my $next_work = sprintf '%03d', $work + 1;
        $cite_block--; # went one too far
        print STDERR "nw: $next_work, cb: $cite_block\n" if $self->{debug};
        # Next block contains the end of our work but ends in the next work.
        $block = $cite_block if exists 
            $last_citation{$self->{type}}{$auth}{$next_work} and exists
            $last_citation{$self->{type}}{$auth}{$next_work}{$cite_block};
    
        print STDERR "Searching entire work!\n" if $self->{debug} and not defined $block;
    }
    $block ||= 0;
    # Catches some idt errors
    $block = $start_block if $block < $start_block;
    my $starting_point = ($block - $start_block) << 13 if $block;
    $i = $starting_point || 0;
    $i--;

    # seek through first block to the beginning of the work we want
    while ( 0 + $self->{work_num} < 0 + $work) 
    {
        $code = ord (substr ($buf, ++$i, 1));
        next unless ($code >> 7);
        $self->parse_non_ascii (\$buf, \$i);
        warn ".." . $self->{work_num} . "\n" if $self->{debug};     
    }
    if (0 + $self->{work_num} > 0 + $work)
    {
        warn "Error in searching for start of work: trying again from the beginning\n"
            if $self->{debug};
        $i = 0;
        while ( 0 + $self->{work_num} != 0 + $work) 
        {
            $code = ord (substr ($buf, ++$i, 1));
            next unless ($code >> 7);
            $self->parse_non_ascii (\$buf, \$i);
            print "::" . $self->{work_num} . "\n" if $self->{debug};
        }
    }
    if (0 + $self->{work_num} != 0 + $work)
    {
        barf("Error: cannot find the start of the work\n");
    }
    print STDERR "Search begins: $i \n" if $self->{debug};

    # For some texts we have to do a strict match rather than
    # matching when the citation is higher than the target.  For
    # Sextus Empiricus AM, books 1-6 come after 7-11.  In Plato's
    # Spuria, the Stephanus numbers jump around.
    my $weird_text;
    $weird_text = 1 if $typeauth eq 'tlg0544';
    $weird_text = 1 if $typeauthwork eq 'tlg0059038';

    # read first bookmark
    $code = ord (substr ($buf, ++$i, 1));
    $self->parse_non_ascii (\$buf, \$i) if ($code >> 7);
    
    # Loop in reverse order through the levels, matching eg. first the book, then
    # the chapter, then the line. 
    
  LEV: foreach $lev (reverse sort numerically 
                     keys %{ $level_label{$self->{type}}{$auth}{$work} }) 
  {
      print STDERR "==> $self->{level}{$lev} :: $target{$lev} \n" if $self->{debug};
      # labels that begin with a `*' are not hierarchical wrt the others
      next LEV if $level_label{$self->{type}}{$auth}{$work}{$lev} =~ m#^\*#;
      
      # loop until the count at this level reaches the desired number
      next LEV unless $target{$lev};
      if ($weird_text) {
          next LEV if (compare($self->{level}{$lev}, $target{$lev}) == 0);
      } else {
          next LEV if (compare($self->{level}{$lev}, $target{$lev}) >= 0);
      }
      
      # Scan the text
    SCAN:   while ($i <= length $buf) 
    { 
        $code = ord (substr ($buf, ++$i, 1));
        next SCAN unless ($code >> 7);
        $self->parse_non_ascii (\$buf, \$i);
        redo SCAN unless defined $self->{level}{$lev};

        if (0 + $self->{work_num} != 0 + $self->{browse_work} ) {
            if (ref $self eq 'Diogenes::Browser::Stateless') {
                print qq{<h1 style="text-align:center">Error: End of work reached without finding target citation!</h1>};
            }
            else {
                print "End of work reached without finding target citation!\n"
            }
            # TODO: Return from failure more elegantly than this.
            die "Bad browser request.\n";
        }
        
        # String equivalence
        print STDERR "=> $self->{level}{$lev} :: $target{$lev} \n" if $self->{debug};
        if ($weird_text) {
            last SCAN if (compare($self->{level}{$lev}, $target{$lev}) == 0);
        } else {
            last SCAN if (compare($self->{level}{$lev}, $target{$lev}) >= 0);
        }
    } 
      print STDERR "Target found: $target{$lev}, level: $self->{level}{$lev}\n" 
          if $self->{debug};
  }
    # Seek to end of current non-ascii block
    while (ord (substr ($buf, $i, 1)) >> 7) { $i++ };
    
    print STDERR "Offset: ", ($i + $offset), "\n" if $self->{debug};
    
    # store a reference to the string holding the text and the start point of the 
    # portion selected.
    $self->{browse_buf_ref} = \$buf;
    $self->{browse_begin} = $i;
    $self->{browse_end} = -1;
    
    return ($offset + $i, -1);  # $abs_begin and $abs_end 
}

sub compare
{
    # As defined by the PHI spec
    # Returns 0 for =, -1 for < and 1 for >
    my ($current, $target) = @_;
    $current ||= 0;

    # Match if we have no target or is zero
    return 1 unless $target;
    $target  ||= 0;

    my ($current_bin, $current_ascii) = $current =~ m/^(\d+)?(.*)$/;
    my ($target_bin,  $target_ascii ) = $target  =~ m/^(\d+)?(.*)$/;
    
    #print STDERR "|$current_bin|$current_ascii|$target_bin|$target_ascii|\n";
    
    # Match if leading binary part greater than or less than target
    return -1 if defined $current_bin and defined $target_bin and 
        $current_bin < $target_bin;
    return  1 if defined $current_bin and defined $target_bin and 
        $current_bin > $target_bin;
    return -1 if not defined $current_bin and defined $target_bin;
    # This is wrong.  If we are looking for a target of "fr" and the
    # fragments are at the end of the file, we don't want to match on
    # a bare book number.
    # return  1 if defined $current_bin and not defined $target_bin;
    
    # If both are not defined or both are defined and equal, we
    # examine the ascii part
    $current_ascii = lc $current_ascii;
    $target_ascii  = lc $target_ascii;
    return 0 if $current_ascii eq $target_ascii;
    if ((index $target_ascii, ':') == 0)
    {
        # The INS database sometimes has document 1:300[2], etc. where
        # the second half is really ordered numerically
        my ($current_extra_num) = $current_ascii =~ m/^:(\d+)/;
        my ($target_extra_num)  = $target_ascii  =~ m/^:(\d+)/;
        return -1 if defined $current_extra_num and defined $target_extra_num and 
            $current_extra_num < $target_extra_num;
        return  1 if defined $current_extra_num and defined $target_extra_num and 
            $current_extra_num > $target_extra_num;
    }
    # If both are single letters, match alphabetically (important for Plato)
    if ($current_ascii =~ m/^[a-zA-Z]$/ and $target_ascii =~ m/^[a-zA-Z]$/)
    {
        return ord lc $current_ascii <=> ord lc $target_ascii;
    }
    
    # Match if one is a substring of the other, and don't match
    # otherwise, if we are dealing with strings (my addition) --
    # comment it out, since it breaks the Suda (searching for "iota",
    # we hit "t" and then "alpha iota".  return 1 if (index
    # $current_ascii, $target_ascii) >= 0; return 1 if (index
    # $target_ascii, $current_ascii) >= 0;
    return -1 unless defined $current_bin or defined $target_bin;

    # If we are looking for a text suffix, e.g. Val Max section
    # 1(ext), don't match if the suffix is not there.
    return -1 if $target_ascii ne '' and $current_ascii eq '';
    
    # Is this really necessary?
    my @current = ($current_ascii =~ m/(\d+|\D)/g);
    my @target  = ($target_ascii  =~ m/(\d+|\D)/g);
    
    for my $n (0 .. $#current)
    {
        return  1 unless defined $target[$n];
        return  1 if $current[$n] =~ m/^\d+$/ and $target[$n] =~ m/^\d+$/ 
            and $current[$n] > $target[$n];
        return -1 if $current[$n] =~ m/^\d+$/ and $target[$n] =~ m/^\d+$/
            and $current[$n] < $target[$n];
        return  0 if $current[$n] =~ m/^\d+$/ and $target[$n] =~ m/^\d+$/;
        
        # We can't match on alphabetic sorting, because most texts don't work that way
        return -1 if $current[$n] =~ m/^\D$/ and $target[$n] =~ m/^\D$/;
        # The PHI spec is unclear and seems contradictory to me on what to do when
        # comparing strings character by character and you have a number on the one
        # hand and a string on the other.
    }
    return 0;
}

#####################################################################
# Private method that prints the location for the following two     #
# methods.  This code is lightly adapted from extract_hits.         #
#####################################################################

sub print_location 
{
    my $self = shift;
    # args: offset in buffer, reference to buffer
    my ($offset, $ref) = @_;
    my $i;
    my $cgi = (ref $self eq 'Diogenes::Browser::Stateless') ? 1 : 0;
    my ($location, $code);
    
    my $block_start = $cgi ? 0 :(($offset >> 13) << 13);
    
    $self->{work_num} = 0;
    $self->{auth_num} = 0;
    
    # Handle out of bounds conditions
    $offset = 0 if $offset < 0;
    $offset = length $$ref if $offset > length $$ref;
    
    for ($i = $block_start; $i <= $offset; $i++ ) 
    {
        $code = ord (substr ($$ref, $i, 1));
        next unless ($code >> 7); # high bit set
        $self->parse_non_ascii ($ref, \$i);             
    }
    # In case we try to read beyond the work currently in memory 
    return 0 
        if (not $cgi and $self->{work_num} != $self->{current_work});
    
    my $this_work = 
        "$author{$self->{type}}{$self->{auth_num}}, " .
        "$work{$self->{type}}{$self->{auth_num}}{$self->{work_num}} ";
    $location = '&';
    $location .= ($self->{print_bib_info} and not 
                  $self->{bib_info_printed}{$self->{auth_num}}{$self->{work_num}})
        ? $self->get_biblio_info($self->{type}, $self->{auth_num}, $self->{work_num})
        : '';
    $self->{bib_info_printed}{$self->{auth_num}}{$self->{work_num}} = 'yes'
        if $self->{print_bib_info}; 
    $location .="\&\n";

    $location .= $self->get_citation('full');
    
    $location .= "\n\n";
    $self->print_output(\$location);

    if ($self->{output_format} eq 'html') {
        my $picture_dir = 'images/';
        print qq{<input type="image" name="browser_back" class="prev" src="${picture_dir}go-previous.png" srcset="${picture_dir}go-previous.hidpi.png 2x" alt="Previous Text" /> };
        print qq{<input type="image" name="browser_forward" class="next" src="${picture_dir}go-next.png" srcset="${picture_dir}go-next.hidpi.png 2x" alt="Subsequent Text" />};
        print '<p style="clear: left;"></p>';
    }
    
    return 1;   
}

sub get_citation
{
    # Full means "Book 1, Line 2", else means "1.2".
    my $self = shift;
    my $full = shift;
    my $cit = '';
    
    foreach (reverse sort keys %{ $self->{level} }) 
    {
        if ($self->{level}{$_} and 
            $level_label{$self->{type}}{$self->{auth_num}}{$self->{work_num}}{$_})
        # normal case
        {
            if ($full)
            {
                $cit .=
                    "$level_label{$self->{type}}{$self->{auth_num}}{$self->{work_num}}{$_}".
                    " $self->{level}{$_}, "
            }
            else
            {
                $cit .= "$self->{level}{$_}.";
            }
        }
        elsif ($self->{level}{$_} ne '1') 
        {   # The Theognis exception 
            # and what unused levels in the ddp and ins default to
            if ($full)
            {
                $cit .= "$self->{level}{$_}, ";
            }
            else
            {
                $cit .= "$self->{level}{$_}.";
            }
        }
    }
    if ($full)
    {
        $cit =~ s/, $//;
    }
    else
    {
        $cit =~ s/\.$//;
    }
    return $cit;
}

sub numerically { $a <=> $b; }

#############################################################################
#                                                                           #
# Method to print out the lines following the currently selected point in   #
# the file.      Select the default number of lines via `browse_lines'.     #
#                                                                           #
#############################################################################

sub browse_forward 
{
    my $self = shift;
    my ($abs_begin, $abs_end, $auth, $work);
    my ($ref, $begin, $end, $line, $result, $buf, $offset);
    
    if (ref $self eq 'Diogenes::Browser')
    {   # Get persistent browser info from object
        $ref = $self->{browse_buf_ref};
        $self->{browse_begin} = $self->{browse_end} unless $self->{browse_end} == -1;
        $begin = $self->{browse_begin};
        $offset = 0;
    }
    elsif (ref $self eq 'Diogenes::Browser::Stateless')
    {       # Browser info is passed as arguments
        ($abs_begin, $abs_end, $auth, $work) = @_;
        $auth = 1 if  $self->{type} eq 'bib' and $auth =~ m/9999/;
        
        $begin = ($abs_end == -1) ? $abs_begin : $abs_end;
        $self->{current_work} = $work;
        $self->parse_idt ($auth);
        
        # open the file and seek to the beginning of the first block containing
        # our start-point
        open INP, "$self->{cdrom_dir}$self->{file_prefix}$auth$self->{txt_suffix}" or
            $self->barf("Couldn't open $self->{file_prefix}$auth$self->{txt_suffix}");
        binmode INP;
                
        my $start_block = $begin >> 13;
        $offset = $start_block  << 13;
        seek INP, $offset, 0;
        
        # read three 8k blocks -- should be enough!
        my $amount = 8192 * 3;
        read INP, $buf, $amount or 
            die "Could not read from file $self->{file_prefix}$auth.txt!\n" .
            "End of file?";
        
        close INP or $self->barf("Couldn't close $self->{file_prefix}$auth.txt");
        $ref = \$buf;
        $self->{browse_begin} = $begin;
        $begin = $begin - $offset;
    }
    else
    { 
        die "What is ".ref $self."?\n"
    }
    print STDERR "Beginning: $begin\n" if $self->{debug}; 
    
    # find the right length of chunk
  CHUNK:
    for ($end = $begin, $line = 0; 
         ($line <= $self->{browse_lines}) and ($end < length $$ref) ; 
         $end++) 
    {
        $line++ if ((ord (substr ($$ref, $end, 1)) >> 7) and not
                    (ord (substr ($$ref, $end + 1, 1)) >> 7)) ; 
        # for papyri, etc. get only one document at a time
        if ($self->{documentary} and ord (substr ($$ref, $end, 1)) >= hex 'd0'
            and ord (substr ($$ref, $end, 1)) <= hex 'df'
            and not ord (substr ($$ref, $end - 1, 1)) >> 7)
        {       # Seek to end of non-ascii block beginning with \xd0 -- \xdf
            while (ord (substr ($$ref, $end, 1)) >> 7)      { $end++ };
            last CHUNK;
        }
        if (substr ($$ref, $end, 2) eq "\xfe\x00") # EoB
        {
            $end++;
            while (substr ($$ref, $end, 1) eq "\x00")  { $end++; };
            
        }
    }
#    while (ord (substr ($$ref, --$end, 1)) >> 7)  { };

    $result = substr ($$ref, $begin, ($end - $begin));
    my $base = ($self->{current_lang} eq 'g')
        ? '$'
        : '&';
    $result = $base . $result  ;
    
    if ($self->print_location ($begin, $ref))
    {
#             print STDERR join "\n>>", @{ $self->interleave_citations(\$result) };
        $self->{interleave_printing} = $self->interleave_citations(\$result);
        $self->print_output (\$result);
    }
    elsif ($self->{browse_backwards_scan})
    {
        $self->{browse_backwards_scan} = 0;
        my @beginning = (0) x $self->{target_levels};
        my $ret = $self->seek_passage ($self->{browse_auth}, $self->{browse_work}, @beginning);
        if ($ret eq 'fail') {
            print "Passage not found!\n";
            return(0,0);
        }
        else {
            $self->browse_forward;
        }
    }
    else
    {
        print "Sorry.  That's beyond the scope of the requested work.\n" unless 
            $self->{quiet};
	return $self->{browse_begin}, -1;
    }
    $self->{browse_backwards_scan} = 0 if exists $self->{browse_backwards_scan};
    $begin = $end;
    # Store and pass back the start and end points of the whole session
    $self->{browse_end} = $end + $offset;
    return ($self->{browse_begin}, $end + $offset);  # $abs_begin and $abs_end
}

my $fill_spaces = 14;

%cite_info = ( html =>
               { before_cit => '<div class="citation">',
                 after_cit => '</div>',
                 before_text => '<div class="text">',
                 before_text_with_cit => '<div class="text-noindent">',
                 after_text => '</div>',
                 before_cit_hit => '<div class="citation" id="hit">',
                 after_cit_hit => '</div>',
                 before_text_hit => '<div class="text-noindent" id="hit">',
                 before_note => '<div class="special-note">',
                 after_note => '</div>',
               },
               ascii =>
               { before_cit => '',
                 after_cit => "FILL",
                 before_text => ' ' x $fill_spaces,
                 before_text_with_cit => "",
                 after_text => '',
                 before_cit_hit => '',
                 after_cit_hit => 'FILL',
                 before_text_hit => "",
                 before_note => ' (',
                 after_note => ') ',
               } );

sub interleave_citations
{
    my $self = shift;
    my $buf = shift;
    $$buf =~ s/\n$//;
#     print STDERR $$buf;
    my @cites;
    push @cites, $self->build_citation('first');
    for ($i = 0; $i <= length $$buf; $i++ ) 
    {
        $code = ord (substr ($$buf, $i, 1));
        next unless ($code >> 7); # high bit set
        $self->parse_non_ascii ($buf, \$i);
        my $cit = $self->build_citation;
        # print STDERR "]]$cit\n";
        # print STDERR "]]".substr ($$buf, $i, 10)."\n";
        push @cites, $cit;
    }
    # Just eliminate the last citation, as it tends to cause problems
    my $last = pop @cites;
    push @cites, $self->build_citation('last');
    push @cites, $cite_info{$self->{output_format}}{after_text};

    return \@cites;
}

sub build_citation
{
    my $self = shift;
    my $pos = shift || '';
    my $format = $self->{output_format};
    my $cit = $self->maybe_use_cit;
    my $note = $self->{special_note};
    if ($note) {
        $self->format_output(\$note, 'l');
        $note = $cite_info{$format}{before_note} . $note . $cite_info{$format}{after_note};
    }
    else {
        $note = '';
    }
    if ($pos eq 'last')
    {
        return $cite_info{$format}{after_text} . $cite_info{$format}{before_text}; 
    }
    my $output = '';
    unless ($pos eq 'first')
    {
        $output .=
            $cite_info{$format}{after_text} 
    }

    $output .= $note;
    if ($cit and $self->{target_citation} and $cit eq $self->{target_citation})
    {
        if ($cite_info{$format}{after_cit_hit} eq 'FILL') {
            $output .=
                $cite_info{$format}{before_cit_hit} .
                $cit .
                ' ' x ($fill_spaces - length $cit).
                $cite_info{$format}{before_text_hit};
        } else {
            $output .=
                $cite_info{$format}{before_cit_hit} .
                $cit .
                $cite_info{$format}{after_cit_hit}.
                $cite_info{$format}{before_text_hit};
        }
    }
    elsif ($cit)
    {
        if ($cite_info{$format}{after_cit} eq 'FILL') {
            $output .=
                $cite_info{$format}{before_cit} .
                $cit .
                ' ' x ($fill_spaces - length $cit).
                $cite_info{$format}{before_text_with_cit}; 
        } else {
            $output .=
                $cite_info{$format}{before_cit} .
                $cit .
                $cite_info{$format}{after_cit}.
                $cite_info{$format}{before_text_with_cit};
        }
    }
    else
    {
        $output .=
            $cite_info{$format}{before_text}; 
    }
    return $output;
}


sub maybe_use_cit
{
    my $self = shift;
    my $cit = $self->get_citation;
    my ($higher, $line);
    if ($cit =~ m/^(.*)\.(\d+)$/) {
        $higher = $1;
        $line = $2;
    } else {
        $higher = "";
        $line = "";
    }
    my $output = '';
    unless ($higher and $line) {
        # For works with only line numbers and no higher levels
        if ($cit =~ m/^(\d+)$/) {
            $line = $1;
        }
    }
    return '' unless $line;
    $self->{higher_levels} = $higher unless $self->{higher_levels};
#     print STDERR "($higher)\n";
#     print STDERR "+--$higher +++ $line\n";
    if ($self->{work_num} != $self->{current_work})
    {
        $self->{current_work} = $self->{work_num};
        $output = $work{$self->{type}}{$self->{auth_num}}{$self->{work_num}} . ' ';
    }
    if ($output or ($self->{higher_levels} and $higher ne $self->{higher_levels}))
    {
        $self->{higher_levels} = $higher;
        $output .= $higher . '.' . $line;
    }
    elsif ($line % $self->{line_print_modulus} == 0
           or
           $cit and $self->{target_citation} and $cit eq $self->{target_citation}
           or
           $self->{last_line} and $line != $self->{last_line} + 1 )
    {
         # use this to just print the line number; but it looks a bit odd in prose 
#         $output .= $line;
        $output .=  $higher ? $higher . '.' . $line : $line;
    }

    $self->{last_line} = $line;

    return $output;
}

sub browse_half_backward
{
    # The first time the browser is called, we usually want to move
    # half a page backward.
    my $self = shift;
    my @args = @_;
    my $lines = $self->{browse_lines};
    $self->{browse_lines} = $lines/2 - 2;
    $self->{browse_backwards_scan} = 1;
    my @location = $self->browse_backward(@args);
    my @a = ($location[0], -1, $args[2], $args[3]);
    print STDERR join '--', @a if $self->{debug};
    $self->{browse_lines} = $lines;
    $self->{browse_end} = -1;
    return $self->browse_forward(@a);
}

    
# Method to print out the lines immediately preceding the previously
# specified point in our work.  With browse_backwards_scan, just scan
# backwards and do not print anything.

sub browse_backward 
{
    my $self = shift;
    my ($abs_begin, $abs_end, $auth, $work);
    my ($ref, $begin, $end, $line, $result, $buf, $offset);
    
    if (ref $self eq 'Diogenes::Browser')
    {   # Get persistent browser info from object
        $ref = $self->{browse_buf_ref};
        $end = $self->{browse_begin};
        $self->{browse_end} = $end;
        $offset = 0;
    }
    elsif (ref $self eq 'Diogenes::Browser::Stateless')
    {       # Browser info is passed as arguments
        ($abs_begin, $abs_end, $auth, $work) = @_;
        $auth = 1 if  $self->{type} eq 'bib' and $auth =~ m/9999/;
        
        $end = $abs_begin;
        $self->{current_work} = $work;
        $self->parse_idt ($auth);
        $self->{browse_auth} = $auth;
        $self->{browse_work} = $work;
        
        # open the file and seek to the beginning of the first block containing
        # our start-point
        open INP, "$self->{cdrom_dir}$self->{file_prefix}$auth$self->{txt_suffix}" or
            $self->barf("Couldn't open $self->{file_prefix}$auth$self->{txt_suffix}");
        binmode INP;
        
        my $end_block = $end >> 13;
        # read four 8k blocks -- should be enough!
        my $blocks = 4;
        my $start_block = $end_block - $blocks + 1;
        $start_block = 0 if $start_block < 0;
        $offset = $start_block  << 13;
        seek INP, $offset, 0;

        my $amount = 8192 * $blocks;
        read INP, $buf, $amount or 
            die "Could not read from file $self->{file_prefix}$auth.txt!\n" ;
        
        close INP or die "Couldn't close $self->{file_prefix}$auth.txt";
        $ref = \$buf;
        $self->{browse_end} = $end;
        $end = $end - $offset;
    }
    else
    { 
        die "What is ".ref $self."?\n";
    }
    
    $begin = $end;

    # Seek to beginning of any preceding  non-ascii block
    while (ord (substr ($$ref, --$begin, 1)) >> 7)  { };
        
    # find the right length of chunk
  CHUNK:
    for ($line = 0; 
         ($line <= $self->{browse_lines}) and ($begin > 0);
         $begin--) 
    {
        next if (ord (substr ($$ref, $begin, 1)) == 0);
        $line++ if ((ord (substr ($$ref, $begin, 1)) >> 7) and not
                    (ord (substr ($$ref, $begin - 1, 1)) >> 7)) ; 
        # for papyri, etc. get only one document at a time
        if ($self->{documentary} and ord (substr ($$ref, $begin, 1)) >= hex 'd0'
            and ord (substr ($$ref, $begin, 1)) <= hex 'df'
            and not ord (substr ($$ref, $begin - 1, 1)) >> 7)
        {       # Seek to end of non-ascii block beginning with \xd0 -- \xdf
            while (ord (substr ($$ref, $begin, 1)) >> 7)    { $begin++ };
            $begin--;
            last CHUNK;
        }
    }

    while (ord (substr ($$ref, ++$begin, 1)) >> 7)  { };

    $self->{browse_begin} = $offset + $begin;
    print STDERR "Beginning: $begin\n" if $self->{debug}; 
    return ($self->{browse_begin}, $self->{browse_end}) if $self->{browse_backwards_scan};
    
    my ($start_point, $end_point) = ($begin, $end);
    $result = substr ($$ref, $start_point, ($end_point - $start_point));
    my $base = ($self->{current_lang} eq 'g')
        ? '$'
        : '&';
    $result = $base . $result ;
    
    if ($self->print_location ($start_point + 1, $ref))
    {
        $self->{interleave_printing} = $self->interleave_citations(\$result);
        $self->print_output (\$result);
    }
    else
    {
        my @beginning = (0) x $self->{target_levels};
        my $ret = $self->seek_passage ($self->{browse_auth}, $self->{browse_work}, @beginning);
        if ($ret eq 'fail') {
            print "Passage not found!\n";
            return(0,0);
        }
        else {
            $self->browse_forward;
        }
    }
    # Store and pass back the start and end points of the whole session
    return ($self->{browse_begin}, $self->{browse_end});  # $abs_begin and $abs_end
}

#############################################
#-------------------------------------------#
#------------CGI File Browser---------------#
#-------------------------------------------#
#############################################

# As above, except with CGI scripts we have to re-read the text, since
# we don't want to hold it in memory between invocations.

package Diogenes::Browser::Stateless;
@Diogenes::Browser::Stateless::ISA = qw( Diogenes::Browser );

# Everything is delegated to the parent -- browse_forward and
# browse_backward work somewhat differently and expect arguments

1;
