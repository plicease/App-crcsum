# App::crcsum ![static](https://github.com/plicease/App-crcsum/workflows/static/badge.svg) ![linux](https://github.com/plicease/App-crcsum/workflows/linux/badge.svg)

Perl port of dos-crcsum16

# SYNOPSIS

```perl
use App::crcsum;
exit App::crcsum->run(@ARGV);
```

# DESCRIPTION

This module implements [crcsum](https://metacpan.org/pod/crcsum), an `md5sum` style CRC-32 checksum
utility.  It is a Unix port of `dos-crcsum16`, and reads and writes the
same manifest format.  See [crcsum](https://metacpan.org/pod/crcsum) for the command line interface.

The CRC is CRC-32/ISO-HDLC, the CRC used by ZIP, gzip and Ethernet.  It
detects accidental corruption; it is **not** cryptographically secure.

# METHODS

## run

```perl
my $status = App::crcsum->run(@args);
```

Run the command with the given command line arguments, and return the
exit status: `0` if every file was read and every checksum matched,
`1` if a file was missing, unreadable or did not match, and `2` for a
usage error, an unreadable or malformed manifest, or a write error on
standard output.

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2026 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
