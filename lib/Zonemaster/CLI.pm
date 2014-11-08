# Brief help module to define the exception we use for early exits.
package NormalExit;
use Moose;
extends 'Zonemaster::Exception';

# The actual interesting module.
package Zonemaster::CLI;

use 5.014002;
use warnings;

our $VERSION = '0.03';

use Locale::TextDomain 'Zonemaster-CLI';
use Moose;
with 'MooseX::Getopt';

use Zonemaster;
use Zonemaster::Logger::Entry;
use Zonemaster::Translator;
use Zonemaster::Util qw[pod_extract_for];
use Zonemaster::Exception;
use Scalar::Util qw[blessed];
use Encode;
use Net::LDNS;
use POSIX qw[setlocale LC_MESSAGES];
use List::Util qw[max];

our %numeric = Zonemaster::Logger::Entry->levels;

STDOUT->autoflush( 1 );

has 'version' => (
    is            => 'ro',
    isa           => 'Bool',
    default       => 0,
    required      => 0,
    documentation => __('Print version information and exit.'),
);

has 'level' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    default       => 'NOTICE',
    documentation => __('The minimum severity level to display. Must be one of CRITICAL, ERROR, WARNING, NOTICE, INFO or DEBUG.'),
);

has 'locale' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __('The locale to use for messages translation.'),
);

has 'json' => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
    documentation => __('Flag indicating of output should be in JSON or not.'),
);

has 'raw' => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
    documentation => __('Flag indicating if output should be translated to human language or dumped raw.'),
);

has 'time' => (
    is            => 'ro',
    isa           => 'Bool',
    documentation => __('Print timestamp on entries.'),
    default       => 1,
);

has 'show_level' => (
    is            => 'ro',
    isa           => 'Bool',
    documentation => __('Print level on entries.'),
    default       => 1,
);

has 'show_module' => (
    is            => 'ro',
    isa           => 'Bool',
    documentation => __('Print the name of the maodule on entries.'),
    default       => 0,
);

has 'ns' => (
    is            => 'ro',
    isa           => 'ArrayRef',
    documentation => __('A name/ip string giving a nameserver for undelegated tests. Can be given multiple times.'),
);

has 'save' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __('Name of a file to save DNS data to after running tests.'),
);

has 'restore' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __('Name of a file to restore DNS data from before running test.'),
);

has 'ipv4' => (
    is            => 'ro',
    isa           => 'Bool',
    default       => 1,
    documentation => __('Flag to permit or deny queries being sent via IPv4. --ipv4 permits IPv4 traffic, --no-ipv4 forbids it.'),
);

has 'ipv6' => (
    is            => 'ro',
    isa           => 'Bool',
    default       => 1,
    documentation => __('Flag to permit or deny queries being sent via IPv6. --ipv6 permits IPv6 traffic, --no-ipv6 forbids it.'),
);

has 'list_tests' => (
    is            => 'ro',
    isa           => 'Bool',
    default       => 0,
    documentation => __('Instead of running a test, list all available tests.'),
);

has 'test' => (
    is       => 'ro',
    isa      => 'ArrayRef',
    required => 0,
    documentation =>
__('Specify test to run. Should be either the name of a module, or the name of a module and the name of a method in that module separated by a "/" character (Example: "Basic/basic1"). The method specified must be one that takes a zone object as its single argument. This switch can be repeated.')
);

has 'stop_level' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __('As soon as a message at this level or higher is logged, execution will stop. Must be one of CRITICAL, ERROR, WARNING, NOTICE, INFO or DEBUG.')
);

has 'config' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __('Name of configuration file to load.'),
);

has 'policy' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __('Name of policy file to load.'),
);

has 'ds' => (
    is            => 'ro',
    isa           => 'ArrayRef[Str]',
    required      => 0,
    documentation => __('Strings with DS data on the form "keytag,algorithm,type,digest"'),
);

has 'count' => (
    is            => 'ro',
    isa           => 'Bool',
    required      => 0,
    documentation => __('Print a count of the number of messages at each level'),
);

has 'progress' => (
    is => 'ro',
    isa => 'Bool',
    default => !!(-t STDOUT),
    documentation => __('Boolean flag for activity indicator. Defaults to on if STDOUT is a tty, off if it is not.'),
);

has 'encoding' => (
    is => 'ro',
    isa => 'Str',
    default => sub {
        my $locale = $ENV{LC_CTYPE} // 'C';
        my ($e) = $locale =~ m|\.(.*)$|;
        $e //= 'UTF-8';
        return $e;
    },
    documentation => __('Name of the character encoding used for command line arguments'),
);

has 'nstimes' => (
    is => 'ro',
    isa => 'Bool',
    required => 0,
    default => 0,
    documentation => 'At the end of a run, print a summary of the times the zone\'s name servers took to answer.',
);

sub run {
    my ( $self ) = @_;
    my @accumulator;
    my %counter;
    my $printed_something;

    if ($self->locale) {
        my $loc = setlocale(LC_MESSAGES,$self->locale);
        if (not defined $loc) {
            printf STDERR __("Warning: setting locale %s failed.\n\n"), $self->locale;
        }
    }

    if ( $self->version ) {
        print_versions();
        exit;
    }

    if ( $self->list_tests ) {
        my %methods = Zonemaster->all_methods;
        foreach my $module ( sort keys %methods ) {
            say $module;
            my $doc = pod_extract_for( $module );
            foreach my $method ( sort @{ $methods{$module} } ) {
                print "\t$method";
                if ( $doc and $doc->{$method} ) {
                    print "\t" . $doc->{$method};
                }
                print "\n";
            }
        }
        exit( 0 );
    }

    my ( $domain ) = @{ $self->extra_argv };
    if ( not $domain ) {
        die __("Must give the name of a domain to test.\n");
    }
    $domain = $self->to_idn($domain);

    if ( $self->stop_level and not defined( $numeric{ $self->stop_level } ) ) {
        die __("Failed to recognize stop level '") . $self->stop_level . "'.\n";
    }

    if (not defined $numeric{$self->level}) {
        die __("--level must be one of CRITICAL, ERROR, WARNING, NOTICE, INFO, DEBUG, DEBUG2 or DEBUG3.\n");
    }

    Zonemaster->config->get->{net}{ipv4} = $self->ipv4;
    Zonemaster->config->get->{net}{ipv6} = $self->ipv6;

    my $translator;
    $translator = Zonemaster::Translator->new unless ( $self->raw or $self->json );
    $translator->locale($self->locale) if $translator and $self->locale;
    eval { $translator->data } if $translator;    # Provoke lazy loading of translation data

    if ( $self->restore ) {
        Zonemaster->preload_cache( $self->restore );
    }

    # Callback defined here so it closes over the setup above.
    Zonemaster->logger->callback(
        sub {
            my ( $entry ) = @_;

            $self->print_spinner();

            $counter{ uc $entry->level } += 1;

            if ( $numeric{ uc $entry->level } >= $numeric{ uc $self->level } ) {
                $printed_something = 1;

                if ( $translator ) {
                    if ( $self->time ) {
                        printf "%7.2f ", $entry->timestamp;
                    }

                    if ( $self->show_level ) {
                        printf "%-9s ", __($entry->level);
                    }

                    if ( $self->show_module ) {
                        printf "%-12s ", $entry->module;
                    }

                    say $translator->translate_tag( $entry );
                }
                elsif ( $self->json ) {
                    # Don't do anything
                }
                elsif ( $self->show_module ) {
                    printf "%7.2f %-9s %-12s %s\n", $entry->timestamp, $entry->level, $entry->module, $entry->string;
                }
                else {
                    printf "%7.2f %-9s %s\n", $entry->timestamp, $entry->level, $entry->string;
                }
            } ## end if ( $numeric{ uc $entry...})
            if ( $self->stop_level and $numeric{ uc $entry->level } >= $numeric{ uc $self->stop_level } ) {
                die( NormalExit->new( { message => "Saw message at level " . $entry->level } ) );
            }
        }
    );

    if ( $self->policy ) {
        say __("Loading policy from ") . $self->policy;
        Zonemaster->config->load_policy_file( $self->policy );
    }

    if ( $self->config ) {
        say __("Loading configuration from ") . $self->config;
        Zonemaster->config->load_config_file( $self->config );
    }

    if ( $self->config or $self->policy ) {
        print "\n";    # Cosmetic
    }

    if ( $translator ) {
        if ( $self->time ) {
            print __('Seconds ');
        }
        if ( $self->show_level ) {
            print __('Level     ');
        }
        if ( $self->show_module ) {
            print __('Module       ');
        }
        say __('Message');

        if ( $self->time ) {
            print __('======= ');
        }
        if ( $self->show_level ) {
            print __('========= ');
        }
        if ( $self->show_module ) {
            print __('============ ');
        }
        say __('=======');
    }

    if ( $self->ns and @{ $self->ns } > 0 ) {
        $self->add_fake_delegation( $domain );
    }

    if ( $self->ds and @{ $self->ds } ) {
        $self->add_fake_ds( $domain );
    }

    # Actually run tests!
    eval {
        if ( $self->test and @{ $self->test } > 0 ) {
            foreach my $t ( @{ $self->test } ) {
                my ( $module, $method ) = split( '/', $t, 2 );
                if ( $method ) {
                    Zonemaster->test_method( $module, $method, Zonemaster->zone( $domain ) );
                }
                else {
                    Zonemaster->test_module( $module, $domain );
                }
            }
        }
        else {
            Zonemaster->test_zone( $domain );
        }
    };
    if ($translator) {
        if (not $printed_something) {
            say __("Looks OK.");
        }
    }

    if ( $@ ) {
        my $err = $@;
        if ( blessed $err and $err->isa( "NormalExit" ) ) {
            say STDERR "Exited early: " . $err->message;
        }
        else {
            die $err;    # Don't know what it is, rethrow
        }
    }

    if ( $self->count ) {
        say __("\n\n   Level\tNumber of log entries");
        say        "   =====\t=====================";
        foreach my $level ( sort { $numeric{$b} <=> $numeric{$a} } keys %counter ) {
            printf __("%8s\t%5d entries.\n"), __($level), $counter{$level};
        }
    }

    if ( $self->nstimes ) {
        my $zone = Zonemaster->zone($domain);
        my $max = max map {length("$_")} @{$zone->ns};

        print "\n";
        printf "%${max}s %s\n", 'Server',   ' Max (ms)      Min      Avg   Stddev   Median     Total';
        printf "%${max}s %s\n", '=' x $max, ' ======== ======== ======== ======== ======== =========';

        foreach my $ns (@{$zone->ns}) {
            printf "%${max}s ", $ns->string;
            printf "%9.2f ", 1000*$ns->max_time;
            printf "%8.2f ", 1000*$ns->min_time;
            printf "%8.2f ", 1000*$ns->average_time;
            printf "%8.2f ", 1000*$ns->stddev_time;
            printf "%8.2f ", 1000*$ns->median_time;
            printf "%9.2f\n", 1000*$ns->sum_time;
        }
    }

    if ( $self->json ) {
        say Zonemaster->logger->json($self->level);
    }

    if ( $self->save ) {
        Zonemaster->save_cache( $self->save );
    }

    return;
} ## end sub run

sub add_fake_delegation {
    my ( $self, $domain ) = @_;
    my %data;

    foreach my $pair ( @{ $self->ns } ) {
        my ( $name, $ip ) = split( '/', $pair, 2 );

        if (not $name or not $ip) {
            say STDERR "Malformed --ns switch, need name and IP separated by a /.";
            exit(1);
        }

        push @{ $data{$self->to_idn($name)} }, $ip;
    }

    Zonemaster->add_fake_delegation( $domain => \%data );

    return;
}

sub add_fake_ds {
    my ( $self, $domain ) = @_;
    my @data;

    foreach my $str ( @{ $self->ds } ) {
        my ( $tag, $algo, $type, $digest ) = split( /,/, $str );
        push @data, { keytag => $tag, algorithm => $algo, type => $type, digest => $digest };
    }

    Zonemaster->add_fake_ds( $domain => \@data );

    return;
}

sub print_versions {
    say 'CLI version:    ' . $VERSION;
    say 'Engine version: ' . $Zonemaster::VERSION;
    say "\nTest module versions:";

    my %methods = Zonemaster->all_methods;
    foreach my $module ( sort keys %methods ) {
        my $mod = "Zonemaster::Test::$module";
        say "\t$module: " . $mod->version;
    }
}

my @spinner_strings = ( '  | ', '  / ', '  - ', '  \\ ' );

sub print_spinner {
    my ( $self ) = @_;

    state $counter = 0;

    printf "%s\r", $spinner_strings[ $counter++ % 4 ] if $self->progress;
}

sub to_idn {
    my ( $self, $str ) = @_;

    if ($str =~ m/^[[:ascii:]]+$/) {
        return $str;
    }

    if (Net::LDNS::has_idn()) {
        return Net::LDNS::to_idn(encode('utf8',decode($self->encoding, $str)));
    }
    else {
        say __("Warning: Net::LDNS not compiled with libidn, cannot handle non-ASCII names correctly.");
        return $str;
    }
}

1;
