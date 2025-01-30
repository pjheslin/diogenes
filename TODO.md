# For next release
## Fix Mac security issue
Get developer account; notarize app
## Distribute Apple silicon version on website.
Could not do this previously, because gatekeeper complains.
## Fix failure to download TLL PDFs
## Fix date of Antimachus
## Make external PDF viewer configurable
I have a question regarding the display of OLD/TLL pdfs. In the current version, Diogenes opens these pdfs in my standard browser Safari anymore but in an own pdf reader window. While this generally works fine, the former Safari experience suited my workflow better for various reasons (Tabs; no reload of the pdf during successive look up; much faster). Hence my question: Can I change the pdf viewer/browser in the advanced settings and go back to Safari?

# Bugs (Github)
## Test -H option on server
## Weird bug 
Weird side effect in searching for an i with umlaut, as printed in aquaï, auraï. If searching for a word like that, it finds me particular zeros in the texts. I noticed that the forms do show up nicely as result for aquai (etc) searches and get the correct parse.

# Priority to-do items
## Add link to Settings.cgi when not running under Electron.
## Add setting for xml-export path in Settings.cgi
and don’t show the file chooser on the splash page when not running under electron, as it doesn’t work
## Add additional settings
## Add switch to xml-export.pl to force treating texts as prose or verse.
## Remove the cruft of the 2 Perseus XML files from the app.
## Add simple API to link to external dictionaries (e.g Lectus)
Perhaps also remove gcide and make links to all English words link to the API instead, which could provide translations in the user’s own language.
Also provide ability to use e.g. second edition of the OLD. 
## Change prebuilt-data repo to use git-lfs (and my ssh key)
## Add dark mode option.
## Add citation info from authtab.xml to exported XML files.
## Import font_fixes from xml-export into desktop display

# Possible long-term to-do items
## Migrate from Electron to Tauri.
## Fix short defs by using Helma’s data.
## Fix spurious parses by integrating Helma’s data.
## Fix ordering of lemmatized search output
At present, we seem to look for each inflected form in each work separately, which means that the order appears random: one form late in the work is output before another form which comes early in the work.
## Record criteria for complex filters to permit them to be recreated and modified.
## Try XML::YAX
Possibly faster and better supported, by same author as XML::DOM::Lite.
## Fix Strawberry Perl to use included libxml.
I think this just requires adding strawberry\c\bin to the PATH, so that it can find libxml2-2\__.dll
## Possibly refactor application to only parse prefs file once
We should avoid re-parsing prefs file at each query.
## Add better interface to Suda, Etym. Magnum, et al.
Provide a way to search them by headword
## Improve epub output
Write dedicated xml to html-for-epub converter.
## Compare output to Hipparchia
Make sure we correctly export to XML hidden sources for fragments, as in Accius, Carmina
# DiogenesWeb
## Add search facility
# Diogenes 5
## Written in Node.js
## Add additional XML corpora
Especially for Latin, the PHI texts need to be supplemented with additional works from Perseus and DigiLibLT.  Supporting this would require  rewriting Diogenes so that it operates on the XML versions of the PHI and TLG databases.  But much of the code could be taken from DiogenesWeb, after search has been implemented there.
## On installation, it would have to convert existing databases.
- Interface would be rewritten from Perl/cgi to html/js.  No need for a server, except for morphological Ajax requests.
- Keep Perl infrastructure for converting XML and Perseus/Logeion server, at least for now. Eventually rewrite the morph server in Node.js.
