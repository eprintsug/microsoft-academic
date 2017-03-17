# Microsoft Academic - map EPrints repository data to Microsoft Academic Graph data

The Microsoft Academic Graph (MAG) is a graph containing scientific publication data and
(citation) relationships between the graph entities (publications, authors, institutions,
journals, conferences, and fields of study), see 
https://www.microsoft.com/en-us/research/project/microsoft-academic-graph/ , and currently
comprises about 150 million publications. It can be accessed using the Microsoft Cognitive
Services Academic Knowledge API (AK API, 
https://www.microsoft.com/cognitive-services/en-us/academic-knowledge-api ).

This software repository provides a bin/academic_search script that can be used to access 
the AK API and the MAG data starting from an EPrints repository.

It has been employed for a study to assess coverage of ZORA (Zurich Open Repository and 
Archive data) publications in MAG. The findings of this study have been submitted to 
the Journal of the Association for Information Science and Technology (JASIST) and are 
available on arXiv: https://arxiv.org/abs/1703.05539

When using this code or parts of it for scientific purposes, please cite this study as 
follows:

Sven E. Hug, Martin P. Brändle, The coverage of Microsoft Academic: Analyzing the 
publication output of a university, arXiv:1703.05539 [cs.DL] (2017).

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
