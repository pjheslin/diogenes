#!/usr/bin/env perl

##########################################################################
#                                                                        #
# Diogenes is a set of programs including this CGI script which provides #
# a graphical interface to the CD-Rom databases published by the         #
# Thesaurus Linguae Graecae and the Packard Humanities Institute.        #
#                                                                        #
# Copyright P.J. Heslin 1999 - 2005.                                     #
# Diogenes comes with ABSOLUTELY NO WARRANTY;                            #
# for details see the file named COPYING.                                #
#                                                                        #
##########################################################################

# This is a slightly odd module, in that it has been lightly converted
# from a CGI script (which was once written to run under mod_perl,
# hence the use of lexical vars everywhere to hold coderefs).  The
# entry point is the single exception, go().

# We start with compile-time declarations

package Diogenes::Script;
use strict;
use warnings;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use lib ($Bin, catdir($Bin, '..', 'dependencies', 'CPAN') );
use Data::Dumper;
use Diogenes::Base qw(%encoding %context @contexts %choices %work %author %database @databases @filters);
use Diogenes::Search;
use Diogenes::Indexed;
use Diogenes::Browser;
use Encode;
use CGI qw(:standard :utf8);
use JSON::Tiny qw(from_json to_json);
use utf8;
binmode STDERR, ":raw";


BEGIN {
   if ( $Diogenes::Base::OS eq 'windows' ) {
      eval "use Win32::ShellQuote qw(quote_native); 1" or die $@;
   }
}

# These are lexical vars shared between the subroutines below.  Many
# are config-dependent.  They are initialised at run-time in
# $setup->().

my ($f, $init, $filter_file, $default_encoding, $default_choice,
    $default_criteria, $filter_flag, $charset);

# These are lexical constants whose values are fixed.

my @choices = (
    'TLG Texts',
    'PHI Latin Corpus',
    'Duke Documentary Papyri',
    'Classical Inscriptions',
    'Christian Inscriptions',
    'Miscellaneous PHI Texts',
    'PHI Coptic Texts',
    'TLG Bibliography',
    );
# Probable input language for morphological search
my %prob_lang = ( 'phi' => 'lat',
                  'tlg' => 'grk',
                  'ddp' => 'grk',
                  'ins' => 'grk',
                  'chr' => 'grk',
                  'misc' => 'lat' );
my $picture_dir = 'images/';
my $version = $Diogenes::Base::Version;

# Containers for coderefs
my (%handler, %output);

# Preserving state: all previous parameters are embedded as hidden
# fields in each subsequent page.  Remember that this sets up a single
# namespace for all cgi parameters on all pages of the script, so be
# careful not to duplicate parameter names from page to page.
my %st;
my $previous_page;

my $set_state = sub
{
    for (keys %st)
    {
        print $f->hidden( -name => $_.'XXstate',
                          -default => $st{$_},
                          -override => 1 );
    }
};

# Put cgi parameters into %st, putting multi-valued params into array
# refs.  Some lists should always be lists, however, even single-valued.

# If a named param is hidden (previous state) it should not override
# any unhidden parameter of the same name.  If we have come back to
# the same page, we want the new value, not the old one or a list of
# both.  So old state params have XXstate appended to them.  This
# allows us to avoid restoring the state of params which have new,
# real values for this submission.

my $get_state = sub
{
    # Make sure to clear state (esp. in non-forking server)
    %st = ();

    my @params = $f->param();
    my %real_params;
    /XXstate$/ || $real_params{$_}++ for @params;

    for my $p ( @params )
    {
        my $r = $p;
        $r =~ s/XXstate$//;
        next if $p =~ m/XXstate$/ and exists $real_params{$r};
        my @tmp = $f->param($p);
        if ($init->{input_encoding} eq 'Unicode') {
            @tmp = map {Encode::decode(utf8=>$_) } @tmp;
        }
        if ( scalar @tmp == 1 and not $r =~ /_list/)
        {
            $st{$r} = $tmp[0];
        }
        else
        {
            $st{$r} = [ @tmp ];
        }
    }
    # These are filter names that have been typed in by the user on
    # the pages that define filters, as opposed to being selected from
    # a list.  So they need to be treated differently and have to be
    # tagged as utf8 in order to save correctly on disk.

    # This is the only place where (unavoidably) we pass a utf8 custom
    # filter name as a cgi parameter.  Everywhere else we use a
    # numerical index from the list of custom filters to avoid
    # encoding nightmares.

    utf8::encode($st{saved_filter_name}) if $st{saved_filter_name};
    utf8::encode($st{duplicate_filter_name}) if $st{duplicate_filter_name};
};

my $read_filters = sub {
    if (-e $filter_file)
    {
        open(my $filter_fh,'<:raw', $filter_file)
            or die "Can't read from filter file ($filter_file): $!";
        local $/ = undef;
        my $contents = <$filter_fh>;
        close $filter_fh or die "Can't close filter file ($filter_file): $!";

        if ($contents =~ m/^\@filters =/) {
            # Legacy code to eval old-style Data Dumper file, which
            # simply cannot deal reliably with Unicode data
            eval $contents;
            warn "Error reading in saved corpora: $@" if $@;
        }
        elsif ($contents) {
            @filters = @{ from_json $contents };
            #print STDERR 'Filter: ', %{ $_ }, "\n" for @filters;
        }
    }
};

my $check_chunking = sub {
    my $retval = shift;
    if ($retval eq 'done') {
        print $f->center($f->h2('Search finished'));
        return;
    }
    # In case we have already searched through the last author on the list
    # NB. This does not yet take unfiltered word-list searches into account.
    my $q = shift;
    my @seen = sort @{ $q->{seen_author_list} };
    my @auths = sort (keys %{ $q->{req_authors} }, keys %{ $q->{req_auth_wk} }, );
    if ($q->{filtered} and @auths == @seen and "@auths" eq "@seen") {
        my $whom = 'all authors';
        $whom = 'author' if @auths == 1;
        print $f->center($f->h2("Finished searching $whom"));
        return;
    }

    # Save the cumulative list of authors printed so far
    $st{seen_author_list} = $q->{seen_author_list};
    $st{hits} = $q->{hits};

    print $f->center($f->h2('Page limit reached'),
                    $f->p($f->submit( -name=>'next_chunk',
                                    -Value=>'Load next page of search results')));
};

my $my_footer = sub
{
    $set_state->();

    # Close Perseus main div
    print '</div>';

    print $f->end_form,
        '<div class="push"></div></div>'; # sticky footer
    print
        $f->p({class => 'footer'}, qq{Diogenes (version $version) is free software, &copy; 1999-2019 Peter Heslin.});

    print $f->end_html;
};

my $numerically = sub { $a <=> $b; };

my $print_title = sub
{
    print $f->header(-type=>"text/html; charset=$charset");
    my $title = shift;
    my $extra_script = shift;
    my $script;
    if ($extra_script) {
        $script = [{-type=>'text/javascript',
                    -src=>'diogenes-cgi.js'},
                   {-type=>'text/javascript',
                    -src=>$extra_script}];
    }
    else {
        $script = {-type=>'text/javascript',
                   -src=>'diogenes-cgi.js'};
    }
    my $user_css = '';
    for my $file (qw(config.css user.css)) {
        my $css_file = File::Spec->catfile($Diogenes::Base::config_dir, $file);
        if (-e $css_file) {
            open my $css_fh, '<', $css_file or die $!;
            local $/ = undef;
            $user_css .= <$css_fh>;
            $user_css .= "\n";
        }
    }
    print
        $f->start_html(-title=>$title,
                       -encoding=>$charset,
                       -script=>$script,
                       -style=>{ -type=>'text/css',
                                 -src=>'diogenes.css',
                                 -verbatim=>$user_css},
                       -meta=>{'content' => 'text/html;charset=utf-8'},
                       -class=>'waiting'),
    '<div class="wrapper">', # for sticky footer and side padding
    $f->start_form(-name=>'form', -id=>'form', -method=> 'get');
    # We put this here (other hidden fields are at the end), so that
    # Javascript can use it for jumpTo even before the page has
    # completely loaded.  JumpFrom is a place to hold Perseus query
    # params, in case they are needed later.
    print $f->hidden( -name => 'JumpToFromPerseus',
                      -default => "",
                      -override => 1 );
    print $f->hidden( -name => 'JumpFromQuery',
                      -default => "",
                      -override => 0 );
    print $f->hidden( -name => 'JumpFromLang',
                      -default => "",
                      -override => 0 );
    print $f->hidden( -name => 'JumpFromAction',
                      -default => "",
                      -override => 0 );

    # for Perseus data
    print qq{<div id="sidebar" class="sidebar-$init->{perseus_show}"></div>};
    print '<div id="main_window" class="main-full">';
};

my $print_header = sub
{
    print q{<div class="header_back"><a onclick="window.history.back()" class="back_button">
    <svg width="15px" height="20px" viewBox="0 0 50 80" xml:space="preserve">
    <polyline fill="none" stroke="#28709a" stroke-width="6" stroke-linecap="round" stroke-linejoin="round" points="
        45,80 0,40 45,0"/></svg><div class="back_button_text">Back</div></a></div>};

    # Provide facility to restore an earlier Perseus query, but make invisible to start.
    print qq{<div class="invisible" id="header_restore"><a onclick="jumpFrom()"><span class="restore_text">Restore</span><img id="splitscreen" src="${picture_dir}view-restore.png" srcset="${picture_dir}view-restore.hidpi.png 2x" alt="Split Screen" /></a></div>};

    print qq(
        <div class="header_logo">
        <a id="logo" href="Diogenes.cgi" title="New Diogenes Search">
        <img src="${picture_dir}Diogenes_Logo_Small.png" alt="Logo"
        srcset="${picture_dir}Diogenes_Logo_Small.hidpi.png 2x"
        height="38" width="109" /></a>
       </div>);
};

my $print_error_page = sub
{
    my $msg = shift;
    $msg ||= 'Sorry. You seem to have made a request that I do not understand.';

    $print_title->('Diogenes Error Page');
    $print_header->();

    print $f->center(
        $f->h1('ERROR'),
        $f->p($msg));

    print $f->end_html;
};

my $print_error = sub
{
    my $msg = shift;
    $msg ||= 'Sorry. You seem to have made a request that I do not understand.';

    print $f->center(
        $f->h1('ERROR'),
        $f->p($msg));

    print $f->end_html;
};

my $strip_html = sub
{
    my $ref = shift;
    $$ref =~ s#<[^>]*>##g;
    $$ref =~ s#&amp;#&#g;
    $$ref =~ s#&lt;#<#g;
    $$ref =~ s#&gt;#>#g;
    $$ref =~ s#&quot;#"#g;
    $$ref =~ s#&nbsp;# #g;
    $$ref =~ s/&#14[78];/"/g;
    $$ref =~ s/&#x?[0-9a-fA-F]+;/ /g;
};

my $database_error = sub
{
    my $self = shift;
    my $disk_type = $st{short_type};
    if ($disk_type eq 'cop' or $disk_type eq 'ins' or $disk_type eq 'chr') {
        $disk_type = 'ddp';
    }
    elsif ($disk_type eq 'misc') {
        $disk_type = 'phi';
    }
    elsif ($disk_type eq 'bib') {
        $disk_type = 'tlg';
    }
    $print_title->('Database Error');
    $print_header->();
    print qq(<center>
               <div style="display: block; width: 50%;">
                 <h2 id="database-error">Error: Database not found</h2>
                 <p>The <b>$disk_type</b> database was not found.  Diogenes does not come with databases of texts; these must be acquired separately.</p>
                 <p>To tell Diogenes where on your computer the text are located, go to File -> Database Locations in the menu.</p>
               </div>
             </center>
                );

    $st{current_page} = 'splash';
    $my_footer->();
};

my $print_navbar = sub {
    print q{
  <div class="navbar-area">
    <nav role="navigation">
      <ul class="menu">
        <li><a href="#" onclick="info('browse')" onfocus="dropup('submenu1'); dropup('submenu2')" accesskey="r">Read</a></li>
        <li onmouseover="dropdown('submenu1')" onmouseout="dropup('submenu1')"><a href="#" onfocus="dropdown('submenu1');dropup('submenu2')">Search</a>
          <ul id="submenu1">
            <li><a href="#" onclick="info('search')" accesskey="s">Simple</a></li>
            <li><a href="#" onclick="info('author')" accesskey="a">Within an Author</a></li>
            <li><a href="#" onclick="info('multiple')" accesskey="m">Multiple Terms</a></li>
            <li><a href="#" onclick="info('lemma')" accesskey="f">Inflected Forms</a></li>
            <li><a href="#" onclick="info('word_list')" accesskey="w">Word List</a></li>
          </ul>
        </li>
        <li onmouseover="dropdown('submenu2')" onmouseout="dropup('submenu2')"><a href="#"  onfocus="dropdown('submenu2');dropup('submenu1')">Lookup</a>
          <ul id="submenu2">
            <li><a href="#" onclick="info('lookup')" accesskey="l">Lexicon</a></li>
            <li><a href="#" onclick="info('parse')" accesskey="i">Inflexion</a></li>
            <li><a href="#" onclick="info('headwords')" accesskey="h">Headwords</a></li>
          </ul>
        </li>
        <li><a href="#" onclick="info('filters')" onfocus="dropup('submenu1'); dropup('submenu2')" accesskey="f">Filter</a></li>
        <li><a href="#" onclick="info('export')" accesskey="e">Export</a></li>
        <li><a href="#" onclick="info('help')">Help</a></li>
      </ul>
    </nav>
  </div>
    };
};

### Splash page

$output{splash} = sub
{
    my @filter_names;
    push @filter_names, $_->{name} for @filters;

    $print_title->('Diogenes', 'splash.js');
    $st{current_page} = 'splash';

    print '<input type="hidden" name="action" id="action" value=""/>';
    print '<input type="hidden" name="splash" id="splash" value="true"/>';
    print '<input type="hidden" name="export-path" id="export-path" value=""/>';
    print "\n";
    print '<div id="corpora-list1">';
    foreach (@choices) {
        print qq{<option value="$_">$_</option>};
    }
    print '</div>';
    print '<div id="corpora-list2">';
    my $i = 0;
    foreach (@filter_names) {
        print qq{<option value="$i">$_</option>};
        $i++;
    }
    print '</div>';
    print "\n";
    print $f->div(
        {-class=>'header_logo'},
        $f->img({-src=>$picture_dir.'Diogenes_Logo.png',
                     -srcset=>$picture_dir.'Diogenes_Logo.hidpi.png 2x',
                     -alt=>'Diogenes',
                     -onClick=>'sessionStorage.removeItem("action");location.reload();',
                     -height=>'104',
                     -width=>'374'}));
    $print_navbar->();
    print "\n";
    print $f->div({-class=>'info-area', -id=>'info'},
                  $f->p({class => "homewelcome"},
                   q{Welcome to Diogenes, a tool for reading and searching through legacy databases of ancient texts.}));
    print "\n";
    $my_footer->();
};

### Splash handler

$handler{splash} = sub
{
    my $corpus = $st{corpus};
    my $action = $st{action};

    if ($action eq 'browse') {
        $st{query} = $st{author}
    }
    if (defined $corpus and $choices{$corpus})
    {
        # One of the built-in corpora
        # Convert to abbreviated form
        $st{short_type} = $choices{$corpus};
        $st{type} = $corpus;
    }
    elsif (defined $corpus and $corpus =~ m/^\d+$/)
    {
        # Custom corpora are selected by number (an index into the
        # list of filters), so that we do not have to worry about
        # encoding/decoding issues arising from passing utf8 filter
        # names back and forth.

        $st{custom_corpus} = $corpus;
        $st{short_type} = $filters[$corpus]->{type};
        $st{type} = $st{short_type};
#        print STDERR "Custom: $st{custom_corpus} $st{short_type}\n";
    }
    elsif (defined $corpus) {
        print STDERR "Error: $corpus is not built-in and is not a number.\n";
        $print_title->('Error');
        $print_header->();
        print $f->center($f->p($f->strong('Error.')),
                         $f->p("Error: Custom corpus filter not found for choice $corpus!\n"));
    }
 
    if ((not $st{query}) and $action eq 'search')
    {
        $print_title->('Error');
        $print_header->();
        print $f->center($f->p($f->strong('Error.')),
                         $f->p('You must specify a search pattern.'));
    }
    elsif ($action eq 'filters')
    {
        $output{filter_splash}->();
    }
    elsif ($action eq 'lemma')
    {
        $output{lemma}->();
    }
    elsif ($action eq 'lookup' or $action eq 'parse')
    {
        $print_error_page->('Request for Perseus lookup should not get through to Diognenes.cgi');
#        $output{lookup}->($action);
    }
    elsif ($action eq 'search')
    {
        $output{search}->();
    }
    elsif ($action eq 'multiple')
    {
        $output{multiple}->();
    }
    elsif ($action eq 'word_list')
    {
        $st{short_type} = 'tlg';
        $st{type} = 'TLG Word List';
        $output{indexed_search}->();
    }
    elsif ($action eq 'browse')
    {
        $output{browser}->();
    }
    elsif ($action eq 'author')
    {
        $output{author_search}->();
    }
    elsif ($action eq 'export')
    {
        $output{export_xml}->();
    }
    elsif ($action eq 'headwords')
    {
        $output{headwords}->();
    }
    else
    {
        $print_title->('Error');
        $print_header->();
        print $f->center($f->p($f->strong('Flow Error.')));
    }

};

$output{multiple} = sub
{
    $print_title->('Diogenes Multiple Search Page');
    $print_header->();
    $st{current_page} = 'multiple';

    my $new_pattern = $st{query};

    print '<div style="margin-left: auto; margin-right: auto; width: 50%">';
    print
        $f->h1('Multiple Patterns'),
        $f->p( 'Use this page to search for multiple words or phrases
         within a particular scope');

    my @patterns = ();
    @patterns = @{ $st{query_list} } if $st{query_list};
    push @patterns, $new_pattern if $new_pattern;
    $st{query_list} = \@patterns;

    if (@patterns)
    {
        print
            $f->h2('Patterns Entered:'),
            $f->p('Here is a list of the patterns you have entered thus far:');
        print '<p><ol>';
        print "<li>$_</li>\n" foreach @patterns;
        print '</ol></p>';
    }

    print
        $f->h2('Add a Pattern'),
        $f->p('You may add a' . (@patterns ? 'nother' : '') . ' pattern:'),
            $f->p(
                $f->textfield(-name=>'query', -size=>40, -default=>'',
                              -override=>1)),
            $f->p(
                $f->submit(-name=>'Add_Pattern',
                           -value=>'Add this pattern to the list'));

    # In case we allow repetition, we want to permit a higher number
    # of matches than just the number of patterns
    my $max_matches = 5 + $#patterns;
    my @matches = ('any', 2 .. $max_matches, 'all');

    print
        $f->hr(),
        $f->h1('Search Options'),
        $f->h2('Scope'),
        $f->p( 'Define the scope within which these patterns are to
    be found together.  The number of lines is an exact measure,
    whereas the others depend on punctuation, which is guesswork.'),
        $f->popup_menu( -name => 'context',
                        -Values => \@contexts,
                        -Default => 'sentence');

    print
        $f->h2('Quantity'),
        $f->p('Define the minimum number of times these patterns must match ',
              'within a given scope in order to qualify as a successful ',
              'hit.'),
        $f->popup_menu( -name => 'min_matches',
                        -Values => \@matches,
                        -Default => 'all');

    print
        $f->h2('Reject pattern'),
        $f->p('Optionally, if there is a word or phrase whose presence in a given ',
              'context should cause a match to be rejected, specify it here.'),
        $f->textfield( -name => 'reject_pattern',
                       -size => 50,
                       -default => '');
    print
        $f->h2('Permit repetition'),

        $f->p('Tick to permit a pattern that matches more than once in a passage to 
              count multiple times toward the quantity of successful matches set above. ',
              'E.g. to search for the repetition of a word or pattern, enter one pattern, 
              enter the minimum number of times it needs to appear, and tick this box.'),
        $f->checkbox(-name=>'repeat_matches',
                                  -checked=>0,
                                  -value=>1,
                                  -label=>'Count repeating matches');
    print
        $f->p('&nbsp;'),
        $f->center(
            $f->p(
                $f->submit( -name =>'do_search',
                            -value=>'Do Search')));

    print '</div>';
    $my_footer->();
};

$handler{multiple} = sub
{
#     push @{ $st{query_list} }, $st{query};

    if ($st{do_search})
    {
        $output{search}->();
    }
    else
    {
        $output{multiple}->();
    }
};

my $get_args = sub
{
    my %args = (
        type => $st{short_type},
        output_format => 'html',
        highlight => 1,
        );

    # These don't matter for indexed searches
    if (exists $st{query_list})
    {
        $args{pattern_list} = $st{query_list};
    }
    else
    {
        $args{pattern} = $st{query};
    }

    for my $arg (qw(context min_matches reject_pattern repeat_matches seen_author_list hits))
    {
        $args{$arg} = $st{$arg} if $st{$arg};
    }
    $args{context} = '2 lines' if $st{type} =~ m/inscriptions|papyri/i
                               and not exists $st{context};

    $args{encoding} = $st{greek_output_format} || $default_encoding;

    return %args;
};

$output{export_xml} = sub {

    $print_title->('Diogenes XML Export Page');
    $print_header->();
    $st{current_page} = 'export';
    my %args = $get_args->();
    $args{type} = $st{short_type};
    my $q = new Diogenes::Search(%args);
    $database_error->($q) if not $q->check_db;

    my @auths;

    if ($st{author} and $st{author} =~ m/\S/) {
        @auths = sort keys %{ $q->match_authtab($st{author}) };
        unless (scalar @auths)
        {
            $print_error->(qq(There were no texts matching the author $st{author}));
            return;
        }
    }
    elsif ($st{custom_corpus}) {
        my $filter_number = $st{custom_corpus};
        my $filter = $filters[$filter_number];
        if (ref $filter->{authors} eq 'ARRAY') {
            @auths = sort @{ $filter->{authors} };
        }
        elsif (ref $filter->{authors} eq 'HASH') {
            @auths = sort keys %{ $filter->{authors} };
        }
        else {
            $print_error->("ERROR in filter definition.")
        }
    }

    my $export_path = $st{'export-path'};
    print $f->h2('Exporting texts as XML'),
        $f->p("This can take a while. Go to menu item Navigate -> Stop/Kill to interrupt conversion. Export folder: $export_path"),
        $f->hr;

    # TODO: Should have just used $^X
    my $perl_name;
    if ($Diogenes::Base::OS eq 'windows') {
        $perl_name = File::Spec->catfile($Bin, '..', 'strawberry', 'perl', 'bin', 'perl.exe');
    }
    else {
        # For Mac and Unix, we assume perl is in the path
        $perl_name = 'perl';
    }
    my @cmd;
    push @cmd, $perl_name;
    push @cmd, File::Spec->catfile($Bin, 'xml-export.pl');
    # LibXML does not work under Strawberry Perl
    push @cmd, '-x' if $Diogenes::Base::OS eq 'windows';
    push @cmd, '-c';
    push @cmd, $st{short_type};
    push @cmd, '-o';
    push @cmd, $export_path;
    if (@auths) {
        my $n = join ',', @auths;
        push @cmd, '-n';
        push @cmd, $n;
    }
    my ($command, $fh);
    if ($Diogenes::Base::OS eq 'windows') {
        $command = quote_native(@cmd);
        open ($fh, '-|', $command) or die "Cannot exec $command: $!";
    }
    else {
        open ($fh, '-|', @cmd) or die "Cannot exec: "
            . (join ' ', @cmd) . ": $!";
    }
    # print $f->p("Command: $command \n");
    $fh->autoflush(1);
    print '<pre>';
    {
        local $/ = "\n";
        print $_ while (<$fh>);
    }
    print $f->h3('Finished XML conversion.');
    print '</pre>';
};

$output{author_search} = sub
{
    # A quick and dirty author search
    $print_title->('Diogenes Author Search Page');
    $print_header->();
    $st{current_page} = 'author_search';

    my %args = $get_args->();
    $args{type} = $choices{$st{corpus}};
    my $q = new Diogenes::Search(%args);
    $database_error->($q) if not $q->check_db;
    my @auths = $q->select_authors(author_regex => $st{author});
    unless (scalar @auths)
    {
        $print_error->(qq(There were no texts matching the author $st{author_pattern}));
        return;
    }

    print $f->h2('Searching in the following authors'),
        $f->ul($f->li(\@auths)),
        $f->hr;

    my $retval = $q->do_search;
    if ($q->{server_error}) {
        $print_error_page->($q->{server_error});
        return;
    }

    $check_chunking->($retval, $q);
    $my_footer->();
};

$handler{author_search} = sub
{
    # For chunking
    $output{author_search}->()
};


my $use_and_show_filter = sub
{
    my $q = shift;
    my $word_list_search = shift;
    my $filter_number = $st{custom_corpus};
    if (defined $filter_number) { 
        my $filter = $filters[$filter_number];
        if ($filter)
        {
            if ($word_list_search and $filter->{type} ne 'tlg') {
                $print_error->('You cannot perform a TLG word-index search on a user-defined subcorpus which is not part of the TLG!');
                $q->barf;
            }
            my $work_nums = $filter->{authors};
            my @texts = $q->select_authors( -author_nums => $work_nums);
            
            print $f->h2('Searching in the following authors/texts:'),
                $f->ul($f->li(\@texts)),
                $f->hr;
        }
    }
};

my $input_encoding = sub {
    my $word = shift;
    if ($word =~ m/^\p{InBasicLatin}+$/) {
        return ('lat', '')
    }
    else {
        return ('grk', 'Unicode')
    }
};

$output{lookup} = sub {
    my $action = shift;
    $print_title->('Diogenes Perseus Lookup Page');
    $print_header->();
    $st{current_page} = 'lookup';

    my $query = $st{query};
    my ($lang, $inp_enc) = $input_encoding->($query);
    $query =~ s/\s//g;
    if ($inp_enc eq 'Unicode') {
        $lang = ($query =~ m/^[\x01-\x7f]+$/) ? 'lat' : 'grk';
    }
    $lang = 'eng' if $query =~ s/^@//;
#     my $perseus_params = qq{do=$action&lang=$lang&q=$query&popup=1&noheader=1&inp_enc=$inp_enc};
    my $perseus_params = qq{do=$action&lang=$lang&q=$query&noheader=1&inp_enc=$inp_enc};
    print STDERR ">>X $perseus_params\n"  if $init->{debug};
    $Diogenes_Daemon::params = $perseus_params;
    eval { $Diogenes::Perseus::go->($perseus_params) };
    $my_footer->();

};


$output{lemma} = sub {
    $print_title->('Diogenes Lemma Search Page');
    $print_header->();
    $st{current_page} = 'lemma';
    my %args = $get_args->();
    my $q = new Diogenes::Base(%args);
    my ($lang, $inp_enc) = $input_encoding->($st{query});
    $st{lang} = $lang;
    my $perseus_params = qq{do=lemma&lang=$st{lang}&q=$st{query}&noheader=1&inp_enc=}.$inp_enc;
    print STDERR ">>XX $perseus_params\n" if $init->{debug};
    $Diogenes_Daemon::params = $perseus_params;
    eval { $Diogenes::Perseus::go->($perseus_params) };

    print
        $f->p(
            $f->button( -Value  =>"Select All",
                        -onClick=>"setAll()"),
            '&nbsp;&nbsp;&nbsp;&nbsp;',
            $f->reset( -value  =>'Deselect All')),
        $f->p('Select the lemmata above that interest you.'),

        $f->submit( -name => 'proceed',
                    -Value  =>'Show Inflected Forms');

    $my_footer->();

};

$handler{lemma} = sub {
    $output{lemmata}->();
};

$output{lemmata} = sub {
    unless ($st{lemma_list}) {
        $print_error_page->('No lemmata were chosen!');
        return;
    }
    $print_title->('Diogenes Lemma Choice Page');
    $print_header->();
    my $n = 0;
    $st{current_page} = 'inflections';
    my $lem_string = join "{}", @{ $st{lemma_list} };
    my $perseus_params = qq{do=inflects&lang=$st{lang}&q=$lem_string&noheader=1};
    $Diogenes_Daemon::params = $perseus_params;
    print STDERR ">>XXX $perseus_params\n" if $init->{debug};
    eval { $Diogenes::Perseus::go->($perseus_params) };

    delete $st{lemma_list};
    print
        $f->hr,
        $f->p('Show only forms matching this text (e.g. "aor opt" for only aorist optatives):',
              $f->br,
              $f->textfield(-name => 'form_filter',
                            -id => 'form_filter',
                            -default => '',
                            -size => 25),
              '&nbsp;<a onClick="formFilter();">Go</a>');

    print qq{<p><a onClick="selectVisible(true);">Select All Visible Forms</a><br>
<a onClick="selectVisible(false);">Unselect All Visible Forms</a></p>};


    print
        $f->p(
            $f->submit( -name => 'proceed',
                        -Value  =>'Search for selected forms'),
            qq{(Current corpus: $st{type})});

    $my_footer->();
};

$handler{inflections} = sub {
    unless ($st{lemma_list}) {
        $print_error_page->('No lemmata were chosen!');
        return;
    }
    $print_title->('Diogenes Morphological Search');
    $print_header->();
    $st{current_page} = 'inflections';
    if ($st{short_type} eq "tlg") {
        my %args = $get_args->();
        $args{use_tlgwlinx} = 1;
        my $q = new Diogenes::Indexed(%args);
        $database_error->($q) if not $q->check_db;
        $use_and_show_filter->($q);

        my %seen = ();
        for my $upcase (@{ $st{lemma_list} }) {
            $upcase =~ tr/a-z/A-Z/;
            unless ($seen{$upcase}) {
                my $bare = $upcase;
                $bare =~ s/[^A-Z]//g;
                $q->{input_raw} = 1;
                my ($ref, @wlist) = $q->read_index($bare);
                # Make sure we get back what we put in
                warn "Inflection $upcase is not in the word-list!\n" unless exists $ref->{$upcase};
                $seen{$_}++ for @wlist;
            }
        }
        # Since the morphological variants of a given lemma can look
        # very heterogeneous, it doesn't make sense to search for them
        # via one big regexp as would be the case for
        # $q->do_search($st{lemma_list}).  Instead we pass an array of
        # single-element arrays to treat each word as a separate
        # "word-set".
        my @word_sets;
        push @word_sets, [$_] for @{ $st{lemma_list} };
        my $retval = $q->do_search(@word_sets);
        $check_chunking->($retval, $q);
        $my_footer->();
    }
    else {
        # Simple searches
        delete $st{query};
        for my $form (@{ $st{lemma_list} }) {
            push @{ $st{query_list} }, " $form ";
        }
        my %args = $get_args->();
        $args{input_lang} = $st{lang};
        if ($prob_lang{$st{short_type}} eq "grk" or $st{lang} eq "grk") {
            $args{input_encoding} = 'BETA code';
        }
        my $q = new Diogenes::Search(%args);
        $database_error->($q) if not $q->check_db;
        $use_and_show_filter->($q);
        my $retval = $q->do_search();
        $check_chunking->($retval, $q);
        $my_footer->();
    }
};

$output{indexed_search} = sub
{
    my %args = $get_args->();
    my $q = new Diogenes::Indexed(%args);
    $database_error->($q) if not $q->check_db;

    $print_title->('Diogenes TLG word list result');
    $print_header->();
    $st{current_page} = 'word_list';
    my @params = $f->param;

    $use_and_show_filter->($q, 'true');

    my $pattern_list = $st{query_list} ? $st{query_list} : [$st{query}];
    print $f->p('Here are the entries in the TLG word list that match your ',
                $st{query_list} ? 'queries: ' : 'query: ');

    for my $pattern (@{ $pattern_list })
    {
        my ($wref, @wlist) = $q->read_index($pattern) if $pattern;

        if (not @wlist)
        {
            print $f->p(
                $f->strong('Error'),
                "Nothing maches $pattern in the TLG word list!");
            return;
        }

        my %labels;
        foreach my $word (@wlist)
        {
            $labels{$word} = $word;
            $q->encode_greek($default_encoding, \$labels{$word});
            $labels{$word} .= "&nbsp;($wref->{$word}) ";
        }
        $f->autoEscape(undef);
        print $f->checkbox_group( -name => "word_list",
                                  -Values => \@wlist,
                                  -labels => \%labels,
                                  -columns=>'3');

        $f->autoEscape(1) ;
        print $f->hr;
    }

    print
        $f->p(
            $f->button( -Value  =>"Select All",
                        -onClick=>"setAll()"),
            '&nbsp;&nbsp;&nbsp;&nbsp;',
            $f->reset( -value  =>'Deselect All')),
        $f->p('Select the forms above that interest you.'),

        $f->submit( -name => 'search',
                    -Value  =>'Do Search');
    $my_footer->();
};

$handler{word_list} = sub
{
    $output{search}->()
};

$output{search} = sub
{
    if ($st{type} =~ m/TLG Word List/ and not $st{word_list})
    {
        $output{indexed_search}->();
        return;
    }

    $st{current_page} = 'doing_search';

    my %args = $get_args->();

    my $q;
    if ($st{type} =~ m/TLG Word List/)
    {
        $q = new Diogenes::Indexed(%args);
    }
    else
    {
        $q = new Diogenes::Search( %args );
    }
    $database_error->($q) if not $q->check_db;

    $print_title->('Diogenes Search');
    $print_header->();

    $use_and_show_filter->($q);

    if ($st{type} =~ m/TLG Word List/)
    {
        my $patterns = $st{query_list} ? $st{query_list} : [$st{query}];
        $q->read_index($_) for @{ $patterns };
        my $retval = $q->do_search($st{word_list});
        $check_chunking->($retval, $q);
    }
    else
    {
        my $retval = $q->do_search;
        $check_chunking->($retval, $q);
    }
    if ($q->{server_error}) {
        $print_error_page->($q->{server_error});
        return;
    }

    $my_footer->();

};

$handler{doing_search} = sub
{
    # For chunking
    $output{search}->()
};

$output{browser} = sub
{
    my %args = $get_args->();
    my $q = new Diogenes::Browser::Stateless(%args);
    $database_error->($q) if not $q->check_db;

    my %auths = $q->browse_authors($st{query});
    if ($q->{server_error}) {
        $print_error_page->($q->{server_error});
        return;
    }
    # Because they are going into form elements, and most browsers
    # do not allow HTML there.
    $strip_html->(\$_) for values %auths;

    # Skip ahead if there is only one match
    if (keys %auths == 1)
    {
        my $auth = (keys %auths)[0];
        $st{author} = [keys %auths]->[0];
        $output{browser_works}->();
        return;
    }

    my $author_sort = sub
    {
        my ($a, $b) = @_;
        $a =~ tr/a-zA-Z0-9//cd;
        $b =~ tr/a-zA-Z0-9//cd;
        return (uc $a cmp uc $b);
    };


    $print_title->('Diogenes Author Browser');
    $print_header->();
    $st{current_page} = 'browser_authors';

    if (keys %auths == 0)
    {
        print
            $f->p($f->strong('Sorry, no matching author names')),
            $f->p(
                'To browse texts, enter part of the name of the author ',
                'or corpus you wish to examine.'),
            $f->p('To get a list of all authors, simply leave the text area blank.');
    }
    else
    {
        my $size = keys %auths;
        $size = 20 if $size > 20;
        print
            $f->center(
                $f->p( 'Here is a list of authors corresponding to your request.'),
                $f->p( 'Please select one and click on the button below.'),
                $f->p(
                    $f->scrolling_list( -name => 'author',
                                        -Values => [sort {$author_sort->($auths{$a}, $auths{$b})} keys %auths],
#                                         -Values => [sort $numerically keys %auths],
                                        -labels => \%auths, -size=>$size,
                                        -autofocus => 'autofocus',
                                        -required => 'required'
                                      )),
                $f->p(
                    $f->submit(-name=>'submit',
                               -value=>'Show works by this author')));
    }

    $my_footer->();

};

$handler{browser_authors} = sub { $output{browser_works}->(); };

$output{browser_works} = sub
{
    my %args = $get_args->();
    my $q = new Diogenes::Browser::Stateless(%args);
    $database_error->($q) if not $q->check_db;

    my %auths = $q->browse_authors( $st{author} );
    my %works = $q->browse_works( $st{author} );
    if ($q->{server_error}) {
        $print_error_page->($q->{server_error});
        return;
    }
    $strip_html->(\$_) for (values %works, keys %works);

    # Skip ahead if there is just one work
    if (keys %works == 1)
    {
        my $work = (keys %works)[0];
        $st{work} = $work;
        $output{browser_passage}->();
    }

    $print_title->('Diogenes Work Browser');
    $print_header->();
    $st{current_page} = 'browser_works';


    if (keys %works == 0)
    {
        print $f->p($f->strong('Sorry, no matching names'));
    }
    else
    {
        print
            $f->center(
                $f->p('Here is a list of works by your author:'),
                $f->p( $auths{$st{author}} ),
                $f->p('Please select one.'),
                $f->p(
                    $f->scrolling_list( -name => 'work',
                                        -Values => [sort $numerically keys %works],
                                        -labels => \%works,
                                        -autofocus => 'autofocus',
                                        -required => 'required')),
                $f->p(
                    $f->submit( -name => 'submit',
                                -value => 'Find a passage in this work')));
    }
    $my_footer->();
};

$handler{browser_works} = sub { $output{browser_passage}->() };


$output{browser_passage} = sub
{
    my %args = $get_args->();
    my $q = new Diogenes::Browser::Stateless(  %args );
    $database_error->($q) if not $q->check_db;

    $print_title->('Diogenes Passage Browser');
    $print_header->();
    $st{current_page} = 'browser_passage';

    print
        $f->center(
            $f->p(
                'Please select the passage you require by filling ',
                'out the following form with the appropriate numbers; ',
                'then click on the button below.'),
            $f->p(
                '(Hint: use zeroes to see the very beginning of ',
                'a work, including the title and proemial material.)'));

    print '<center><table><tr><td>';

    my @labels = $q->browse_location ($st{author}, $st{work});
    if ($q->{server_error}) {
        $print_error_page->($q->{server_error});
        return;
    }
    $st{levels} = $#labels;

    my $j = $#labels;
    my %fields;
    foreach my $lev (@labels)
    {
        my $lab = $lev;
        next if $lab =~ m#^\*#;
        $lab =~ s#^(.)#\U$1\E#;
        %fields = ( -default => '0', -name => "level_$j", -size => 25 );
        # autofocus first input box (HTML5) and select the 0 to easily overwrite it
        if ($j == $#labels) {
            $fields{'-autofocus'} = '';
            $fields{'-onfocus'} = "this.select()"
        }
        print
            "$lab: ", '</td><td>',
            $f->textfield( %fields ) ,
            '</td></tr><tr><td>';
        $j--;
    }
    print
        '</td></tr><tr><td colspan=2>',
        $f->center(
            $f->p(
                $f->submit( -name => 'submit',
                            -Value => 'Show me this passage'))),
            '</table></center>';

    $my_footer->();

};

$handler{browser_passage} = sub { $output{browser_output}->() };
$handler{browser_output} = sub { $output{browser_output}->() };

$output{browser_output} = sub
{
    my $jump =  shift;
    my $perseus_jump = shift;
    my $jumpTo = $jump || $perseus_jump;
    my %args = $get_args->();
    my $q = new Diogenes::Browser::Stateless( %args );
    $database_error->($q) if not $q->check_db;

    my @target;
    $print_title->('Diogenes Browser');
    $print_header->();
    $st{current_page} = 'browser_output';

    if ($jumpTo)
    {
        # Set signal to show the lexicon entry from whence we jumped
        # (the params have been stored previously in the other hidden
        # fields).
        if ($perseus_jump) {
            print $f->hidden( -name => 'JumpFromShowLexicon',
                              -default => "yes",
                              -override => 1 );
        }
        if ($jumpTo =~ m/^([^,]+),\s*(\d+?),\s*(\d+?):(.+)$/) {
            my $corpus = $1;
            $st{author} = $2;
            $st{work} = $3;
            my $loc = $4;
            if ($loc =~ m/:/){
                @target = split(/:/, $loc);
            } else {
                push @target, $loc;
            }
             print STDERR "$jumpTo; $corpus, $st{author}, $st{work}, @target\n" if $q->{debug};
        }
        else {
            $print_error->("Bad location description: $jumpTo");
        }
        # Try to fix cases where we are not given the number of levels we expect
        $q->parse_idt($st{author});
        my $levels = scalar keys %{ $Diogenes::Base::level_label{$st{short_type}}{$st{author}}{$st{work}} };
        my $diff = $levels - scalar @target;
        print STDERR "**$levels**$diff**\n" if $q->{debug};
        if ($diff > 0) {
            while ($diff > 0) {
                push @target, 1;
                $diff--;
            }
        } elsif ($diff < 0) {
            while ($diff < 0) {
                pop @target;
                $diff++;
            }
        }
    }
    elsif (exists $st{levels})
    {
        for (my $j = $st{levels}; $j >= 0; $j--)
        {
            push @target, $st{"level_$j"};
        }
    }

    if ($jumpTo or $previous_page eq 'browser_passage')
    {
        my ($begin_offset, $end_offset) = $q->seek_passage ($st{author}, $st{work}, @target);
        if ($q->{server_error}) {
            $print_error_page->($q->{server_error});
            return;
        }

        # When looking at the start of a work, don't browse back
        if (grep {!/^0$/} @target and not $q->{documentary})
        {
            ($st{begin_offset}, $st{end_offset}) =
                $q->browse_half_backward($begin_offset, $end_offset, $st{author}, $st{work});
        }
        else
        {
            ($st{begin_offset}, $st{end_offset}) =
                $q->browse_forward($begin_offset, $end_offset, $st{author}, $st{work});
        }
    }
    # Submit button or submit image
    elsif ($st{browser_forward} or $st{'browser_forward.x'})
    {
        ($st{begin_offset}, $st{end_offset}) =
            $q->browse_forward($st{begin_offset}, $st{end_offset}, $st{author}, $st{work});
    }
    elsif ($st{browser_back} or $st{'browser_back.x'})
    {
        ($st{begin_offset}, $st{end_offset}) =
            $q->browse_backward($st{begin_offset}, $st{end_offset}, $st{author}, $st{work});
    }
    else
    {
        warn('Unreachable code!');
    }

    print
        '<p>',
        $f->p($f->hr),
        qq{<input type="image" name="browser_back" class="prev" src="${picture_dir}go-previous.png" srcset="${picture_dir}go-previous.hidpi.png 2x" alt="Previous" /> },
        ($q->{end_of_file_flag} ? '' :
        qq{<input type="image" name="browser_forward" class="next" src="${picture_dir}go-next.png" srcset="${picture_dir}go-next.hidpi.png 2x" alt="Subsequent" />});


    print
        $f->center(
            $f->submit( -name => 'browser_back',
                        -id => 'browser_back_submit',
                        -value => 'Previous Text'),
        
            ($q->{end_of_file_flag} ?
             $f->submit( -name => 'end_of_file',
                         -value=> 'End of File',
                         -disabled=> 1) :
             $f->submit( -name => 'browser_forward',
                         -id => 'browser_forward_submit',
                         -value=> 'Subsequent Text')),
            ' | Passage: ',
            $f->textfield( -name => 'citation_jump_loc',
                           -size => 15,
                           -onkeydown => "if (event.keyCode == 13) {document.getElementById('citationGo').click();event.returnValue=false;event.cancel=true;}" ),
            $f->submit( -name => 'citation_jump',
                        -value=> 'Go',
                        -id=>'citationGo')
        ),
        '</p>';

    delete $st{browser_forward}; delete $st{'browser_forward.x'}; delete $st{'browser_forward.y'};
    delete $st{browser_back}; delete $st{'browser_back.x'}; delete $st{'browser_back.y'};

    $my_footer->();
};

############ Filters ###############

# @filters is an array of hash-refs, each of which have the keys
# "name", "type", and "authors".  The latter points to either an
# array-ref of author numbers (use the whole author) or a hash-ref
# whose keys are author numbers, and whose values are a ref to an
# array of work numbers.  Suitable for passing to
# select_authors(author_nums=>foo).

$output{filter_splash} = sub
{
    $st{current_page} = 'filter_splash';
    $print_title->('Diogenes Corpora');
    $print_header->();

    my $no_filters_msg = 'There are no saved texts';
    my $dis = '';
    $dis = '-disabled=>"true"' unless @filters;
    my @filter_names;
    @filter_names = ($no_filters_msg) unless @filters;
    push @filter_names, $_->{name} for @filters;
    my %labels;
    $labels{$_} = $filter_names[$_] for (0 .. $#filter_names);

    print
        $f->h1("Filters: user-defined subsets of the databases."),

        $f->p('From this page you can create new corpora or subsets of
        the databases to search within, and you can also view and
        delete existing user-defined corpora.  Note that these
        user-defined corpora must be a subset of one and only one
        database; currently you cannot define a corpus to encompass
        texts from two different databases.');

    if (not @filters) {
        print $f->p('You do not have any currently defined filters.');
    } else {
        print $f->p('Here are your currently defined filters:');
        print $f->ul($f->li(\@filter_names));

        print
            $f->h2('List or remove items from an existing filter'),

            $f->p( 'Corpus : ',
                   $f->popup_menu( -name => 'filter_choice',
                                   -Values => [0 .. $#filter_names],
                                   -labels => \%labels,
                                   $dis)),
            $f->p(
                $f->submit (-name=>'delete',
                            -value=>'Delete entire subset')),
            $f->p(
                $f->submit (-name=>'list',
                            -value=>'List or modify contents of subset')),
            $f->p(
                $f->submit (-name=>'duplicate',
                            -value=>'Duplicate subset under new name: '),
                $f->textfield( -name => 'duplicate_filter_name',
                               -size => 60, -default => '')),

        $f->p('<strong>N.B.</strong> To delete individual items from a
        corpus, choose "List contents" and you can do that on the next
        page.  To add authors to an existing corpus, find the new
        authors using either the simple corpus or complex subset
        options below, and then use the name of the existing corpus
        you want to add them to.  The new authors will be merged into
        the old, and for any duplicated author the new set of works will
        replace the old.  If you want to preserve the existing corpus
        and create a new one based on it, first use the "Duplicate corpus"
        function, and then add new authors to
        the duplicate. ');


    }

    print $f->h2('Define a new filter'),

        $f->p(q(Enter a name or names or parts thereof, in order to
        narrow down the scope of your search within a particular
        database; you may separate multiple names by spaces or commas.
        When you proceed, this will bring you to another page where
        you can select which matching authors you wish to search in;
        you can then further narrow your selection down to particular
        works.));

    my $default_db;
    if ($st{database}) {
        # In case we have prompted the user for db path.
        $default_db = $st{database};
    } elsif ($st{corpus} and exists $choices{$st{corpus}}) {
        $default_db = $choices{$st{corpus}};
    } else {
        $default_db = 'tlg';
    }

    print
        $f->table({cellspacing=>'10px'},
                  $f->Tr(
                      $f->th({align=>'right'}, 'Author name(s): '),
                      $f->td(
                          $f->textfield( -name => 'author_pattern',
                                         -size => 60, -default => ''))),
                  $f->Tr(
                      $f->th({align=>'right'}, 'Database: '),
                      $f->td(
                          $f->popup_menu(
                              -name=>'database',
                              -Values=>\@databases,
                              -labels=>\%database,
                              -Default=>$default_db),
                          $f->submit( -name =>'simple',
                                      -value=>'Define subset' ))));

    print
        $f->h2('Define a complex subset of the TLG'),

        $f->p('The TLG classifies its texts into a large number of
        categories: chronological, generic, geographical, and so
        forth.  You can use these classifications to define a subset
        of works in the TLG to narrow down your search. '),

        $f->p($f->submit( -name => 'complex',
                -value => 'Define a complex TLG corpus'));


    $my_footer->();
};

$handler{filter_splash} = sub
{
    if ($st{simple})
    {
        $output{simple_filter}->();
    }
    elsif ($st{complex})
    {
        $output{tlg_filter}->();
    }
    elsif ($st{list})
    {
        $output{list_filter}->();
    }
    elsif ($st{delete})
    {
        $output{delete_filter}->();
    }
    elsif ($st{duplicate})
    {
        $output{duplicate_filter}->();
    }
    else {
        $print_title->('Error');
        $print_header->();
        print $f->center($f->p($f->strong('Flow Error.')));
    }

};

$output{simple_filter} = sub
{
    my %args;
    $args{type} = $st{database};
    $args{output_format} = 'html';
    $args{encoding} = $default_encoding;
    $st{short_type} = $st{database};
    $st{type} = $database{$st{database}};
    my $q = new Diogenes::Search(%args);
    $database_error->($q) if not $q->check_db;

    $print_title->('Diogenes Author Select Page');
    $print_header->();
    $st{current_page} = 'simple_filter';

    my @auths = $q->select_authors(author_regex => $st{author_pattern});

    unless (scalar @auths)
    {
        print
            $f->p($f->strong('Error.')),
            $f->p(qq(There were no texts matching the author $st{author_pattern}));
        $my_footer->();
        return;
    }

    $f->autoEscape(undef);
    print $f->h1('Matching Authors'),

    $f->p('Here is a list of the authors that matched your query'),
    $f->p('Please select as many as you wish to search in, then go to
    the bottom of the page.');

    my @auth_nums = @{ $q->{prev_list} };
    my %labels;
    $labels{"$auth_nums[$_]"} = $auths[$_] for (0 .. $#auths);
    print $f->checkbox_group( -name => 'author_list',
                              -Values => \@auth_nums,
                              -labels => \%labels,
                              -linebreak => 'true');

    print
        $f->p(
            $f->button( -value => "Select All",
                        -onClick => "setAll()" ),
            '&nbsp;&nbsp;&nbsp;&nbsp;',
            $f->reset( -value => 'Unselect All')),
        $f->p('&nbsp;');

    print $f->p('Please choose one of the following options before proceeding');

    my @values = qw(refine_works save_filter);
    my %radio_labels = ( save_filter =>
                         'Save the selected authors as a subset for later
use under this name:',
                         refine_works =>
                         'Further narrow down to particular works of
the selected authors' );
    my $default_choice = $st{simple_filter_option} || 'save_filter';

    my @group = $f->radio_group( -name => 'simple_filter_option',
                                 -values => \@values,
                                 -default => $default_choice,
                                 -labels => \%radio_labels );

    print $f->table(
        $f->Tr(
            $f->td( $group[0] )),
        $f->Tr(
            $f->td( $group[1] ),
            $f->td(
                $f->textfield( -name => 'saved_filter_name',
                               -size => 60,
                               -default => '' ))));

    print $f->p($f->submit( -name =>'Proceed'));

    $my_footer->();

};

my $save_filters = sub {

    # It's important that we read and write the filter file in raw
    # mode, as the data are already unflagged utf8; we don't want it
    # encoded again.

    open(my $filter_fh,'>:raw', $filter_file)
        or die "Can't write to filter file ($filter_file): $!";
    print STDERR "Saving filters ...\n" if $init->{debug};
    print $filter_fh to_json \@filters;
    print STDERR to_json \@filters if $init->{debug};
    close $filter_fh or die "Can't close filter file ($filter_file): $!";
};

my $go_splash = sub {
    $output{splash}->();
};

my $save_filters_and_go = sub {
    $save_filters->();
    %st = ();
    $read_filters->();
    $go_splash->();
};

my $merge_filter = sub {
    my $new = shift;
    my $name = $new->{name};
    print STDERR "Merging $name\n" if $init->{debug};
    $print_error_page->('You must give your corpus a name!') unless ($name and $name =~ m/\S/);
    unless (defined $new->{authors}) {
        $print_error_page->('Your corpus has no authors in it!')
    }
    my $merge;
    for my $f (@filters) {
        if ($f->{name} eq $name) {
            unless ($f->{type} eq $new->{type}) {
                $print_error_page->("Cannot merge two corpora of different type!\n");
            }
            $merge = 1;
            my %tmp;
            if (ref($f->{authors}) eq 'ARRAY' and ref($new->{authors}) eq 'ARRAY') {
                $f->{authors} = [@{ $f->{authors} }, @{ $new->{authors} }];
            }
            elsif (ref($f->{authors}) eq 'HASH' and ref($new->{authors}) eq 'ARRAY') {
                $tmp{$_}++ for @{ $new->{authors} };
                $f->{authors} = { %{ $f->{authors} }, %tmp };
            }
            elsif (ref($f->{authors}) eq 'ARRAY' and ref($new->{authors}) eq 'HASH') {
                $tmp{$_}++ for @{ $f->{authors} };
                $f->{authors} = { %tmp, %{ $new->{authors} } };
            }
            elsif (ref($f->{authors}) eq 'HASH' and ref($new->{authors}) eq 'HASH') {
                $f->{authors} = { %{ $f->{authors} }, %{ $new->{authors} } };
            }
            else {
                die "Unreachable code!";
            }
        }
    }
    unless ($merge) {
        push @filters, $new;
    }
};

$handler{simple_filter} = sub
{
    if ($st{simple_filter_option} eq 'save_filter') {
        $merge_filter->({ name => $st{saved_filter_name},
                          authors => $st{author_list},
                          type => $st{database} });

        $save_filters_and_go->();
    }
    elsif ($st{simple_filter_option} eq 'refine_works') {
        $output{refine_works}->();
    }
    else{
        $print_error_page->();
    }
};

$output{refine_works} = sub
{
    my %args = ( -type => $st{database},
                 -output_format => 'html',
                 -encoding => $default_encoding );
    my $q = new Diogenes::Search( %args );
    $database_error->($q) if not $q->check_db;

    $print_title->('Diogenes Individual Works');
    $print_header->();
    $st{current_page} = 'select_works';
    print
        $f->h1('Individual Works'),
        $f->p('Select the works you wish to use for searching.');


    unless ($st{author_list})
    {
        print
            $f->p($f->strong('Error.')),
            $f->p(qq(You must select at least one author));
        $my_footer->();
        return;
    }
    my @auth_nums = @{ $st{author_list} };
    unless (scalar @auth_nums)
    {
        print
            $f->p($f->strong('Error.')),
            $f->p(qq(There were no texts matching the author $st{author_pattern}));
        $my_footer->();
        return;
    }


    for my $a (@auth_nums)
    {
        my @work_nums = ();
        my %labels = ();
        $q->parse_idt($a);
        my $author = $author{$q->{type}}{$a};
        $q->format_output(\$author, 'l', 1);

        print $f->h2($author);
        for my $work_num (sort $numerically
                          keys %{ $work{$q->{type}}{$a} })
        {
            push @work_nums, $work_num;
            $labels{"$work_num"} = $work{$q->{type}}{$a}{$work_num};
        }
        $q->format_output(\$_, 'l', 1) for values %labels;
        $strip_html->(\$_) for values %labels;
        print $f->checkbox_group( -name => "work_list_for_$a",
                                  -Values => \@work_nums,
                                  -labels => \%labels,
                                  -linebreak => 'true');
    }
    print
        $f->hr,
        $f->p('Please choose a name for this corpus before saving it.');

    my $default_filter_name = $st{saved_filter_name} || '';
    print
        $f->textfield( -name => 'saved_filter_name',
                       -size => 60,
                       -default => $default_filter_name,
                       -required => 'required'),
        $f->p('&nbsp;'),
        $f->p($f->submit( -name =>'Save'));

    $my_footer->();
};

$handler{select_works} = sub
{
    my $work_nums;
    for my $k (keys %st)
    {
        next unless $k =~ m/^work_list_for_/;
        my $auth_num = $k;
        $auth_num =~ s/^work_list_for_//;
        $work_nums->{$auth_num} = $st{$k};
    }
    $merge_filter->({ name => $st{saved_filter_name},
                      authors => $work_nums,
                      type => $st{database} });

    $save_filters_and_go->();
};

$output{tlg_filter} = sub
{
    my %args;
    $args{type} = $st{database};
    $args{output_format} = 'html';
    $args{encoding} = $default_encoding;
    $st{short_type} = 'tlg';
    $st{type} = 'TLG Texts';
    my $q = new Diogenes::Search(%args);
    $database_error->($q) if not $q->check_db;

    $print_title->('Diogenes TLG Selection Page');
    $print_header->();

    $st{current_page} = 'tlg_filter';

    my %labels = %{ $q->select_authors(get_tlg_categories => 1) };
    my %nice_labels = ( 'epithet' => 'Author\'s genre',
                        'genre_clx' => 'Text genre',
                        'location'  => 'Location' );
    my $j = 0;

    print
        $f->h1('TLG Classification'),
        $f->p(
            'Here are the various criteria by which the texts contained in
         the TLG are classified.'),
        $f->p('You may select as many items as you like in each box.  Try holding down
               the control key to select multiple items.');
    print '<table border=0 cellpadding=10px><tr><td>';
    foreach my $label (sort keys %labels)
    {
        unshift @{$labels{$label}}, '--';

        next if $label eq 'date' or $label eq 'gender' or $label eq 'genre';
        $j++;
        print "<strong>$j. $nice_labels{$label}:</strong><br>";
        print $f->scrolling_list( -name => $label,
                                  -Values => \@{ $labels{$label} },
                                  -multiple => 'true',
                                  -size => 8,
                                  -Default => '--');
        print '</td><td>';
    }
    print '</td></tr><tr><td>';
    $j++;
    print
        "<strong>$j. Gender:</strong><br>",
        $f->scrolling_list( -name => 'gender',
                            -Values => \@{ $labels{gender} },
                            -multiple => 'true',
                            -Default => '--'),
        '</td><td>';
    $j++;
    print
        "<strong>$j. Name of Author(s):</strong><br>",
        $f->textfield(-name=>'author_regex', -size=>25),

        '</td><td>',
        '<TABLE border=0><TR><TD colspan=2>';
    $j++;
    print
        "<strong>$j. Date Range:</strong>",
        '</td></tr><tr><td>',
        "After &nbsp;",
        '</td><td>';
    my @dates = @{ $labels{date} };
    pop @dates while $dates[-1] =~ m/Varia|Incertum/;
    unshift @dates, '--';
    print
        $f->popup_menu( -name => 'date_after',
                        -Values => \@dates,
                        -Default => '--'),
        '</td><td rowspan=2>',
        $f->checkbox( -name =>'Varia',
                      -label => ' Include Varia and Incerta?'),

        '</td></tr><tr><td>',
        "Before ",
        '</td><td>',
        $f->popup_menu( -name => 'date_before',
                        -Values => \@dates,
                        -Default => '--'),

        '</td></tr></table></td></tr></table>',
        $f->p('You may select multiple values for as many ',
        'of the above criteria as you wish.'),
        $f->p(
            'Then indicate below how many of ',
            'the stipulated criteria a text must meet ',
            'in order to be included in the search.'),
        $f->p(
            "<p><strong>Number of criteria to match: </strong>");
    my @crits = ('Any', 2 .. --$j, 'All');
    print
        $f->popup_menu(-name=>'criteria',
                       -Values=>\@crits,
                       -Default=>$default_criteria),
        '&nbsp;',
        $f->submit(  -name => 'tlg_filter_results',
                     -value => 'Get Matching Texts');

        $my_footer->();
};

$handler{tlg_filter} = sub
{
    $output{tlg_filter_results}->();
};

my $get_args_for_tlg_filter = sub
{
    my %args;
    for (qw(epithet genre_clx location gender))
    {
        next if not defined $st{$_} or $st{$_} eq '--';
        my $ref = ref $st{$_} ? $st{$_} : [ $st{$_} ];
        my @non_empty = grep {$_ ne '--'} @{ $ref };
        $args{$_} = \@non_empty if @non_empty;
    }
    for (qw(author_regex criteria))
    {
        $args{$_} = $st{$_} if $st{$_};
    }
    $args{criteria} = 1 if $args{criteria} =~ m/any/;
#       $args{criteria} = 6 if $args{criteria} eq 'All';
    my @dates;
    push @dates, $st{'date_after'};
    push @dates, $st{'date_before'};
    push @dates, 1, 1 if $st{'Varia'};

    @{ $args{date} } = @dates
        if @dates and (($st{'date_after'} ne '--')
                       and ($st{'date_before'} ne '--'));

    return %args;
};


$output{tlg_filter_results} = sub
{
    my %args;
    $args{type} = $st{database};
    $args{output_format} = 'html';
    $args{encoding} = $default_encoding;
    my $q = new Diogenes::Search(%args);
    $database_error->($q) if not $q->check_db;

    $print_title->('Diogenes TLG Select Page');
    $print_header->();

    $st{current_page} = 'tlg_filter_output';

    $f->autoEscape(undef);
    %args = $get_args_for_tlg_filter->();
    my @texts = $q->select_authors(%args);
    my %labels;
    $labels{$_} = $texts[$_] for (0 .. $#texts);

    unless (scalar @texts)
    {
        print
            $f->p($f->strong('Error.')),
            $f->p(qq(There were no texts matching the criteria you gave.'));
        $my_footer->();
        return;
    }

    print $f->h1('Matching Authors and/or Texts'),
        $f->p('Here is a list of the texts that matched your query.'),
        $f->p('Please select as many as you wish to search in' ,
              'and click on the button at the bottom.'),

        $f->checkbox_group(-name => 'works_list',
                           -Values => [0 .. $#texts],
                           -labels => \%labels,
                           -linebreak => 'true');

    print
        $f->p(
            $f->button( -value => "Select All",
                        -onClick => "setAll()" ),
            '&nbsp;&nbsp;&nbsp;&nbsp;',
            $f->reset( -value => 'Unselect All')),
        $f->hr;

    print
        $f->p('Please choose a name for this corpus before saving'),
        $f->textfield( -name => 'saved_filter_name',
                       -size => 60,
                       -default => '' ),
        $f->p('&nbsp'),
        $f->p($f->submit( -name =>'Save'));

    $my_footer->();

};

$handler{tlg_filter_output} = sub
{
    my %args;
    $args{type} = $st{database};
    $args{output_format} = 'html';
    $args{encoding} = $default_encoding;
    my $q = new Diogenes::Search(%args);
    $database_error->($q) if not $q->check_db;

    %args = $get_args_for_tlg_filter->();

    () = $q->select_authors(%args);
    () = $q->select_authors(previous_list => $st{works_list});

    my $work_nums = $q->{req_authors};
    for my $k (keys %{ $q->{req_auth_wk} })
    {
        $work_nums->{$k} = [keys %{ $q->{req_auth_wk}{$k} }];
    }
    $merge_filter->({ name => $st{saved_filter_name},
                      authors => $work_nums,
                      type => $st{database} });
    $save_filters_and_go->();
};

$output{list_filter} = sub
{
    my $filter_number = $st{filter_choice};
    my $filter = $filters[$filter_number];
    my $type = $filter->{type};
    my $name = $filter->{name};
    $st{short_type} = $type;
    $st{type} = $database{$type};

    my %args = ( -type => $type );
    my $q = new Diogenes::Search( %args );
    $database_error->($q) if not $q->check_db;

    $print_title->('User-defined corpus listing');
    $print_header->();
    $st{current_page} = 'list_filter';

    my $work_nums = $filter->{authors};
    my @texts = $q->select_authors( -author_nums => $work_nums);
    my %labels;
    $labels{$_} = $texts[$_] for 0 .. $#texts;


    print
        $f->h2('User-defined corpus listing'),
        $f->p(qq(Here is the subset of the $type database named $name:));
#               (join '<br />', @texts);
    print $f->checkbox_group( -name => "filter_list",
                              -Values => [0 .. $#texts],
                              -labels => \%labels,
                              -columns=>'1');

    print
        $f->hr,
        $f->submit(-name=>'delete_items',
                   -value=>'Click here to delete selected items');
    $my_footer->();
};

$output{delete_filter} = sub {
    my $filter_number = $st{filter_choice};
    if (defined $filter_number) {
        splice @filters, $filter_number, 1;        
        $save_filters_and_go->();
    }
    else {
        die ("Could not find filter to delete it!");
    }
};

$handler{list_filter} = sub
{
    if ($st{delete_items}) {
        $output{delete_filter_items}->();
    }
    else {
        $print_title->('Error');
        $print_header->();
        print $f->center($f->p($f->strong('Flow Error.')));
    }
};

my $deep_copy;
$deep_copy = sub {
    my $this = shift;
    if (not ref $this) {
      $this;
    } elsif (ref $this eq "ARRAY") {
        [map $deep_copy->($_), @$this];
    } elsif (ref $this eq "HASH") {
        +{map { $_ => $deep_copy->($this->{$_}) } keys %$this};
    } else { die "what type is $_?" }
};


$output{duplicate_filter} = sub {
    my $old_filter_number = $st{filter_choice};
    my $new_filter = $deep_copy->($filters[$old_filter_number]);
    $new_filter->{name} = $st{duplicate_filter_name};
    push @filters, $new_filter;
    $save_filters_and_go->();
};



$output{delete_filter_items} = sub {
    my $filter_number = $st{filter_choice};
    unless (defined $filter_number) {
        print STDERR "Missing number $st{filter_choice} for deletion";
        return;
    }
    my $filter = $filters[$filter_number];
    my $type = $filter->{type};
    my %args = ( -type => $type );
    my $q = new Diogenes::Search( %args );
    $database_error->($q) if not $q->check_db;
    my $work_nums = $filter->{authors};
    my @orig_texts = $q->select_authors( -author_nums => $work_nums);
    # Naughty -- we ought to expose this in the API
    my @list = @{ $q->{prev_list} };
    splice @list, $_, 1 for @{ $st{filter_list} };
    my %new_work_nums;
    for my $item (@list) {
        if (ref $item) {
            my ($auth, $wk) = @{ $item };
            next if $new_work_nums{$auth} and $new_work_nums{$auth} eq 'all';
            my @w = exists $new_work_nums{$auth} ? @{ $new_work_nums{$auth} } : ();
            push @w, $wk;
            $new_work_nums{$auth} = \@w;
        }
        else {
            $new_work_nums{$item} = 'all';
        }
    }
    $filter->{authors} = \%new_work_nums;
    $save_filters_and_go->();

};

$output{headwords} = sub {

    $print_title->('Diogenes Headword Search Page');
    $print_header->();
    $st{current_page} = 'author_search';
    $st{type} = 'tlg';
    $st{short_type} = 'tlg';
    my %args = $get_args->();
    $args{context} = 'level';
    my $q = new Diogenes::Search(%args);

    my $pattern = $q->{pattern_list}->[0];
    # Non-ascii byte at start tries to ensure this is not an internal
    # ref to a headword.  Would be better to use the start of an entry
    # ([\x90-\xff]), but entries are not marked by level in Photius.
    # Limit match to within <> by excluding those chars from before
    # and after.
    $pattern = '[\x80-\xff][\[%]?\d?<\d?\d?[^<>]{0,50}?' . $pattern . '[^<>]{0,50}?>\d?\d?';
    $q->{pattern_list}->[0] = $pattern;
    $database_error->($q) if not $q->check_db;

    my @ancient_lexica = qw(9010 4085 4040 4097 4098 4099 4311 9018 9009 9018 9023);

    my @auths = $q->select_authors(author_nums => \@ancient_lexica);
    unless (scalar @auths)
    {
        $print_error->(qq(There were no texts matching the author $st{author_pattern}));
        return;
    }

    print $f->h2('Searching headwords only in the following lexicographers'),
        $f->ul($f->li(\@auths)),
        $f->hr;

    my $retval = $q->do_search;
    $check_chunking->($retval, $q);
    $my_footer->();

};

my $mod_perl_error = sub
{
    $print_title->('Error');
    $print_header->();
    print '<p><center><strong>Error</strong></center></p>',
    '<p>This CGI script is set up to expect to run under mod_perl, ',
    'and yet it seems not to be doing so.</p>',
    '<p>Either comment out the relevant line at the start of this script, ',
    'or fix your mod_perl configuration.<p> ',
    '<p>Here is the current environment: <p> ';
    print "<pre>\n";
    print map { "$_ = $ENV{$_}\n" } sort keys %ENV;
    print "</pre>\n";
    return;
};

# Initialization of query
my $setup = sub {

    my $parameters = shift;
    if ($parameters) {
        $f = new CGI($parameters);
    }
    elsif ($Diogenes_Daemon::params) {
        $f = new CGI($Diogenes_Daemon::params)
    }
    else {
        $f = new CGI;
    }

    $Diogenes::Base::cgi_flag = 1;

    # Force read of config files
    my %args_init = (-type => 'none');
    $init = new Diogenes::Base(%args_init);
    $filter_file = $init->{filter_file};

    my $choice_from_config = quotemeta $init->{cgi_default_corpus};
    for (@choices)
    {
        if ($_ =~ m/$choice_from_config/i)
        {
            $default_choice = $_;
            last;
        }
    }
    warn "I don't understand default search type $init->{cgi_default_corpus}\n"
        unless $default_choice;

    $default_encoding = $init->{cgi_default_encoding} || 'UTF-8';
    $default_criteria = $init->{default_criteria};

    $ENV{PATH} = "/bin/:/usr/bin/";
    $| = 1;

    # Everything else is obsolete
    $charset = 'UTF-8';

    # Persisting this variable across calls causes problems
    undef @filters;
    $get_state->();
    $read_filters->();
    $previous_page = $st{current_page};
};

# Dispatch query
my $dispatch = sub {
    
    my $check_mod_perl = $init->{check_mod_perl};
    if ($check_mod_perl and not $ENV{GATEWAY_INTERFACE} =~ /^CGI-Perl/)
    {
        $mod_perl_error->();
    }
    elsif ($f->param('JumpTo') or $f->param('JumpToFromPerseus') or $f->param('citation_jump'))
    {
        my $context_jump;
        if ($f->param('citation_jump')) {
            $context_jump = $choices{$st{corpus}} . ',' . $st{author} . ',' . $st{work} . ':';
            my $loc = $f->param('citation_jump_loc');
            $loc =~ s/\s//g;
            $loc =~ s/[\.,;]/:/g;
            $context_jump .= $loc;
        } else {
            # Jump straight to a passage from the text browser, not the sidebar
            $context_jump = $f->param('JumpTo');
        }
        # If we have jumped from the sidebar, we want to restore the sidebar
        my $perseus_jump = $f->param('JumpToFromPerseus');
        my $jump = $context_jump || $perseus_jump;
        $jump =~ m/^([^,]+)/;
        $st{short_type} = $1;
        $st{type} = $database{$1};
        $output{browser_output}->($jump, $perseus_jump);
    }
    elsif (not $previous_page)
    {
        # First time, print opening page
        $output{splash}->();
    }
    else
    {
        # Data present, pass control to the appropriate subroutine
        if ($handler{$previous_page})
        {
            $handler{$previous_page}->();
        }
        else
        {
            $print_error_page->();
        }
    }
};

$Diogenes::Script::go = sub {
    my $parameters = shift;
    $setup->($parameters);
    $dispatch->()
};


# End of module
1;
