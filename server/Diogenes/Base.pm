##############################################################################
# Diogenes is a set of programs including this Perl module which provides      
# an object-oriented interface to the CD-Rom databases published by the        
# Thesaurus Linguae Graecae and the Packard Humanities Institute.              
#                                                                              
# Send your feedback, suggestions, and cases of fine wine to                   
# P.J.Heslin@durham.ac.uk
#
#       Copyright (c) 1999-2001 Peter Heslin.  All Rights Reserved.
#       This module is free software.  It may be used, redistributed,
#       and/or modified under the terms of the GNU General Public 
#       License, either version 2 of the license, or (at your option)
#       any later version.  For a copy of the license, write to:
#
#               The Free Software Foundation, Inc.
#               675 Massachussets Avenue
#               Cambridge, MA 02139
#               USA
#
#       This module and its associated programs are distributed in the
#       hope that they will be useful, but WITHOUT ANY WARRANTY;
#       without even the implied warranty of MERCHANTABILITY or
#       FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
#       Public License for more details.
################################################################################

package Diogenes::Base;
require 5.006;

$Diogenes::Base::Version =  "4.7.0";
$Diogenes::Base::my_address = 'p.j.heslin@durham.ac.uk';

use strict;
use integer;
use Cwd;
use Carp;
use Data::Dumper;
# Use local CPAN
use File::Spec;
use FindBin qw($Bin);
use lib ($Bin, File::Spec->catdir($Bin, '..', 'dependencies', 'CPAN') );
use Module::Path 'module_path';

use Diogenes::BetaHtml;
use Diogenes::UnicodeInput;

our(%encoding, %context, @contexts, %choices, %list_labels, %auths,
    %lists, %work, %lang, %author, %last_work, %work_start_block,
    %level_label, %sub_works, %top_levels, %last_citation, $bibliography,
    %coptic_encoding, %database, @databases, @filters);

use Exporter;
@Diogenes::Base::ISA = qw(Exporter Diogenes::UnicodeInput);
@Diogenes::Base::EXPORT_OK = qw(%encoding %context @contexts
    %choices %work %author %last_work %work_start_block %level_label
    %top_levels %last_citation %database @databases @filters);
our($RC_DEBUG, $OS, $config_dir);
$RC_DEBUG = 0;

use Encode;
BEGIN {
    $OS = ($^O=~/MSWin/i or $^O=~/Win32/i or $^O =~/dos/) ? 'windows' :
        ($^O=~/darwin/i) ? 'mac' : 'unix';

    if ($OS eq 'windows' ) {
        eval "use Win32; 1" or die $@;
    }
}


# For Windows pathnames
our $code_page;
if ($OS eq 'windows') {
    $code_page = Win32::GetACP() || q{};
    if ($code_page) {
        $code_page = 'cp'.$code_page;
        $code_page = Encode::resolve_alias($code_page) || q{};
        print STDERR "Code page: $code_page\n";
    }
}


# Because of the pre-Unicode history of Diogenes, most of its data is
# represented by Perl internally as octets, even when those bytes
# represent utf8 data.  The prefs file, however, is now written by
# Node.js as utf8, so it makes sense to read that in as utf8.  Using
# these database paths works fine on Linux and Mac and recent versions
# of Windows, but there are issues with older versions of Windows.

# It used to be the case that the only way to use Unicode file paths
# in a system-independent way on Windows was to use the UTF-16 "W"
# APIs; but Perl uses the old "A" APIs.  These old APIs depend on the
# current codepage, which used to be set at OS installation and
# couldn't be changed.  Since Version 1903 (May 2019) of Windows 10,
# however, it became possible to change the codepage of an executable
# to utf-8 via its manifest.  That is what we do now, and it solves
# the problem for these recent systems.  Older Windows systems will
# ignore that manifest, however, and will use the 8-bit system
# codepage.

# Here, for older systems which ignore the attempt to change the
# codepage to utf8, we convert the paths from the prefs file to the
# local Windows 8-bit codepage using Encode.  (If we read in the prefs
# file as raw bytes, we would have to use Encode::from_to instead.)
# This is an imperfect solution, as it only permits paths that use a
# very limited set of characters from that local codepage rather than
# arbitrary Unicode.

# However, there is a mysterious bug I never tracked down that causes
# this limited solution to fail.  The codepage path conversion on
# Windows works fine for basic searching, but fails when browsing
# through a text.  The .txt file fails to open when there is non-ascii
# code in the path in seek_passage and browse_forward, even though
# the authtab file and the corresponding .idt file open fine.  So best
# to advise users of older Windows systems to use paths to the
# databases that only contain ascii characters

sub windows_filename {
    my ($filename) = @_;
    if ($code_page and not $code_page =~ m/utf|65001/) {
        # my $ret = Encode::from_to($filename, 'utf8', $codepage);
        # print STDERR "Codepage conversion failed\n" unless defined $ret;
        $filename = Encode::encode($code_page, $filename);
    }
    return $filename;
}

eval "require 'Diogenes.map';";
$Diogenes::Base::map_error = $@;
# Add in the built-in encodings
$encoding{Beta} = {};
$encoding{Ibycus} = {};
$encoding{Transliteration} = {};
# UTF-8 is just an alias for -CB (precomposed characters)
$encoding{'UTF-8'} = $encoding{'UTF-8-CB'};

# Define some globals
$context{g} = {
    'sentence'  => '[.;]',
    'clause'    => '[.;:]',
    'phrase'    => '[.;:,_]', 
    'paragraph' => '[@{}]'
};
$context{l} = {
    'clause'    => '[.!?;:]',
    'sentence'  => '[.!?]',
    'phrase'    => '[.!?;:,_]',
    'paragraph' => '[@{}<>]'
};

@contexts = (
    'paragraph',
    'sentence',
    'clause',
    'phrase',
    '1 line',
    '2 lines',
    '5 lines',
    '10 lines',
    '50 lines',
    );

# These are the choices presented (e.g. on the opening CGI page).  

%choices =  (
    'PHI Latin Corpus' => 'phi',
    'TLG Texts' => 'tlg',
    'TLG Bibliography' => 'bib',
    'Duke Documentary Papyri' => 'ddp',
    'Classical Inscriptions' =>'ins',
    'Christian Inscriptions' => 'chr',
    'Miscellaneous PHI Texts' => 'misc',
    'PHI Coptic Texts' => 'cop',
    );

%database =  (
    'phi' => 'PHI Latin Corpus',
    'tlg' => 'TLG Texts',
    'ddp' => 'Duke Documentary Papyri',
    'ins' => 'Classical Inscriptions',
    'chr' => 'Christian Inscriptions',
    'misc' => 'Miscellaneous PHI Texts',
    'cop' => 'PHI Coptic Texts',
    'bib' => 'TLG Bibliography',
    );
@databases = qw(tlg phi ddp ins chr cop misc);

# Here are some handy constants
use constant MASK     => hex '7f';
use constant RMASK    => hex '0f';
use constant LMASK    => hex '70';
use constant OFF_MASK => hex '1fff';
$| = 1;

# Default values for all Diogenes options.
# Overridden by rc files and constructor args.
my %defaults = (
    type => 'phi',
    output_format => 'ascii',
    highlight => 1,
    printer => 0,
    input_lang => '',
    input_raw => 0,
    input_pure => 0,
    input_beta => 0,
    debug => 0,
    bib_info => 1,
    max_context => 20,
    encoding => 'UTF-8',
    
    # System-wide defaults
    tlg_dir => '',
    phi_dir => '',
    ddp_dir => '',
    tll_pdf_dir => '',
    # Not a dir but a file path, but this makes the Electron code easier
    old_pdf_dir => '',
    authtab => 'authtab.dir',
    tlg_file_prefix => 'tlg',
    phi_file_prefix => 'lat',
    ddp_file_prefix => 'ddp',
    ins_file_prefix => 'ins',
    chr_file_prefix => 'chr',
    cop_file_prefix => 'cop',
    misc_file_prefix => 'civ',
    uppercase_files => 0,
    dump_file => '', 
    blacklist_file => '', 
    blacklisted_works_file => '', 
    ibycus4 => 0,
    prosody => 0,
    psibycus => 0,
    idt_suffix => '.idt',
    txt_suffix => '.txt',
    latex_pointsize => '',
    latex_baseskip => '',
    latex_counter => 1,

    # Slower, but not rooted at the start of words
    use_tlgwlinx => 0,
    
    # Lines per pass in browser
    browse_lines => 29,
    
    # Pattern to match
    pattern => '',
    pattern_list => [],
    min_matches => 1,
    context => 'sentence',
    reject_pattern => '',
    
    # The max number of lines for different types of context
    overflow => {
        'sentence'      => 10,
        'clause'        => 5,
        'phrase'        => 3,
        'paragraph'     => 20,
    },
    
    # Additional file handle to write raw output to 
    aux_out => undef,
    input_source => undef,
    
    coptic_encoding => 'UTF-8',
    input_encoding => 'Unicode',

    # These are obsolete -- kept to avoid errors in old config files
    cgi_input_format => '',
    perseus_server => '',

    cgi_default_corpus => 'TLG Texts', 
    cgi_default_encoding => 'UTF-8', 
    cgi_buttons => 'Go to Context', 
    cgi_font => '', 
    default_criteria => 'All',
    cgi_multiple_fields => 6,
    check_mod_perl => 0,

    perseus_links => 1, # links to Perseus morphological parser 
    perseus_show => "split",

    hit_html_start => '<font color="red"><b><u>',
    hit_html_end => '</u></b></font>',
    quiet => 0,

    line_print_modulus => 5,

    # Chronological search may be a bit slower, but negligible these days.
    tlg_use_chronology => 1,

    # For multiple matching, count multiple matches for each pattern
    repeat_matches => 0,

    # obsolete
    user => 'default',

    # Use the bug-prone ToC in the idt file (maybe for slow computers)
    use_idt_browsing => 0,

    # After this many characters of search output, stop chunk after current author
    chunk_size => 1000000,
    seen_author_list => [],
    hits => 0,
    );

sub validate
{
    my $key = shift;
    $key =~ s/-?(\w+)/\L$1/;
    return $key if exists $defaults{$key};
    die ("Configuration file error in parameter: $key\n");
};


# The electron client sets the environment variable.
sub get_user_config_dir
{
    if ($ENV{'Diogenes_Config_Dir'})
    {
        return $ENV{'Diogenes_Config_Dir'};
        
    }
    elsif ($OS eq 'unix')
    {
        # Electron's config dirs, which we will want to use from the
        # command-line if settings were earlier set from the GUI
        if ($ENV{XDG_CONFIG_HOME} and -e "$ENV{XDG_CONFIG_HOME}/Diogenes") {
            return "$ENV{XDG_CONFIG_HOME}/Diogenes/";
        }
        elsif (-e "$ENV{HOME}/.config/Diogenes") {
            return "$ENV{HOME}/.config/Diogenes/";
        }
        elsif ($ENV{HOME})
        {
            # The old, pre-Electron config dir
            return "$ENV{HOME}/.diogenes/";
        }
        else { warn "Could not find user profile dir! \n" }
    }
    elsif ($OS eq 'mac')
    {
        if ($ENV{HOME})
        {
            return "$ENV{HOME}/Library/Application Support/Diogenes/";
        }
        else { warn "Could not find user profile dir! \n" }
    }
    elsif ($OS eq 'windows')
    {
        if ($ENV{USERPROFILE})
        {
            if (-e "$ENV{USERPROFILE}\\AppData\\Roaming")
            {
                # Vista
                return "$ENV{USERPROFILE}\\AppData\\Roaming\\Diogenes\\";
            }
            elsif (-e "$ENV{USERPROFILE}\\Application Data")
            {
                # Windows 2000 and XP
                return "$ENV{USERPROFILE}\\Application Data\\Diogenes\\";
            }
            else { warn "Could not find user profile dir!! \n" }
        }
        else { warn "Could not find user profile dir! \n" }
    }
}

# Global var for diogenes-server.pl
$config_dir = get_user_config_dir();

sub read_config_files
{
    my $self = shift;
    my %configuration = ();
    
    my @rc_files;
    
    # System-wide config files, in case they are needed.
    if ($OS eq 'unix')
    {
        @rc_files = ('/etc/diogenes.config');
    }
    elsif ($OS eq 'mac')
    {
        @rc_files = ('/Library/Application Support/Diogenes/diogenes.config');
    }
    elsif ($OS eq 'windows')
    {
        @rc_files = ('C:\\diogenes.config');
    }

    push @rc_files, $self->{auto_config};
    push @rc_files, $self->{user_config};
    
    my ($attrib, $val);
    
    foreach my $rc_file (@rc_files) 
    {
        next unless $rc_file;
        print STDERR "Trying config file: $rc_file ... " if $RC_DEBUG;
        next unless -e $rc_file;
        open RC, '<:encoding(UTF-8)', "$rc_file" or die ("Can't open (apparently extant) file $rc_file: $!");
        print STDERR "Opened.\n" if $RC_DEBUG;
        local $/ = "\n";
        while (<RC>) 
        {
            next if m/^#/;
            next if m/^\s*$/;
            ($attrib, $val) = m#^\s*(\w+)[\s=]+((?:"[^"]*"|[\S]+)+)#;
            $val =~ s#"([^"]*)"#$1#g;
            print STDERR "parsing $rc_file for '$attrib' = '$val'\n" if $RC_DEBUG;
            die "Error parsing $rc_file for $attrib and $val: $_\n" unless 
                $attrib and defined $val;
            $attrib = validate($attrib);
            $configuration{$attrib} = $val;   
        }
        close RC or die ("Can't close $rc_file");
    }
    return %configuration;
}

sub read_tlg_chronology {
    my $self = shift;
    return if $self->{tlg_chron_info} or $self->{tlg_ordered_filenames}
    or $self->{tlg_ordered_authnums};
    my ($vol, $dir, $file) = File::Spec->splitpath(module_path('Diogenes::Base'));
    my $chron_file = File::Spec->catpath( $vol, $dir, 'tlg-chronology.txt');
    open my $chron_fh, "<$chron_file" or die "Could not open $chron_file: $!";
    local $/ = "\n";
    my $missing = 0;
    while (<$chron_fh>) {
        if (m/^(\d\d\d\d)\s+(.*?)$/) {
            my $num = $1;
            my $date = $2;
            $date =~ s/\s+$//;
            my $filename = $self->{tlg_file_prefix}.$num.$self->{txt_suffix};
            my $path = File::Spec->catpath("", $self->{tlg_dir}, $filename);
            if (-e $path) {
                push @{ $self->{tlg_ordered_filenames} }, $filename;
                push @{ $self->{tlg_ordered_authnums} }, $num;
                $self->{tlg_chron_info}{$num} = $date;
            }
            else {
                $missing++;
                warn "Missing TLG file: $filename\n" if $self->{debug};
            }
        }
        else {
            die "Badly formed line in $chron_file: $_";
        }
    }
    if ($missing) {
        warn "Number of files missing from TLG version E: $missing";
        $self->{tlg_files_missing} = $missing;
    }
}

sub new 
{
    my $proto = shift;
    my $type = ref($proto) || $proto;
    my $self = {};
    bless $self, $type;
    
    my %args;
    my %passed = @_;

    $args{ validate($_) } = $passed{$_} foreach keys %passed;

    my $user_config_dir = get_user_config_dir;
    # For prefs saved by Electron.js and Settings.cgi
    $self->{auto_config} = File::Spec->catfile($user_config_dir, 'diogenes.prefs');
    # For manual editing by the user
    $self->{user_config} = File::Spec->catfile($user_config_dir, 'diogenes.config');
    # For saving user-defined corpora
    $self->{filter_file} = File::Spec->catfile($user_config_dir, 'diogenes.corpora');

    # We just re-read the config file each time.  It would be nice to
    # do this only when needed, but then you need to arrange for
    # communication between one process doing the writing and another
    # doing the reading.

    %{ $self } = ( %{ $self }, %defaults, $self->read_config_files, %args );
    
    my @dirs = qw/tlg_dir phi_dir ddp_dir tll_pdf_dir old_pdf_dir/;

    # Make sure all the directories end in a '/' (except for empty
    # values).
    for my $dir (@dirs) 
    {
        if ($OS eq 'windows') {
            $self->{$dir} = windows_filename($self->{$dir});
        }
        next if $dir eq 'old_pdf_dir';
        $self->{$dir} .= '/' unless $self->{$dir} eq '' or
            $self->{$dir} =~ m#[/\\]$#;
        # print STDERR "--$dir: $self->{$dir}\n";
    }
    
    # Clone values that are references, so we don't clobber what was passed.
    $self->{pattern_list} = [@{$self->{pattern_list}}] if $self->{pattern_list};
    $self->{seen_author_list} = [@{$self->{seen_author_list}}] if $self->{seen_author_list};
    $self->{overflow}     = {%{$self->{overflow}}}     if $self->{overflow};

    $self->{type} = 'tlg' if ref $self eq 'Diogenes_indexed';
    $self->{debug} = 1 if $ENV{Diogenes_Debug};
    
    unless ($self->{type} eq 'none')
    {
        $self->{word_key} = "";
        $self->{current_work} = 0;
        $self->{word_list} = {};
        $self->{auth_num} = 0;
        $self->{work_num} = 0;
        $self->{list_total} = 0;
    }
    print STDERR "\nTYPE: $self->{type}\n" if $self->{debug};
    print STDERR "input_lang: $self->{input_lang}\n" if $self->{debug};
    # Dummy object where no database access is desired -- e.g. to get at 
    # configuration values or to format some Greek input from elsewhere.
    if ($self->{type} eq 'none') 
    {
        $self->{cdrom_dir}   = undef;
        $self->{file_prefix} = "";
    }
    # PHI
    elsif ($self->{type} eq 'phi') 
    {
        $self->{cdrom_dir}   = $self->{phi_dir};
        $self->{file_prefix} = $self->{phi_file_prefix};
        $self->{input_lang} = 'l' unless $self->{input_lang};
    }
    
    # TLG
    elsif ($self->{type} eq 'tlg') 
    {
        $self->{cdrom_dir}   = $self->{tlg_dir};
        $self->{file_prefix} = $self->{tlg_file_prefix};
        $self->{input_lang} = 'g' unless $self->{input_lang};
    }
    
    # DDP
    elsif ($self->{type} eq 'ddp') 
    {
        $self->{cdrom_dir}   = $self->{ddp_dir};
        $self->{file_prefix} = $self->{ddp_file_prefix};
        $self->{input_lang} = 'g' unless $self->{input_lang};
        $self->{documentary} = 1;
    }
    
    # INS
    elsif ($self->{type} eq 'ins') 
    {
        $self->{cdrom_dir}   = $self->{ddp_dir};
        $self->{file_prefix} = $self->{ins_file_prefix};
        $self->{documentary} = 1;
    }
    # CHR
    elsif ($self->{type} eq 'chr') 
    {
        $self->{cdrom_dir}   = $self->{ddp_dir};
        $self->{file_prefix} = $self->{chr_file_prefix};
        $self->{documentary} = 1;
    }
    
    # COP
    elsif ($self->{type} eq 'cop') 
    {
        $self->{cdrom_dir}   = $self->{ddp_dir};
        $self->{file_prefix} = $self->{cop_file_prefix};
        $self->{latin_handler} = \&beta_latin_to_utf;
        $self->{coptic_encoding} = 'beta' if 
            $args{output_format} and $args{output_format} eq 'beta';
        $self->{input_lang} = 'c' unless $self->{input_lang};
    }
    
    # CIV
    elsif ($self->{type} eq 'misc') 
    {
        $self->{cdrom_dir}   = $self->{phi_dir};
        $self->{file_prefix} = $self->{misc_file_prefix};
    }
    # BIB
    elsif ($self->{type} eq 'bib') 
    {
        $self->{cdrom_dir}   = $self->{tlg_dir};
        $self->{file_prefix} = 'doccan';
    }
    else 
    {
        die ("I did not understand the type => $self->{type}\n");
    }

    # For all searches:
    
    if (exists $self->{pattern}
        and not exists $self->{pattern_list})
    {
        $self->{pattern_list} = [$self->{pattern}];
        $self->{min_matches_int} = 1;
    }
    elsif ($self->{pattern})
    {
        push @{ $self->{pattern_list} }, $self->{pattern};
    }
    $self->{word_pattern} = $self->{pattern};

    if ($self->{input_encoding} eq 'BETA code') {
        $self->{input_beta} = 1;
    }
    
    # With Unicode we don't have to guess whether the input is Latin or Greek
    if ($self->{input_encoding} eq 'Unicode') {
        $self->unicode_make_patterns;
    }
    elsif (ref $self eq 'Diogenes::Indexed') 
    {
        $self->{pattern} = $self->simple_latin_to_beta ($self->{pattern});
    }
    elsif (ref $self eq 'Diogenes::Search') 
    {
        if ($self->{input_lang} =~ /^g/i)   
        { 
            $self->make_greek_patterns_translit; 
        }
        elsif ($self->{input_lang} =~ /^l/i) 
        { 
            $self->make_latin_pattern;
        }
    }

    if (defined $self->{cdrom_dir}
        and not -e File::Spec->catfile($self->{cdrom_dir}, 'authtab.dir')
        and -e File::Spec->catfile($self->{cdrom_dir}, 'AUTHTAB.DIR'))
    {
        $self->{uppercase_files} = 1;
    }
    
    # Evidently some like to mount their CD-Roms in uppercase
    if ($self->{uppercase_files})
    {
        $self->{$_} = uc $self->{$_} for 
            qw(file_prefix txt_suffix idt_suffix authtab tlg_file_prefix);
    }

    # This has to come after we have adjusted for uppercase
    if ($self->{type} eq 'tlg' and $self->{tlg_use_chronology}) {
        $self->read_tlg_chronology;
    }

    
    # min_matches_int is for "internal", since we have to munge it here
    $self->{min_matches_int} = '';
    unless (ref $self eq 'Diogenes_indexed')
    {
        $self->{min_matches_int} = $self->{min_matches};
        $self->{min_matches_int} = 1 if $self->{min_matches} eq 'any';
        $self->{min_matches_int} =  scalar @{ $self->{pattern_list} } if 
            $self->{min_matches} eq 'all';
    }
    print STDERR "MM: $self->{min_matches}\n" if $self->{debug};
    print STDERR "MMI: $self->{min_matches_int}\n" if $self->{debug};
    
    $self->{context} = $1 if 
        $self->{context} =~ /(sentence|paragraph|clause|phrase|level|\d+\s*(?:lines?)?)/i;
    $self->{context} = lc $self->{context};
    die "Undefined value for context.\n" unless defined $self->{context};
    die "Illegal value for context: $self->{context}\n" unless 
        $self->{context} =~ 
        m/^(?:sentence|paragraph|clause|phrase|level|\d+\s*(?:lines?)?)$/;
    $self->{numeric_context} = ($self->{context} =~ /\d/) ? 1 : 0;
    print STDERR "Context: $self->{context}\n" if $self->{debug};
    
    # Check for external encoding
    die "You have asked for an external output encoding ($self->{encoding}), "
        . "but I was not able to load a Diognes.map file in which such encodings "
        . "are defined: $Diogenes::Base::map_error \n"  
        if  $self->{encoding} and $Diogenes::Base::map_error;
    die "You have specified an encoding ($self->{encoding}) that does not "
        . "appear to have been defined in your Diogenes.map file.\n\n"
        . "The following Greek encodings are available:\n"
        . (join "\n", $self->get_encodings)
        . "\n\n"
        if $self->{encoding} and not exists $encoding{$self->{encoding}};
    
    # Some defaults       
    if (not $self->{encoding})
    {
        # force encoding Ibycus for repaging output removing hyphens and
        # using TLG non-ascii markers for section references.  PAM 090102
        $self->{encoding} = 'Ibycus' if $self->{output_format} =~ m/repaging/i;
        $self->{encoding} = 'Ibycus' if $self->{output_format} =~ m/latex/i;
        $self->{encoding} = 'Transliteration' if $self->{output_format} =~ m/ascii/i;
        $self->{encoding} = 'UTF-8' if $self->{output_format} =~ m/html/i;
        $self->{encoding} = 'Beta' if $self->{output_format} =~ m/beta/i;
    }
    
    $self->set_handlers;    
    
    print STDERR "Using prefix: $self->{file_prefix}\nUsing pattern(s): ",
    join "\n\n", @{ $self->{pattern_list} }, "\n\n" if $self->{debug};
    print STDERR "Using reject pattern: $self->{reject_pattern}\n" if 
        $self->{debug} and $self->{reject_pattern};
    
    # Read in some preliminary data, except for a dummy object
    if (($self->{type} eq 'none') or ($self->parse_authtab))
    {
        if ($self->{bib_info})
        {
            $self->read_tlg_biblio if $self->{type} eq 'tlg';
            $self->read_phi_biblio if $self->{type} eq 'phi';
        }
    }
    return $self;
}

sub unicode_make_patterns {
    my $self = shift;
    $self->{reject_pattern} = $self->Diogenes::UnicodeInput::unicode_pattern($self->{reject_pattern});
    foreach my $pat (@{ $self->{pattern_list} }) {
        $pat = $self->Diogenes::UnicodeInput::unicode_pattern($pat);
    }
}

# For nicest error handling, run check_db before doing a search to
# make sure current database is accessible
sub check_db
{
    my $self= shift;
    my $file = File::Spec->catfile($self->{cdrom_dir}, $self->{authtab});
    my $check = check_authtab($file);

    if ($check and $self->{type} eq 'phi') {
        # Fix up the case where the "lat" prefix is wrong.
        # Can we find Cicero? If not, try other prefixes
        if (not -e File::Spec->catfile($self->{cdrom_dir}, $self->{file_prefix}.'0474'.$self->{txt_suffix})) {
            my $pre;
            foreach (qw(lat LAT phi PHI)) {
                if (-e File::Spec->catfile($self->{cdrom_dir}, $_.'0474'.$self->{txt_suffix})) {
                    $pre = $_;
                    last;
                }
            }
            if ($pre) {
                $self->{file_prefix} = $pre;
            }
            else {
                warn 'Found authtab, but could not find Cicero!';
            }
        }
        # Inventory of TLG files is done in the chronology code, so we do a
        # quick check of the PHI files here.
        my ($vol, $dir, $file) = File::Spec->splitpath(module_path('Diogenes::Base'));
        my $phi_file_list = File::Spec->catpath( $vol, $dir, 'phi_files.txt');
        open my $phi_fh, "<$phi_file_list" or die "Could not open $phi_file_list: $!";
        local $/ = "\n";
        my $missing = 0;
        my $damaged = 0;
        while (<$phi_fh>) {
            if (m/^(\d\d\d\d)\t(.*?)$/) {
                my $num = $1;
                my $len = $2;
                my $filename = $self->{file_prefix}.$num.$self->{txt_suffix};
                my $path = File::Spec->catpath("", $self->{phi_dir}, $filename);
                if (-e $path) {
                    unless (-s $path == $len) {
                        $damaged++;
                        warn "Apparently damaged PHI file: $filename";
                    }
                }
                else {
                    $missing++;
                    warn "Missing PHI file: $filename\n" if $self->{debug};
                }
            }
            else {
                die "Badly formed line in $phi_file_list: $_";
            }
        }
        if ($missing) {
            warn "Number of files missing from PHI Latin database: $missing";
            $self->{phi_files_missing} = $missing;
        }       
        if ($damaged) {
            warn "Number of files damaged in PHI Latin database: $damaged";
            $self->{phi_files_damaged} = $damaged;
        }       
    }
    return $check;
}


# Returns tlg, phi or ddp (or '' if not extant or recognized).  Class method.
sub check_authtab
{
    my $file = shift;
    if (-e $file)
    {
        open AUTHTAB, "<$file" or warn ("Can't open (apparently extant) file $file: $!");
        my $buf;
        read AUTHTAB, $buf, 4;
        $buf =~ s/^\*//;
        $buf = lc $buf;
        $buf = 'phi' if $buf eq 'lat';
        $buf = 'ddp' if $buf eq 'ins' or $buf eq 'chr' or $buf eq 'cop';
        return $buf if $buf eq 'tlg' or $buf eq 'phi' or $buf eq 'ddp';
        return '';
    }
    return '';
}

sub set_handlers
{
    my $self = shift;
    
    if ($self->{encoding} =~ m/Beta/i)
    {
        $self->{greek_handler} = sub { return shift };
        $self->{latin_handler} = sub { return shift };
    }
    elsif ($self->{encoding} =~ m/Ibycus/i)
    {
        print STDERR "Ibycus encoding\n" if $self->{debug};
        $self->{greek_handler} = sub { beta_encoding_to_ibycus($self, shift)} ;
        $self->{latin_handler} = \&beta_encoding_to_latin1;
    }
    elsif ($self->{encoding} =~ m/Transliteration/i)
    {
        print STDERR "Transliteration encoding\n" if $self->{debug};
        $self->{greek_handler} = sub { beta_encoding_to_transliteration($self, shift)} ;
        $self->{latin_handler} = \&beta_encoding_to_latin1;
    }
    elsif ($self->{encoding} =~ m/ISO_8859_7/i)
    {
        $self->{greek_handler} = sub { beta_encoding_to_external($self, shift) }; 
        $self->{latin_handler} = sub { return shift };
    }
    elsif ($self->{encoding} =~ m/Babel/i)
    {
        $self->{greek_handler} = sub { beta_encoding_to_external($self, shift) }; 
        $self->{latin_handler} = \&beta_encoding_to_latin_tex;
    }
    elsif ($self->{encoding} =~ m/utf/i)
    {
        $self->{greek_handler} = sub { beta_encoding_to_external($self, shift) }; 
        $self->{latin_handler} = \&beta_latin_to_utf;
    }
    # The fall-back
    elsif (defined $encoding{$self->{encoding}})
    {
        $self->{greek_handler} = sub { beta_encoding_to_external($self, shift) }; 
        $self->{latin_handler} = \&beta_encoding_to_latin1;
    }
    else 
    {
        die "I don't know what to do with $self->{encoding}!\n";
    }

    $self->{perseus_morph} = 0 ; 
    $self->{perseus_morph} = 1 if 
        $self->{perseus_links} and $self->{output_format} =~ m/html/; 
    $self->{perseus_morph} = 0 if $self->{type} eq 'cop';
    $self->{perseus_morph} = 0 if $self->{encoding} =~ m/babel/i;
    
#       if ($self->{output_format} =~ m/html/i)
#       {
#               # Note that null chars need to stay in until the html or whatever is done.
#               # We make this a no-op instead of generating latin-1, because Netscape under
#               # Windows doesn't handle those chars properly with a Unicode font.
##              $self->{latin_handler} = sub {return shift };
#               $self->{latin_handler} = sub { beta_encoding_to_html($self, shift) };
#       }
#       if ($self->{output_format} =~ m/ascii/i)
#       {
#               $self->{latin_handler} = sub { beta_encoding_to_latin1(shift) };
#       }

}

# Restricts the authors and works according to the settings passed,
# and returns the relevant authors and works.
sub select_authors 
{
    my $self = shift;
    my %passed = @_;
    my (%args, %req_authors, %req_a_w, %req_au, %req_auth_wk);
    my ($file, $baseline);
    
    $self->parse_lists if $self->{type} eq 'tlg' and not %list_labels;
    
    # A call with no params returns all authors.
    return $auths{$self->{type}} if (! %passed); 
    
    # This is how we get the categories into which the TLG authors are divided
    die "Only the TLG categorizes text by genre, date, etc.\n" 
        if $passed{'get_tlg_categories'} and $self->{type} ne 'tlg';
    return \%list_labels if $passed{'get_tlg_categories'};
    
    my @universal = (qw(criteria author_regex author_nums select_all previous_list) );
    my @other_attr = ($self->{type} eq 'tlg') ? keys %list_labels : ();
    my %valid = map {$_ => 1} (@universal, @other_attr);
    my $valid = sub 
    {
        my $key = shift;
        $key =~ s/-?(\w+)/\L$1/;
        return $key if exists $valid{$key};
        die ("I did not understand the parameter: $key\n");
    };
    
    $args{ $valid->($_) } = $passed{$_} foreach keys %passed;
    
    if ($args{'select_all'}) 
    {
        undef $self->{req_authors};
        undef $self->{req_auth_wk};
        undef $self->{filtered};
        undef @ARGV;
        return $auths{$self->{type}};
    }
    
    $self->{filtered} = 1;
    foreach my $k (keys %args) 
    {
        print STDERR "$k: $args{$k}\n" if $self->{debug};
        if ($k eq 'criteria') 
        {
            # do nothing
        }
        elsif ($k eq 'author_regex') 
        {
            $req_authors{ $_ }++ foreach
                keys %{ $self->match_authtab($args{$k}) };
        }                
        elsif ($k eq 'date') 
        {
            my ($start_date, $end_date, $var_flag, $incert_flag) = @{ $args{$k} };
            my ($start, $end, $varia, $incertum);
            my $n = 0;
            foreach (@{ $list_labels{date} })
            {
                $start = $n if $_ eq $start_date;
                $end = $n if $_ eq $end_date;
                $varia = $n if $_ =~ /vari/i;
                # Note the space at the end of Incertum
                $incertum = $n if $_ =~ /incert/i;
                $n++;
            }
            $start = 0 if $start_date =~ /--/;
            $end = length @{ $list_labels{date} } - 1 if $end_date =~ /--/;
            my @dates = ($start .. $end);
            push @dates, $varia if $var_flag;
            push @dates, $incertum if $incert_flag;
            
            foreach my $date (@{ $list_labels{date} }[@dates]) 
            {
                $req_authors{$_}++ foreach @{ $lists{'date'}{$date} };
            }
        }
        
        elsif ($k eq 'author_nums') 
        {
            if (ref $args{$k} eq 'ARRAY')
            {
                foreach my $a (@{ $args{$k} }) 
                {
                    my $auth = sprintf '%04d', $a;
                    $req_authors{$auth}++ ;
                }
            }
            elsif (ref $args{$k} eq 'HASH')
            {
                foreach my $a (keys %{ $args{$k} })
                {
                    my $auth = sprintf '%04d', $a;
                    $req_authors{$auth}++, next unless ref $args{$k}{$a};
                    $self->{check_word_stats} = 1;
                    foreach my $w (@{ $args{$k}{$a} })
                    {
                        my $work = sprintf '%03d', $w;
                        $req_auth_wk{$auth}{$work}++;
                    }
                }
            }
            else { die 'Error on parsing author_nums parameter' }
        }
        
        elsif ($k eq 'previous_list') 
        {
            die "You asked for a subset of the previous list, ".
                "but I have no record of such." unless $self->{prev_list};
            
            my ($au, $wk);
            foreach my $index (@{ $args{$k} }) 
            {
                die "You seem to have pointed to a non-extant ".
                    "member of the previous list" unless $self->{prev_list}[$index];
                if (ref $self->{prev_list}[$index]) 
                {
                    $self->{check_word_stats} = 1;
                    ($au, $wk) = @{ $self->{prev_list}[$index] };
                    $req_auth_wk{$au}{$wk}++;
                }
                else
                {
                    $au = $self->{prev_list}[$index];
                    $req_authors{$au}++;    
                }
            }
            delete $self->{prev_list};
        }

        else 
        {
            undef %req_au;
            undef %req_a_w;
            foreach my $x (map $lists{$k}{$_},  @{ $args{$k} }) 
            {
                if (ref $x eq 'ARRAY') 
                {
                    $req_au{$_}++ foreach @{ $x };
                }
                elsif (ref $x eq 'HASH')
                {
                    $self->{check_word_stats} = 1;
                    foreach my $au (keys %{ $x }) 
                    {
                        $req_a_w{$au}{$_}++ foreach @{ $x->{$au} };
                    }
                }
                else {  die "Error parsing argument $k => (". 
                            (join ', ', @{ $args{$k} }) .")"; }
            }
            
            # Eliminate duplicate hits on same author or work as selected via
            # different values of the same criterion
            $req_authors{$_}++ foreach keys %req_au;
            foreach my $au (keys %req_a_w) 
            {
                $req_auth_wk{$au}{$_}++ foreach keys %{ $req_a_w{$au} };
            }
        }
    }       
    
    # This makes `or' rather than `and' the default.  Better?
    $args{'criteria'} = 1 unless exists $args{'criteria'};
    $args{'criteria'} = ((keys %args) - 1) if 
        $args{'criteria'} =~ m/all/i; #the 1 is 'criteria' itself
    $args{'criteria'} = 1 if $args{'criteria'} =~ m/any/i;
    print STDERR "Criteria: ", $args{criteria}, "\n" if $self->{debug};
    
    # Eliminate auths & works that don't meet enough criteria
    undef $self->{req_auth_wk};
    undef $self->{req_authors};
    foreach (keys %req_authors) 
    {
        $self->{req_authors}{$_}++ if $req_authors{$_} >= $args{'criteria'};
    }               
    foreach my $au (keys %req_auth_wk) 
    {
        next if $self->{req_authors}{$au}; # already added to the list
        foreach my $wk ( keys %{ $req_auth_wk{$au} } ) 
        {
            local $^W;
            $self->{req_auth_wk}{$au}{$wk}++ if 
                ((0 + $req_authors{$au}) + (0 + $req_auth_wk{$au}{$wk}) 
                 >= $args{'criteria'});
        }
    }
    print STDERR Data::Dumper->Dump ([\$self->{req_authors}, \$self->{req_auth_wk}], 
                                     ['req_authors', 'req_auth_wk']) if $self->{debug};

    # NB. This is where we set up searches restricted by author.
    # Searches restricted by author/work are handled in Search.pm.  If
    # you mix both types of restriction (which the GUI does not
    # allow), the searches will be separate and sequential, which may
    # look odd from a chronological point of view.  So don't do that.

    @ARGV = ();
    # Only put into @ARGV those files we want to search in their entirety!
    if ($self->{tlg_use_chronology} and $self->{type} eq 'tlg') {
        # Do chronological sort of authors for TLG
        foreach my $num (@{ $self->{tlg_ordered_authnums} }) {
            my $short_num = $num;
            $short_num =~ s/^0+//g;
            if (exists $self->{req_authors}{$num} or exists $self->{req_authors}{$short_num}) {
                push @ARGV, $self->{tlg_file_prefix} . (sprintf '%04d', $num) . $self->{txt_suffix};
            }
        }
    }
    else {
        foreach my $au (keys %{ $self->{req_authors} }) {
            $file = $self->{file_prefix} . (sprintf '%04d', $au) . $self->{txt_suffix};
            push @ARGV, $file;
        }
    }

    # print "\nusing \@ARGV: ", Data::Dumper->Dump ([\@ARGV], ['*ARGV']);
    warn "There were no texts matching your criteria" unless 
        @ARGV or $self->{req_auth_wk};
    
    return unless wantarray;
    
    # return auth & work names
    my ($basename, @ret);
    my $index = 0;
    my @ordered_authors = ();
    if ($self->{tlg_use_chronology} and $self->{type} eq 'tlg') {
        foreach my $num (@{ $self->{tlg_ordered_authnums} }) {
            if (exists $self->{req_authors}{$num}) {
                push @ordered_authors, $num;
            }
        }
    }
    else {
        @ordered_authors = sort numerically keys %{ $self->{req_authors} };
    }

    foreach my $auth (@ordered_authors)
    {
        my $formatted_auth = $auths{$self->{type}}{$auth};
        $self->format_output(\$formatted_auth, 'l');
        push @ret, $formatted_auth;
        $self->{prev_list}[$index++] = $auth;
    }

    @ordered_authors = ();
    if ($self->{tlg_use_chronology} and $self->{type} eq 'tlg') {
        foreach my $num (@{ $self->{tlg_ordered_authnums} }) {
            if (exists $self->{req_auth_wk}{$num}) {
                push @ordered_authors, $num;
            }
        }
    }
    else {
        @ordered_authors = sort numerically keys %{ $self->{req_auth_wk} };
    }

    foreach my $auth (@ordered_authors)
    {
        $basename = $auths{$self->{type}}{$auth};
        $self->format_output(\$basename, 'l');
        my $real_num = $self->parse_idt($auth);
        foreach my $work ( sort numerically keys %{ $self->{req_auth_wk}{$auth} } ) 
        {
            my $wk_name = $work{$self->{type}}{$real_num}{$work};
            $self->format_output(\$wk_name, 'l');
            push @ret, "$basename: $wk_name";
            $self->{prev_list}[$index++] = [$auth, $work];
        }
    }
    return @ret;
}

sub do_format
{
    my $self = shift;
    $self->begin_boilerplate;
    
    die "You must specify an input_source for do_format!\n" unless $self->{input_source};
    die "input_source should be a reference!\n" unless ref $self->{input_source};
    my $input = $self->{input_source};
    my $ref = ref $input;
    my $inp;
    if ($ref eq 'SCALAR')
    {
        $inp = $input;
        $self->format_output(\$inp);
        print $inp;
    }
    elsif ($ref eq 'ARRAY')
    {
        for (@{$input})
        {
            my $inp = $_;
            $self->format_output(\$inp);
            print $inp;
        }
    }
    elsif ($ref eq 'CODE')
    {
        while ($input->())
        {
            my $inp = $_;
            $self->format_output(\$inp);
            print $inp;
        }
    }
    else
    {
        local $/ =  "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n";
        my $holder = $self->{latex_counter};
        $self->{latex_counter} = 0;
        while (<$input>)
        {
            my $inp = $_;
            $self->format_output(\$inp);
            print $inp;
        }
        $self->{latex_counter} = $holder;
    }
    
    $self->end_boilerplate;
    
}

sub get_encodings
{
    return sort keys %encoding;
}

sub encode_greek
{
    my ($self, $enc, $ref) = @_;
    my $old_encoding = $self->{encoding};
    $self->{encoding} = $enc;
    $self->set_handlers;
    $self->greek_with_latin($ref);
    $$ref =~ s/\x03\x01/"/g;
    $$ref =~ s/\x03\x02/%/g;
    $$ref =~ s/\x03\x03/_/g;
    $self->{encoding} = $old_encoding;
    $self->set_handlers;
}


###############################################################################
#-----------------------------------------------------------------------------#
#---------------- Only private subs and methods below ------------------------#
#-----------------------------------------------------------------------------#
###############################################################################

#########################################################################
#                                                                       #
# Parse list3cla.bin, etc. for genre, date, etc. info.  Only useful for #
# tlg searches.                                                         #
#                                                                       #
#########################################################################

sub parse_lists 
{
    my $self = shift;
    my @tlg_class_files = 
        ( qw(list3cla.bin list3clx.bin list3dat.bin list3epi.bin 
             list3fem.bin list3geo.bin) );
    my @tlg_classifications = 
        ( qw(genre genre_clx date epithet gender location) );
    if ($self->{uppercase_files}) 
    {
        @tlg_class_files = map {uc($_)} @tlg_class_files ;
    }
    
    my ($base_ptr, $ptr, $label, $j, $ord, $auth_num, @works, $old);
    my ($type, $high);
    my $d = 0;
    foreach my $file (@tlg_class_files) 
    {
        $type = shift @tlg_classifications;
        
        open BIN, "<$self->{cdrom_dir}$file" or die ("couldn't open $file: $!");
        binmode BIN;
        local $/;
        undef $/;
        
        my $buf = <BIN>;
        
        $base_ptr = unpack 'N', substr ($buf, 0, 4);
        my $i = 4;
        
        while ($i <= length $buf) 
        {
            $ptr = $base_ptr + unpack 'N', substr ($buf, $i, 4);
            $i += 4;
            
            last if ord (substr ($buf, $i, 1)) == 0;
            
            $label = Diogenes::Base::get_pascal_string(\$buf, \$i);       
            $self->beta_formatting_to_ascii(\$label, 'l') if $type eq 'date';
            $i++;
            push @{ $list_labels{$type} }, $label;
            $j = $ptr;
            $ord = ord (substr ($buf, $j, 1));
            
            until ($ord == 0) 
            {
                $auth_num = (unpack 'n', substr ($buf, $j, 2)) & hex '7fff';
                $auth_num = sprintf '%04d', $auth_num;
                $j += 2;
                $ord = ord (substr ($buf, $j, 1));
                
                if ( ($ord & hex '80') or ($ord == 0) ) 
                {
                    push @{ $lists{$type}{$label} }, $auth_num;
                    next;
                }
                @works = ();
                $old = 0;       
                until ( ($ord & hex '80') or ($ord == 0) ) 
                {
                    if ( $ord < hex '20' ) 
                    {
                        push @works, $ord;
                        $old = $ord;
                    }
                    elsif ( $ord == hex '20' ) 
                    {
                        warn("Ooops while parsing $file at $j") if $ord & hex '20';
                    }
                    elsif ( $ord < hex '40' ) 
                    {
                        push @works, (($old + 1) .. ($old + ($ord & hex '1f')));
                        $old = 0;
                    }
                    elsif ( $ord < hex '60' ) 
                    {
                        warn("Ooops while parsing $file at $j\n") if $ord & hex '20';
                        $high = ($ord & hex '01') << 8; 
                        $j++;
                        $ord = ord (substr ($buf, $j, 1));
                        $old = $high + $ord;
                        push @works, $old;
                    }
                    elsif ( $ord == hex '60' ) 
                    {
                        $j++;
                        $ord = ord (substr ($buf, $j, 1));
                        push @works, (($old + 1) .. ($ord + 1));
                    }
                    else 
                    {
                        warn("Oops while parsing $file at $j");
                    }
                    
                    $j++;
                    $ord = ord (substr ($buf, $j, 1));
                }
                push @{ $lists{$type}{$label}{$auth_num} }, 
                map {sprintf '%03d', $_ } @works;
            }
        }
        close BIN;
    }
}

######################################################################
#                                                                    #
# Parse the author names in authtab.dir and store the                #
# matches as a reference to a hash keyed by author numbers.  Also    #
# determines the fundamental language of each text file.             #
#                                                                    #
######################################################################

sub parse_authtab 
{
    my $self = shift;
    my $prefix = "\U$self->{file_prefix}\E";
    my (%authtab_entry, $file_num, $base_lang);
    
    # Maybe CD-Rom is not mounted yet
    return undef unless -e $self->{cdrom_dir}.$self->{authtab};
    
    open AUTHTAB, $self->{cdrom_dir}.$self->{authtab} or 
        $self->barf("Couldn't open $self->{cdrom_dir}$self->{authtab}");
    binmode AUTHTAB;
    local $/ = "\xff";
    
    my $regexp = qr!$prefix(\w\w\w\d)\s+([\x01-\x7f]*[a-zA-Z][^\x83\xff]*)!;
    
    while (my $entry = <AUTHTAB>)
    {
        # get new base language if this is a new prefix group: e.g. *CIV.
        $base_lang = $1 if $entry =~ m/^\*$prefix[^\x83]*\x83(\w)\xff/;
        # English uses the Latin alphabet, or so I've heard.
        # Don't know what to do with Hebrew yet.
        $base_lang = 'l' if defined $base_lang and ($base_lang eq 'e'
                                                    or $base_lang eq 'h');
        
        # get auth num and name
        my ($file_num, $name) = $entry =~ $regexp;
        next unless defined $file_num;
        $file_num =~ tr/A-Z/a-z/; # doccanx.txt
        # Get rid of non-ascii stuff
        $name =~ s#[\x80-\xff]+# #g;
        #$self->format_output (\$name, 'l'); #no, no here, takes too much time
        
        $authtab_entry{$file_num} = $name; 
        
        # get deviant lang, if any, of this particular entry 
        my ($lang) = $entry =~ m/\x83(\w)/;
        $lang = 'l' if defined $lang and ($lang eq 'e' or $lang eq 'h');
        $lang{$self->{type}}{$file_num} = (defined $lang) ? $lang : $base_lang;
    }
    if (keys %authtab_entry == 0 and $self->{type} ne 'bib')
    {
        warn "No matching files found in authtab.dir: \n",
        "Is $prefix the correct file prefix for this database?\n";
        return undef;
    }
    close AUTHTAB;
#     print STDERR %authtab_entry if $self->{debug};
    #print STDERR Dumper $lang if $self->{debug};
    
    $auths{$self->{type}} = \%authtab_entry;
    return 1;
}

# Extract a given pattern from the authtab info read in above
sub match_authtab
{
    my $self = shift;
    my $big_pattern = shift;
    utf8_to_beta_encoding(\$big_pattern);
    $big_pattern ||= '.';            # Avoid warnings on null pattern
    my %total = ();
    my %match;
    $self->parse_authtab unless $auths{$self->{type}};
    die "Unable to get author info from the authtab.dir file!\n" unless 
        $auths{$self->{type}};

    for my $pattern (split /[\s,]+/, $big_pattern)
    {
        print STDERR "pattern: $pattern\n" if $self->{debug};

        if ($pattern =~ /\D/)
        {       # Search values (auth names)
            %match = map { $_ => $auths{$self->{type}}{$_} }
            grep $auths{$self->{type}}{$_} =~ /$pattern/i,
            keys %{ $auths{$self->{type}} };
        }
        elsif ($pattern =~ /\d+/)
        {       # Search keys (auth nums)
            $pattern = sprintf '%04d', $pattern; 
            %match = map { $_ => $auths{$self->{type}}{$_} }
            grep /$pattern/, keys %{ $auths{$self->{type}} };
        }
        (%total) = (%total, %match);
    }
    # Strip formatting
    $self->format_output(\$total{$_}, 'l') for keys %total;
    return \%total;
}


######################################################################
#                                                                    #
# Method to extract the author, work and label info from an idt file #
# -- the info goes into globals %author, %work and %level_label,     #
# keyed by type of search -- may be reused in subsequent searches.   #
#                                                                    #
######################################################################

sub parse_idt 
{
    my ($self, $au_num) = @_;
    my ($lev, $str, $auth_num, $author_name, $work_num, $work_name, $old_work_num);
    my ($sub_work_abbr, $sub_work_name, $code, $desc_lev, $start_block, $first_byte);
    my ($subsection, $current_block, $block);
    $current_block = 0;
    
    $self->{current_lang} = $lang{$self->{type}}{$au_num};
    $self->{current_lang} = 'l' if $self->{type} eq 'bib';
    $self->{current_lang} = 'g' if $self->{type} eq 'cop';
    
    # Don't read again (except for CIV texts, where $au_num is not a number)
    return $au_num if exists $author{$self->{type}}{$au_num}; 
    
    # This file must be read via unbuffered system I/O if it is to be interwoven
    # between successive reads of .txt files from <ARGV>.  Otherwise this flushes 
    # the .txt files out of the I/O cache and hugely increases search times.
    
    # We therefore do not want to overwrite buf, which may now contain the
    # contents of the corresponding .txt file, so we use idt_buf
    # instead.
    my $file = $self->{file_prefix} . $au_num . $self->{idt_suffix};
    my $i; 
    my $idt_buf = '';
    
    unless (sysopen IDT, $self->{cdrom_dir}.$file, 0) {
        print "IDT File Missing!\n";
        $self->barf("Could not open $self->{cdrom_dir}$file - $!");
        return;
    }   
    binmode IDT;
    
    while (my $len = sysread IDT, $idt_buf, 8192, length $idt_buf) 
    {
        if (!defined $len) 
        {
            next if $! =~ /^Interrupted/;
            $self->barf ("System read error on $self->{cdrom_dir}.$file: $!\n");
        }
    }
    my $end = length $idt_buf;
    close IDT or warn "Could not close $file";
    
    undef $old_work_num;
    for ($i = 0; ($i < $end); $i++) 
    {
        $code = ord (substr ($idt_buf, $i, 1));
        
        last if ($code == 0);           # eof
        
        if ($code == 1 or $code == 2) 
        {       # new author or work
            $subsection = 0;
            undef %{ $self->{level} };
            $i += 2;
            $first_byte = ord (substr $idt_buf, ++$i, 1) << 8;
            $start_block = $first_byte + ord (substr $idt_buf, ++$i, 1);
            
            if (ord (substr ($idt_buf, ++$i, 1)) == hex ("ef")) 
            {
                $lev = (ord (substr ($idt_buf, ++$i, 1))) & MASK;
                $str = get_ascii_string( \$idt_buf, \$i );
                if ($lev == 0) 
                {
                    $auth_num = $str;
                    $last_work{$self->{type}}{$auth_num} = 0;
                    # The misc files (CIV000x on the LAT disk) have an
                    # alphabetic string here, rather than the number, so now
                    # be careful not to assume that $auth_num is a number.
                    if ((ord (substr ($idt_buf, ++$i, 1)) == hex ("10")) &&
                        ((ord (substr ($idt_buf, ++$i, 1))) == hex ("00"))) 
                    {
                        $i++;
                        $author_name = get_pascal_string( \$idt_buf, \$i );
                        $author{$self->{type}}{$auth_num} = $author_name;
                    } 
                    else 
                    { 
                        $self->barf("Author number apparently was not followed by".
                                    " author name in idt file $file");
                    }
                }
                elsif ($lev == 1) 
                {
                    $work_num = $str;
                    $last_work{$self->{type}}{$auth_num} = $work_num 
                        if $work_num > $last_work{$self->{type}}{$auth_num};
                    if      ((ord (substr ($idt_buf, ++$i, 1))  == hex ("10")) &&
                             ((ord (substr ($idt_buf, ++$i, 1))) == hex ("01"))) 
                    {
                        $i++;
                        $work_name = get_pascal_string( \$idt_buf, \$i );
                        $work{$self->{type}}{$auth_num}{$work_num} = $work_name; 
                        
                        $work_start_block{$self->{type}}
                        {$auth_num}{$work_num} = $start_block;
                        
                        # Get the level labels
                        if ($self->{type} eq 'misc' and defined $old_work_num)
                        {
                            # For CIV texts, only level labels that change are listed
                            # explicitly, so we must preinitialize them.
                            $level_label{$self->{type}}
                            {$auth_num}{$work_num} =
                            { % {$level_label{$self->{type}}
                                 {$auth_num}{$old_work_num}} };
                        }
                        while (ord (substr ($idt_buf, ++$i, 1)) == hex("11")) 
                        {
                            $desc_lev = ord (substr ($idt_buf, ++$i, 1));
                            $i++;
                            $level_label{$self->{type}}
                            {$auth_num}{$work_num}{$desc_lev} =
                                get_pascal_string( \$idt_buf, \$i ); 
                        }
                        $i--;           # went one byte too far
                        $old_work_num = $work_num;
                    } 
                    else 
                    { 
                        $self->barf("Work number apparently was not followed by work 
                                                name in idt file $file")
                    }
                    
                    if ($self->{documentary})
                    {
                        $level_label{$self->{type}}
                        {$auth_num}{$work_num}{5} =
                            delete $level_label{$self->{type}}
                        {$auth_num}{$work_num}{0};
                    }
                } 
                elsif ($lev == 2) 
                {       # Trap this for now
                    $self->barf ("Hey! I found a sub-work level in idt file $file");
                    
                    # The real code should look something like this:        
                    $sub_work_abbr = $str;
                    if (ord (substr ($idt_buf, ++$i, 2)) == hex '1002') 
                    {
                        $i++;
                        $sub_work_name = get_pascal_string( \$idt_buf, \$i );
                        $sub_works{$self->{type}}{$auth_num}{$work_num}{$sub_work_abbr} = $sub_work_name; 
                    } 
                    else 
                    { 
                        $self->barf(
                            "Sub-work number apparently was not followed by sub-work name in idt file $file")
                    }
                }
                else 
                {
                    $self->barf (
                        "I don't understand level $lev after \0xef in idt file $file.")
                }
            }
            else 
            {
                $self->barf ("I see a new author or a new work in ".
                             "idt file $file, but it is not followed after 5 ".
                             "bytes by \\0xef.");
            }
        } 
        elsif ($code == 3)
        {
            # Get the starting blocks of each top-level subsection    
            $block = (ord (substr $idt_buf, ++$i, 1) << 8) + ord (substr $idt_buf, ++$i, 1);
            warn("Error.  New section not followed by beginning ID")
                unless ord (substr $idt_buf, ++$i, 1) == 8;
            $i++;
            while ((my $sub_code = ord (substr ($idt_buf, $i, 1))) >> 7)
            {
                parse_bookmark($self, \$idt_buf, \$i, $sub_code);
                $i++;
            }
            $i--;           # went one byte too far
            my $top_level = (sort {$b <=> $a} keys %{ $self->{level} })[0];
            $top_levels{$self->{type}}{$auth_num}{$work_num}[$subsection] = 
                [$self->{level}{$top_level}, $block];
            $subsection++;
            
            # NB. This resynchronization is necessary for the TLG, not the PHI
            $current_block = $block;
        }
        elsif ($code == 10)
        {
            $i++;
            while ((my $sub_code = ord (substr ($idt_buf, $i, 1))) >> 7)
            {
                parse_bookmark($self, \$idt_buf, \$i, $sub_code);
                $i++;
            }
            $i--;           # went one byte too far
            $last_citation{$self->{type}}{$auth_num}{$work_num}{$current_block} 
            = {%{ $self->{level} }};
            $current_block++;
        }
        elsif ($code == 11 or $code == 13) 
        {   # "Exceptions" -- which we ignore
            $i += 2;
        }
        
        # do nothing in the other cases
        
    } # end of for loop
    
#       use Data::Dumper;
#       print Dumper $top_levels{$self->{type}}{$auth_num};
#       print Dumper $last_citation{$self->{type}}{$auth_num};
#       print "$auth_num => $current_block \n"
#        if ($current_block +1 << 13) != -s "$self->{cdrom_dir}$self->{file_prefix}$auth_num.txt";
    return $auth_num;
}



####################################################################
#                                                                  #
# Subroutine to get a string from $$buf until a \xff is hit,       #
# starting at $i.                                                  #
#                                                                  #
####################################################################

sub get_ascii_string 
{
    my ($buf, $i) = @_;
    my $char;
    my $string = "";
    until ((ord ($char = substr ($$buf, ++$$i, 1))) == hex("ff") or $$i > length $$buf)
    {
        $string .= chr ((ord $char) & MASK);
    }
    return $string
}


###############################################################
#                                                             #
# Subroutine to extract pascal-style strings with the         #
# length byte first (used for list.bin files).                #
#                                                             #
###############################################################

sub get_pascal_string 
{
    my ($buf, $i) = @_;
    my $str = "";
    my $len = ord (substr ($$buf, $$i, 1));
    for ($$i++; $len > 0; $$i++, $len--) 
    {
        $str .= chr (ord (substr ($$buf, $$i, 1)));
    }
    $$i--;  # went one byte too far
    return $str;
}

sub read_tlg_biblio
{
    # Only reads in file, too massive to parse now
    my $self = shift;
    $self->{print_bib_info} = 1;
    return if $bibliography;
    local $/;
    undef $/;
    my $filename = "$self->{cdrom_dir}doccan2.txt";
    my $Filename = "$self->{cdrom_dir}DOCCAN2.TXT";
    open BIB, $filename or open BIB, $Filename or die "Couldn't open $filename: $!";
    binmode BIB;
    $bibliography = <BIB>;
    close BIB, $filename or die "Couldn't close $filename: $!";
}

sub read_phi_biblio
{
    # Read and parses file
    my $self = shift;
    my $filename = "$self->{cdrom_dir}$self->{file_prefix}9999.txt";
    if (-e "$filename")
    {
        local undef $/;
        open PHI_BIB, $filename or die "Couldn't open $filename: $!";
        binmode PHI_BIB;
        my $canon = <PHI_BIB>;
        while ($canon =~ m/([^{]+)\{\`?(\d\d\d\d)\.(\d\d\d)\}/g)
        {
            my ($info, $auth, $work) = ($1, $2, $3);
            $info =~ s/[\x80-\xff][\@\s\x80-\xff]*/\n/g;
            $info =~ s/\n+/\n/g;
            $info =~ s/^[\n\s]+//;
            $info .= ' ('.$auth.': '.$work.')';
            $info .="\n" unless $info =~ m/\n$/;
            $self->{phi_biblio}{$auth}{$work} = $info;
        }
        close PHI_BIB, $filename or die "Couldn't close $filename: $!";
        $self->{print_bib_info} = 1;
    }
    else
    {
        print STDERR "PHI Canon ($filename) not found!" if $self->{debug};
    }
}

sub get_biblio_info
{
    my ($self, $type, $auth, $work) = @_;
    
    return $self->get_tlg_biblio_info($auth, $work) if $type =~ m/tlg/i;
    if (exists $self->{phi_biblio}{$auth}{$work})
    {
	return $self->{phi_biblio}{$auth}{$work} if $type =~ m/phi/i ;
    }
    return ' ('.$auth.': '.$work.')';
}


sub get_tlg_biblio_info
{
    # Looks for a single work, memoizes result
    my ($self, $auth, $work) = @_;
    return undef unless $bibliography;
    return $self->{biblio_details}{$auth}{$work}    
    if exists $self->{biblio_details}{$auth}{$work};
    
    my ($info) = $bibliography =~ 
        m/key $auth $work (.+?)[\x90-\xff]*key/;
     return $work{$self->{type}}{$self->{auth_num}}{$self->{work_num}}
         unless $info;
    my %data;
    my @fields = qw(wrk tit edr pla pub pyr ryr ser pag);
    foreach my $field (@fields)
    {
        while 
            ($info =~ 
             m/[\x80-\x8f]?$field ([\x00-\x7f]*(?:[\x80-\x8f]    [\x00-\x7f]+)*)?\s?[\x80-\x8f]?/g)
            
        {
            my $datum = $1 || '';
            $datum =~ s/\s*$//;                     # trailing spaces
            $datum =~ s/[\x80-\x8f]    //g; # long lines
            $data{$field} .= $data{$field} ? ", $datum" : $datum;
        }
    }
    my $chron = ($self->{tlg_chron_info}) ? $self->{tlg_chron_info}{$self->{auth_num}} : '';
    if ($chron eq 'Varia' or $chron eq 'Incertum') {
        $chron = ' (' . $chron . '), ';
    }
    elsif ($chron) {
        $chron = ' (c. ' . $chron . '), '
    }

    $self->{biblio_details}{$auth}{$work} = 
        join '', (
            "$author{$self->{type}}{$self->{auth_num}}",
            $chron,
            ($data{wrk}) ? "$data{wrk}\&" : '' ,
            ' ('.$self->{auth_num}.': '.$self->{work_num}.')',
            ($data{tit}) ? "\n\"$data{tit}\&\"" : '' ,
            ($data{edr}) ? ", Ed. $data{edr}\&" : '' , 
            ($data{pla}) ? "\n$data{pla}\&" : '' ,
            ($data{pub}) ? ": $data{pub}\&" : '' ,
            ($data{pyr}) ? ", $data{pyr}\&" : '' ,
            ($data{ryr}) ? ", Repr. $data{ryr}\&" : '' ,
            ($data{ser}) ? "; $data{ser}\&" : '' ,
#                       ($data{pag}) ? ", $data{pag}\&" : '',
            '.');
    return $self->{biblio_details}{$auth}{$work};
}


###################################################################
#                                                                 #
# Method to get the author and work numbers and to update the     #
# bookmarks in %level while reading from a .txt file block.       #
#                                                                 #
###################################################################

sub parse_non_ascii 
{
    my ($auth_abbr, $work_abbr, $lev, $str);
    my ($new_auth_num, $new_work_num, $code);
    my ($self, $buf, $i) = @_;
    undef $self->{special_note};
    
    # Parse all of the non-ascii data in this block
    while (($code = ord (substr ($$buf, $$i, 1))) >> 7)
    {
#         printf STDERR "Code: %x \n", $code if $self->{debug};
        # Ok. This is legacy code from when I was trying to understand the
        # file formats.  At some stage this sub should be folded in with 
        # parse_bookmarks, so that level `e' ( = 6 ) is handled just like       
        # the rest.  At the moment this code seems to work, so we'll leave it.
        if ($code == hex 'e0')
        {
            $self->{work_num}++ if ord substr ($$buf, ++$$i, 1) == hex '81';
        }
        elsif ($code > hex 'e0' and $code < hex 'e8')
        {
            $self->{work_num} = $code & RMASK if ord substr ($$buf, ++$$i, 1) == hex '81';
        }
        
        # Do we need at some point to handle e8 < $code < ef ??
        
        elsif ($code == hex 'ef') 
        { 
            $lev = (ord substr ($$buf, ++$$i, 1)) & MASK;
            $str = get_ascii_string( $buf, $i );
            if ($str eq '')
            {       # do nothing
            }
            elsif ($lev == 0) 
            {
                $new_auth_num = $str;
                if ($new_auth_num ne $self->{auth_num}) 
                {
                    undef %{ $self->{level} };
                    $self->{auth_num} = $new_auth_num;
                }
            } 
            elsif ($lev == 1) 
            {
                $new_work_num = $str;
                if ($new_work_num ne $self->{work_num}) 
                {
                    undef %{ $self->{level} };
                    $self->{work_num} = $new_work_num;
                }
                
            } 
            elsif ($lev == 2) 
            {
                $work_abbr = $str;      #  Evidently useless info
            }               
            elsif ($lev == 3) 
            {
                $auth_abbr = $str;      #  Ditto
            }
            elsif ($lev == hex '6c')
            {
                # Papyrus provenance
                
                # There are sometimes non-printable chars in here ...
                # and get rid of &'s, since these never switch back to Greek
                $str =~ s/[\x00-\x1f\x7f]//g;
                $str =~ s/\&\d*//g;
                $self->{special_note} = '';
                $self->{special_note} .= "Loc: $str" if $str;
            }
            elsif ($lev == hex '64')
            {
                # Papyrus date
                $str =~ s/[\x00-\x1f\x7f]//g;
                $str =~ s/\&\d*//g;
                $self->{special_note} .= '; ' if $self->{special_note};
                $self->{special_note} .= "Date: $str" if $str;
            }
            elsif ($lev == hex '74')
            {
                # Papyrus what??
                
                $str =~ s/[\x00-\x1f\x7f]//g;
                $str =~ s/\&\d*//g;
                $self->{special_note} .= " $str" if $str;
            }
            elsif ($lev == hex '72')
            {
                # Papyrus reprintings
                
                $str =~ s/[\x00-\x1f\x7f]//g;
                $str =~ s/\&\d*//g;
                $self->{special_note} .= '; ' if $self->{special_note};
                $self->{special_note} .= "Repr: $str" if $str;
            }
            
            # elsif ($lev == 99) {$self->{special_note} = $str}
            # else die("What is level $lev after 0xef? ($i)")
            # Some newer PHI disks encode additional info here, such as the dates
            # of Cicero's letters.
            
            else 
            {
                # For PHI disks, the info is included in the text itself 
                # on newer disks -- we would like to know
                # what distinguishes source references, from, say, the dates of
                # Cicero's letters.  This must be documented somewhere
                $self->{special_note} .= '; ' if $self->{special_note};
                $self->{special_note} .= $str;
            }
        }
        
        # This "junk" is e.g. the citation codes for Plato!  
        ##elsif ($code == hex '9f' or $code == hex '8f') 
        ##{     # What does this mean ?
        ##      my $junk = get_ascii_string( $buf, $i );
        ##}    
        
        elsif ($code == hex 'fe') 
        {
            # End of block: this should only be encountered when
            # browsing past the end of a block -- so we skip over end
            # of block (nulls) Added: then we parse the beginning of
            # the next block, which will give us the info we want
            while (ord (substr ($$buf, ++$$i, 1)) == hex("00"))
            {
                #do nothing, except error check
                if ($$i > length $$buf)
                {
                    warn ("Went beyond end of the buffer!");
                    $self->{end_of_file_flag} = 1;
                    return;
                }
            }
            $self->parse_non_ascii($buf, $i);

        }
        elsif ($code == hex 'f0')
        {
            # End of file
            warn "Hit end of file marker!";
            return;
        }
        else 
        {
            # none of the above, so update bookmark 
            parse_bookmark ($self, $buf, $i, $code);
#             print STDERR ">$$i\n";
        }
        
        $$i++; # peek ahead to next $code
    }
    $$i--; # went one too far -- end on end of block (\xff, usually)
    return;
}

###################################################################################
#                                                                                 #
# Subroutine to parse a non-ascii bookmark that sets or increments one of the     #
# counters that keep track of what line, chapter, book, etc. we are currently at. #
#                                                                                 #
###################################################################################

sub parse_bookmark 
{       
    # adjust counters
    my ($self, $buf, $i, $code) = @_;
    my ($left, $right, $num, $char, $top_byte, $low_byte, $str);
    my ($letter, $j);
    
    # left nybble: usually gives the level of the counter being modified.
    $left = ($code & LMASK) >> 4;   
    
    # right nybble: dictates the form of the upcoming data (when > 8).
    $right = $code & RMASK; 

    # 7 is EOB, EOF, or end of string, and should not be encountered here.  
    # 6 (apart from 0xef as end of string, which is handled elsewhere) seems
    # to have been used in newer PHI disks ( >v.5.3 -- eg. Ennius).  The 
    # earlier disks don't have this info, and it doesn't add much, so
    # we might consider throwing it away (see below, where is is used).
    # 5 is the top level counter for the DDP disks.
    
    if ($left == 7) 
    {       
        # These bytes are found in some versions of the PHI disk
        # (eg. Phaedrus) God knows what they mean.  phi2ltx says they
        # mark the beginning and end of an "exception".
        return if $code == hex('f8') or $code == hex('f9');
        
        warn("I don't understand what to do with level ".
             "$left (right = $right, code = ". (sprintf "%lx", $code) . 
             "; offset ". (sprintf "%lx", $$i) );
        return;
    }
    
    if ($left == 6) 
    {
        # This is redundant info (?), since earlier versions of the
        # disks apparently omit it and do just fine.  
        # This are the a -- z levels: encoded ascii!!
        
        # Commented out since the DDP encodes something wierd here,
        # and it is not synonymous with the other levels info
        
        #my %letters = (        z => 0, y => 1, x => 2, w => 3, 
        #                               v => 4, u => 5, t => 6, s => 7 );
        # Let's hope that's enough!
        
        #$letter = chr (ord (substr ($$buf, ++$$i, 1)) & MASK); 
        #$left = $letters{$letter} || 0;
        
        # Throw this info away
        $$i++;
        $$i++           if $right == 8 or $right == 10;
        $$i += 2        if $right == 9 or $right == 11 or $right == 13;
        $$i += 3        if $right == 12;
        my $junk = get_ascii_string( $buf, $i ) if $right == 10 
            or $right == 13 or $right == 15;
        warn("I don't understand a right nybble value of 14") if $right == 14;
        return;
    }
    
    # NB. All lower levels go to one when an upper one changes.
    # In some texts (like Catullus on the older PHI disks), 
    # lower level counters are assumed to go to one, rather than
    # to disappear when higher levels change.  
    # This is also true for the DDP disk!
    $left and map $self->{level}{$_} = 1, (0 .. ($left - 1));
    
    # The usual case: increment the counter specified by the left nybble.
    if ($right == 0) 
    {       
        # print STDERR ">$left, $right, $self->{level}{$left}\n";
        # When previous line num is "post 308" for a lacuna, delete
        # post before incrementing
        $self->{level}{$left} =~ s/^post\s+//;
        # Also incr. non-digits: 1e1 goes to 1e2, 1b goes to 1c, etc.
        $self->{level}{$left} = '' unless exists $self->{level}{$left};
        $self->{level}{$left} =~ s/([a-zA-Z]*[0-9]*)$/my $rep = $1 || 0;
        $rep++; $rep/ex;
        ##print "))".$left.": ".$self->{level}{$left}."\n" if $self->{debug};
    }
    # Otherwise, set counter to value whose type is given in right nybble.
    elsif (($right > 0) and ($right < 8)) 
    {
        $self->{level}{$left} = $right;
    }
    # That value can be multi-byte, of several varieties
    
    elsif ($right == 8) 
    {   # next byte, num (7-bit) only
        $self->{level}{$left} = ord (substr ($$buf, ++$$i, 1)) & MASK;
    }
    elsif ($right == 9) 
    {   # num, then char
        $num = ord (substr ($$buf, ++$$i, 1)) & MASK;
        $char = chr (ord (substr ($$buf, ++$$i, 1)) & MASK);
        $self->{level}{$left} = $num.$char;
    }
    elsif ($right == 10) 
    {   # num, then string
        $num = ord (substr ($$buf, ++$$i, 1)) & MASK;
        $str = get_ascii_string( $buf, $i );
        if ($self->{documentary})
        {
            # Nasty hack for when this string contains stuff
            # like 1[3], which could be BETA formatting code,
            # but isn't (see Fouilles de Delphes in the
            # Cornell inscriptions database).
            $str =~ s#([\[\]])#\`$1\`#g; #These are BETA null chars.
        }
        $self->{level}{$left} = $num.$str;
    }
    elsif  ($right == 11) 
    {   # next two bytes hide a 14-bit number
        $top_byte = ord (substr ($$buf, ++$$i, 1)) & MASK;
        $low_byte = ord (substr ($$buf, ++$$i, 1)) & MASK;
        $self->{level}{$left} = ($top_byte << 7) + $low_byte;
    }
    elsif  ($right == 12) 
    {   # 2-byte num, then char
        $top_byte = ord (substr ($$buf, ++$$i, 1)) & MASK;
        $low_byte = ord (substr ($$buf, ++$$i, 1)) & MASK;
        $char = chr (ord (substr ($$buf, ++$$i, 1)) & MASK);
        $num = ($top_byte << 7) + $low_byte;
        $self->{level}{$left} = $num.$char;
    }
    elsif  ($right == 13) 
    {   # 2-byte num, then string
        $top_byte = ord (substr ($$buf, ++$$i, 1)) & MASK;
        $low_byte = ord (substr ($$buf, ++$$i, 1)) & MASK;
        $num = ($top_byte << 7) + $low_byte;
        $str = get_ascii_string( $buf, $i );
        $self->{level}{$left} = $num.$str;
    }
    elsif  ($right == 14) 
    {   # Is this correct? Only append a char to the (unincremented) counter?
        # Apparently confirmed by phi2ltx.
        # die("I don't understand a right nybble value of 14");
        $char = chr (ord (substr ($$buf, ++$$i, 1)) & MASK);
        $self->{level}{$left} .= $char;
    } 
    elsif  ($right == 15) 
    {   # a string comes next 
        $str = get_ascii_string( $buf, $i ); 
        $self->{level}{$left} = $str; 
        ##print ")".$left.": ".$self->{level}{$left}."\n" if $self->{debug};
    } 
    else 
    {   #no other possibilities 
        warn("I've fallen and I can't get up!");
    }
}

######################## Output munging routines ####################

sub print_output
{
    my ($self, $ref) = @_;

    # Running tally of characters of output
    $self->{current_chunk} += length($$ref);
    
    # Replace runs of non-ascii with newlines and add symbol for the
    # base language of the text at the start of the excerpt and after
    # every run of non-ascii (only for documentary texts such as the
    # DDP, which have lots of unterminated Latin embedded in
    # non-ascii). Actually, we turn out to need this for PHI Latin
    # texts, too, since it assumes reversion to Latin at the start of
    # a line and will not terminate Greek quotes if they end a line
    # (see Gellius, NA pref.)

    # Add null char afterwards, in case line begins with
    # a number

    # \x01 is to protect `
    # \x02 is to protect \n

    my $lang = $self->{current_lang} || 'g';
    my $newline = "\n\x02"; 
    $newline = "\n" . (($lang =~ m/g/) ? '$' : '&') . "\x02" if
        $self->{documentary} or $self->{type} eq 'phi';
    $$ref =~ s/[\x00-\x06\x0e-\x1f]+//g ;
    $$ref =~ s/[\x80-\xff]+/$newline/g ;
    # Don't interrupt a run of Greek with a Latin indicator at the start of the line.
    $$ref =~ s/\&\x02\$/\x02\$/g ;
    $$ref =~ s/\$\x02\&/\x02\&/g ;

#     print STDERR "::$$ref\n";
    if (defined $self->{aux_out})
    {
        my $aux = $$ref;
        $aux =~ s#\x02##g;
        my $success = print { $self->{aux_out} } ($aux);
        print STDERR "Aux print failed! $!\n" unless $success;
    }

    return if $self->{output_format} eq 'none';
    print STDERR "Formatting...\n" if $self->{debug};
    $self->format_output($ref);

    print STDERR "Printing...\n" if $self->{debug};
    if (not defined $self->{interleave_printing})
    {
        $$ref =~ s#\x02##g;
        my $success = print $$ref;
        print STDERR "Print failed! $!\n" unless $success;
    }
    else
      {
        my $success;
        my $first_cit = shift @{ $self->{interleave_printing} };
        $success = print $first_cit if $first_cit;
        print STDERR "Print failed (first_cit)! $!\n" unless $success;
        while ($$ref =~ m#(.*?)(?:\x02|$)#gs)
        {
            $success = print $1;
            print STDERR "Print failed ($1)! $!\n" unless $success;
            my $citation = shift @{ $self->{interleave_printing} };
            $success = print $citation if $citation;
            print STDERR "Print failed (citation)! $!\n" unless $success;
        }
        my $citation = shift @{ $self->{interleave_printing} };
        $success = print $citation if $citation;
        print STDERR "Print failed (last_cit)! $!\n" unless $success;
    }
    print STDERR "Printed.\n" if $self->{debug};
}

sub format_output
{
    my ($self, $ref, $current_lang, $inhibit_perseus) = @_;
    print STDERR "+".$$ref."\n" if $self->{debug};
    my $lang = $self->{current_lang} || 'g';
    $lang = $current_lang if $current_lang;
    $self->{perseus_morph} = 0 if ($encoding{$self->{encoding}}{remap_ascii});
    $self->{perseus_morph} = 0 if $inhibit_perseus;
    
    # Get rid of null chars.  We can't do this last, as we would like,
    # because this represents a grave accent for many encodings
    # (e.g. displaying Ibycus via HTML).  We have to leave something
    # here as a marker or formatting gets confused.  So all formats
    # must remember to remove this string.
    $$ref =~ s/\`/\x01/g;

    if ($self->{type} eq 'cop' and $lang !~ m/l/)
    {
        $self->coptic_with_latin($ref);
    }
    elsif ($lang eq 'g')
    {
        $self->greek_with_latin($ref);
    }
    else
    {
        $self->latin_with_greek($ref);
    }
    
    
    $self->beta_formatting_to_ascii ($ref) if $self->{output_format} eq 'ascii';
    # use beta_formatting_to_ascii with encoding Ibycus for repaging
    # output PAM 090102
    $self->beta_formatting_to_ascii ($ref) if $self->{output_format} eq 'repaging';
    $self->beta_to_latex ($ref) if $self->{output_format} eq 'latex';
    if ($self->{output_format} eq 'html')
    {
        if ($encoding{$self->{encoding}}{remap_ascii})
        {
            # This is a Greek font that remaps the ascii range, and so
            # it is almost certainly not safe to parse the output as
            # Beta, since the Greek encoding will contain HTML Beta
            # control and formatting chars.  So we just escape the
            # HTML codes, and send it as-is
            $self->html_escape($ref);
            $$ref = "\n<pre>\n$$ref\n</pre>\n";
        }
        else
        {
            $self->beta_to_html ($ref);
        }
    }
    $$ref =~ s/\x01//g;
    print STDERR "Formatted.\n" if $self->{debug};
}

sub greek_with_latin
{
    my ($self, $ref) = @_;
#     $self->{perseus_morph} = 0;
    $$ref =~ s/([^\&]*)([^\$]*)/
                                        my $gk = $1 || '';
                                        if ($gk)
                                        {
                                                $self->{perseus_morph} ? 
                                                  $self->perseus_handler(\$gk, 'grk') 
                                                : $self->{greek_handler}->(\$gk);
                                        }
                                        my $lt = $2 || '';
                                        if ($lt)
                                        {
                                                $self->{perseus_morph} ? 
                                                  $self->perseus_handler(\$lt, 'lat') 
                                                : $self->{latin_handler}->(\$lt);
                                        }
                                        $gk.$lt;
                                        /gex;
}

sub latin_with_greek
{
    my ($self, $ref) = @_;
    $$ref =~ s/([^\$]*)([^\&]*)/
                                        my $lt = $1 || '';
                                        if ($lt)
                                        {
                                                $self->{perseus_morph} ? 
                                                  $self->perseus_handler(\$lt, 'lat') 
                                                : $self->{latin_handler}->(\$lt);
                                        }
                                        my $gk = $2 || '';
                                        if ($gk)
                                        {
                                                $self->{perseus_morph} ? 
                                                  $self->perseus_handler(\$gk, 'grk') 
                                                : $self->{greek_handler}->(\$gk);
                                        }
                                        $lt.$gk;
                                        /gex;
}
#/
sub perseus_handler
{
    my ($self, $ref, $lang) = @_;
    my $out = '';
    my ($h_word, $h_space) = ('', '');

    $$ref =~ s/%15/'/g; # Used irregularly in Pindar for a mid-word apostrophe
    # $punct are not part of the word, but should not interfere in morph lookup
    my ($beta, $punct) = $lang eq 'grk' ? ('-A-Za-z/\\\\|+)(=*~\'', '\\[\\]!?.')
        : ('-A-Za-z~\'', '\\[\\]!?.,:+\\\\/=');  
    while ($$ref =~ m/(~~~.+?~~~)|([$beta$punct\d]*)([^$beta]*)/g)
    {
        # This is a context/divider
        $out .= $1, next if $1;
        my $orig_word  = $2 || '';
        my $space = $3 || '';
        my $link = $h_word . $orig_word;
        my $word = $h_word . $h_space . $orig_word;
        # print STDERR "1>>$word\n";
            
        if ($word =~ m/-~?$/)
        {       # Carry over hyphenated parts
            ($h_word, $h_space) = ($word, $space);
        }
        else
        {
            $link =~ s/[$punct\d-]//g;
            # Perseus morph parser takes Beta, but lowercase 
            $link =~ tr/A-Z/a-z/ if $lang eq 'grk'; 
            $link =~ s#\\#/#g if $lang eq 'grk';    # normalize barytone
            
            # print STDERR "2>>$link\n";

            $link =~ s/~[Hh]it~([^~]*)~/$1/g; 
            # Encode word itself
            if ($lang eq 'grk')
            {
                $self->{greek_handler}->(\$word); 
                $self->{greek_handler}->(\$space); 
            }
            elsif ($lang eq 'lat')
            {
                $self->{latin_handler}->(\$word); 
                $self->{latin_handler}->(\$space); 
            }
            else
            {
                warn("What language is $lang?\n");
            }
            $self->html_escape(\$word);
            $self->html_escape(\$space);
            # \x03\x02 gets changed to %, \x03\x01 to " and \x03\x03 to _
            # URL escape (from CGI.pm)
            $link =~ s/([^a-zA-Z0-9_.%;&?\/\\:=-])/"\x03\x02".sprintf("%02X",ord($1))/eg;
            my $html = qq(<a onClick=\x03\x01parse\x03\x03$lang('$link', this)\x03\x01>$word</a>);
            $out .= $html.$space;
            ($h_word, $h_space) = ('', '');
            # print STDERR "3>>$html\n";
            
        }
    }
    $$ref = $out;
}


########################################################################
#                                                                      #
# Subroutine to convert a string from raw BETA code to Pierre MacKay's #
# ibycus format.                                                       #
#                                                                      #
########################################################################

    sub beta_encoding_to_ibycus 
{
    # Unlike many other encodings, Ibycus takes care of medial/final
    # sigmas for us, so we only have to worry about explicit S1, etc.
    # \x04 is used to protect dangerous analphabetics
    my ($self, $ref) = @_;
    $$ref =~ tr/A-Z/a-z/;
    $$ref =~ s/s1/s\|/g;
    $$ref =~ s/s2/j/g;
    $$ref =~ s/s3/c+/g;
    $$ref =~ s/'/\x041/g; # Converted to {'} or '' later
    $$ref =~ s/\//'/g;
    $$ref =~ s/\\/`/g;
    $$ref =~ s/\*(\W*)(\w)/$1\u$2/g;
    $$ref =~ s#;#\x042#g; # Must be converted to "?" *after* ?'s for underdots are done
    $$ref =~ s#:#;#g;
    $$ref =~ s#\[1#\x043(\x044#g; # These punctuation marks can cause trouble
    $$ref =~ s#\]1#\x043)\x044#g;
    $$ref =~ s#\[(?!\d)#\x043[\x044#g;
    $$ref =~ s#\](?!\d)#\x043]\x044#g;
    $$ref =~ s#J#{\\nrm{}h}#g;  # Early orthography in epigraphical corpus
}

sub beta_encoding_to_transliteration 
{
    # Just like Ibycus above, but a bit cleaner to read as text
    my ($self, $ref) = @_;
    $$ref =~ tr/A-Z/a-z/;
    $$ref =~ s/s1/s\|/g;
    $$ref =~ s/s2/j/g;
    $$ref =~ s/s3/c+/g;
    $$ref =~ s/'/$self->{ibycus4} ? '{\'}' : '\'\''/ge;
    $$ref =~ s/\//'/g;
    $$ref =~ s/\\/`/g;
    $$ref =~ s/\*(\W*)(\w)/$1\u$2/g;
    $$ref =~ s#;#?#g; 
    $$ref =~ s#:#;#g;
    $$ref =~ s#\[1#(#g; 
    $$ref =~ s#\]1#)#g;
    $$ref =~ s#\[(?!\d)#[#g;
    $$ref =~ s#\](?!\d)#]#g;
}


sub beta_encoding_to_latin1
{
    my $ref = shift;
    
    my %acute = (a => "\xe1", e => "\xe9", i => "\xed", o => "\xf3", u => "\xfa", y => "\xfd",
                 A => "\xc1", E => "\xc9", I => "\xcd", O => "\xd3", U => "\xda", Y => "\xdd");
    my %grave = (a => "\xe0", e => "\xe8", i => "\xec", o => "\xf2", u => "\xf9", 
                 A => "\xc0", E => "\xc8", I => "\xcc", O => "\xd2", U => "\xd9"); 
    my %diaer = (a => "\xe4", e => "\xeb", i => "\xef", o => "\xf6", u => "\xfc", y => "\xfd",
                 A => "\xc4", E => "\xcb", I => "\xcf", O => "\xd6", U => "\xdc", Y => "\x178");
    my %circm = (a => "\xe2", e => "\xea", i => "\xee", o => "\xf4", u => "\xfb", 
                 A => "\xc2", E => "\xca", I => "\xce", O => "\xd4", U => "\xdb"); 


    $$ref =~ s/([aeiouyAEIOUY])\//$acute{$1}||'?'/ge;
    $$ref =~ s/([aeiouAEIOU])\\/$grave{$1}||'?'/ge;
    $$ref =~ s/([aeiouyAEIOUY])\+/$diaer{$1}||'?'/ge;
    $$ref =~ s/([aeiouAEIOU])\=/$circm{$1}||'?'/ge;
}

sub utf8_to_beta_encoding
{
    # For input (esp. to browser)
    my $ref = shift;
    
    my %accents = ( 
        '225' => 'a/', '233' => 'e/', '237' => 'i/', '243' => 'o/', '250' =>'u/', 
        '193' => 'A/', '201' => 'E/', '205' => 'I/', '211' => 'O/', '218' => 'U/',
        '224' => 'a\\', '232' => 'e\\', '236' => 'i\\', '242' => 'o\\', '249' => 'u\\', 
        '192' => 'A\\', '200' => 'E\\', '204' => 'I\\', '210' => 'O\\', '217' => 'U\\',
        '228' => 'a+', '235' => 'e+', '239' => 'i+', '246' => 'o+', '252' => 'u+', 
        '196' => 'A+', '203' => 'E+', '207' => 'I+', '214' => 'O+', '220' => 'U+',
        '226' => 'a=', '234' => 'e=', '238' => 'i=', '244' => 'o=', '251' => 'u=', 
        '194' => 'A=', '202' => 'E=', '206' => 'I=', '212' => 'O=', '219' => 'U='
        ); 
    
    $$ref =~ s#([\x80-\xff]+)#      my @chars=unpack'U*',$1; 
                                    my $out = '';
                                    map { $out .= $accents{$_} } @chars;
                                    $out;
              #ge;

}


sub beta_encoding_to_latin_tex
{
    my $ref = shift;
    
    $$ref =~ s#([\s\n~])"#$1``#g;
    $$ref =~ s#"#''#g;
    $$ref =~ s#([aeiouAEIOU])\/#\\'{$1}#g;
    $$ref =~ s#([aeiouAEIOU])\\#\\`$1;#g;
    $$ref =~ s#([aeiouAEIOU])\=#\\^{$1}#g;
    $$ref =~ s#([aeiouAEIOU])\+#\\"{$1}#g;
    $$ref =~ s/([\%\$\@\#])/\\$1/g;
}

sub beta_latin_to_utf
{
    my $ref = shift;

    # First, we translate to iso-8859-1
    beta_encoding_to_latin1($ref);

    # Then to utf-8 (but we don't use the pragma)
    $$ref =~ s#(\x05|[\x80-\xff])#my $c = $1;
                                if ($c =~ m/\x05/)
                                {       
                                        $c;
                                }
                                else
                                {
                                        chr(((ord $c) >> 6) | hex 'c0') . 
                                        chr((ord $c & hex '3f') | hex '80') ;
                                }
                                #ge;
}

sub beta_encoding_to_html
{
    my ($self, $ref) = @_;
    
    # these are really part of the encoding
    $$ref =~ s#([aeiouAEIOU])\/#&$1acute;#g;
    $$ref =~ s#([aeiouAEIOU])\\#&$1grave;#g;
    $$ref =~ s#([aeiouAEIOU])\=#&$1circ;#g;
    $$ref =~ s#([aeiouAEIOU])\+#&$1uml;#g;
    
    if ($encoding{$self->{encoding}}{remap_ascii})
    {
        # This is going to the browser directly without re-formatting in HTML,
        # so we might as well strip the junk out here
        $self->beta_formatting_to_ascii($ref);
    }
}
sub beta_formatting_to_ascii 
{
    my ($self, $ref) = @_;
    
    # Turn off warnings when we access phantom elements of the following
    # arrays.
    local $^W = 0;
    
    my @punct = (qw# ? * / ! | = + % & : . * #);  
    my @bra   = ('', '(', qw/< { [[ [ [ [ [ [ [ ( -> [ [ [ [[ [[/, '', '', qw/{ { { {/);
    my @ket   = ('', ')', qw/> } ]] ] ] ] ] ] ] ) <- ] ] ] ]] ]]/, '', '', qw/} } } }/);
    
    $$ref =~ s#_#-#g if $self->{documentary};
    $$ref =~ s#_# -- #g;
    
    #       $$ref =~ s#\?#\(?\)#g   unless $self->{current_lang} eq 'l';
    $$ref =~ s#\!#.#g               unless $self->{current_lang} eq 'l';
    $$ref =~ s#[\&\$]\d*##g;
    $$ref =~ s#%(\d+)#$punct[$1]#g;
    $$ref =~ s#\"\d*#\"#g;
    
    $$ref =~ s#@\d+#\ \ #g;
    $$ref =~ s#@#\ \ #g;
    $$ref =~ s#\^\d+#\ \ \ \ #g;
    
    # Get rid of numbers after brackets, etc
    $$ref =~ s#([\<\>\{\}])\d+#$1#g;
    # Get rid of # except for &#0000; etc.
    $$ref =~ s/#\d+/#/g unless $self->{encoding} =~ m/Unicode_Entities/;

    $$ref =~ s#\[(\d+)#$bra[$1]#g; 
    $$ref =~ s#\](\d+)#$ket[$1]#g;
    
    $$ref =~ s#\x042#?#g;
    $$ref =~ s#s\x041#$self->{ibycus4} ? 's\'' : 's\'\''#ge; # stop spurious final sigmas
    $$ref =~ s#\x041#$self->{ibycus4} ? '{\'}' : '\'\''#ge;
    $$ref =~ s#\x043#{#g;
    $$ref =~ s#\x044#}#g;

    # Capitalization of vowels with diacrits won't work with many 
    # of the wierder encodings
    if ($self->{current_lang} eq 'g' 
        and $self->{encoding} !~ m/Ibycus/i
        and $self->{encoding} !~ m/Transliteration/i
        and $self->{encoding} !~ m/Beta/i       )
    {
        $$ref =~ s#~[Hh]it~([^~]+)~#->$1<-#g;
    }
    else
    {
        $$ref =~ s#~[Hh]it~([^~]+)~#\U$1\Q#g;
    }
}


sub html_escape
{
    my ($self, $ref) = @_;
#   $$ref =~ s/&/&amp;/g;
    $$ref =~ s/&(?!#|[aeiouAEIOU](?:acute|grave|circ|uml);)/&amp;/g;
    $$ref =~ s/>/&gt;/g;
    $$ref =~ s/</&lt;/g;

}

##############################################################################
# Subroutine to convert the formatting codes in the search result to html    #
# markup.  Feed me one entry at a time, please.                              #
##############################################################################

sub beta_to_html 
{
    my ($self, $ref) = @_;


    # more could be done with < and >, but mark them with braces for now
    # escape all < and > so as not to confuse html
    # escape & when not followed by # (html numerical entity)
    # Text including Perseus links will already be html-escaped
    
    unless ($self->{perseus_morph})
    {       
        $$ref =~ s/&(?!#|[aeiouAEIOU](?:acute|grave|circ|uml);)/&amp;/g;
        $$ref =~ s#\<#&lt;#g;
        $$ref =~ s#\>#&gt;#g;
    }
    $$ref =~ s#&lt;1(?!\d)((?:(?!\>|$).)+)(?:&gt;1(?!\d))#<u>$1</u>#gs;
    
    # undo the business with ~hit~...~
#     $$ref =~ s#~[Hh]it~([^~]*)~#<u>$1</u>#g;

    # " (quotes)
    $$ref =~ s/([\$\&\d\s\n~])\"3\"3/$1&#147;/g;
    $$ref =~ s/([\$\&\d\d\s\n~])\"3/$1&#145;/g;
    $$ref =~ s/\"3\"3/&#148;/g;
    $$ref =~ s/\"3/&#146;/g;

    $$ref =~ s/([\$\&\d\s\n~])\"[67]/$1&laquo;/g;
    $$ref =~ s/\"[67]/&raquo;/g;

    $$ref =~ s/([\x01-\x1f@\$\&\d\s\n~])\"\d?/$1&#147;/g;
    $$ref =~ s/\"\d?/&#148;/g;
    $$ref =~ s/\"\d+/&quot;/g;
    
    $$ref =~ s#\x03\x01#"#g;

    $$ref =~ s#~[Hh]it~([^~]*)~#$self->{hit_html_start}$1$self->{hit_html_end}#g;
    
    $$ref =~ s#&lt;\d*#&lt;#g;
    $$ref =~ s#&gt;\d*#&gt;#g;

    # Note that $ must be escaped in these regexen, or the $] is parsed as a var.
    $$ref =~ s#(?:\$|&amp;)10((?:(?!\$|&amp;).)+)#<font size=-1>$1</font>#gs;
    $$ref =~ s#(?:\$|&amp;)11((?:(?!\$|&amp;).)+)#<font size=-1><b>$1</b></font>#gs;
    $$ref =~ s#(?:\$|&amp;)13((?:(?!\$|&amp;).)+)#<font size=-1><i>$1</i></font>#gs;
    $$ref =~ s#(?:\$|&amp;)14((?:(?!\$|&amp;).)+)#<font size=-1><sup>$1</sup></font>#gs;
    $$ref =~ s#(?:\$|&amp;)15((?:(?!\$|&amp;).)+)#<font size=-1><sub>$1</sub></font>#gs;
    $$ref =~ s#&amp;16((?:(?!\$|&amp;).)+)#<sup><i>$1</i></sup>#gs;
    $$ref =~ s#(?:\$|&amp;)20((?:(?!\$|&amp;).)+)#<font size=+1>$1</font>#gs;
    $$ref =~ s#(?:\$|&amp;)21((?:(?!\$|&amp;).)+)#<font size=+1><b>$1</b></font>#gs;
    $$ref =~ s#(?:\$|&amp;)23((?:(?!\$|&amp;).)+)#<font size=+1><i>$1</i></font>#gs;
    $$ref =~ s#(?:\$|&amp;)24((?:(?!\$|&amp;).)+)#<font size=+1><sup>$1</sup></font>#gs;
    $$ref =~ s#(?:\$|&amp;)25((?:(?!\$|&amp;).)+)#<font size=+1><sub>$1</sub></font>#gs;
    $$ref =~ s#(?:\$|&amp;)30((?:(?!\$|&amp;).)+)#<font size=-2>$1</font>#gs;
    $$ref =~ s#(?:\$|&amp;)40((?:(?!\$|&amp;).)+)#<font size=+2>$1</font>#gs;
    
    $$ref =~ s#(?:\$|&amp;)1((?:(?!\$|&amp;).)+)#<b>$1</b>#gs;
    $$ref =~ s#(?:\$|&amp;)3((?:(?!\$|&amp;).)+)#<i>$1</i>#gs;
    $$ref =~ s#(?:\$|&amp;)4((?:(?!\$|&amp;).)+)#<sup>$1</sup>#gs;
    $$ref =~ s#(?:\$|&amp;)5((?:(?!\$|&amp;).)+)#<sub>$1</sub>#gs;
    $$ref =~ s#\&amp;[678]((?:(?!\$|&amp;).)+)#<font size=-1>\U$1\E</font>#gs;
    $$ref =~ s#\$\d6((?:(?!\$|&amp;).)+)#<b><sup>$1</sup></b>#gs;

    $$ref =~ s#\&amp\;##g;
    $$ref =~ s#\$##g;
    
    # BETA { and } -- title, marginalia, etc.
    # what to do about half-cut off bits? must stop at a blank line.
    #
    $$ref =~ s#\{1((?:[^\}]|\}[^1]|\})*?)(?:\}1|$)#<p><b>$1</b></p>#g;
    $$ref =~ s#((?:[^\}]|\}[^1]|\})*?)\}1#<p><b>$1</b></p>#g;
    # Servius
    $$ref =~ s#\{43((?:[^\}]|\}[^4]|\}4[^3])*?)(?:\}43|$)#<i>$1</i>#g;
    $$ref =~ s#((?:[^\}]|\}[^4]|\}4[^3])*?)\}43#<i>$1</i>#g;
#     $$ref =~ s#\{\d+([^\}]+)(?:\}\d+|$)#<h5>$1</h5>#g;
    $$ref =~ s#\{\d+([^\}]+)(?:\}\d+|$)#$1#g;

    
    
    # record separators
    if ($Diogenes::Base::cgi_flag and $self->{cgi_buttons})
    {
        $$ref =~ s#~~~(.+?)~~~#<p class="gotocontext"><a href="/Diogenes.cgi?JumpTo=$1">$self->{cgi_buttons}</a></p><hr>#g;
        
    }
    else
    {
        $$ref =~ s#~~~~~+#<hr>\n#g;
        $$ref =~ s#~~~.+?~~~#<hr>\n#g;
        $$ref =~ s#^\$\-?$#\$<p> #g;
    }
    
    # eliminate `#' except as part of &#nnn;
    #$$ref =~ s/(?<!&)#\d*([^;])/$1/g;  

    # # and *#
    $$ref =~ s/\*#(\d+)/$Diogenes::BetaHtml::starhash{$1}/g;
    $$ref =~ s/(?<!&)#(\d+)/$Diogenes::BetaHtml::hash{$1}||'??'/ge;
    $$ref =~ s/(?<!&)#/&#x0374/g;
    
    # some punctuation
    $$ref =~ s/_/\ &#150;\ /g;


    # Perseus links use % for URL-escaped data in the href, so these are 
    # written as \x03\x02 until now 
    # % (more punctuation)
    # s/([])%24/&$1tilde;/g;
    $$ref =~ s#%(\d+)(?:\x01)?#$Diogenes::BetaHtml::percent{$1}#g;
    $$ref =~ s/%/\&\#134\;/g;
    $$ref =~ s/\x03\x02/%/g;
    $$ref =~ s/\x03\x03/_/g;
    
    $$ref =~ s#s\x041#$self->{ibycus4} ? 's\'' : 's\'\''#ge; # stop spurious final sigmas
    $$ref =~ s#\x041#$self->{ibycus4} ? '{\'}' : '\'\''#ge;
    $$ref =~ s#\x042#?#g;
    $$ref =~ s#\x043#{#g;
    $$ref =~ s#\x044#}#g;
    
    # @ (whitespace)
    $$ref =~ s#@(\d+)#'&nbsp;' x $1#ge;
    $$ref =~ s#(\ \ +)#'&nbsp;' x (length $1)#ge;
    $$ref =~ s#@#&nbsp;#g;
    
    # ^
    $$ref =~ s#\^(\d+)#my $w = 5 * $1;qq{<spacer type="horizontal" size=$w>}#ge;
    
    # [] (brackets of all sorts)
    $$ref =~ s#\[(\d+)#$Diogenes::BetaHtml::bra{$1}#g; 
    $$ref =~ s#\](\d+)#$Diogenes::BetaHtml::ket{$1}#g;

    
#     $$ref =~ s#\n\s*\n#\n#g; 

    # Try not to have citation info appear next to blank lines
#     $$ref =~ s#\x02\n#\n\x02#g;
    $$ref =~ s#\n+#<br/>\n#g;
    $$ref =~ s#(</[Hh]\d>)\s*<br/>#$1#g;
    $$ref =~ s#<[Hh]\d></[Hh]\d>##g; # void marginal comments

#   These have to stay, since babel, Ibycus uses ` as the grave accent
    if ($self->{encoding} =~ m/Ibycus/i or $self->{encoding} =~ m/Babel/i) {
        $$ref =~ s/\x01/\`/g;
    }
#      print STDERR ">>$$ref\n";
    

}

########################################################################
#                                                                      #
# Method to convert the formatting codes in the search result to latex #
# markup.   For Greek mostly.                                          #
#                                                                      #
########################################################################

sub beta_to_latex 
{
    my ($self, $ref) = @_;

    # \x061 protects \ \x062 protects { and \x063 protects } \x064 protects :
    
    # We may get many chunks now
    $$ref = "xxbeginsamepage\n" . $$ref . "\x061endsamepage\n" 
        unless $$ref =~ m/^\&\nIncidence of all words as reported by word list:/;
    
    # record separators
    $$ref =~ s#~~~~~*\n#\x061forcepagebreak#g;
    $$ref =~ s#~~~.+?~~~\n#\x061forcepagebreak#g;
    $$ref =~ s#\n\&\&\n+#\x061forcepagebreak\n\n\&#g;
    

    # \familydefault to ibycus means that marginal notes and such are always set
    # in greek
    my ($small, $large);
    if ($self->{printer}) 
    {
        $small = '{8}{10}';
        $large = '{14}{17}';
    }
    else 
    {
        $small = '{14}{21}';
        $large = '{21}{25}';
    }

    # Here is some data used for turning BETA formatting codes into a twisted
    # form of LaTeX.
    
    local $^W = 0;

    my @punct = (
        '', qw#\textsterling $*$ / ! \ensuremath{|} $=$ $+$ \% \&#, "\x064", qw# . $*$#, 
        '{\ddag}', '{\P}', '\ensuremath{|}','\ensuremath{|}', '\ensuremath{|}', 
        '\'', '-', '', '', '', '', '', '', '', '', '', '', '{})', '{}(', '{}\'', 
        '{}`', '{}\~{}', '{})\'', '{}(\'', '{}(`', '{}(=', '{}\"{~}');  
    my @bra   = ('', '\ensuremath{(}', '\ensuremath{<}', 
                 qw/\{ [[ [ [ [ [ [ [ ( -> [ [ [ [[ [[/, '', '', qw/\{ \{ \{ \{/);
    my @ket   = ('', '\ensuremath{)}', '\ensuremath{>}', 
                 qw/\} ]] ] ] ] ] ] ] ) <- ] ] ] ]] ]]/, '', '', qw/\} \} \} \}/);
    if ($self->{ibycus4})
    {   #iby4extr
        $bra[5] = "{\\bracketleftbt}";
        $ket[5] = "{\\bracketrightbt}";
    }
    my @gk_font = (
        '', '\fontseries{b}', '', '\fontshape{sl}','','','','','', '', 
        "\\fontsize$small", "\\fontsize$small\\fontseries{b}", '', 
        "\\fontsize$small\\fontshape{sl}",'','','','','','',"\\fontsize$large",
        "\\fontsize$large\\fontseries{b}", '', "\\fontsize$small\\fontshape{sl}");
    my @rm_font = ('', '\fontseries{bx}', '', '\fontshape{it}','','',
                   '\fontshape{sc}','\fontshape{sc}','\fontshape{sc}','',
                   "\\fontsize$small", "\\fontsize$small\\fontseries{bx}",
                   '',"\\fontsize$small\\fontshape{it}",'','','','','','',
                   "\\fontsize$large", "\\fontsize$large\\fontseries{bx}", 
                   '', "\\fontsize$small\\fontshape{it}");
    my @sym = (
        '', '{\greek{k+}}', '\ensuremath{\cdot}', '{\greek{k+}}', '', '{\greek{s+}}',
        '\makebox[0pt][l]{\hspace{-2mm}\rule[-3.5mm]{5mm}{.2mm}\rule[-5mm]{0mm}{9mm}}', 
        '.', 
        '\makebox[0pt][l]{\hspace{-2mm}\rule[-3.5mm]{5mm}{.2mm}\rule[-5mm]{0mm}{9mm}}', 
        '', '\ensuremath{\supset}', '', '--',
        '\ensuremath{\divideontimes}', '\dipleperi{}',
        '\ensuremath{>}');

    # If we are generating postscript or PDF for portability, we don't
    # want any bitmapped fonts
    my @oddquotes = $self->{psibycus} ?
        ('{,,}',
         '{,}',
         '{\\greek{<<}}',
         '{\\greek{<<}}',
         '{\\greek{>>}}',
         '{\\greek{>>}}' 
        )  :
        ('{\\fontencoding{T1}\\fontfamily{cmr}\\selectfont\\quotedblbase}',
         '{\\fontencoding{T1}\\fontfamily{cmr}\\selectfont\\quotesinglbase}',
         '{\\fontencoding{T1}\\fontfamily{cmr}\\selectfont\\guillemotleft}',
         '{\\fontencoding{T1}\\fontfamily{cmr}\\selectfont\\guilsinglleft}',
         '{\\fontencoding{T1}\\fontfamily{cmr}\\selectfont\\guillemotright}',
         '{\\fontencoding{T1}\\fontfamily{cmr}\\selectfont\\guilsinglright}'  ) ;
    
    # BETA { and } -- title, marginalia, etc.
    
    #$$ref =~ s#\{1(?!\d)(([\$\&]\d*)?(?:[^\}]|\}[^1]|\})*?)(?:\}1(?!\d)|\x06)#\x061titlebox\x062$1\x063\x062$2\x063#g;
    $$ref =~ s#\{1(?!\d)([\$\&]\d*)?((?:(?!\}1(?!\d)|\x06).)+)(?:\}1(?!\d))?#\x061titlebox\x062$1\x063\x062$2\x063#gs;
    #$$ref =~ s#\{2(?!\d)((?:[^\}]|\}[^2]|\})*?)([\&\$]?)(?:\}2(?!\d)|\x06)#\\marginlabel\x062$1\x063$2#g;
    $$ref =~ s#\{2(?!\d)((?:(?!\}2(?!\d)|\x06).)+)(?:\}2(?!\d))?#\\marginlabel\x062$1\x063#gs;
    #$$ref =~ s#\{(\D[^\}]*?)([\$\&]?)\}(?:\s*\n)?#\\marginlabel\x062$1\x063$2#g;
    $$ref =~ s#\{(\D[^\}]*?)([\$\&]?)\}(?:\s*\n)?#\\marginlabel\x062$1$2\x063#g;
    ##$$ref =~ s#\{\d*([^\}]*)(?:\}\d*|\x06)#\x061ital\x062$1\x063#g;
    #$$ref =~ s#\{43((?:[^\}]|\}[^4]|\}4[^3])*?)(?:\}43|\x06)#\x061ital\x062$1\x063#g;
    #$$ref =~ s#((?:[^\}]|\}[^4]|\}4[^3])*?)\}43#\x061ital\x062$1\x063#g;
    $$ref =~ s#\{43((?:(?!\}43|\x06).)+)(?:\}43)?#\x061ital\x062$1\x063#g;
    $$ref =~ s#(?:\{43)?((?:(?!\}43|\x06).)+)(?:\}43)#\x061ital\x062$1\x063#g;
    # These {} signs are too multifarious in the papyri to do much with them -- and
    # if we make them italicized, then they often catch and localize wrongly font
    # shifts from rm to gk.
    $$ref =~ s#\{\d*([^\}]*)(?:\}\d*|\x06)#{$1}#g;
    
    # escape all other { and } so as not to confuse latex
    $$ref =~ s#\{\d*#\\\{#g;
    $$ref =~ s#\}\d*#\\\}#g;
    
    # now we can safely use { and } -- undo the business with \x06
    # the eval block is for cases where the ~hit~...~ spans two lines.
    # and to make it spit out the record delimiter when it eats that.
    $$ref =~ s#\x061titlebox\x062([^\x06]*)\x063\x062([^\x06]*)\x063#
                        my $rep = "\\titlebox{$1}{$2}";
                        $rep =~ s/~hit~([^~\n]*)\n([^~]*)~/~hit~$1~\n~hit~$2~/g;
                        $rep =~ s/(\n+\~+\n+)\}(\{[^\}]*\})$/\}$2$1/g;
                        $rep#gex; 

    # The font command to switch back is usually *inside* the marginal note!
    $$ref =~ s#\\marginlabel\x062([^\x06]*)\x063#my $label = $1;
                                my $font = $1 if $label =~ m/([\&\$]\d*)$/;
                                "\\marginlabel{$label}$font"#gex;
    $$ref =~ s#\x061ital\x062([^\x06]*)\x063#\\emph{$1}#gi;
    
    # Pseudo-letterspacing with \,:
    # Real letterspacing separates accents from their letters.
    # This method screws up medial sigma, so we have to force it.
    
    $$ref =~ s#\<20((?:(?!\>20|\x06).)+)(?:\>20)?#my $rep = $1; 
    $rep =~ s/(['`=)(]*[A-Z ][+?]*)(?=[a-zA-Z])/$1\\,/g; 
                        $rep =~ s/([a-z]['`|+=)(?]*)(?=[a-zA-Z])/$1\\,/g; 
                        $rep =~ s/s\\,/s\|\\,/g; 
                        $rep =~ s/$/\\,/; 
                        $rep =~ s/~h\\,i\\,t~/~hit~/; 
                        $rep#gsex;

    $$ref =~ s#\<(\D(?:[^\>\n]|\>\d)*?)(?:\>|\n)#\\ensuremath\{\\overline\{\\mbox\{$1\}\}\}#g;
    $$ref =~ s#\<1(\D(?:[^\>]|\>[^1])*)(?:\>1|\x06)#\\uline\{$1\}#g;
    $$ref =~ s#\<3(\D(?:[^\>\n]|\>[^3])*?)(?:\>3|\n)#\\ensuremath\{\\widehat\{\\mbox\{$1\}\}\}#g;
    $$ref =~ s#\<4(\D(?:[^\>\n]|\>[^4])*?)(?:\>4|\n)#\\ensuremath\{\\underbrace\{\\mbox\{$1\}\}\}#g;
    $$ref =~ s#\<5(\D(?:[^\>\n]|\>[^5])*?)(?:\>5|\n)#\\ensuremath\{\\overbrace\{\\mbox\{$1\}\}\}#g;

    # undo the business with ~hit~...~
    $$ref =~ s#~[Hh]it~([^~]*)~#\\hit{$1}#g;

    # more could be done with < and >, but mark them with braces for now
    $$ref =~ s#\<\d*#\\\{#g;
    $$ref =~ s#\>\d*#\\\}#g;
    
    # Record separator
    $$ref =~ s#^\$\-?$#\$\\rule{0mm}{8mm}\n #g;
    
    # some punctuation
    $$ref =~ s#_#-#g if $self->{documentary};
    $$ref =~ s#_#\ --\ #g;

    # ibycus4 extras
    if ($self->{prosody})
    {
        $$ref =~ s#\%40#\\prosody{u}#g;
        $$ref =~ s#\%41#\\prosody{-}#g;
        $$ref =~ s#\%42#\\prosody{bu}#g;
        $$ref =~ s#\%43#\\prosody{a}#g;
        $$ref =~ s#\%44#\\prosody{a}#g;
        $$ref =~ s#\%45#\\prosody{au}#g;
        $$ref =~ s#\%46#\\prosody{b-}#g;
        $$ref =~ s#\%49#\\prosody{uuu}#g;
    }
    
    # protect ?'s and !'s in latin mode
    $$ref =~ s/([^\&]*)([^\$]*)/
                                        my $gk = (defined $1) ? $1 : '';
                                        my $lt = (defined $2) ? $2 : '';
                                        $lt =~ s#;#\x065#g;         # protect ; : in latin mode
                                        $lt =~ s#:#\x064#g;                 
                                        $lt =~ s#([?!])#$1\{\}$2#g;
                                        $gk.$lt;
                                        /gex;
    $$ref =~ s#s\?(?![\s])#\\d{s|}#g; # medial / final sigma doesn't much matter in frag. pap.
    $$ref =~ s#\!#\.#g;
        
    $$ref =~ s#[\&\$](?:4|14|24)([^\&\$\n]+)(?=[\&\$\n])#\\textrm\{\\ensuremath\{\^\{$1\}\}\}#g;
    $$ref =~ s#[\$\&](?:5|15|25)([^\&\$\n]+)(?=[\&\$\n])#\\textrm\{\\ensuremath\{\_\{$1\}\}\}#g;
        
    # $ (greek fonts)
    $$ref =~ s#\$(\d+)#\\fontfamily{ibycus}$gk_font[$1]\\selectfont{}#g;
    $$ref =~ s#\$\n#\\ngk{} #g;
    $$ref =~ s#\$#\\ngk{}#g;
        
    # & (roman fonts)
    $$ref =~ s#\&(\d+)#\\fontfamily{cmr}$rm_font[$1]\\selectfont{}#g;
    $$ref =~ s#\&\n#\\nrm{} #g;
    $$ref =~ s#\&#\\nrm{}#g;

    # % (more punctuation)
    $$ref =~ s#([a-zA-Z]['`|+)(=]*)%24#\\~\{$1\}#g;
    $$ref =~ s#([a-zA-Z]['`|+)(=]*)%25#\\c\{$1\}#g;
    $$ref =~ s#([a-zA-Z]['`|+)(=]*)%26#\\=\{$1\}#g;
    $$ref =~ s#([a-zA-Z]['`|+)(=]*)%27#\\u\{$1\}#g;
    $$ref =~ s#%80#{\\nrm\\itshape{v}}#g; #Diogenes of Oenoanda 
    $$ref =~ s#%(\d+)#$punct[$1]#g;
    # ? Underdot
    $$ref =~ s#([a-zA-Z]['`|+)(=]*)\?#\\d{$1}#g;
    $$ref =~ s#(['`|+)(=]+)\?#\\d{$1}#g;
    # Sigmas preceeding a \d for underdot wrongly become final
    $$ref =~ s#s\\d\{#s\|\\d\{#g;
    
    $$ref =~ s#%#\\dag{}#g;
    
    # @ (whitespace)
    $$ref =~ s#^([^a-zA-Z]*)@\d*#$1#g; # not when it's at the beginning
    $$ref =~ s#@\d+#\n#g; 
    $$ref =~ s#@#~~#g;
    $$ref =~ s#\ (?=\ )#~#g; # All spaces followed by another
    $$ref =~ s#\.\ #.~#g; # For abbrs.
    
    # ^
    $$ref =~ s#\^\d+#~~~~#g;
    
    # [] (brackets of all sorts)
    $$ref =~ s#\[(\d+)#$bra[$1]#g; 
    $$ref =~ s#\](\d+)#$ket[$1]#g;
    # [ and ] must be like this: {[} for latex
    $$ref =~ s#(\[+)#{$1}#g;
    $$ref =~ s#(\]+)#{$1}#g;
    
    # # (numerical symbols) this is obviously wrong
    $$ref =~ s/#508/\ --\ /g;
    # get rid of those troublesome brackets around paragraphoi
    $$ref =~ s/\{\[\}\#6\{\]\}/\#6/g;
    $$ref =~ s/#(\d+)/$sym[$1]/g;  
    $$ref =~ s/#/\$\'\$/g;  
    
    # " (quotes)
    
    # Were the \textquotedblleft etc. forms necessary pre-ibycus4 ?
    #$$ref =~ s#([\s\n~])\"3\"3#$1\\textquotedblleft{}#g;
    $$ref =~ s#([\s\n~])\"3(\"3)?#$1`#g;
    #$$ref =~ s#\"3\"3#\\textquotedblright{}#g;
    $$ref =~ s#\"3(\"3)?#'#g;
    
    $$ref =~ s#\"1#$oddquotes[0]#g;
    $$ref =~ s#\"2#\\textrm{\\textquotedblleft}#g;
    $$ref =~ s#\"4#$oddquotes[1]#g;
    $$ref =~ s#\"5(?!\d)#\\textquoteleft{}#g;
    
    #$$ref =~ s#([\s\n~])\"6#$1<<#g; # Bug in ibycus? -- this used to work
    $$ref =~ s/([\s\n~])\"6/$1 $oddquotes[2]/g;
    $$ref =~ s/([\s\n~])\"7/$1 $oddquotes[3]/g;
    #$$ref =~ s#\"6#>>#g;
    $$ref =~ s#\"6#$oddquotes[4]#g;
    $$ref =~ s#\"7#$oddquotes[5]#g;
    
    $$ref =~ s#\"\d\d*#\\texttt{"}#g;
    #$$ref =~ s#([\s\n~])\"\d?#$1\\textquotedblleft{}#g;
    $$ref =~ s#([\s\n~])\"\d?#$1``#g;
    $$ref =~ s#\"\d?#''#g;
    $$ref =~ s#([\s\n~])\'#$1\`#g;
    
    # record separators
    if ($self->{latex_counter})
    {
        $$ref =~ s#xxbeginsamepage(?:\n\\nrm\{} \n)?#\\begin{samepage}\x06counter#g;
    }
    else
    {
        $$ref =~ s#xxbeginsamepage\n?#\\begin{samepage}#g;
    }
    $$ref =~ s#(?:\x06)?\x061endsamepage\n+#\\end{samepage}\\nopagebreak[1]#g;
    $$ref =~ s#(?:\x06)?\x061forcepagebreak\n*#\\pagebreak[3]~\\\\#g;
    $$ref =~ s#\x065#;#g;       # these were escaped above in Latin text
    $$ref =~ s#\x064#:#g;       
    $$ref =~ s#\x042#?#g;
    $$ref =~ s#s\x041#$self->{ibycus4} ? 's\'' : 's\'\''#ge; # stop spurious final sigmas
    $$ref =~ s#\x041#$self->{ibycus4} ? '{\'}' : '\'\''#ge;
    $$ref =~ s#\x043#{#g;
    $$ref =~ s#\x044#}#g;
    $$ref =~ s#\x064#\\textrm{:}#g;
    #   You can eliminate some excess whitespace by commenting this next line out
    $$ref =~ s#\n\n+#~\\nopagebreak[4]\\\\~\\nopagebreak[4]\\\\#g; # consecutive newlines
    $$ref =~ s#\n\n#~\\nopagebreak[4]\\\\#g; # eol
    $$ref =~ s#\n#~\\nopagebreak[4]\\\\\n#g; # eol
    $$ref =~ s#\x04counter#\\showcounter{}#g;
    # for early epigraphical orthography
    $$ref =~ s#([eo][)(]?)\=#\\~{$1}#g;
    $$ref =~ s#([)(]?[EO])\=#\\~{$1}#g;

}

# Here is the stuff for the beginning and ending of latex & html files

sub begin_boilerplate 
{
    my $self = shift;
    my ($size, $skip) = $self->{printer} ? (10, 12) : (17, 21);
    $size = $self->{latex_pointsize} if $self->{latex_pointsize};
    $skip = $self->{latex_baseskip} if $self->{latex_baseskip};
    
    my $begin_latex_boilerplate = "\\documentclass{article}";

    $begin_latex_boilerplate .= $self->{psibycus} ?
        "
\\usepackage{psibycus}" : $self->{ibycus4} ?  "
\\usepackage{ibycus4}"  : "
\\usepackage{ibygreek}" ; 
    
    $begin_latex_boilerplate .= $self->{ibycus4} ?
        "
\\DeclareFontShape{OT1}{ibycus}{bx}{n}{%
   <5> <6> <7> <8> fibb848
   <9> fibb849
  <10> <10.95> <12> <14.40> <17.28> <20.74> <24.88> fibb84}{}" 
  : "
\\DeclareFontShape{OT1}{ibycus}{bx}{n}{%
   <5> <6> <7> <8> gribyb8
   <9> gribyb9
  <10> <10.95> <12> <14.40> <17.28> <20.74> <24.88> gribyb10}{}";

    $begin_latex_boilerplate .= $self->{psibycus} ? "
\\newcommand{\\hit}[1]{\\uline{#1}}\n"            : "
\\newcommand{\\hit}[1]{\\textbf{#1}}\n";

    $begin_latex_boilerplate .= "
\\renewcommand{\\familydefault}{ibycus}
\\newcommand{\\ngk}{\\normalfont\\fontfamily{ibycus}\\fontsize{$size}{$skip pt}\\selectfont}
\\newcommand{\\nrm}{\\normalfont\\fontfamily{cmr}\\fontsize{$size}{$skip pt}\\selectfont}
\\newcommand{\\dipleperi}{\\raisebox{-.8mm}{\\makebox[0pt][l]{\\hspace{1.3mm}.}}\\raisebox{2.5mm}{\\makebox[0pt][l]{\\hspace{1.3mm}.}}\\ensuremath{>}}
\\newcommand{\\marginlabel}[1]{\\mbox{}\\marginpar{\\raggedright\\hspace{0pt}{#1}}}
\\newcommand{\\titlebox}[2]{\\fbox{#1\\begin{minipage}{\\textwidth}\\begin{tabbing}#2\\end{tabbing}\\end{minipage}}\\rule[-8mm]{0mm}{8mm}}
\\usepackage{amssymb}
\\usepackage[latin1]{inputenc}
\\usepackage{ulem}\n";
    
    $begin_latex_boilerplate .= ($self->{printer}) ?  
        '\\usepackage[nohead=true,twoside=false,top=20mm,left=10mm,bottom=5mm,right=10mm,marginpar=40mm,reversemp=true]{geometry}' 
        : 
        '\\usepackage[paperheight=80cm,paperwidth=30cm,nohead=true,twoside=false,top=10mm,left=10mm,bottom=10mm,right=10mm,marginpar=40mm,reversemp=true]{geometry}';
    
    $begin_latex_boilerplate .= ($self->{prosody}) ?  
        '\\DeclareFontFamily{OT1}{hpros}{\hyphenchar\font=-1}
\\DeclareFontShape{OT1}{hpros}{m}{n}{<-> hpros10}{}
\\newcommand{\prosody}[1]{{\fontfamily{hpros}\selectfont #1}}'
    : '';
    
    $begin_latex_boilerplate .=
        "\n\\pagestyle{empty}
\\begin{document}
\\newcounter{resultno}\\setcounter{resultno}{1}
\\newcommand{\\showcounter}{\\marginlabel{{\\hfill\\bf {[}\\arabic{resultno}{]}}}\\addtocounter{resultno}{1}}
\\frenchspacing
\\reversemarginpar
\\normalem
\\begin{flushleft}
\\nrm{}\n";

    # HTML stuff -- but not used by CGI script, which generates its own headers

    my $charset = 'iso-8859-1';
    if ($self->{encoding} =~ m/UTF-?8|Unicode/i)
    {
        $charset = 'UTF-8';
    }
    elsif ($self->{encoding} =~ m/8859.?7/i)
    {
        $charset = 'ISO-8859-7';
    } 

    my $begin_html_boilerplate = << "END_HTML";
    <HTML>
        <head>
        <meta http-equiv="charset" content="$charset">
        <title>Diogenes Result</title>
        </head>
        <body>

END_HTML

    print $begin_latex_boilerplate if $self->{output_format} =~ m/latex/;
    print $begin_html_boilerplate if $self->{output_format} =~ m/html/ 
	and not $Diogenes::Base::cgi_flag;
}

sub end_boilerplate
{
    my $self = shift;
    my $end_latex_boilerplate = "\\end{flushleft}\n\\end{document}\n";
    my $end_html_boilerplate =  '</body></HTML>';
    
    print $end_latex_boilerplate if $self->{output_format} eq 'latex';
    print $end_html_boilerplate if $self->{output_format} eq 'html'
        and not $Diogenes::Base::cgi_flag;
    
}

sub simple_latex_boilerplate
{
    # Used eg. for generating gif of individual words in word list
    my $self = shift;
    my $bp = "\n\\documentclass[12pt]{article}";
    $bp .= $self->{ibycus4} ?
        "\\usepackage{ibycus4}" : 
        "\\usepackage{ibygreek}";
    $bp .="\\pagestyle{empty}
\\begin{document}
\\fontfamily{ibycus}\\fontsize{17}{21pt}\\selectfont\n";
    return $bp;
}

#sub strip_beta_formatting
#{#
#       my ($self, $ref) = @_;
#   warn "$$ref\n";
#       $$ref =~ s/[\x01-\x06\x0e-\x1f\x80-\xff]+/\n/g ;
#       $$ref =~ s/\$//g;
#
#}

sub beta_encoding_to_external
{
    my ($self, $ref) = @_;
    my $encoding = $self->{encoding};
    # Beta code definitions
    my %alphabet = (
	A => 'alpha', B => 'beta', G => 'gamma', D => 'delta', 
	E => 'epsilon', Z => 'zeta', H => 'eta', Q => 'theta', I => 'iota', 
	K => 'kappa', L => 'lambda', M => 'mu', N => 'nu', C => 'xi', 
	O => 'omicron', P => 'pi', R => 'rho', S => 'sigma', T => 'tau', 
	U => 'upsilon', F => 'phi', X => 'chi', 
	Y => 'psi', W => 'omega', V => 'digamma', J => 'special' );
    # Note that rho can take breathings
    my %vowel = (A => 1, E => 1, I => 1, O => 1, U => 1, H => 1, W => 1, R => 1);
    my %other = (
	' ' => 'space', '-' => 'hyphen', ',' => 'comma',
	'.' => 'period', ':' => 'raised_dot', ';' => 'semicolon',
#         '_' => 'dash',
         '_' => 'underscore', # Perseus LSJ uses _ for long vowels, so pass it thru.
	'!' => 'period', '\'' => 'apostrophe');
    # Chars (to search for) in encoding
    my $char = '[A-Z \'\-,.:;_!]';
    my $diacrits = '[)(|/\\\\=+123]*';
    
    if ($encoding{$encoding}{remap_ascii})
    {
        # These fonts cannot reliably be parsed as BETA code once the encoding
        # is done, so we might as well strip the junk out here
        $self->beta_formatting_to_ascii($ref);
    }

    # Lunate sigmas are ``obsolete'' according to the TLG BETA spec.
    $$ref =~ s#S3#S#g;
    # Force final sigmas. (watch out for things like mes<s>on, which shouldn't
    # become final -- I'm not sure that there's much one can do there)
    $$ref =~ s#(?<!\*)S(?![123A-Z)(|/\\=+\'?])#S2#g; 
    $$ref =~ s#(?<!\*)S~(?![123A-Z)(|/\\=+\'?])#S2~#g; 
    
    if (ref $encoding{$encoding}{pre_match} eq 'CODE')
    {   # Code to execute before the match
	$encoding{$encoding}{pre_match}->($ref);
    }
    
    # For encodings close to BETA, we can do translation directly, by
    # giving a code ref, rather than a char map
    if (ref $encoding{$encoding}{sub} eq 'CODE')
    {       
	$encoding{$encoding}{sub}->($ref);
    }
    else
    {
	# This code uses the info in the Diogenes.map file to translate BETA
	# into an arbitrary Greek encoding.  All of this code is eval'ed at each
        # match of the regex, for each char with its diacrits:
	$$ref =~ s!(\*$diacrits)?($char)($diacrits)!
                                my ($a, $b, $c) = ($1, $2, $3);
                                if ($a and $c)
                                {       # Caps and trailing diacrits
                                        if        ($b eq 'S' and $c eq '2') { $c = ''; } # Oops. final sigma
                                        elsif ($c eq '|' ) { $a .= '|'; } # Iota "subscript" after a cap
                                        elsif ($a =~ m/^\*/) {$a .= $c} # In all caps titles, sometimes accents are put after the letter
                                        else  { warn "Unknown BETA code: $a$b$c"; }
                                }
                                my $code = $alphabet{$b} || '';
                                my $pre = '';
                                my $post = '';
                                if ($a and not $encoding{$encoding}{caps_with_diacrits})
                                {   # Magiscule (with leading diacrits for vowels as separate
                                        # glyphs in this encoding)
                                        $code =~ s/^(.)/\u$1/;
                                        if ($vowel{$b})
                                        {
                                                my @codes = ();
                                                $a =~ /\+/ and push @codes, 'diaer';
                                                ($a =~ /\)/ and push @codes, 'lenis') or
                                                ($a =~ /\(/ and push @codes, 'asper');
                                                ($a =~ /\// and push @codes, 'oxy') or
                                                ($a =~ /\\/ and push @codes, 'bary') or
                                                ($a =~ /\=/ and push @codes, 'peri');
                                                my $loner = join '_', @codes; 
                                                $pre = $encoding{$encoding}{$loner} || '';
                                                warn 'No mapping exists for BETA code (pre) '.
                                                        ($a||'').($b||'').($c||'')." in encoding $encoding.\n" 
                                                        if (not $pre) and (length $a > 1);
                                        }
                                }
                                elsif ($a)
                                {   # Magiscule (vowels combined with leading diacrits as 
                                        # fully-fledged, composite glyphs in this encoding)
                                        $code =~ s/^(.)/\u$1/;
                                        if ($vowel{$b})
                                        {
                                                $a =~ /\+/ and $code .= '_diaer';
                                                ($a =~ /\)/ and $code .= '_lenis') or
                                                ($a =~ /\(/ and $code .= '_asper');
                                                ($a =~ /\// and $code .= '_oxy')  or
                                                ($a =~ /\\/ and $code .= '_bary') or
                                                ($a =~ /\=/ and $code .= '_peri');
                                                $a =~ /\|/ and $code .= '_isub';
                                        }
                                }
                                elsif ($c and $vowel{$b})
                                {       # Miniscule vowels with (trailing) diacrits
                                        $c =~ /\+/ and $code .= '_diaer';
                                        ($c =~ /\)/ and $code .= '_lenis') or
                                        ($c =~ /\(/ and $code .= '_asper');
                                        ($c =~ /\// and $code .= '_oxy')  or
                                        ($c =~ /\\/ and $code .= '_bary') or
                                        ($c =~ /\=/ and $code .= '_peri');
                                        $c =~ /\|/ and $code .= '_isub';
                                }
                                elsif ($b eq 'S' and $c)
                                {
                                        ($c eq '2' and $code .= '_final') or
                                        ($c eq '3' and $code .= '_lunate');
                                } 
                                elsif ($c =~ m/^\d+$/)
                                {       # We've picked up some numbers spuriously (123, no S)
                                        $post = $b.$c;
                                }
                                $code = $other{$b} if $b and $other{$b}; 

                                $post = $encoding{$encoding}{$code} unless $post;
                                warn 'No mapping exists for BETA code (post) '.
                                        ($a||'').($b||'').($c||'')." in encoding $encoding.\n" unless $post;
                                $post ? $pre.$post : $a.$b.$c;
                                !gex;
    }
        
    if (ref $encoding{$encoding}{post_match} eq 'CODE')
    {   # Code to execute after the match
        $encoding{$encoding}{post_match}->($ref);
    }

}

sub coptic_with_latin
{
    my ($self, $ref) = @_;
    $$ref =~ s/([^\&]*)([^\$]*)/
        my $cp = $1 || '';
    if ($cp)
    {
        $self->coptic_handler(\$cp);
    }
    my $lt = $2 || '';
    if ($lt)
    {
        $lt =~ s!\&(\d+)!\& $1!g; # horribleness
                                                $self->{latin_handler}->(\$lt);
                                        }
                                        $cp.$lt;
                                        /gex;
}
sub coptic_handler
{
    my ($self, $ref) = @_;
    my $encoding = $self->{coptic_encoding};
    
    return if $self->{coptic_encoding} eq 'beta';
    
    my %alphabet = ( A => 'alpha', B => 'beta', G => 'gamma', D => 'delta', 
                     E => 'epsilon', Z => 'zeta', H => 'eta', Q => 'theta', I => 'iota', 
                     K => 'kappa', L => 'lambda', M => 'mu', N => 'nu', C => 'xi', 
                     O => 'omicron', P => 'pi', R => 'rho', S => 'sigma', T => 'tau', 
                     U => 'upsilon', F => 'phi', X => 'chi', Y => 'psi', W => 'omega', V => 'digamma',
                     s => 'shei', f => 'fei', h => 'hori', t => 'dei', j => 'gangia', g => 'shima');
    # Note that rho can take breathings
    my %other = (' ' => 'space', '-' => 'hyphen', ',' => 'comma',
                 '.' => 'period', ':' => 'raised_dot', ';' => 'semicolon', '_' => 'dash',
                 '!' => 'period', '\'' => 'apostrophe', '/' => 'forward_slash');
    # Chars (to search for) in encoding
    my $char = '[A-Z \'\-,.:;_!sfhtjg/]';
    my $diacrits = '[=+?]*';
    
    if ($coptic_encoding{$encoding}{remap_ascii})
{
    # These fonts cannot reliably be parsed as BETA code once the encoding
    # is done, so we might as well strip the junk out here
    $self->beta_formatting_to_ascii($ref);
}
# Code designed for Greek captures \ within hit,
# but here it really belongs to the following letter
$$ref =~ s/~hit~([^~]+)\\~/~hit~$1~\\/g;
$$ref =~ s/\\~hit~([^~]+)~/~hit~\\$1~\\/g;
# For greek, the lowercase protects "hit" from conversion, but not for coptic.
$$ref =~ s/~hit~/\x08\x08/g;
if (ref $coptic_encoding{$encoding}{pre_match} eq 'CODE')
{       # Code to execute before the match
    $coptic_encoding{$encoding}{pre_match}->($ref);
}

# For encodings close to BETA, we can do translation directly, by
# giving a code ref, rather than a char map
if (ref $coptic_encoding{$encoding}{sub} eq 'CODE')
{       
    $coptic_encoding{$encoding}{sub}->($ref);
}
else
{
    $$ref =~ s!(\\?)($char)($diacrits)!
                            my ($a, $b, $c) = ($1, $2, $3);
                            my $post = '';
                            my $code = $alphabet{$b} || '';
                            $code = $other{$b} if $b and $other{$b}; 
                            if ($b and $c)
                            {       # Miniscule vowels with (trailing) diacrits
                                    $c =~ /\+/ and $code .= '_diaer';
                                    $c =~ /\=/ and $code .= '_peri';
                            }
                            $post .= $coptic_encoding{$encoding}{overline}
                                         if $a and $encoding =~ m/utf/i; # combining overline
                            $post .= $encoding =~ m/utf/i ? '̣' : '?' if $c =~ m/\?/;
                            my $char = $coptic_encoding{$encoding}{$code} || '';
                            warn 'No mapping exists for BETA (Coptic) code '.
                                    ($a||'').($b||'').($c||'')." in encoding $encoding.\n" unless $char;
#                             print STDERR ">>$char.$post\n";
                            $char.$post;
                            !gex;
    }
    
    if (ref $coptic_encoding{$encoding}{post_match} eq 'CODE')
    {   # Code to execute after the match
        $coptic_encoding{$encoding}{post_match}->($ref);
    }
$$ref =~ s/\x08\x08/~hit~/g;

}

# Bits and pieces

sub numerically { $a <=> $b; }

sub barf 
{
    my $self = shift;
    my $msg = shift;
    if ($self and $self->{dump_file}) {
        use Data::Dumper;
        open DUMP, ">$self->{dump_file}" or die ("Can't open dump file");
        #print DUMP Data::Dumper->Dump ([$self], ['Diogenes']);
        print DUMP "\n\n#####################################################\n\n";
        print DUMP ${ $self->{buf} } if defined $self->{buf}; 
        close DUMP or die ("Can't close dump file");
    }
    ## Let error messages propagate up to the web interface
    if ($Diogenes::Base::cgi_flag) {
        $self->{server_error} = $msg || 'Server Error';
        return;
    }
    else {
        # We die here, and let server spawn another child.
        confess $msg;
    }
}

1;
