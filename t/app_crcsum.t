use Test2::V0 -no_srand => 1;
use v5.42;
use App::crcsum;
use File::Temp ();
use Cwd ();

# Expected CRCs were computed independently with Python's zlib.crc32.

my $orig = Cwd::getcwd();
my $tmp  = File::Temp->newdir;
chdir $tmp or die "chdir $tmp: $!";

sub spew ($name, $data) {
    open my $fh, '>:raw', $name or die "$name: $!";
    print $fh $data;
    close $fh or die "$name: $!";
}

# crcsum([{ stdin => $data },] @args): ($status, $stdout, $stderr)
sub crcsum (@args) {
    my $stdin = ref $args[0] ? (shift @args)->{stdin} : '';
    my ($out, $err) = ('', '');
    my $rc = do {
        local *STDIN;
        local *STDOUT;
        local *STDERR;
        local $SIG{__WARN__} = sub ($msg) { $err .= $msg };
        open STDIN,  '<', \$stdin or die;
        open STDOUT, '>', \$out   or die;
        open STDERR, '>', \$err   or die;
        App::crcsum->run(@args);
    };
    return ($rc, $out, $err);
}

my %crc = (
    'a.txt'     => '363a3020',
    'empty.dat' => '00000000',
    'check.txt' => 'cbf43926',
    'ctrlz.bin' => '7c7eb670',
    'big.bin'   => '4d56f02d',
    '-x.txt'    => '324c684e',
);

spew 'a.txt',     "hello\n";
spew 'empty.dat', '';
spew 'check.txt', '123456789';
# Ctrl-Z, CR LF and high bytes must all be hashed as they are
spew 'ctrlz.bin', "one\r\n\x1atwo\x00\x80\xff\x1a\r\nend";
# bigger than the read buffer and not a multiple of it
spew 'big.bin',   join('', map { chr } 0..255) x 391 . 'x';
spew '-x.txt',    "dash\n";
mkdir 'dir' or die;

sub sumline ($name, $marker = '*') { "$crc{$name} $marker$name\n" }

my @FILES = qw( a.txt empty.dat ctrlz.bin big.bin );
my $good  = join '', map { sumline $_ } @FILES;
my $ok    = join '', map { "$_: OK\n" } @FILES;

subtest 'sum files' => sub {
    is [crcsum(@FILES, 'check.txt')],
       [0, $good . sumline('check.txt'), ''];

    is [crcsum('nothere.txt')],
       [1, '', match qr/^crcsum: nothere.txt: No such file/];

    is [crcsum('a.txt', 'nothere.txt', 'check.txt')],
       [1, sumline('a.txt') . sumline('check.txt'), match qr/nothere.txt/];

    is [crcsum('dir')],
       [1, '', match qr/^crcsum: dir: Is a directory/];
};

subtest 'standard input' => sub {
    is [crcsum({ stdin => '123456789' }, '-')],
       [0, "cbf43926 *-\n", ''];
    is [crcsum({ stdin => '123456789' })],
       [0, "cbf43926 *-\n", ''], 'no arguments';
    is [crcsum({ stdin => $good }, '-c', '-')],
       [0, $ok, ''], 'manifest';
    is [crcsum({ stdin => $good }, '-c')],
       [0, $ok, ''], 'manifest, no arguments';
};

subtest 'check' => sub {
    my %manifest = (
        lf    => $good,
        crlf  => $good =~ s/\n/\r\n/gr,
        cr    => $good =~ s/\n/\r/gr,
        ctrlz => "$good\x1agarbage after Ctrl-Z\n",
    );
    for my $name (sort keys %manifest) {
        spew "$name.sum", $manifest{$name};
        is [crcsum('-c', "$name.sum")], [0, $ok, ''], $name;
    }

    # GNU text marker, upper case hex, comments, blank line, no final newline
    spew 'text.sum', "# made on Linux\n"
        . uc($crc{'a.txt'}) . "  a.txt\n\n"
        . sumline('check.txt', ' ') =~ s/\n//r;
    is [crcsum('--check', 'text.sum')],
       [0, "a.txt: OK\ncheck.txt: OK\n", ''], 'text';

    spew 'dup.sum', sumline('a.txt') x 2;
    is [crcsum('-c', 'dup.sum')], [0, "a.txt: OK\n" x 2, ''], 'duplicate';

    spew 'bad1.sum', "00000000 *a.txt\n";
    is [crcsum('-c', 'bad1.sum')],
       [1, "a.txt: FAILED\n",
        "crcsum: WARNING: 1 computed checksum did NOT match\n"], 'mismatch';

    spew 'miss.sum', $good . "d41d8cd9 *nothere.txt\n";
    is [crcsum('-c', 'miss.sum')],
       [1, $ok . "nothere.txt: FAILED open or read\n",
        match qr/1 listed file could not be read/], 'missing';

    spew 'malf.sum', $good . "this is not a checksum line\n";
    is [crcsum('-c', 'malf.sum')],
       [2, $ok, match qr/malf.sum: 5: improperly formatted line.*1 line is improperly/s],
       'malformed';

    spew 'malfbad.sum', "00000000 *a.txt\ncbf43926 *\n";
    is [crcsum('-c', 'malfbad.sum')], [2, "a.txt: FAILED\n", D()],
       'mismatch and malformed';

    spew 'nul.sum', "$crc{'a.txt'} *a.txt\0x\n";
    is [crcsum('-c', 'nul.sum')], [2, '', D()], 'NUL in name';

    spew 'none.sum', "# nothing here\n\n";
    is [crcsum('-c', 'none.sum')],
       [2, '', "crcsum: none.sum: no checksum lines found\n"], 'no entries';

    is [crcsum('-c', 'nothere.sum')],
       [2, '', match qr/^crcsum: nothere.sum: No such file/], 'no manifest';

    is [crcsum('-c', 'lf.sum', 'bad1.sum')],
       [1, $ok . "a.txt: FAILED\n", D()], 'worst status wins';
};

subtest 'round trip' => sub {
    my ($rc, $out) = crcsum(@FILES);
    is $rc, 0;
    spew 'round.sum', $out;
    is [crcsum('-c', 'round.sum')], [0, $ok, ''];
};

subtest 'options' => sub {
    is [crcsum('--', '-x.txt')], [0, sumline('-x.txt'), ''];
    is [crcsum('lf.sum', '-c')], [0, $ok, ''], 'options after operands';

    for my $bad (['--bogus', 'a.txt'], ['-x', 'a.txt'], ['--chec', 'a.txt']) {
        is [crcsum(@$bad)],
           [2, '', match qr/Try 'crcsum --help'/], "@$bad";
    }

    my ($rc, $help) = crcsum('--help');
    is $rc, 0;
    like $help, qr/^Usage: crcsum/;
    is [crcsum($_)], [0, $help, ''], $_ for qw( -h -? );

    is [crcsum('--version')],
       [0, match qr/^crcsum \(App-crcsum\) \S+\n\z/, ''];
};

chdir $orig or die;

done_testing;
