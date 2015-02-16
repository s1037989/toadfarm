package Toadfarm::Plugin::AccessLog;

=head1 NAME

Toadfarm::Plugin::AccessLog - Log requests

=head1 DESCRIPTION

This module will log the request with "info" log level. The log format
is subject for change. For now it is:

    $remote_address $http_method $url $status_code
    1.2.3.4 GET http://localhost/favicon.ico 200

=cut

use Mojo::Base 'Mojolicious::Plugin';
use Time::HiRes qw( gettimeofday tv_interval );

=head1 METHODS

=head2 register

Register an "around_dispatch" hook which will log the request.

=cut

sub register {
  my ($self, $app, $config) = @_;
  my $log = $app->log;
  my $subscribers;

  $app->hook(
    before_dispatch => sub {
      my $tx = $_[0]->tx;

      $tx->req->env->{t0} = [gettimeofday];

      if (my $stream = Mojo::IOLoop->stream($tx->connection)) {
        Scalar::Util::weaken($tx);
        $subscribers = $stream->subscribers('close');
        unshift @$subscribers, sub { $tx and _log($tx, $log, 'close') };
        $stream->unsubscribe('close');
        $stream->on(close => $_) for @$subscribers;
        $stream->on(timeout => sub { $tx and _log($tx, $log, 'timeout') });
      }

      $tx->once(finish => sub { _log($tx, $log, 'finish') });
    }
  );
}

sub _log {
  return if $_[0]->{_access_logged}++;
  my ($tx, $log, $reason) = @_;
  my $req  = $tx->req;
  my $url  = $req->url->clone->to_abs;
  my $code = $tx->res->code;

  unshift @{$url->path->parts}, @{$url->base->path->parts};
  $code ||= $reason eq 'close' ? '499' : $reason eq 'timeout' ? '504' : '000';
  $url->userinfo(undef);
  $log->info(
    sprintf '%s %s %s %s %.4fs',
    $req->env->{identity} || $tx->remote_address,
    $req->method, $url, $code, tv_interval($req->env->{t0}),
  );
}

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
