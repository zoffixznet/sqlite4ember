# sqlite4ember

A standalone, single-script RESTful web interface to an SQLite 
datebase for the Ember Data portion of the Ember MVC framework.

You do not need a separate web or database server.  This script embeds the Mojolicious web server,
and SQLite is a single-file daemonless SQL database.

Should be easily adaptable to other MVCs.  Great for front end development.  Feasible for
small production apps, but you'll need to add authentication.


## Performance
Small queries on small tables take 5ms or less on my system according to Chrome's developer console

Using a copy of my production work database as-is, I used several parallel runs of "curl -s" to individually query all 78,000 rows of a table with over 30 columns and managed around 3000/second in the default single-instance non-preforking daemon mode.  

## Prerequisites
Install sqlite with your OS's package manager or grab it at https://www.sqlite.org/

Then install some Perl modules:
```
perl -MCPAN -e "install Mojolicious"
perl -MCPAN -e "install Mojo::SQLite"
perl -MCPAN -e "install IO::Socket::SSL" # (only if you want access via https)
```

## Database Creation
```
sqlite3 <filename>
create table test (id integer primary key, stuff text)
<inserts and whatever other standard SQL you want>
control-D
```

Every table needs an id column with type "integer primary key".

You don't need to tell this script about your database tables unless your table names don't
match your Ember models/routes (see config section at top of script)

## Run the web server
```
./sqlite4ember.pl daemon -l http://*:8000
./sqlite4ember.pl daemon -l https://*:8443
```

URLs are automatically mapped to database tables, with table names at the root of the URL:

* http://localhost:8000/            (list all tables found in database)
* http://localhost:8000/widgets     (query all widgets)
* http://localhost:8000/widgets/45  (query widget 45)

## Ember code

To have Ember grok database errors, you'll want to set up your adapter with an ajaxError
member like so:

```
export default DS.RESTAdapter.extend({
    host: 'http://localhost:3000',
    ajaxError: function(jqXHR) {
        var error = this._super(jqXHR);
        if (jqXHR && jqXHR.status === 422) {
            var jsonErrors = Ember.$.parseJSON(jqXHR.responseText)["errors"]; 
            return new DS.InvalidError(jsonErrors);
        } else {
            return error;
        }
    }
});
```

And then in your route, do something like this:

```
export default Ember.Route.extend({
     model: function() {
        return this.store.find('widget').then(null, function(response) { alert("Query failed: " + response.errors[0].detail);});;
    },

    ...

});
```

response.errors[0].detail will hold the actual error message returned by the database library

## Further reading
* http://mojolicio.us/perldoc
* http://emberjs.com
* http://search.cpan.org/~dbook/Mojo-SQLite   
* https://www.sqlite.org
