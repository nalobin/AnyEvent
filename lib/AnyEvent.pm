=head1 NAME

AnyEvent - provide framework for multiple event loops

Event, Coro, Glib, Tk - various supported event loops

=head1 SYNOPSIS

use AnyEvent;

   my $w = AnyEvent->io (fh => ..., poll => "[rw]+", cb => sub {
      my ($poll_got) = @_;
      ...
   });

- only one io watcher per $fh and $poll type is allowed
(i.e. on a socket you can have one r + one w or one rw
watcher, not any more.

- AnyEvent will keep filehandles alive, so as long as the watcher exists,
the filehandle exists.

   my $w = AnyEvent->timer (after => $seconds, cb => sub {
      ...
   });

- io and time watchers get canceled whenever $w is destroyed, so keep a copy

- timers can only be used once and must be recreated for repeated operation

   my $w = AnyEvent->condvar; # kind of main loop replacement
   $w->wait; # enters main loop till $condvar gets ->broadcast
   $w->broadcast; # wake up current and all future wait's

- condvars are used to give blocking behaviour when neccessary. Create
a condvar for any "request" or "event" your module might create, C<<
->broadcast >> it when the event happens and provide a function that calls
C<< ->wait >> for it. See the examples below.

=head1 DESCRIPTION

L<AnyEvent> provides an identical interface to multiple event loops. This
allows module authors to utilizy an event loop without forcing module
users to use the same event loop (as only a single event loop can coexist
peacefully at any one time).

The interface itself is vaguely similar but not identical to the Event
module.

On the first call of any method, the module tries to detect the currently
loaded event loop by probing wether any of the following modules is
loaded: L<Coro::Event>, L<Event>, L<Glib>, L<Tk>. The first one found is
used. If none is found, the module tries to load these modules in the
order given. The first one that could be successfully loaded will be
used. If still none could be found, it will issue an error.

=over 4

=cut

package AnyEvent;

no warnings;
use strict 'vars';
use Carp;

our $VERSION = 0.3;
our $MODEL;

our $AUTOLOAD;
our @ISA;

my @models = (
      [Coro  => Coro::Event::],
      [Event => Event::],
      [Glib  => Glib::],
      [Tk    => Tk::],
);

our %method = map +($_ => 1), qw(io timer condvar broadcast wait cancel DESTROY);

sub AUTOLOAD {
   $AUTOLOAD =~ s/.*://;

   $method{$AUTOLOAD}
      or croak "$AUTOLOAD: not a valid method for AnyEvent objects";

   unless ($MODEL) {
      # check for already loaded models
      for (@models) {
         my ($model, $package) = @$_;
         if (scalar keys %{ *{"$package\::"} }) {
            eval "require AnyEvent::Impl::$model";
            last if $MODEL;
         }
      }

      unless ($MODEL) {
         # try to load a model

         for (@models) {
            my ($model, $package) = @$_;
            eval "require AnyEvent::Impl::$model";
            last if $MODEL;
         }

         $MODEL
           or die "No event module selected for AnyEvent and autodetect failed. Install any one of these modules: Coro, Event, Glib or Tk.";
      }
   }

   @ISA = $MODEL;

   my $class = shift;
   $class->$AUTOLOAD (@_);
}

=back

=head1 EXAMPLE

The following program uses an io watcher to read data from stdin, a timer
to display a message once per second, and a condvar to exit the program
when the user enters quit:

   use AnyEvent;

   my $cv = AnyEvent->condvar;

   my $io_watcher = AnyEvent->io (fh => \*STDIN, poll => 'r', cb => sub {
      warn "io event <$_[0]>\n";   # will always output <r>
      chomp (my $input = <STDIN>); # read a line
      warn "read: $input\n";       # output what has been read
      $cv->broadcast if $input =~ /^q/i; # quit program if /^q/i
   });

   my $time_watcher; # can only be used once

   sub new_timer {
      $timer = AnyEvent->timer (after => 1, cb => sub {
         warn "timeout\n"; # print 'timeout' about every second
         &new_timer; # and restart the time
      });
   }

   new_timer; # create first timer

   $cv->wait; # wait until user enters /^q/i

=head1 REAL-WORLD EXAMPLE

Consider the L<Net::FCP> module. It features (among others) the following
API calls, which are to freenet what HTTP GET requests are to http:

   my $data = $fcp->client_get ($url); # blocks

   my $transaction = $fcp->txn_client_get ($url); # does not block
   $transaction->cb ( sub { ... } ); # set optional result callback
   my $data = $transaction->result; # possibly blocks

The C<client_get> method works like C<LWP::Simple::get>: it requests the
given URL and waits till the data has arrived. It is defined to be:

   sub client_get { $_[0]->txn_client_get ($_[1])->result }

And in fact is automatically generated. This is the blocking API of
L<Net::FCP>, and it works as simple as in any other, similar, module.

More complicated is C<txn_client_get>: It only creates a transaction
(completion, result, ...) object and initiates the transaction.

   my $txn = bless { }, Net::FCP::Txn::;

It also creates a condition variable that is used to signal the completion
of the request:

   $txn->{finished} = AnyAvent->condvar;

It then creates a socket in non-blocking mode.

   socket $txn->{fh}, ...;
   fcntl $txn->{fh}, F_SETFL, O_NONBLOCK;
   connect $txn->{fh}, ...
      and !$!{EWOULDBLOCK}
      and !$!{EINPROGRESS}
      and Carp::croak "unable to connect: $!\n";

Then it creates a write-watcher which gets called wehnever an error occurs
or the connection succeeds:

   $txn->{w} = AnyEvent->io (fh => $txn->{fh}, poll => 'w', cb => sub { $txn->fh_ready_w });

And returns this transaction object. The C<fh_ready_w> callback gets
called as soon as the event loop detects that the socket is ready for
writing.

The C<fh_ready_w> method makes the socket blocking again, writes the
request data and replaces the watcher by a read watcher (waiting for reply
data). The actual code is more complicated, but that doesn't matter for
this example:

   fcntl $txn->{fh}, F_SETFL, 0;
   syswrite $txn->{fh}, $txn->{request}
      or die "connection or write error";
   $txn->{w} = AnyEvent->io (fh => $txn->{fh}, poll => 'r', cb => sub { $txn->fh_ready_r });

Again, C<fh_ready_r> waits till all data has arrived, and then stores the
result and signals any possible waiters that the request ahs finished:

   sysread $txn->{fh}, $txn->{buf}, length $txn->{$buf};

   if (end-of-file or data complete) {
     $txn->{result} = $txn->{buf};
     $txn->{finished}->broadcast;
   }

The C<result> method, finally, just waits for the finished signal (if the
request was already finished, it doesn't wait, of course, and returns the
data:

   $txn->{finished}->wait;
   return $txn->{buf};

The actual code goes further and collects all errors (C<die>s, exceptions)
that occured during request processing. The C<result> method detects
wether an exception as thrown (it is stored inside the $txn object)
and just throws the exception, which means connection errors and other
problems get reported tot he code that tries to use the result, not in a
random callback.

All of this enables the following usage styles:

1. Blocking:

   my $data = $fcp->client_get ($url);

2. Blocking, but parallelizing:

   my @datas = map $_->result,
                  map $fcp->txn_client_get ($_),
                     @urls;

Both blocking examples work without the module user having to know
anything about events.

3a. Event-based in a main program, using any support Event module:

   use Event;

   $fcp->txn_client_get ($url)->cb (sub {
      my $txn = shift;
      my $data = $txn->result;
      ...
   });

   Event::loop;

3b. The module user could use AnyEvent, too:

   use AnyEvent;

   my $quit = AnyEvent->condvar;

   $fcp->txn_client_get ($url)->cb (sub {
      ...
      $quit->broadcast;
   });

   $quit->wait;

=head1 SEE ALSO

Event modules: L<Coro::Event>, L<Coro>, L<Event>, L<Glib::Event>, L<Glib>.

Implementations: L<AnyEvent::Impl::Coro>, L<AnyEvent::Impl::Event>, L<AnyEvent::Impl::Glib>, L<AnyEvent::Impl::Tk>.

Nontrivial usage example: L<Net::FCP>.

=head1

=cut

1

