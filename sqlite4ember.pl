#!/usr/bin/perl
use Mojolicious::Lite;
use Mojo::SQLite;
use Mojo::JSON qw(decode_json);

#
# A standalone (no web server needed), single-script RESTful web interface to an Sqlite 
# datebase for the Ember MVC framework (Ember Data specifically).  Should be easily adaptable 
# to other MVCs.  Great for front end development.  Avoid production without adding 
# authentication and probably a bunch more sanity checking.
#
# Database creation: sqlite3 <filename>
#                    create table test (id integer primary key, stuff text)
#                    <inserts and whatever other standard SQL you want>
#                    control-D
#
# Run the web server: ./sqlite4ember.pl daemon -l http://*:8000
#   (https also works if you have the required perl modules)
#
# Further reading: http://mojolicio.us/perldoc                  http://emberjs.com
#                  http://search.cpan.org/~dbook/Mojo-SQLite    https://www.sqlite.org
#
# To have Ember grok database errors, you'll want to set up your adapter with an ajaxError
# member like so:
#
# export default DS.RESTAdapter.extend({
#     host: 'http://localhost:3000',
#     ajaxError: function(jqXHR) {
#         var error = this._super(jqXHR);
#         if (jqXHR && jqXHR.status === 422) {
#             var jsonErrors = Ember.$.parseJSON(jqXHR.responseText)["errors"]; 
#             return new DS.InvalidError(jsonErrors);
#         } else {
#             return error;
#         }
#     }
# });
#

##### configurable section #######################

my $dbfile = "test.db";
my $origins = '*'; # acceptable originating URLs allowed to hit this server.  replace wildcard.

# map Ember model/route names to table names (e.g. employee -> employees), in case the front 
# end uses singular data model names for plural route names, etc.  By default, this script
# assumes tables, models and routes all have the same name and will find the tables 
# automatically.
helper model_to_table => sub {
  my $model = $_[1];
  # here's a dumb pluralizer.  could also hardcode a hash, store the map in a table, 
  # or just enforce model names matching route names matching database names and make this
  # return $model unmodified;
  # $model .= "s" unless $model =~ /s$/i;
  return $model;
};

###################################################

helper sqlite => sub { state $sql = Mojo::SQLite->new($dbfile) };

# headers for cache control and cross-site configuration so db web interface can be on 
# a different host/port than the one serving the front end
hook after_dispatch => sub {
  my $c = shift;
  $c->res->headers->header('Access-Control-Allow-Origin' => $origins); 
  $c->res->headers->header('Access-Control-Allow-Methods' => 'POST,GET,PUT,DELETE,OPTIONS');
  $c->res->headers->header('Access-Control-Allow-Headers' => 'accept,content-type');
  $c->res->headers->header('Pragma' => 'no-cache');
  $c->res->headers->header('Cache-Control' => 'no-cache');
};

# send error reponses to the frontend (see http://suffix.be/blog/ember-data-error-handling)
helper err => sub {
  my $c = $_[0];
  my $error = $_[1];
  if($error) {
    say "Database Error: $error";
    $c->render(json => { "errors" => $error }, status => 422);
  } else {
    return undef; # $error was empty, so we can do:  $c->err($error) || some_success_function
  }
};

# Ember pings the server with an OPTIONS request before getting down to business.  It's
# looking for the headers we add in the hook above and a 200 status
options '/*all' => sub {
  my $c = shift;
  $c->render(text => 'ok', status => 200);
};

# query entire table
get '/#table' => sub {
  my $c = shift;
  my $table = $c->stash('table');
  $c->render(json => { $table => $c->sqlite->db->query("select * from $table")->hashes });
};

# query one record
get '/#table/#id' => sub {
  my $c = shift;
  my $table = $c->stash('table');
  my $id = $c->stash('id');
  $c->render(json => $c->sqlite->db->query("select * from $table where id = $id")->hash);
};
 
# update existing record
put '/#table/#id' => sub {
  my $c = shift;
  my $table = $c->stash('table');
  my $id = $c->stash('id');
  my $newrecord = decode_json($c->req->body); 
  my $error;
  foreach my $k (keys %$newrecord) {
    my $t = $c->model_to_table($k);
    my (@vars, @vals);
    foreach my $l (keys %{$$newrecord{$k}}) {
      push @vars, "$l = ?";
      push @vals, $$newrecord{$k}{$l};
    }
    my $sql = "update $t set " . join(',', @vars) . " where id = $id";
    $c->sqlite->db->query("$sql", @vals, sub { $error = $_[1]; });
  }
  $c->err($error) || $c->render(json => { $table => {"id"  => $id}});
};
 
#create new record
post '/#table' => sub {
  my $c = shift;
  my $table = $c->stash('table');
  my $newrecord = decode_json($c->req->body); 
  my $error;
  foreach my $k (keys %$newrecord) {
    my $t = $c->model_to_table($k);
    say "table: $t";
    my (@vars, @vals, @q);
    foreach my $l (keys %{$$newrecord{$k}}) {
      push @vars, $l;
      push @vals, $$newrecord{$k}{$l};
      push @q, '?';
    }
    my $sql = "insert into $t (" . join(',', @vars) . ") values (" . join(',', @q) . ")";
    $c->sqlite->db->query("$sql", @vals, sub { $error = $_[1]; });
  }
  my $lastid = $c->sqlite->db->query("select last_insert_rowid() as id")->hash->{id};
  $c->err($error) || $c->render(json => { $table => {"id" => $lastid}});
};

#delete existing record
del '/#table/#id' => sub {
  my $c = shift;
  my $table = $c->stash('table');
  my $id = $c->stash('id');
  my $error;
  $c->sqlite->db->query("delete from $table where id = ?", $id, sub { $error = $_[1]; });
  $c->err($error) || $c->render(json => { $table => {"id" => $id}});
};


app->start;

