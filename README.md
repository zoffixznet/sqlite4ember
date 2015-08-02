# sqlite4ember

A standalone (web server built in), single-script RESTful web interface to an Sqlite 
datebase (single file, daemonless) for the Ember MVC framework (Ember Data specifically).  
Should be easily adaptable to other MVCs.  Great for front end development.  Feasible for
small production apps, but you'll need to add authentication.

```
Performance: Small queries on small tables take 5ms or less on my system according to
             Chrome's developer console
```

```
Prerequisites: 
    perl -MCPAN -e "install Mojolicious"
    perl -MCPAN -e "install Mojo::SQLite"
    Install sqlite with your OS's package manager or grab it at https://www.sqlite.org/
```

```
Database creation: sqlite3 <filename>
                   create table test (id integer primary key, stuff text)
                   <inserts and whatever other standard SQL you want>
                   control-D

Run the web server: ./sqlite4ember.pl daemon -l http://*:8000
  (https also works if you have the required perl modules)
```

```
URLs are automatically mapped to database tables, with table names at the root of the URL:

  http://localhost:8000/widgets     (query all widgets)
  http://localhost:8000/widgets/45  (query widget 45)

You don't need to tell this script about your database tables unless your table names don't
match your Ember models/routes (see config section at top of script)
```

```
To have Ember grok database errors, you'll want to set up your adapter with an ajaxError
member like so:

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

And then in your route, do something like this:

export default Ember.Route.extend({
     model: function() {
        return this.store.find('widget').then(null, function(response) { alert("Query failed: " + response.errors[0].detail);});;
    },

    ...

});


response.errors[0].detail will hold the actual error message returned by the database library

```

Further reading: 
* http://mojolicio.us/perldoc
* http://emberjs.com
* http://search.cpan.org/~dbook/Mojo-SQLite   
* https://www.sqlite.org
