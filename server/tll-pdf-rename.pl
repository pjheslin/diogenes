#!/usr/bin/env perl
use strict;
use warnings;
use File::Copy qw(mv);
use Cwd qw(cwd);

# The BAdW has severl times moved the PDF files of the ThLL around on
# their server and has also changed the name of PDFs that were already
# released by them.  Furthermore, the filenames themselves are
# inconsistent in their application of their own conventions.  This
# makes them very difficult to handle programmatically. For these
# reasons, Diogenes standardizes the naming of the PDFs as follows:

# * The internal BAdW numbers are removed along with the curly brackets.
# * The CC license name is removed, whether it appears at the start or end
# * Punctuation in the middle of volume numbers is standardized to . not ,
# * All utf8 en-dashes to indicate ranges are standardized to hyphens
# * Single-digit volume numbers are standardized to have a leading zero

# This script renames already downloaded PDFs to follow this convention.

my $tll_path = shift @ARGV;
chdir($tll_path) or die "No directory: $tll_path\n$!";

my %mapping;
foreach my $correct (canonical()) {
    my $range = get_range($correct);
    $mapping{$range} = $correct;
}

my $changed = 0;
my @files = glob("*.pdf");
foreach my $file ( @files ) {
    if ($file eq 'ThLL_IX_1__3_UEberhang_nemo_nemus.pdf') {
        unlink($file) or die "Cannot delete $file: $!";
        next;
    }
    my $range = get_range($file);
    my $correct = $mapping{$range};
    unless ($correct) {
        print STDERR "Skipping: no mapping for $range in $file";
        next;
    }
    if ($file eq $correct) {
        # print STDERR "Leaving untouched: $file\n";
        next;
    }
    print STDERR "Renaming $file to $correct\n";
    mv($file, $correct) or die "Error: could not rename $file";
    $changed++;
}

print "Done: $changed files renamed.\n";

sub get_range {
    my $filename = shift;
    $filename =~ m#\(([a-zA-Z]+).*?([a-zA-Z]+)\)#;
    die "Range not found in $filename" unless $1 and $2;
    my $range = $1.'-'.$2;
    return $range;
}


sub canonical {
    return (
"ThLL vol. 01 col. 0001-0724 (a-adli).pdf",
"ThLL vol. 01 col. 0725-1410 (adluc-agoge).pdf",
"ThLL vol. 01 col. 1411-2032 (agogima-Amyzon).pdf",
"ThLL vol. 02 col. 0001-0706 (an-Artigi).pdf",
"ThLL vol. 02 col. 0707-1324 (artigraphia-Aves).pdf",
"ThLL vol. 02 col. 1325-1646 (Avesica-Azzi).pdf",
"ThLL vol. 02 col. 1647-2270 (b-Byzeres).pdf",
"ThLL vol. 03 col. 0001-0748 (c-celebro).pdf",
"ThLL vol. 03 col. 0749-1444 (celebrum-coevangelista).pdf",
"ThLL vol. 03 col. 1445-2186 (coeuntia-comus).pdf",
"ThLL vol. 04 col. 0001-0788 (con-controversus).pdf",
"ThLL vol. 04 col. 0789-1594 (controverto-cyulus).pdf",
"ThLL vol. 05.1 col. 0001-0558 (d-deopto).pdf",
"ThLL vol. 05.1 col. 0559-1102 (deorata-diffidus).pdf",
"ThLL vol. 05.1 col. 1103-1812 (diffindentia-dogarius).pdf",
"ThLL vol. 05.1 col. 1813-2334 (dogma-dze).pdf",
"ThLL vol. 05.2 col. 0001-0758 (e-ergenna).pdf",
"ThLL vol. 05.2 col. 0759-1276 (erginario-excolligo).pdf",
"ThLL vol. 05.2 col. 1277-1822 (excolo-exquiro).pdf",
"ThLL vol. 05.2 col. 1823-2134 (exquisitim-eozani).pdf",
"ThLL vol. 06.1 col. 0001-0808 (f-firmitas).pdf",
"ThLL vol. 06.1 col. 0809-1664 (firmiter-fysis).pdf",
"ThLL vol. 06.2 col. 1665-2388 (g-gytus).pdf",
"ThLL vol. 06.3 col. 2389-2780 (h-hieranthemis).pdf",
"ThLL vol. 06.3 col. 2781-3166 (hierarchia-hystrix).pdf",
"ThLL vol. 07.1 col. 0001-0840 (i-inaures).pdf",
"ThLL vol. 07.1 col. 0841-1596 (inauricula-inhonestitas).pdf",
"ThLL vol. 07.1 col. 1597-2304 (inhonesto-intervulsus).pdf",
"ThLL vol. 07.2.1 col. 0001-0760 (intestabilis-kyrie).pdf",
"ThLL vol. 07.2.2 col. 0761-1346 (l-librariolus).pdf",
"ThLL vol. 07.2.2 col. 1347-1952 (librarium-lyxipyretos).pdf",
"ThLL vol. 08 col. 0001-0786 (m-meocarius).pdf",
"ThLL vol. 08 col. 0787-1332 (meoculos-mogilalus).pdf",
"ThLL vol. 08 col. 1333-1764 (moincipium-myzon).pdf",
"ThLL vol. 09.1.1 col. 0001-0208 (n-navalis).pdf",
"ThLL vol. 09.1.2 col. 0209-0336 (navalis-nebel).pdf",
"ThLL vol. 09.1.3 col. 0337-0516 (nebel-nemo).pdf",
"ThLL vol. 09.1.4 col. 0513-0648 (nemo-netura).pdf",
"ThLL vol. 09.2 col. 0001-0624 (o-omnividens).pdf",
"ThLL vol. 09.2 col. 0625-1214 (omnividentia-ozynosus).pdf",
"ThLL vol. 10.1.1 col. 0001-0694 (p-paternaliter).pdf",
"ThLL vol. 10.1.1 col. 0695-1472 (paterne-perimelides).pdf",
"ThLL vol. 10.1.2 col. 1473-2074 (perimetros-piceno).pdf",
"ThLL vol. 10.1.2 col. 2075-2780 (picercula-porrus).pdf",
"ThLL vol. 10.2.1 col. 0001-0644 (porta-praefinitivus).pdf",
"ThLL vol. 10.2.1 col. 0645-1232 (praefinitus-primaevitas).pdf",
"ThLL vol. 10.2.2 col. 1233-1970 (primaevus-propello).pdf",
"ThLL vol. 10.2.2 col. 1971-2798 (propemodum-pyxodes).pdf",
"ThLL vol. 11.2.1 col. 0001-0144 (r-rarus).pdf",
"ThLL vol. 11.2.2 col. 0145-0320 (rarus-recido).pdf",
"ThLL vol. 11.2.3 col. 0321-0496 (recido-reddo).pdf",
"ThLL vol. 11.2.4 col. 0497-0656 (reddo-refocilo).pdf",
"ThLL vol. 11.2.5 col. 0657-0784 (refodio-regnum).pdf",
"ThLL vol. 11.2.6 col. 0785-0960 (regnum-relinquo).pdf",
"ThLL vol. 11.2.7 col. 0961-1120 (relinquosus-renuo).pdf",
"ThLL vol. 11.2.8 col. 1121-1280 (renuo-repressio).pdf",
"ThLL vol. onom.2 col. 0001-0814 (c-cyzistra).pdf",
"ThLL vol. onom.3 col. 0001-0280 (d-dzoni).pdf",        
        )
    
}
