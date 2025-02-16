# For next release
## Fix Mac security issue
Get developer account; notarize app
## Distribute Apple silicon version on website.
Could not do this previously, because gatekeeper complains.
## 
# Future to-do items
## Change prebuilt-data repo to use git-lfs (and my ssh key)
## Add dark mode option.
## Add citation info from authtab.xml to exported XML files.
### Check that we export all embedded citation info
(for fragments, etc.)
## Import font_fixes from xml-export into desktop display
## Fix unicode input for Latin to search for accented words

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
