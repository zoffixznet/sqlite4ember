#!/usr/bin/perl
use Mojolicious::Lite;
use Mojo::SQLite;
use Mojo::JSON qw(decode_json);

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

if (! -f $dbfile) {
  print STDERR "database $dbfile does not exist.  Create one like so:\n  sqlite3 $dbfile \"create table test (id int primary key, stuff text)\"\n";
  exit 1;
}
if (! -r $dbfile) {
  print STDERR "database $dbfile exists but is not readable.\n";
  exit 1;
}

my $d = Mojo::SQLite->new($dbfile);
if(! $d->db->ping) {
  print STDERR "Failed to open database $dbfile.";
  exit 1;
}
$d->db->disconnect;

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
    $c->render(json => { "errors" => { "database" => [$error] }}, status => 422);
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

# list available tables
get '/' => sub {
  my $c = shift;
  my @tables;
  my $tabsth = $c->sqlite->db->dbh->table_info();
  while (my (undef, undef, $name, $type, undef ) = $tabsth->fetchrow_array()) {
    push @tables, $name if $type eq "TABLE" && $name ne "sqlite_sequence";
  }
  $c->stash(tables => \@tables);
  $c->stash(baseurl => $c->url_for('/')->to_abs);
  $c->render('index');
};


# query entire table
get '/#table' => sub {
  my $c = shift;
  my $table = $c->stash('table');
  my $i_table = $c->sqlite->db->dbh->quote_identifier( $table );
  my $error;
  $c->sqlite->db->query("select * from $i_table", sub { 
    my ($db, $error, $results) = @_;
    $c->err($error) || $c->render(json => { $table => $results->hashes });
  });
};

# query one record
get '/#table/#id' => sub {
  my $c = shift;
  my $table = $c->stash('table');
  my $i_table = $c->sqlite->db->dbh->quote_identifier( $table );
  my $id = $c->stash('id');
  $c->sqlite->db->query("select * from $i_table where id = ?", $id, sub {
    my ($db, $error, $results) = @_;
    $c->err($error) || $c->render(json => { $table => $results->hash });
  });
};
 
# update existing record
put '/#table/#id' => sub {
  my $c = shift;
  my $table = $c->stash('table');
  my $id = $c->stash('id');
  my $newrecord = decode_json($c->req->body); 
  my $error;
  my $dbh = $c->sqlite->db->dbh;
  foreach my $k (keys %$newrecord) {
    my $t = $dbh->quote_identifier( $c->model_to_table($k) );
    my (@vars, @vals);
    foreach my $l (keys %{$$newrecord{$k}}) {
      push @vars, $dbh->quote_identifier($l) . ' = ?';
      push @vals, $$newrecord{$k}{$l};
    }
    my $sql = "update $t set " . join(',', @vars) . ' where id = ?';
    $c->sqlite->db->query($sql, @vals, $id, sub { $error = $_[1]; });
  }
  $c->err($error) || $c->render(json => { $table => {"id"  => $id}});
};
 
#create new record
post '/#table' => sub {
  my $c = shift;
  my $table = $c->stash('table');
  my $newrecord = decode_json($c->req->body); 
  my $error;
  my $dbh = $c->sqlite->db->dbh;
  foreach my $k (keys %$newrecord) {
    my $t = $dbh->quote_identifier( $c->model_to_table($k) );
    my (@vars, @vals, @q);
    foreach my $l (keys %{$$newrecord{$k}}) {
      push @vars, $dbh->quote_identifier( $l );
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
  my $i_table = $c->sqlite->db->dbh->quote_identifier( $table );
  my $id = $c->stash('id');
  my $error;
  $c->sqlite->db->query("delete from $i_table where id = ?", $id, sub { $error = $_[1]; });
  $c->err($error) || $c->render(json => { $table => {"id" => $id}});
};


app->start;
__DATA__

@@ index.html.ep
<!DOCTYPE html>
<html>
  <head><title>SQLite4Ember Table List</title></head>
  <body>
    <h1><a href=https://github.com/groovy9/sqlite4ember>SQLite4Ember</a></h1>
    <h2>Tables found in database:</h1>
    % for my $t (@$tables) {
      <a href=<%=$baseurl%><%=$t%>><%=$t%></a><br>
    % }
  </body>
</html>
