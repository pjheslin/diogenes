# Changes in Version 4 of Diogenes

## 4.7
- More helpful error messages when files in databases are missing or damaged.
- Logeion links work again.

## 4.6

* Browser front-end updated to Electon version 20 (from version 5):
    * This should eliminate spurious anti-virus warnings (for now);
    * PDFs are now shown in a new Diogenes window rather than in an
      external browser; likewise for external web links.
* Tweaks to the user interface:
    * better keyboard navigation;
    * semi-persistent state for the splash screen;
    * facility to jump to a new passage in the work currently being read.
* Added support for the the more recent TLL fascicles (from vols. 9.1 and 11.2).
* Updated icon for Macs (thanks to Helge Baumann).
* Very large search output is now split into pages to avoid crashing the browser.
* Facility to search the headwords of ancient lexica (e.g. the Suda).
* Better display of editorial notes in PHI texts.
* Fixed a long-standing bug that prevented accented and non-Latin
  characters from being used in the names of in user-defined subsets of
  texts.
* Fixed (for Windows 10 and later) another long-standing Windows bug
  that caused problems when non-Latin characters were used in the names
  of the paths to the folder holding the databases.
* Removed problematic code that sometimes interfered with finding
  citations in very short or fragmentary texts.

### Changes implemented earlier but not released then
* TLG search results are now presented in (rough) chronological order
  (with huge thanks to Jiang Qian for his assistance).
* Multiple search feature now permits looking for the repetition of
  a word (thanks to Michael Putnam for the suggestion).
* Many errors in Lewis and Short, especially citation references, have
  been fixed by Logeion (thanks to Helma Dik).
* Diogenes now deals more gracefully with hitting the end of a file
  while browsing.
* There is a new software package (diogenes-epub) for converting Diogenes XML
  output to epub format for e-readers.
* Fixed display of some LSJ entries.
* Fixed picking up GUI config settings when running server from the Linux command-line.
* Fix to bug that interfered with chronological ordering except on Windows.

## 4.5

* Fixed downloading of TLL PDFs after reorganization of BAdW website.
* Fixed OLD and TLL links for words with diacritics.
* Fixed bug in morphological search for Perseus lemmata with commas.
* Fixed some errors in TLL page numbers.
* Fixed LSJ link when parsing ὄνος.

## 4.4

* Added a new menu item to permit the user to set the display font.
* Added a facility to permit user-defined CSS to override display settings.
* Fixed a bug where parsing a word caused the program to hang for certain
  Windows users.
* Fixed bug so that a new window adopts the user-specified window size.
* Reinstated word-list searches for user-defined subsets of the TLG.
* Fixed morphological search functionality that was inadvertently broken in the
  previous release.
* Fixed find-in-page mini-window bug in fullscreen mode.
* Fixed bug where full bibliographical information was displayed inconsistently
  on Windows.
* Fixed some erroneous TLL page references, caused by later corrigenda.

## 4.3

* Highlight clicked word.
* Fix sorting of authors with identical names.
* Automatically clear Electron's HTTP cache when upgrading to a new version of
  Diogenes, which was a source of some subtle bugs.
* Fix export crash when dealing with corrupted input files.
* Now using the Logeion version of Lewis and Short.
* Aligned Greek punctuation with current Unicode recommendations.
* Reinstated searching for Greek words with accents and capital letters.
* Added tooltip for Greek text entry, strict and loose.
* Fixed parsing of capitalized Latin words.
* Improved speed of Perseus look-ups.
* Fixed crash in Juvenal when encountering unknown markup.
* Fixed LSJ short definition for πᾶς.
* Added key binding for Escape key to dismiss sidebar.

## 4.2

* Fixed bug where the morphology of elided Greek forms was not parsed.
* Fixed LSJ short definition for κόλπος.
* Restored behaviour of simple full search to read texts in numerical order.
* Fixed bug in simple searching through sub-corpora.
* Fixed bug when parsing capitalized Greek words with separate parses for upper
  and lower-case.
* Fixed broken .rpm installer for Linux

## 4.1

* Bug that broke find-in-page feature fixed.
* Alphanumeric headings added back to LSJ entries.
* Links to Logeion added.
* "Close window" menu item added.

## 4.0

* Major New Release
