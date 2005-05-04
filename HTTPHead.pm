package POE::Filter::HTTPHead_Line;
use strict;

use HTTP::Response;

sub FRAMING_BUFFER   () { 0 }
sub CURRENT_STATE    () { 1 }
sub WORK_RESPONSE    () { 2 }
sub PROTOCOL_VERSION () { 3 }

sub STATE_STATUS () { 0x00 }  # waiting for a status line
sub STATE_HEADER () { 0x02 }  # gotten status, looking for header or end


sub new {
  my $type = shift;

  my $self =
    bless [ [],			    # FRAMING_BUFFER
            STATE_STATUS,	    # CURRENT_STATE
	    undef,		    # WORK_RESPONSE
	    "0.9",		    # PROTOCOL_VERSION
          ], $type;

  $self;
}

sub get {
}

sub get_one_start {
  my ($self, $chunks) = @_;

  push (@{$self->[FRAMING_BUFFER]}, @$chunks);
}

sub get_one {
  my $self = shift;

  while (defined (my $line = shift (@{$self->[FRAMING_BUFFER]}))) {
      if ($self->[CURRENT_STATE] == STATE_STATUS) {
	 #expect a status line
	 if ($line =~ m|^(?:HTTP/(\d+\.\d+) )?(\d{3})(?: (.+))?$|) {
	    $self->[PROTOCOL_VERSION] = $1
		if (defined $1);
	    $self->[WORK_RESPONSE] = HTTP::Response->new ($2, $3);
	    $self->[CURRENT_STATE] = STATE_HEADER;
	 } else {
	    return [undef];
	    #return [HTTP::Response->new ('500', 'Bad Response')];
	 }
      } else {
	 unless (@{$self->[FRAMING_BUFFER]} > 0) {
	    unshift (@{$self->[FRAMING_BUFFER]}, $line);
	    return [];
	 }
	 while ($self->[FRAMING_BUFFER]->[0] =~ /^[\t ]/) {
	    my $next_line = shift (@{$self->[FRAMING_BUFFER]});
	    $next_line =~ s/^[\t ]+//;
	    $line .= $next_line;
	 }
	 if ($line =~ /^([^\x00-\x19()<>@,;:\\"\/\[\]\?={} \t]+):\s*([^\x00-\x07\x09-\x19]+)$/) {
	    $self->[WORK_RESPONSE]->header($1, $2)
	 }
	 if ($line eq '') {
	    $self->[CURRENT_STATE] = STATE_STATUS;
	    return [$self->[WORK_RESPONSE]];
	 }
      }
  }
  return [];
}

sub put {
  my ($self, $responses) = @_;
  my $out;

  foreach my $response (@$responses) {
    $out = $response->as_string
  }

  $out;
}

sub get_pending {
  my $self = shift;
  return $self->[FRAMING_BUFFER];
}

package POE::Filter::HTTPHead;
use strict;

use vars qw($VERSION);
$VERSION = '0.01';

use base qw(POE::Filter::Stackable);
use POE::Filter::Line;

sub new {
  my $type = shift;

  my $self = $type->SUPER::new (Filters => [
      POE::Filter::Line->new,
      POE::Filter::HTTPHead_Line->new,
    ],
  );

  return bless $self, $type;
}

sub get_pending {
  my $self = shift;

  my @pending = map {"$_\n"} @{$self->[0]->[1]->get_pending};
  push (@pending, @{$self->[0]->[0]->get_pending});

  return \@pending;
}

sub put {
  my $self = shift;

  return $self->[0]->[1]->put (@_);
}

1;
