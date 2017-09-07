###############################################################################
#
# Microsoft Academic Knowledge API configuration. See 
# https://www.microsoft.com/cognitive-services/en-us/academic-knowledge-api/documentation/overview
#
###############################################################################

$c->{msacademic} = {};

#
# The MS Academic Knowledge API developer key
#
$c->{msacademic}->{apikey} = "insert_key_here";
#
# The base URL for the Evaluate REST Endpoint
#
$c->{msacademic}->{uri} = URI->new( 'https://westus.api.cognitive.microsoft.com/academic/v1.0/evaluate' );
#
# The fields that shall be returned by the MS Academic Knowledge API
#
$c->{msacademic}->{msacademic_fields} = "Id,Ti,Y,D,CC,ECC,AA.AuN,AA.AuId,AA.AfN,AA.AfId,F.FN,F.FId,J.JN,J.JId,C.CN,C.CId,RId,E";
#
# The number of records that shall be returned by the MS Academic Knowledge API
#
$c->{msacademic}->{answer_count} = 10;
#
# The crawl delay in seconds between two queries
#
$c->{msacademic}->{crawl_delay} = 1;
#
# The number of retries if there is no answer after 60 seconds
#
$c->{msacademic}->{crawl_retry} = 3;
#
# The EPrints fields that shall be output together with the MS Academic Knowledge API results
#
$c->{msacademic}->{eprint_fields} = [
  'eprintid',
  'title',
  'type',
  'date',
  'doi',
  'language_mult',
  'subjects',
  'dewey',
  'scopus_cluster',
  'scopus_impact',
  'woslamr_cluster',
  'woslamr_times_cited',
  'refereed',
  'full_text_status',
  'publisher'
];
#
# The affiliation id of the institution of interest.
#
$c->{msacademic}->{affiliation_id} = 202697423;

