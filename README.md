# Microsoft Academic - map EPrints repository data to Microsoft Academic Graph data

> Microsoft has announced in its [Blog](https://www.microsoft.com/en-us/research/project/academic/articles/microsoft-academic-to-expand-horizons-with-community-driven-approach/) that it will retire the Microsoft Academic Services and the Microsoft Academic Graph end of 2021. The EPrints - MA code here will not developed further and just stay here for
archival purposes. A replacement for Microsoft Academic will be built by
[OpenAlex](https://openalex.org).


The Microsoft Academic Graph (MAG) is a graph containing scientific publication data and
(citation) relationships between the graph entities (publications, authors, institutions,
journals, conferences, and fields of study), see
https://www.microsoft.com/en-us/research/project/microsoft-academic-graph/ , and currently
comprises about 150 million publications. It can be accessed using the Microsoft Cognitive
Services Academic Knowledge API (AK API,
https://www.microsoft.com/cognitive-services/en-us/academic-knowledge-api ).

This software repository provides a bin/microsoft_academic script and a MSAcademic
citation import plug-in that can be used to access the AK API and the MAG data starting
from an EPrints repository.

The citation import plug-in can also be used in connection with the [Citation Count and
Import Plug-ins](https://github.com/QUTlib/citation-import) developed by Queensland
University of Technology Library.

It has been employed for a study to assess coverage of ZORA (Zurich Open Repository and
Archive data) publications in MAG. The findings of this study have been submitted to
the journal Scientometrics and are available on arXiv: https://arxiv.org/abs/1703.05539

When using this code or parts of it for scientific purposes, please cite this study as
follows:

Sven E. Hug, Martin P. Brändle, The coverage of Microsoft Academic: Analyzing the
publication output of a university, arXiv:1703.05539 [cs.DL] (2017).

The original bin/academic_search script used for this study is available via the 1.0
branch.

While this code is specific to checking coverage of an EPrints repository against MAG and
is submitted here as supplemental material to the article, parts of it can be used to
write own code to access the AK API and use citation or other metadata.

To access the AK API, an API key (free or subscribed access) is required. See
https://www.microsoft.com/cognitive-services/en-us/pricing

The API key, the accessed entities and other settings can be configured in
cfg/cfg.d/z_ms_knowledge_api.pl

mapping_example/mapping_example.csv provides an example for mappings of institutes to the
research fields according to the field of science and technology (FOS) classification in
the Frascati manual.

## Contributors

The MA citation import script and plug-in was developed by the ZORA

Developer and Maintainer:

* [Martin Brändle](https://github.com/mpbraendle)


## Copyright

Copyright (c) 2017 University of Zurich, Switzerland

The script and plug-in are free software; you can redistribute them and/or modify them
under the  terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later version.

The plug-ins are distributed in the hope that they will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with EPrints 3;
if not, write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
MA 02111-1307 USA

## Changelog

* May 2017
  * original academic_search script split into script and plug-in
  * plug-in rewritten as Citation Import plugin to be used with QUT Library citation
    import
  * configurable query methods implemented; the full method calls all query methods in
    row
  * querying and matching improved for technical symbols, special characters and LaTeX
    code in titles
* July 2021
  * MA retired
