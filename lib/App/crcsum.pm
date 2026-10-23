package App::crcsum;

use warnings;
use 5.042;
use Getopt::Long ();
use Compress::Raw::Zlib ();
use List::Util ();

# ABSTRACT: Perl port of dos-crcsum16
# VERSION

=head1 SYNOPSIS

 use App::crcsum;
 exit App::crcsum->run(@ARGV);

=head1 DESCRIPTION

This module implements L<crcsum>, an C<md5sum> style CRC-32 checksum
utility.  It is a Unix port of C<dos-crcsum16>, and reads and writes the
same manifest format.  See L<crcsum> for the command line interface.

The CRC is CRC-32/ISO-HDLC, the CRC used by ZIP, gzip and Ethernet.  It
detects accidental corruption; it is B<not> cryptographically secure.

=head1 METHODS

=head2 run

 my $status = App::crcsum->run(@args);

Run the command with the given command line arguments, and return the
exit status: C<0> if every file was read and every checksum matched,
C<1> if a file was missing, unreadable or did not match, and C<2> for a
usage error, an unreadable or malformed manifest, or a write error on
standard output.

=cut

use constant {
    RC_OK    => 0,     # everything read and matched
    RC_FAIL  => 1,     # missing, unreadable or mismatched file
    RC_FATAL => 2,     # usage error, bad manifest, write error
    BUFSIZE  => 65536,
};

my $USAGE = <<~'EOF';
    Usage: crcsum [FILE]...
      or:  crcsum -c [MANIFEST]...
    Print or check CRC-32 (ZIP/Ethernet) checksums.
    With no FILE, or when FILE is -, read standard input.

      -c, --check    read checksums from the MANIFESTs and check them
      -h, -?, --help display this help and exit
          --version  output version information and exit

    The exit status is 0 if all files were read and all checksums matched,
    1 if a file was missing, unreadable or did not match, and 2 for a
    usage error, an unreadable or malformed manifest, or an output write
    error.

    CRC-32 detects accidental corruption; it is not secure against
    deliberate tampering.
    EOF

sub _error (@msg) {
    say STDERR join ': ', 'crcsum', @msg;
    return;
}

# Open a file, or standard input for '-', for binary reading.
sub _open ($name) {
    if ($name eq '-') {
        binmode STDIN;
        return \*STDIN;
    }
    open my $fh, '<:raw', $name or return undef;
    return $fh;
}

# CRC of a named file, or undef with $! set.
sub _crc_file ($name) {
    my $fh = _open($name) // return undef;
    my $crc = 0;
    while (1) {
        my $n = read $fh, my $buf, BUFSIZE;
        return undef unless defined $n;
        last if $n == 0;
        $crc = Compress::Raw::Zlib::crc32($buf, $crc);
    }
    return $crc;
}

sub _sum_one ($name) {
    my $crc = _crc_file($name);
    unless (defined $crc) {
        _error($name, $!);
        return RC_FAIL;
    }
    printf "%08x *%s\n", $crc, $name;
    return RC_OK;
}

# Lines of a manifest, without their terminators.  Lines end at LF,
# CR LF or a lone CR; a Ctrl-Z ends the manifest.  Returns undef with $!
# set on error.
sub _manifest_lines ($name) {
    my $fh = _open($name) // return undef;
    my $data = do { local $/; readline $fh };
    return undef unless defined $data;
    $data =~ s/\x1a.*//s;
    my @lines = split /\r\n|\r|\n/, $data, -1;
    pop @lines if @lines && $lines[-1] eq '';
    return \@lines;
}

sub _check_list ($listname) {
    my $lines = _manifest_lines($listname);
    unless (defined $lines) {
        _error($listname, $!);
        return RC_FATAL;
    }

    my %count = (ok => 0, bad_format => 0, bad_read => 0, bad_sum => 0);

    for my $i (0..$#$lines) {
        my $line = $lines->[$i];
        next if $line eq '' || $line =~ /\A#/;

        unless ($line =~ /\A([0-9a-fA-F]{8}) [ *]([^\0]+)\z/) {
            $count{bad_format}++;
            _error($listname, $i + 1, 'improperly formatted line');
            next;
        }
        my ($want, $name) = (hex $1, $2);

        my $got = _crc_file($name);
        if (!defined $got) {
            $count{bad_read}++;
            _error($name, $!);
            say "$name: FAILED open or read";
        } elsif ($got != $want) {
            $count{bad_sum}++;
            say "$name: FAILED";
        } else {
            $count{ok}++;
            say "$name: OK";
        }
    }

    unless (List::Util::sum0(values %count)) {
        _error($listname, 'no checksum lines found');
        return RC_FATAL;
    }

    _error('WARNING', $count{bad_format} == 1
        ? "1 line is improperly formatted"
        : "$count{bad_format} lines are improperly formatted") if $count{bad_format};
    _error('WARNING', $count{bad_read} == 1
        ? "1 listed file could not be read"
        : "$count{bad_read} listed files could not be read") if $count{bad_read};
    _error('WARNING', $count{bad_sum} == 1
        ? "1 computed checksum did NOT match"
        : "$count{bad_sum} computed checksums did NOT match") if $count{bad_sum};

    return RC_FATAL if $count{bad_format};
    return RC_FAIL  if $count{bad_read} || $count{bad_sum};
    return RC_OK;
}

sub run ($class, @args) {
    my %opt;
    my $parser = Getopt::Long::Parser->new(
        config => [qw( bundling no_ignore_case no_auto_abbrev )],
    );
    unless ($parser->getoptionsfromarray(\@args, \%opt,
        'c|check',
        'h|?|help',
        'version',
    )) {
        say STDERR "Try 'crcsum --help' for more information.";
        return RC_FATAL;
    }

    if ($opt{h}) {
        print $USAGE;
        return RC_OK;
    }
    if ($opt{version}) {
        say "crcsum (App-crcsum) ", $class->VERSION // 'dev';
        return RC_OK;
    }

    @args = ('-') unless @args;

    my $rc = RC_OK;
    for my $arg (@args) {
        my $r = $opt{c} ? _check_list($arg) : _sum_one($arg);
        $rc = $r if $r > $rc;
    }

    unless (STDOUT->flush && !STDOUT->error) {
        _error('write error', $!);
        $rc = RC_FATAL;
    }
    return $rc;
}
