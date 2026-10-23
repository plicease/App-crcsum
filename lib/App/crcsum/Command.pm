package App::crcsum::Command;

use warnings;
use 5.042;
use experimental qw( defer try );
use true;

# ABSTRACT: Perl port of dos-crcsum16
# VERSION

use App::Cmd::Setup -command;

sub opt_spec ($self) {
}

sub validate_args ($self, $opt, $args) {
}
