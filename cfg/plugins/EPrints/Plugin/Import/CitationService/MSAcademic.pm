######################################################################
#
#  Import::CitationService::MSAcademic
#
#  This plug-in will retrieve citation data from Microsoft Academic. 
#  This data should be stored in the "msacademic" dataset.
# 
######################################################################
#
#  Copyright 2017 University of Zurich. All Rights Reserved.
#
#  Martin Brändle
#  Zentrale Informatik
#  Universität Zürich
#  Stampfenbachstr. 73
#  CH-8006 Zürich
#
#  The plug-ins are free software; you can redistribute them and/or modify
#  them under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The plug-ins are distributed in the hope that they will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with EPrints 3; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
######################################################################


=head1 NAME

EPrints::Plugin::Import::CitationService::MSAcademic - Plugin for importing 
data from MS Academic (https://academic.microsoft.com/)

=head1 DESCRIPTION

This plugin imports data from the MS Academic Graph. It can be used standalone 
(e.g. using the microsoft_academic script) or within the CitationService plugin
framework developed by the Queensland University of Technology.


=head1 METHODS

=over 4

=item $plugin = EPrints::Plugin::Import::CitationService::MSAcademic->new( %params )

Creates a new MS Academic Import CitationService plugin.
The plugin has the following data structure:

$plugin->{queries} : A list of query methods to process
$plugin->{report}  : A report hash for storing the eprint and MS Academic entity properties
$plugin->{param}   : A set of parameters
$plugin->{mapping} : Mappings from subject id to discipline
$plugin->{baseuri} : The base URI of the MS Academic Knowledge API REST point
$plugin->{apikey}  : The API Key, can be obtained from MS Azure Services

=item $plugin->set_query_method( $querymethod )

Sets the query method. Current query methods are _get_queryexp_id, 
_get_queryexp_title_exact, and _get_queryexp_title_words.

=item $boolean = $plugin->can_process( $eprint )

Test whether or not this plug-in can hope to retrieve data for a given eprint.

=item $epdata = $plugin->get_epdata( $eprint )

This method queries the MS Academic Knowledge API for a given eprint.
It returns an epdata hashref for a citation datum for $eprint or undef
if no matches were found in the MS Knowledge API and EPrints.
It croaks if there are problems receiving or parsing responses from the
citation service, or if the citation service returns an error response.

=item $plugin->read_msacademic_data( $eprint )

Reads MS Academic data from a JSON file stored on disk and processes it.

=item $epdata = $plugin->convert_to_epdata( $eprint )

Converts the MS Academic Knowledge API response to a epdata hash.

=item $plugin->process_eprint_fields( $dataset, $eprint )

Processes the eprint fields specified in the configuration and stores
their values for a given eprint in the report hash.

=item $plugin->process_eprint_author_count( $eprint )

Determines the author count of an eprint and stores it in the report hash.

=item $plugin->apply_discipline_mappings( $eprint )

Applies the subject->discipline mappings to a given eprint and store them 
in the report hash.

=item $plugin->reset_msacademic_fields( $eprint )
 
Fill fields with empty values in order to create an aligned CSV file.

=item $ms_reponse = $plugin-submit_request( $eprint, $request_url )

Submit a request to the MS Academic Knowledge API.

=item $json_reponse = $plugin->process_json_response( $eprint, $ms_response )

Decode and process the JSON response.

=item $plugin->save_json_response( $eprint, $json_response ) 

Save the MS Academic Knowledge API JSON response to disk.

=item $found_match = $plugin->find_match( $eprint, $ms_data) 

Finds out if one the returned MS Academic entities is matching, 
and on which property it is matching.
Returns the number of the matched MS Academic entity (0 = no match).

=item $plugin->process_msdata( $eprint, $ms_data, $entity_matched )

Processes the Academic Knowledge API entities.

=item $plugin->process_msacademic_fields( $eprint, $msacademic_record )

Processes the MS Academic Knowledge API fields of a matched entity
and stores them in the report hash.

=item $boolean = $plugin->process_affiliation( $msacademic_record ) 

Processes the affiliation of a MS Academic Graph entity and set a flag 
if the affiliation id matches the given institution affiliation id

=item $reference_count = $plugin->process_reference_count( $msacademic_record )  

Returns the reference count of a MS Academic Graph entity

=item $author_count = $plugin->process_msacademic_author_count( $msacademic_record ) 

Returns the author count of a MS Academic Graph entity

=item $ms_response = $plugin->read_json_response( $eprint )

Reads the stored MS Academic Knowledge API JSON response for
a given eprint from disk and return a decoded JSON hash. 

=item $plugin->save_report_xml()

Saves the report as XML file.

=item $plugin->save_report_csv()

Saves the report as CSV file.
 
=item $plugin->read_discipline_mappings( $csv_file )

Read the mappings from subject ids to disciplines from a CSV file.

=item $plugin->process_error( $eprint, $ms_data )

Processes the error if the MS Academic Knowledge API did not respond and
saves it to the report hash.

=back

=cut

package EPrints::Plugin::Import::CitationService::MSAcademic;

use strict;
use warnings;
use utf8;

use Encode;
use JSON;
use EPrints::Plugin::Import::CitationService;
use Search::Xapian;
use Text::CSV;
use XML::LibXML;

use base 'EPrints::Plugin';

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new( %params );

	$self->{name} = "Microsoft Academic Knowledge API Plugin";
	$self->{visible} = "all";
	
	$self->{baseuri} = $self->{session}->config( "msacademic", "uri" );
	$self->{apikey} = $self->{session}->config( "msacademic", "apikey" );
	
	
	if( !defined( $self->{apikey} ) )
	{
		$self->{error}   = 'Unable to load the MS Academic Knowledge API key.';
		$self->{disable} = 1;
		return $self;
	}
	
	# An ordered list of the methods for generating query strings
	# used for the full method
	$self->{queries} = [
		qw{
			_get_queryexp_id
			_get_queryexp_title_exact
			_get_queryexp_title_words
			_get_queryexp_title_exact_greek
		}
	];
	
	$self->{current_query} = -1;
	
	return $self;
}

#
# Set a specific query method if there is not a sequence of query methods.
#
sub set_query_method
{
	my ( $plugin, $query_method ) = @_;
	
	$plugin->{queries} = [ $query_method ];
	$plugin->{current_query} = -1;
	
	return;
}

#
# Test whether or not this plug-in can hope to retrieve data for a given eprint.
#
sub can_process
{
	my ($plugin, $eprint) = @_;

	if ( $eprint->is_set( "msacademic_cluster" ) )
	{
		
		# do not process eprints with MS Academic entity ID set to "-"
		return 0 if $eprint->get_value( "msacademic_cluster" ) eq "-";

		# otherwise, we can use the existing MS Academic entity ID to retrieve data
		return 1;
	}
	
	return $eprint->is_set( "title" );
}

#
#
# This method queries the MS Academic Knowledge API for a given eprint.
#
# It returns an epdata hashref for a citation datum for $eprint or undef
# if no matches were found in the MS Knowledge API and EPrints.
#
# Croaks if there are problems receiving or parsing responses from the
# citation service, or if the citation service returns an error
# response.
#
sub get_epdata
{
	my ($plugin, $eprint) = @_;
	
	my $param = $plugin->{param};
	my $restart = $param->{restart};
	my $eprintid = $eprint->id;
	
	my $ms_data;
	my $found_match = 0;
	
	my $do_query = 1;
	if ($restart)
	{
		my $json_dir = $param->{report_dir} . '/json';
		my $filename =  $json_dir . '/msacademic_' . sprintf('%06s',$eprintid) . '.txt';
		if (-e $filename)
		{
			$do_query = 0;
			my $ms_response = $plugin->read_json_response( $eprint ); 
			
			if (defined $ms_response)
			{
				if ( $ms_response->{id} == 200 )
				{
					$ms_data = $plugin->process_json_response( $eprint, $ms_response );
					$found_match = $plugin->find_match( $eprint, $ms_data );
				}
			
				if ($ms_response->{id} >= 400 && $ms_response->{id} <= 410)
				{
					$plugin->process_error( $eprint, $ms_response );
				}
			}
		}
	}
	
	if ($do_query)
	{
		$plugin->_reset_query_methods();
	
		QUERY_METHOD: while( !$found_match && defined $plugin->_next_query_method() )
		{
			my $search = $plugin->_get_query( $eprint );
			next QUERY_METHOD if( !defined $search );

			# build the URL from which we can download the data
			my $request_uri = $plugin->_get_request_uri( $search );
		
			# Repeatedly query MS Academic Knowledge API until a response is
			# received or max allowed network requests has been reached.
			my $ms_response = $plugin->submit_request( $eprint, $request_uri );
		
			if (defined $ms_response)
			{
				if ( $ms_response->{id} == 200 )
				{
					$ms_data = $plugin->process_json_response( $eprint, $ms_response );
					$found_match = $plugin->find_match( $eprint, $ms_data );
				}
			
				if ($ms_response->{id} >= 400 && $ms_response->{id} <= 410)
				{
					$plugin->process_error( $eprint, $ms_response );
				}
			}
		}
	}
	
	if ( $found_match > 0 )
	{
		$plugin->process_msdata($eprint, $ms_data, $found_match);
		my $epdata = $plugin->response_to_epdata( $eprint );
		return $epdata;
	}
	
	return;
}

#
# Read MS Academic data from a JSON file stored on disk and process it.
#
sub read_msacademic_data
{
	my ($plugin, $eprint) = @_;
	
	my $ms_data;
	my $ms_response = $plugin->read_json_response( $eprint );
	
	if (defined $ms_response)
	{
		if ( $ms_response->{id} == 200 )
		{
			$ms_data = $plugin->process_json_response( $eprint, $ms_response );
			my $found_match = $plugin->find_match( $eprint, $ms_data );
				
			if ( $found_match > 0 )
			{
				$plugin->process_msdata($eprint, $ms_data, $found_match);
			}
		}
			
		if ($ms_response->{id} >= 400 && $ms_response->{id} <= 410)
		{
			$plugin->process_error( $eprint, $ms_response );
		}
	}

	return;
}

#
# Converts the MS Academic Knowledge API response to a epdata hash.
#
sub response_to_epdata
{
	my ($plugin, $eprint) = @_;
	
	my $cluster;
	my $citation_count;

	my $param = $plugin->{param};
	my $report = $plugin->{report};
	
	my $eprintid = $eprint->id;
	
	$cluster = $report->{$eprintid}->{msacademic}->{id};
	$citation_count = $report->{$eprintid}->{msacademic}->{citation_count};
	
	if( !defined $cluster )
	{
		$plugin->error( "MS Academic Knowledge API responded with no 'id' for eprint " . $eprintid );
		$cluster = $eprint->get_value( "msacademic_cluster" );
		$citation_count = $eprint->get_value( "msacademic_citation_count" );
	}
	
	return { 
		cluster => $cluster,
		impact => $citation_count
	};
}

#
# Process the eprint fields specified in the configuration and store
# their values for a given eprint in the report hash.
#
sub process_eprint_fields
{
	my ( $plugin, $dataset, $eprint ) = @_;
	
	my $param = $plugin->{param};
	my $report = $plugin->{report};
	my $eprint_fields = $param->{eprint_fields};
	
	my $eprintid = $eprint->id;
	
	foreach my $fieldname (@$eprint_fields)
	{
		my $field = $dataset->field( $fieldname );
		
		my $multiple = 0;
		$multiple = 1 if (defined $field->property( "multiple" ));

	    my $values = $eprint->get_value( $fieldname );
	    
	    $report->{$eprintid}->{eprint}->{$fieldname}->{multiple} = $multiple;
		$report->{$eprintid}->{eprint}->{$fieldname}->{values} = $values;
	}
	
	$plugin->process_eprint_author_count( $eprint );
	$plugin->apply_discipline_mappings( $eprint );
	
	return;
}

#
#  Determine the author count of an eprint and store it in the report hash
#
sub process_eprint_author_count
{
	my ( $plugin, $eprint ) = @_;
	
	my $param = $plugin->{param};
	my $report = $plugin->{report};
	
	my $eprintid = $eprint->id;
	
	my $creators_count = 0;
	my $editors_count = 0;
	
	if ($eprint->is_set( "creators" ) )
	{
		my $creators = $eprint->get_value( "creators" );
		$creators_count = scalar(@$creators);
	}
	
	if ($eprint->is_set( "editors" ) )
	{
		my $editors = $eprint->get_value( "editors" );
		$editors_count = scalar(@$editors);
	}
	
	my $authors_count = $creators_count + $editors_count;
	
	
	$report->{$eprintid}->{eprint}->{"author_count"}->{multiple} = 0;
	$report->{$eprintid}->{eprint}->{"author_count"}->{values} = $authors_count;

	return;
}

#
# Apply the subject->discipline mappings to a given eprint and store them 
# in the report hash.
#
sub apply_discipline_mappings
{
	my ( $plugin, $eprint ) = @_;
	
	my $param = $plugin->{param};
	
	my $mapping = $plugin->{mapping};
	my $report = $plugin->{report};
	
	my $eprintid = $eprint->id;
	
	my $subjects = $report->{$eprintid}->{eprint}->{'subjects'}->{values};
	my $disciplines;
		
	foreach my $subject (@$subjects)
	{
		my $discipline = "Other";
			
		if (defined $mapping->{$subject})
		{
			$discipline = $mapping->{$subject};
		}
			
		push @$disciplines, $discipline;
	}
		
	$report->{$eprintid}->{eprint}->{'disciplines'}->{multiple} = 1;
	$report->{$eprintid}->{eprint}->{'disciplines'}->{values} = $disciplines;
	
	return;
}

#
# Fill fields with empty values in order to create an aligned CSV file.
#
sub reset_msacademic_fields
{
	my ( $plugin, $eprint ) = @_;
	
	my $param = $plugin->{param};
	
	my $report = $plugin->{report};
	my $eprintid = $eprint->id;
	
	$report->{$eprintid}->{msacademic}->{id} = '';
	$report->{$eprintid}->{msacademic}->{year} = '';
	$report->{$eprintid}->{msacademic}->{date} = '';
	$report->{$eprintid}->{msacademic}->{citation_count} = '';
	$report->{$eprintid}->{msacademic}->{doi} = '';
	$report->{$eprintid}->{msacademic}->{journal} = '';
	$report->{$eprintid}->{msacademic}->{volume} = '';
	$report->{$eprintid}->{msacademic}->{issue} = '';
	$report->{$eprintid}->{msacademic}->{first_page} = '';
	$report->{$eprintid}->{msacademic}->{author_count} = '';
	
	return;
}

#
# Return the query string from the current query method or undef if it
# can't be created, e.g., if the eprint doesn't have the required
# metadata for that query.
#
sub _get_query
{
	my ($plugin, $eprint) = @_;
	
	my $query_generator_fname = $plugin->{queries}->[ $plugin->{current_query} ];
	return $plugin->$query_generator_fname( $eprint );
}

#
# Return the query expression for a MS Academic entity id
#
sub _get_queryexp_id
{
	my ($plugin, $eprint) = @_;
	
	return if ( !$eprint->is_set( 'msacademic_cluster' ) || $eprint->get_value( 'msacademic_cluster' ) eq '-' );
	
	my $msacademic_id = $eprint->get_value( "msacademic_cluster" );
	my $query_expression = 'Id=' . $msacademic_id;
	
	return $query_expression;
}

#
# Return the query expression for an exact title query
#
sub _get_queryexp_title_exact
{
	my ($plugin, $eprint) = @_;
	
	return if ( !$eprint->is_set( 'title' ) );
	
	my $title = $eprint->get_value( "title" );
	$title = $plugin->_clean_title( $title );
		
	my $query_expression = 'Ti=' . $plugin->_get_quoted_value( $title );

	return $query_expression;
}

#
# Return the query expression for an exact title query, transliterate greek symbols
#
sub _get_queryexp_title_exact_greek
{
	my ($plugin, $eprint) = @_;
	
	return if ( !$eprint->is_set( 'title' ) );
	
	my $title = $eprint->get_value( "title" );
	$title = $plugin->_clean_title( $title );
	$title = $plugin->_transliterate_greek( $title );
	
	my $query_expression = 'Ti=' . $plugin->_get_quoted_value( $title );

	return $query_expression;
}

#
# Return the query expression for a title words query,
# using the title terms saved in the Xapian index
#
sub _get_queryexp_title_words
{
	my ($plugin, $eprint) = @_;
	
	my $query_expression;
	my $title_words;
	my $eprintid = $eprint->id;

	my $path = $plugin->{session}->config( "variables_path" ) . "/xapian";
	my $xapian = Search::Xapian::Database->new( $path );
	# $xapian->reopen();

	my $doccount = $xapian->get_doccount;
	
	my $xapian_query = Search::Xapian::Query->new(
		Search::Xapian::OP_AND(),
		Search::Xapian::Query->new( 'eprintid:' . $eprintid )
	);

	my $enq = $xapian->enquire( $xapian_query );

	my @matches = $enq->matches(0, $doccount);

	foreach my $match (@matches)
	{
		$title_words = $plugin->_get_title_words( $match, 'title:', $title_words );
	}
	
	if (scalar keys %$title_words > 0)
	{
		foreach my $title_key (sort keys %$title_words)
		{
			my $word = $title_words->{$title_key};
			if ($title_key == 0)
			{
				$query_expression = "W=" . $plugin->_get_quoted_value( $word );  
			}
			else
			{
				$query_expression = "And(" . $query_expression . ",W=" . $plugin->_get_quoted_value( $word ) . ")";  
			}
		}
	}
	
	return $query_expression;
}

#
# Return the stop-word filtered title words from Xapian index of a 
# document
#
sub _get_title_words
{
	my ( $plugin, $match, $prefix, $words ) = @_;
	
	my $word_count = scalar(keys %$words);
	
	my $stopper = Search::Xapian::SimpleStopper->new( $plugin->_get_stopwords() );
	
	my $doc = $match->get_document();
	my $termlist_iterator = $doc->termlist_begin;
	
	$termlist_iterator->skip_to( $prefix );
	
	while ( $termlist_iterator ne $doc->termlist_end )
	{
		my $term = $termlist_iterator->get_termname();
		
		if ($term =~ /^$prefix/)
		{
			$term =~ s/^$prefix//;
			
			# filter all numbers
			if ($term =~ /^\d+$/ )
			{
				$termlist_iterator++;
				next;
			}
			
			# take the longer part before or after the apostrophe
			if ($term =~ /\'/ )
			{
				$term =~ s/(.*?)\'(.*)/$1 $2/;
				
				if (length($1) > length($2))
				{
					$term = $1;
				}
				else
				{
					$term = $2;
				}
			}
			
			# filter stop words
			if ( !$stopper->stop_word( $term ) )
			{
				$words->{$word_count} = $term;
				$word_count++;
			}
		}
		$termlist_iterator++;
	}
	
	return $words;
}

#
# Enclose the value into single quotes
#
sub _get_quoted_value
{
	my ( $plugin, $value ) = @_;
	
	my $apos = "'";
	return $apos . $value . $apos;
}

#
# Remove special characters, punctuation marks and superfluous white space from title
#
sub _clean_title
{
	my ( $plugin, $title ) = @_;
	
	$title = lc $title;
	
	#remove LaTeX commands
	$title =~ s/\$\_\{(.*?)}\$/$1/g;
	$title =~ s/\_\{(.*?)}/$1/g;
	$title =~ s/\$\^\{(.*?)}\$/$1/g;
	$title =~ s/\^\{(.*?)}/$1/g;
	$title =~ s/\$\^//g;
	$title =~ s/\$_//g;
	$title =~ s/\\overline//g;
	$title =~ s/\\rightarrow//g;
	
	#remove special characters
	$title =~ s/\x{2013}|\x{2032}|\x{2033}|\x{2034}|\x{2212}|\x{221A}/ /g;
	$title =~ s/\+|\-|_|<|=|>|&|%|\(|\)|\[|]|\{|}|\^|\.|,|\:|;|\?|!|'|"|\||\\|\$|\/|\*/ /g;
	$title =~ s/\r//g;
	$title =~ s/^\s+//;
	$title =~ s/\s+$//;
	$title =~ s/\s+/ /g;
	
	return $title;
}

#
# Transliterate greek symbols to their UTF-8 equivalent.
# It is assumed that _clean_title has been called before.
# There may be some ambivalencies, e.g. phi, pi, mu or nu
# may be found as parts of words - however, transliteration
# of those should result in a no-match if queried
#
sub _transliterate_greek
{
	my ( $plugin, $title ) = @_;
		
	my %transliteration = (
		"alpha" => "α",
		"beta" => "β",
		"gamma" => "γ",
		"delta" => "δ",
		"epsilon" => "ε",
		"zeta" => "ζ",
		"eta" => "η",
		"theta" => "θ",
		"iota" => "ι",
		"kappa" => "κ",
		"lambda" => "λ",
		"mu" => "μ",
		"nu" => "ν",
		"xi" => "ξ",
		"omicron" => "ο",
		"pi" => "π",
		"rho" => "ρ",
		"sigma" => "σ",
		"tau" => "τ",
		"upsilon" => "υ",
		"phi" => "φ",
		"chi" => "χ",
		"psi" => "ψ",
		"omega" => "ω",
	);
	
	foreach my $greek (keys %transliteration)
	{
		my $replace = $transliteration{$greek};
		my $find = $greek;
		my $find_re = qr/$find/;
		
		$title =~ s/$find_re/$replace/g;
	}
	
	return $title;
}

#
# Select the next query method. Returns the  zero-based index thereof, or undef 
# if all query options are exhausted.
#
# By default these return undef, so concrete plugins don't need to
# override.
#
sub _next_query_method
{
	my ( $plugin ) = @_;
	if ( $plugin->{current_query} >= ( scalar @{ $plugin->{queries} } - 1 ) )
	{
		$plugin->{current_query} = undef;
		return;
	}
	return $plugin->{current_query}++;
}

#
# Start iterating through the list of query methods again.
#
# next_query_method() must be called before the next query after a
# call to this.
#
sub _reset_query_methods
{
	my ( $plugin ) = @_;
	$plugin->{current_query} = -1;
	return;
}

#
# Construct the query URI.
#
sub _get_request_uri
{
	my( $plugin, $query_expression ) = @_;

	my $param = $plugin->{param};

	my $request = $plugin->{baseuri};
	
	$request->query_form(
		expr => $query_expression,
		model => 'latest',
		count => $param->{answer_count},
		offset => '0',
		attributes => $param->{msacademic_fields},
	);
	
	return $request;
}

#
# Submit the MS Academic Knowledge API request
#
sub submit_request
{
	my ( $plugin, $eprint, $request_url ) = @_;
	
	my $eprintid = $eprint->id;
	my $param = $plugin->{param};
	my $repo_baseurl = $plugin->{session}->get_repository->config( "base_url" );

	my $noise = $param->{noise};
	my $crawl_retry = $param->{crawl_retry};
	my $crawl_delay = $param->{crawl_delay};
	
	print STDOUT "MS Academic Knowledge API URL: [$request_url]\n" if $noise > 1;

	my $response = {};
	my $ms_response = {};
	
	my $request_counter = 1;
	my $success = 0;
	my $req = HTTP::Request->new( "GET", $request_url );
	$req->header( "Accept" => "application/json" );
	$req->header( "Accept-Charset" => "utf-8" );
	$req->header( "User-Agent" => "EPrints MS Academic Knowledge API Sync; EPrints 3.3.x; " . $repo_baseurl );
	$req->header( "Ocp-Apim-Subscription-Key" => $plugin->{apikey});
	
	while (!$success && $request_counter <= $crawl_retry)
	{
		print STDERR "Request #$request_counter\n" if ($noise >= 3);
		my $ua = LWP::UserAgent->new;
		$ua->env_proxy;
		$ua->timeout(60);
		$response = $ua->request($req);
		$success = $response->is_success;
		$request_counter++;
		sleep $crawl_delay;
	}
	
	$ms_response->{id} = $response->code;
	
	if ( $response->code == 200 || ($response->code >= 400 && $response->code <= 410) )
	{
		$ms_response->{content} = $response->content;
	}
	else 
	{
		print STDERR "No response from MS Academic Knowledge API for eprint $eprintid\n";
	}
	
	return $ms_response;
}

#
# Decode and process the JSON response
#
sub process_json_response
{
	my ($plugin, $eprint, $ms_response) = @_;
	
	my $param = $plugin->{param};
	
	my $response_content = $ms_response->{content};
	
	if ($param->{save_json})
	{
		$plugin->save_json_response( $eprint, $response_content );
	}
	
	my $json_vars = JSON::decode_json($response_content);
	return $json_vars;
}

#
# Save the MS Academic Knowledge API JSON response to disk.
#
sub save_json_response
{
	my ($plugin, $eprint, $response) = @_;
	
	my $param = $plugin->{param};
	
	my $json_dir = $param->{report_dir} . '/json';
	
	my $eprintid = $eprint->id;
	
	my $filename =  $json_dir . '/msacademic_' . sprintf('%06s',$eprintid) . '.txt';
	open my $jsonout, ">", $filename or die "Cannot open > $filename\n";
	print $jsonout $response;
	close($jsonout);
	
	return;
}

#
# Find out if one the returned MS Academic entities is matching, 
# and on which property it is matching.
# Returns the number of the matched MS Academic entity (0 = no match).
#
sub find_match
{
	my ($plugin, $eprint, $ms_data) = @_;
	
	my $match_found = 0;
	
	my $param = $plugin->{param};
	my $verbose = $param->{verbose};
	my $report = $plugin->{report};
	
	my $eprintid = $eprint->id;
	
	# variable for id match
	my $eprint_msacademic_cluster;
	if ($eprint->is_set( "msacademic_cluster" ) )
	{
		$eprint_msacademic_cluster = $eprint->get_value( "msacademic_cluster" );
	}
	
	# variable for doi match
	my $eprint_doi;
	if ($eprint->is_set( "doi" ) )
	{
		$eprint_doi = $eprint->get_value( "doi" );
	}

	# variable for title match
	my $eprint_title = $eprint->get_value( "title" );
	my $eprint_title_clean = $plugin->_clean_title( $eprint_title );
	my $eprint_title_greek = $plugin->_transliterate_greek( $eprint_title_clean );
	
	# variables for bibliographic match
	# do not take publication year since this is known to be inexact in MS Academic
	my $eprint_journal_series;
	$eprint_journal_series = $eprint->get_value( "series" ) if ( $eprint->is_set( "series" ) ); 
	$eprint_journal_series = $eprint->get_value( "publication" ) if ( $eprint->is_set( "publication" ) ); 
	my $eprint_volume = $eprint->get_value( "volume" );
    my $eprint_issue = $eprint->get_value( "number" );
    my $eprint_pagerange = $eprint->get_value( "pagerange" );
    
    my $eprint_firstpage;
    if (defined $eprint_pagerange)
    {
    	
    	if ($eprint_pagerange =~ /-/ )
    	{
    		$eprint_pagerange =~ /(.*?)-(.*)/;
    		if ( defined $1 )
    		{
    			$eprint_firstpage = $1;
    		}
    	}
    	else
    	{
    		$eprint_firstpage = $eprint_pagerange;
    	}
    }
    
    my $entities = $ms_data->{entities};
	my $entity_count = scalar @$entities;
	
	$report->{$eprintid}->{msacademic}->{result_status} = "success";
	$report->{$eprintid}->{msacademic}->{result_message} = "";
	$report->{$eprintid}->{msacademic}->{result_count} = $entity_count;
    
    #	
	# Find out which answer and which properties do match
	# Try out: ID, DOI, title, and bibliographic match
	#
	my $id_match = 0;
	my $doi_match = 0;
	my $bibliographic_match = 0;
	my $title_match = 0;
	
	if ($entity_count > 0)
	{
		my $loop = 0;
		foreach my $entity (@$entities)
		{
			$loop++;
			
			my $e_string = $entity->{E};
			my $extended_metadata = $plugin->_parse_extended_metadata( $e_string );
			
			# ID match
			my $msacademic_id = $entity->{Id};
			if ( defined $eprint_msacademic_cluster && $eprint_msacademic_cluster eq $msacademic_id )
			{
				$id_match = $loop;
			}
			
			# DOI match	
			my $msacademic_doi = $extended_metadata->{DOI};
		
			if (defined $msacademic_doi && $eprint_doi eq $msacademic_doi)
			{
				$doi_match = $loop;
			}
			
			# bibliographic match
			my $msacademic_journal = $extended_metadata->{VFN};
			my $msacademic_volume = $extended_metadata->{V};
			my $msacademic_issue = $extended_metadata->{I};
			my $msacademic_firstpage = $extended_metadata->{FP};
			
			# weak match first
			if (defined $msacademic_journal && defined $msacademic_volume && defined $msacademic_firstpage )
			{
				if ($eprint_journal_series eq $msacademic_journal && $eprint_volume eq $msacademic_volume && $eprint_firstpage eq $msacademic_firstpage)
				{
					$bibliographic_match = $loop;
				}
			}
			
			# then stronger match
			if (defined $msacademic_journal && defined $msacademic_volume && defined $msacademic_issue && defined $msacademic_firstpage 
			  && defined $eprint_journal_series && defined $eprint_volume && defined $eprint_issue && defined $eprint_firstpage)
			{
				if ($eprint_journal_series eq $msacademic_journal && $eprint_volume eq $msacademic_volume 
					&& $eprint_issue eq $msacademic_issue && $eprint_firstpage eq $msacademic_firstpage)
				{
					$bibliographic_match = $loop;
				}
			}
			
			# title match
			my $msacademic_title = $entity->{Ti};
			if (defined $msacademic_title && ( $eprint_title_clean eq $msacademic_title || $eprint_title_greek eq $msacademic_title ) )
			{
				$title_match = $loop;
			}
		}
	}
	
	print STDOUT "Entities: $entity_count, Matches: id: $id_match, doi: $doi_match, bib: $bibliographic_match, title: $title_match\n" if $verbose;
	
	my $entity_matched;
	
	# select the entity based on the best match: ID > DOI > title > bibliographic
	$report->{$eprintid}->{msacademic}->{match_type} = "none";

	if ($bibliographic_match > 0)
	{
		$entity_matched = $bibliographic_match - 1;
		$report->{$eprintid}->{msacademic}->{match_type} = "bib";
	}
	if ($title_match > 0)
	{
		$entity_matched = $title_match - 1;
		$report->{$eprintid}->{msacademic}->{match_type} = "tit";
	}
	if ($doi_match > 0)
	{
		$entity_matched = $doi_match - 1;
		$report->{$eprintid}->{msacademic}->{match_type} = "doi";
	}
	if ($id_match > 0)
	{
		$entity_matched = $id_match - 1;
		$report->{$eprintid}->{msacademic}->{match_type} = "id";
	}
	
	if (defined $entity_matched)
	{
		$report->{$eprintid}->{msacademic}->{matched_record} = $entity_matched + 1;
		$report->{$eprintid}->{msacademic}->{bib_match} = $bibliographic_match;
		$report->{$eprintid}->{msacademic}->{tit_match} = $title_match;
		$report->{$eprintid}->{msacademic}->{doi_match} = $doi_match;
		$report->{$eprintid}->{msacademic}->{id_match} = $id_match;
		$match_found = $entity_matched + 1;
	}
	else
	{
		$report->{$eprintid}->{msacademic}->{matched_record} = 0;
		$report->{$eprintid}->{msacademic}->{bib_match} = "none";
		$report->{$eprintid}->{msacademic}->{tit_match} = "none";
		$report->{$eprintid}->{msacademic}->{doi_match} = "none";
	}
    
    return $match_found;
}

#
# parse the MS Academic Knowledge API extended metadata into a JSON hash
#
sub _parse_extended_metadata
{
	my ($plugin, $e_string) = @_;

	$e_string =~ s/\\\\\"\],\"2143890424\"/\"\],\"2143890424\"/g;
	$e_string =~ s/\\\\\"\],\"1965888463\"/\"\],\"1965888463\"/g;	
	$e_string =~ s/\\\\"\],\"2021764794\"/\"\],\"2021764794\"/g;
	$e_string =~ s/\\\\\\\\":\[/":\[/g;
	$e_string =~ s/\\\\":\[/":\[/g;
	$e_string =~ s/"\\\\"/""/g;
	$e_string =~ s/\\r//g;
	$e_string =~ s/\\n//g;
	$e_string =~ s/\\"/'/g;
	$e_string =~ s/\\//g;
	
	my $json = JSON->new->utf8( 0 );
	my $json_extended_metadata = $json->decode($e_string);
	
	return $json_extended_metadata;
}

#
# Process the Academic Knowledge API entities
#
sub process_msdata
{
	my ($plugin, $eprint, $ms_data, $entity_matched) = @_;
	
	my $entities = $ms_data->{entities};
	
	my @msacademic_records = @$entities;
	my $msacademic_record = $msacademic_records[$entity_matched - 1];
	
	$plugin->process_msacademic_fields( $eprint, $msacademic_record );
	
	return;
}

#
# Process the MS Academic Knowledge API fields of a matched entity
# and store them in the report hash
#
sub process_msacademic_fields
{
	my ( $plugin, $eprint, $msacademic_record ) = @_;
	
	my $report = $plugin->{report};
	my $eprintid = $eprint->id;
	
	my $extended_metadata = $plugin->_parse_extended_metadata( $msacademic_record->{E} );
	
	$report->{$eprintid}->{msacademic}->{id} = $msacademic_record->{Id};
	$report->{$eprintid}->{msacademic}->{year} = $msacademic_record->{Y};
	$report->{$eprintid}->{msacademic}->{date} = $msacademic_record->{D};
	$report->{$eprintid}->{msacademic}->{citation_count} = $msacademic_record->{CC};
	$report->{$eprintid}->{msacademic}->{doi} = $extended_metadata->{DOI};
	$report->{$eprintid}->{msacademic}->{journal} = $extended_metadata->{VFN};
	$report->{$eprintid}->{msacademic}->{volume} = $extended_metadata->{V};
	$report->{$eprintid}->{msacademic}->{issue} = $extended_metadata->{I};
	$report->{$eprintid}->{msacademic}->{first_page} = $extended_metadata->{FP};
	
	#
	# check whether the matched record has the own institution's affiliation
	#
	$report->{$eprintid}->{msacademic}->{has_affiliation} = $plugin->process_affiliation( $msacademic_record );
	
	#
	# determine the reference count
	#
	$report->{$eprintid}->{msacademic}->{reference_count} = $plugin->process_reference_count( $msacademic_record );
	
	#
	# determine the author count
	#
	$report->{$eprintid}->{msacademic}->{author_count} = $plugin->process_msacademic_author_count( $msacademic_record );
	
	return;
}

#
# Process the affiliation of a MS Academic entity and set a flag if the affiliation id 
# matches the given institution affiliation id
#
sub process_affiliation
{
	my ( $plugin, $msacademic_record ) = @_;
	
	my $param = $plugin->{param};
	my $institution_id = $param->{institution_id};
	
	my $author_data = $msacademic_record->{AA};
	
	my $has_affiliation = 0; 
	
	foreach my $author (@$author_data)
	{
		if (defined $author->{AfId})
		{
			$has_affiliation = 1 if ($author->{AfId} == $institution_id);
		}
	}
	
	return $has_affiliation;
}

#
# Return the reference count of the matched MS Academic Graph entity
#
sub process_reference_count
{
	my ( $plugin, $msacademic_record ) = @_;
	
	my $reference_count = 0;
	
	my $references = $msacademic_record->{RId};
	
	if (defined $references)
	{
		$reference_count = scalar(@$references);
	}
	
	return $reference_count;
}

#
# Return the author count of the matched MS Academic Graph entity
#
sub process_msacademic_author_count
{
	my ( $plugin, $msacademic_record ) = @_;
	
	my $author_data = $msacademic_record->{AA};
	
	my $author_count = 0;
	
	if (defined $author_data)
	{
		$author_count = scalar(@$author_data) ;
	}
	
	return $author_count;
}


#
# Read the stored MS Academic Knowledge API JSON response for
# a given eprint from disk and return a decoded JSON hash. 
#
sub read_json_response
{
	my ( $plugin, $eprint ) = @_;
	
	my $param = $plugin->{param};
	my $verbose = $param->{verbose};
	my $eprintid = $eprint->id; 
	
	my $json_dir = $param->{report_dir} . '/json';
	my $filename =  $json_dir . '/msacademic_' . sprintf('%06s',$eprintid) . '.txt';
	
	if (-e $filename )
	{
		my $response_data;
		
		open my $jsonin, "<", $filename or die "Cannot open > $filename\n";
		local $/ = undef;
		my $response_content = <$jsonin>;
		close($jsonin);

		print STDOUT $response_content if $verbose;
	
		my $json_vars = JSON::decode_json($response_content);
		
		# check whether we have a error message
		if (defined $json_vars->{error}->{code})
		{
			$response_data->{id} = 400;
		}
		else
		{
			$response_data->{id} = 200;
		}
		
		$response_data->{content} = $response_content;
	
		return $response_data;
	}
	return;
}

#
# Save a report as XML.
#
sub save_report_xml
{
	my ( $plugin ) = @_;
	
	my $param = $plugin->{param};
	my $verbose = $param->{verbose};
	my $report = $plugin->{report};
	my $report_dir = $param->{report_dir};
	
	my $filename = $report_dir . '/report.xml';
	
	print STDOUT "Saving XML report to $filename\n" if $verbose;
	
	my $count = scalar keys %$report;
	
	my $xmldoc = XML::LibXML::Document->new('1.0','utf-8');
	my $element_records = $xmldoc->createElement( "records" );
	$element_records->setAttribute( "count", $count );
	
	foreach my $recordid (sort {$a <=> $b} keys %$report)
	{
		my $element_record = $xmldoc->createElement( "record" );
		$element_record->setAttribute( "id", $recordid );
		$element_records->appendChild( $element_record );
		
		# EPrints part
		my $element_eprint = $xmldoc->createElement( "eprint" );
		$element_record->appendChild( $element_eprint );
		
		my $eprint = $report->{$recordid}->{eprint};
		foreach my $fieldname (keys %{$eprint})
		{
			my $multiple = $eprint->{$fieldname}->{multiple};
			
			my $element_field = $xmldoc->createElement( "field" );
			$element_field->setAttribute( "name", $fieldname );
			$element_field->setAttribute( "multiple", $multiple );
			$element_eprint->appendChild( $element_field );
			
			my $values = $eprint->{$fieldname}->{values};
			if ($multiple == 0)
			{
				my $element_value = $xmldoc->createElement( "value" );
				$element_value->appendTextNode( $values ) if defined $values;
				$element_field->appendChild( $element_value );
			}
			else
			{
				foreach my $value (@$values)
				{
					my $element_value = $xmldoc->createElement( "value" );
					$element_value->appendTextNode( $value );
					$element_field->appendChild( $element_value );
				}
			}
		}
		
		# MS Academic Knowledge API result part
		my $element_msacademic = $xmldoc->createElement( "msacademic" );
		$element_record->appendChild( $element_msacademic );
		
		my $msacademic = $report->{$recordid}->{msacademic};
		
		foreach my $msacademic_key (keys %{$msacademic})
		{
			my $element_field = $xmldoc->createElement( "field" );
			$element_field->setAttribute( "name", $msacademic_key );
			$element_msacademic->appendChild( $element_field );
			
			my $value = $msacademic->{$msacademic_key};
			my $element_value = $xmldoc->createElement( "value" );
			$element_value->appendTextNode( $value ) if defined $value;
			$element_field->appendChild( $element_value );
		}
	}
	
	$xmldoc->setDocumentElement( $element_records );
	my $xmldoc_string = $xmldoc->toString(1);
	
	open my $xmlout, ">", $filename or die "Cannot open > $filename\n";
	print $xmlout $xmldoc_string;
	close $xmlout;
	
	return;
}

#
# Save a report as CSV.
#
sub save_report_csv
{
	my ( $plugin ) = @_;
	
	my $param = $plugin->{param};
	
	my $verbose = $param->{verbose};
	my $report = $plugin->{report};
	my $report_dir = $param->{report_dir};
	
	my $filename = $report_dir . '/report.csv';
	open my $csvout, ">:encoding(utf8)", $filename or die "Cannot open > $filename\n";
	
	print STDOUT "Saving CSV report to $filename\n" if $verbose;
	
	my $csv = Text::CSV->new();
	$csv->eol("\n");
	
	# print headers
	my @headers;
	
	keys %{$report};
	my $recordid = each %$report;
	
	my $eprint = $report->{$recordid}->{eprint};
	foreach my $fieldname (keys %{$eprint})
	{
		push @headers, $fieldname;
	}
	
	my $msacademic = $report->{$recordid}->{msacademic};
	foreach my $msacademic_key (keys %{$msacademic})
	{
		push @headers, $msacademic_key;
	}
	
	$csv->print( $csvout, \@headers );
	
	# print field values
	foreach my $recordid (sort {$a <=> $b} keys %$report)
	{
		my @csv_values = ();
		
		# eprint
		my $eprint_record = $report->{$recordid}->{eprint};
		foreach my $fieldname (keys %$eprint_record)
		{
			my $multiple = $eprint_record->{$fieldname}->{multiple};
			my $csv_value = '';
			my $values = $eprint_record->{$fieldname}->{values};
			if ($multiple == 0)
			{
				$csv_value = $values;
				if (defined $csv_value)
				{
					if ($csv_value =~ /\r/ )
					{
						print STDERR "EPrint $recordid, field $fieldname contains carriage returns.\n";
						$csv_value =~ s/\r//g;
					}
				}
			}
			else
			{
				my $first = 1;
				foreach my $value (@$values)
				{
					if ($first)
					{
						$csv_value = $value;
						$first = 0;
					}
					else
					{
						$csv_value .= ' ' . $value;
					}
				}
			}
			push @csv_values, $csv_value;
		}
		
		# MS Academic Knowledge API fields
		my $msacademic_record = $report->{$recordid}->{msacademic};
		foreach my $msacademic_key (keys %$msacademic_record)
		{
			my $csv_value = $msacademic_record->{$msacademic_key};
			push @csv_values, $csv_value;
		}
		
		$csv->print( $csvout, \@csv_values );
	}
	
	close $csvout;
	
	return;
}

#
# Read the mappings from subject ids to disciplines from a CSV file
#
sub read_discipline_mappings
{
	my ( $plugin, $csv_file ) = @_;
	
	my $param = $plugin->{param};
	my $verbose = $param->{verbose};
	my $mapping = $plugin->{mapping};
	
	print STDOUT "Reading mappings from $csv_file\n" if $verbose;
	
	my $csv = Text::CSV->new() or die "Cannot use CSV: " . Text::CSV->error_diag ();
   
	my $line_count = 0;
	
	open(my $fh, '<', $csv_file) or die "Cannot read file '$csv_file' [$!]\n";
	
	while (my $line = <$fh>) 
	{
		$line_count++;
    	chomp $line;
    	
    	if ( $csv->parse($line) ) 
    	{
    		my @fields = $csv->fields();
    		
    		my $orgid = $fields[0];
    		my $discipline = $fields[1];
    		
    		$mapping->{$orgid} = $discipline;
    	}
		else
    	{
    		print STDERR "Line $line_count could not be parsed: $line\n";
    	}
	}
	close($fh);
	
	return;
}


#
# Process the error if the MS Academic Knowledge API did not respond
#
sub process_error
{
	my ( $plugin, $eprint, $ms_data ) = @_;
	
	my $param = $plugin->{param};
	my $report = $plugin->{report};
	
	my $eprintid = $eprint->id;
	
	my $error_id = $ms_data->{id};
	my $response_content = $ms_data->{content};
	
	if ($param->{save_json})
	{
		$plugin->save_json_response( $eprint, $response_content );
	}
		
	my $json_vars = JSON::decode_json($response_content);
	
	my $error_code = $json_vars->{error}->{code};
	my $error_message = $json_vars->{error}->{message};
	
	$report->{$eprintid}->{msacademic}->{result_status} = "error: " . $error_code;
	$report->{$eprintid}->{msacademic}->{result_message} = $error_message;
	$report->{$eprintid}->{msacademic}->{result_count} = -1;
	
	print STDERR "HTTP Error $error_id, Error: $error_code, $error_message\n";
	
	return;
}



#
# Return the stop words for filtering title words
#
sub _get_stopwords
{
	my ($plugin) = @_;

	my @STOPWORDS = qw(
		a
		about
		above
		abstract
		across
		after
		again
		against
		all
		almost
		alone
		along
		already
		also
		although
		always
		among
		an
		analysis
		analyzed
		and
		another
		any
		anybody
		anyone
		anything
		anywhere
		are
		area
		areas
		around
		as
		ask
		asked
		asking
		asks
		associated
		at
		available
		away
		b
		back
		backed
		backing
		backs
		based
		be
		became
		because
		become
		becomes
		been
		before
		began
		behind
		being
		beings
		best
		better
		between
		big
		both
		but
		by
		c
		came
		can
		cannot
		case
		cases
		certain
		certainly
		clear
		clearly
		come
		compared
		considered
		could
		d
		demonstrate
		demonstrated
		described
		did
		differ
		different
		differently
		discussed
		do
		does
		done
		down
		down
		downed
		downing
		downs
		due
		during
		e
		each
		early
		eight
		either
		end
		ended
		ending
		ends
		enough
		establish
		established
		establishes
		evaluated
		even
		evenly
		ever
		every
		everybody
		everyone
		everything
		everywhere
		f
		face
		faces
		fact
		facts
		far
		felt
		few
		find
		findings
		finds
		first
		five
		for
		four
		from
		full
		fully
		further
		furthered
		furthering
		furthers
		g
		gave
		general
		generally
		get
		gets
		give
		given
		gives
		go
		going
		good
		goods
		got
		great
		greater
		greatest
		group
		grouped
		grouping
		groups
		h
		had
		has
		have
		having
		he
		her
		here
		herself
		high
		high
		high
		higher
		highest
		him
		himself
		his
		how
		however
		i
		if
		ii
		iii
		important
		improve
		improved
		in
		including
		increased
		interest
		interested
		interesting
		interests
		into
		is
		it
		its
		itself
		j
		just
		k
		keep
		keeps
		kind
		knew
		know
		known
		knows
		l
		large
		largely
		last
		later
		latest
		least
		less
		let
		lets
		like
		likely
		long
		longer
		longest
		m
		made
		make
		making
		man
		many
		may
		me
		member
		members
		men
		method
		might
		more
		moreover
		most
		mostly
		mr
		mrs
		much
		must
		my
		myself
		n
		near
		necessary
		need
		needed
		needing
		needs
		never
		new
		new
		newer
		newest
		next
		nine
		no
		nobody
		non
		noone
		not
		nothing
		now
		nowhere
		number
		numbers
		o
		obtained
		of
		off
		often
		old
		older
		oldest
		on
		once
		one
		only
		open
		opened
		opening
		opens
		or
		order
		ordered
		ordering
		orders
		other
		others
		our
		out
		over
		p
		part
		parted
		particular
		parting
		parts
		per
		perhaps
		place
		places
		point
		pointed
		pointing
		points
		possible
		potentially
		present
		presented
		presenting
		presents
		problem
		problems
		produced
		proposed
		provided
		provides
		put
		puts
		q
		quite
		r
		rather
		really
		recent
		related
		report
		reported
		required
		result
		results
		right
		right
		room
		rooms
		s
		said
		same
		saw
		say
		says
		second
		seconds
		see
		seem
		seemed
		seeming
		seems
		sees
		seven
		several
		shall
		she
		should
		show
		showed
		showing
		shows
		side
		sides
		since
		six
		small
		smaller
		smallest
		so
		some
		somebody
		someone
		something
		somewhere
		state
		states
		still
		study
		such
		suggest
		sure
		t
		take
		taken
		ten
		than
		that
		the
		their
		them
		then
		there
		therefore
		these
		they
		thing
		things
		think
		thinks
		this
		those
		though
		thought
		thoughts
		three
		through
		thus
		to
		today
		together
		too
		took
		toward
		turn
		turned
		turning
		turns
		two
		u
		under
		until
		up
		upon
		us
		use
		used
		uses
		using
		v
		various
		very
		w
		want
		wanted
		wanting
		wants
		was
		way
		ways
		we
		well
		wells
		went
		were
		what
		when
		where
		whether
		which
		whichever
		while
		who
		whole
		whose
		why
		will
		with
		within
		without
		work
		worked
		working
		works
		would
		x
		y
		year
		years
		yet
		you
		young
		younger
		youngest
		your
		yours
		z
		ab
		aber
		aber
		ach
		acht
		achte
		achten
		achter
		achtes
		ag
		alle
		allein
		allem
		allen
		aller
		allerdings
		alles
		allgemeinen
		als
		als
		also
		am
		an
		andere
		anderen
		andern
		anders
		au
		auch
		auch
		auf
		aus
		ausser
		außer
		ausserdem
		außerdem
		bald
		bei
		beide
		beiden
		beim
		beispiel
		bekannt
		bereits
		besonders
		besser
		besten
		bin
		bis
		bisher
		bist
		da
		dabei
		dadurch
		dafür
		dagegen
		daher
		dahin
		dahinter
		damals
		damit
		danach
		daneben
		dank
		dann
		daran
		darauf
		daraus
		darf
		darfst
		darin
		darüber
		darum
		darunter
		das
		das
		dasein
		daselbst
		dass
		daß
		dasselbe
		davon
		davor
		dazu
		dazwischen
		dein
		deine
		deinem
		deiner
		dem
		dementsprechend
		demgegenüber
		demgemäss
		demgemäß
		demselben
		demzufolge
		den
		denen
		denn
		denn
		denselben
		der
		deren
		derjenige
		derjenigen
		dermassen
		dermaßen
		derselbe
		derselben
		des
		deshalb
		desselben
		dessen
		deswegen
		d.h
		dich
		die
		diejenige
		diejenigen
		dies
		diese
		dieselbe
		dieselben
		diesem
		diesen
		dieser
		dieses
		dir
		doch
		dort
		drei
		drin
		dritte
		dritten
		dritter
		drittes
		du
		durch
		durchaus
		dürfen
		dürft
		durfte
		durften
		eben
		ebenso
		ehrlich
		ei
		eigen
		eigene
		eigenen
		eigener
		eigenes
		ein
		einander
		eine
		einem
		einen
		einer
		eines
		einige
		einigen
		einiger
		einiges
		einmal
		einmal
		eins
		elf
		en
		ende
		endlich
		entweder
		entweder
		er
		ernst
		erst
		erste
		ersten
		erster
		erstes
		es
		etwa
		etwas
		euch
		früher
		fünf
		fünfte
		fünften
		fünfter
		fünftes
		für
		gab
		ganz
		ganze
		ganzen
		ganzer
		ganzes
		gar
		gedurft
		gegen
		gegenüber
		gehabt
		gehen
		geht
		gekannt
		gekonnt
		gemacht
		gemocht
		gemusst
		genug
		gerade
		gern
		gesagt
		gesagt
		geschweige
		gewesen
		gewollt
		geworden
		gibt
		ging
		gleich
		gross
		groß
		grosse
		große
		grossen
		großen
		grosser
		großer
		grosses
		großes
		gut
		gute
		guter
		gutes
		habe
		haben
		habt
		hast
		hat
		hatte
		hätte
		hatten
		hätten
		heisst
		her
		heute
		hier
		hin
		hinter
		hoch
		ich
		ihm
		ihn
		ihnen
		ihr
		ihre
		ihrem
		ihren
		ihrer
		ihres
		im
		immer
		in
		indem
		infolgedessen
		ins
		irgend
		ist
		ja
		jahr
		jahre
		jahren
		je
		jede
		jedem
		jeden
		jeder
		jedermann
		jedermanns
		jedoch
		jemand
		jemandem
		jemanden
		jene
		jenem
		jenen
		jener
		jenes
		jetzt
		kam
		kann
		kannst
		kaum
		kein
		keine
		keinem
		keinen
		keiner
		kleine
		kleinen
		kleiner
		kleines
		kommen
		kommt
		können
		könnt
		konnte
		könnte
		konnten
		kurz
		lang
		lange
		lange
		leicht
		leide
		lieber
		los
		machen
		macht
		machte
		mag
		magst
		mahn
		man
		manche
		manchem
		manchen
		mancher
		manches
		mann
		mehr
		mein
		meine
		meinem
		meinen
		meiner
		meines
		mensch
		menschen
		mich
		mir
		mit
		mittel
		mochte
		möchte
		mochten
		mögen
		möglich
		mögt
		morgen
		muss
		muß
		müssen
		musst
		müsst
		musste
		mussten
		na
		nach
		nachdem
		nahm
		natürlich
		neben
		nein
		neue
		neuen
		neun
		neunte
		neunten
		neunter
		neuntes
		nicht
		nicht
		nichts
		nie
		niemand
		niemandem
		niemanden
		noch
		nun
		nun
		nur
		ob
		oben
		oder
		offen
		oft
		oft
		ohne
		Ordnung
		recht
		rechte
		rechten
		rechter
		rechtes
		richtig
		rund
		sa
		sache
		sagt
		sagte
		sah
		satt
		schlecht
		Schluss
		schon
		sechs
		sechste
		sechsten
		sechster
		sechstes
		sehr
		sei
		sei
		seid
		seien
		sein
		seine
		seinem
		seinen
		seiner
		seines
		seit
		seitdem
		selbst
		sich
		sie
		sieben
		siebente
		siebenten
		siebenter
		siebentes
		sind
		so
		solang
		solche
		solchem
		solchen
		solcher
		solches
		soll
		sollen
		sollte
		sollten
		sondern
		sonst
		sowie
		später
		statt
		tag
		tage
		tagen
		tat
		teil
		tel
		tritt
		trotzdem
		tun
		über
		überhaupt
		übrigens
		uhr
		um
		und
		uns
		unser
		unsere
		unserer
		unter
		vergangenen
		viel
		viele
		vielem
		vielen
		vielleicht
		vier
		vierte
		vierten
		vierter
		viertes
		vom
		von
		vor
		wahr
		während
		währenddem
		währenddessen
		wann
		war
		wäre
		waren
		wart
		warum
		was
		wegen
		weil
		weit
		weiter
		weitere
		weiteren
		weiteres
		welche
		welchem
		welchen
		welcher
		welches
		wem
		wen
		wenig
		wenig
		wenige
		weniger
		weniges
		wenigstens
		wenn
		wenn
		wer
		werde
		werden
		werdet
		wessen
		wie
		wie
		wieder
		will
		willst
		wir
		wird
		wirklich
		wirst
		wo
		wohl
		wollen
		wollt
		wollte
		wollten
		worden
		wurde
		würde
		wurden
		würden
		zehn
		zehnte
		zehnten
		zehnter
		zehntes
		zeit
		zu
		zuerst
		zugleich
		zum
		zum
		zunächst
		zur
		zurück
		zusammen
		zwanzig
		zwar
		zwar
		zwei
		zweite
		zweiten
		zweiter
		zweites
		zwischen
		zwölf
		à
		â
		abord
		afin
		ah
		ai
		aie
		ainsi
		allaient
		allo
		allô
		allons
		après
		assez
		attendu
		au
		aucun
		aucune
		aujourd
		aujourd'hui
		auquel
		aura
		auront
		aussi
		autre
		autres
		aux
		auxquelles
		auxquels
		avaient
		avais
		avait
		avant
		avec
		avoir
		ayant
		bah
		beaucoup
		bien
		bigre
		boum
		bravo
		brrr
		ça
		car
		ce
		ceci
		cela
		celle
		celle-ci
		celle-là
		celles
		celles-ci
		celles-là
		celui
		celui-ci
		celui-là
		cent
		cependant
		certain
		certaine
		certaines
		certains
		certes
		ces
		cet
		cette
		ceux
		ceux-ci
		ceux-là
		chacun
		chaque
		cher
		chère
		chères
		chers
		chez
		chiche
		chut
		ci
		cinq
		cinquantaine
		cinquante
		cinquantième
		cinquième
		clac
		clic
		combien
		comme
		comment
		compris
		concernant
		contre
		couic
		crac
		da
		dans
		de
		debout
		dedans
		dehors
		delà
		depuis
		derrière
		des
		dès
		désormais
		desquelles
		desquels
		dessous
		dessus
		deux
		deuxième
		deuxièmement
		devant
		devers
		devra
		différent
		différente
		différentes
		différents
		dire
		divers
		diverse
		diverses
		dix
		dix-huit
		dixième
		dix-neuf
		dix-sept
		doit
		doivent
		donc
		dont
		douze
		douzième
		dring
		du
		duquel
		durant
		effet
		eh
		elle
		elle-même
		elles
		elles-mêmes
		en
		encore
		entre
		envers
		environ
		es
		ès
		est
		et
		etant
		étaient
		étais
		était
		étant
		etc
		été
		etre
		être
		eu
		euh
		eux
		eux-mêmes
		excepté
		façon
		fais
		faisaient
		faisant
		fait
		feront
		fi
		flac
		floc
		font
		gens
		ha
		hé
		hein
		hélas
		hem
		hep
		hi
		ho
		holà
		hop
		hormis
		hors
		hou
		houp
		hue
		hui
		huit
		huitième
		hum
		hurrah
		il
		ils
		importe
		je
		jusqu
		jusque
		k
		la
		là
		laquelle
		las
		le
		lequel
		les
		lès
		lesquelles
		lesquels
		leur
		leurs
		longtemps
		lorsque
		lui
		lui-même
		ma
		maint
		mais
		malgré
		me
		même
		mêmes
		merci
		mes
		mien
		mienne
		miennes
		miens
		mille
		mince
		moi
		moi-même
		moins
		mon
		moyennant
		na
		ne
		néanmoins
		neuf
		neuvième
		ni
		nombreuses
		nombreux
		non
		nos
		notre
		nôtre
		nôtres
		nous
		nous-mêmes
		nul
		o|
		ô
		oh
		ohé
		olé
		ollé
		on
		ont
		onze
		onzième
		ore
		ou
		où
		ouf
		ouias
		oust
		ouste
		outre
		paf
		pan
		par
		parmi
		partant
		particulier
		particulière
		particulièrement
		pas
		passé
		pendant
		personne
		peu
		peut
		peuvent
		peux
		pff
		pfft
		pfut
		pif
		plein
		plouf
		plus
		plusieurs
		plutôt
		pouah
		pour
		pourquoi
		premier
		première
		premièrement
		près
		proche
		psitt
		puisque
		qu
		quand
		quant
		quanta
		quant-à-soi
		quarante
		quatorze
		quatre
		quatre-vingt
		quatrième
		quatrièmement
		que
		quel
		quelconque
		quelle
		quelles
		quelque
		quelques
		quelqu'un
		quels
		qui
		quiconque
		quinze
		quoi
		quoique
		revoici
		revoilà
		rien
		sa
		sacrebleu
		sans
		sapristi
		sauf
		se
		seize
		selon
		sept
		septième
		sera
		seront
		ses
		si
		sien
		sienne
		siennes
		siens
		sinon
		six
		sixième
		soi
		soi-même
		soit
		soixante
		son
		sont
		sous
		stop
		suis
		suivant
		sur
		surtout
		ta
		tac
		tant
		te
		té
		tel
		telle
		tellement
		telles
		tels
		tenant
		tes
		tic
		tien
		tienne
		tiennes
		tiens
		toc
		toi
		toi-même
		ton
		touchant
		toujours
		tous
		tout
		toute
		toutes
		treize
		trente
		très
		trois
		troisième
		troisièmement
		trop
		tsoin
		tsouin
		tu
		un
		une
		unes
		uns
		va
		vais
		vas
		vé
		vers
		via
		vif
		vifs
		vingt
		vivat
		vive
		vives
		vlan
		voici
		voilà
		vont
		vos
		votre
		vôtre
		vôtres
		vous
		vous-mêmes
		vu
		zut
		del
		el
		las
		los
		una
		overline
		rightarrow
	);
	
	return @STOPWORDS;
}

1;

=head1 AUTHOR

Martin Braendle <martin.braendle@id.uzh.ch>, Zentrale Informatik, University of Zurich

=head1 COPYRIGHT

=for COPYRIGHT BEGIN

Copyright 2017- University of Zurich.

=for COPYRIGHT END

=for LICENSE BEGIN

This file is of the LinkCheck package based on EPrints L<http://www.eprints.org/>.

EPrints is free software: you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

EPrints is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
License for more details.

You should have received a copy of the GNU Lesser General Public
License along with EPrints.  If not, see L<http://www.gnu.org/licenses/>.

=for LICENSE END
