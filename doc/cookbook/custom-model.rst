.. _cookbook-custom-model:

Create a custom model
=====================

.. seealso:: :ref:`models section <guide-models>` in the Developer Guide
.. seealso:: list of :ref:`all models <models>`.

In this chapter we will look at how to implement a model around the
`The Open Movie Database (OMDB) API <http://www.omdbapi.com/>`_.

We will touch useful background information at the same time.

Model modules
^^^^^^^^^^^^^

Models are Erlang modules that are prefixed with ``m_`` and stored in your main module's subdirectory `models`. For example, the model to access Zotonic resources (syntax ``m.rsc.property``) is written in ``models/m_rsc.erl``.

Each model module is required to implement one function (as defined behavior in ``zotonic_model.erl``):

* m_get/2

m_get
^^^^^

This function fetches a value from a model. Because there are quite some different variation how to use this function, it is good to understand a bit more about the inner workings of data lookup.

Let's start with the parsing of a template expression::

    {{ m.rsc[1].is_cat.person }}

If you have done some work with Zotonic, you will be familiar with this syntax where we can find out if the resource with id ``1`` (the Administrator) is of category Person.

This expression contains 4 parts (separated by dots).

At the very start, the template parser resolves ``m.rsc`` to module ``m_rsc``. The parser then calls ``m_rsc:m_get(Keys, Context)`` to fetch the value (where Keys in our expression has the value of ``[ 1, <<"is_cat">>, <<"person">> ]``).

This is the function specification of ``m_get``::

    -spec m_get(Keys, Msg, Context) -> { term(), RestKeys } when
        Keys :: list(),
        Msg :: zotonic_model:opt_msg(),
        RestKeys :: list(),
        Context:: z:context().

It takes the dotted expression list and returns the looked up value and the unprocessed part of the dotted list (if any).

In this example, the `m_get` is called as::

    m_rsc:m_get([ 1, <<"is_cat">>, <<"person">> ], _Msg, Context)

And will return:

    {ok, {true, []}}

Where ``true`` is returned because rescource id 1 is indeed a person, and ``[]`` is returned because the call consumed all
parts of the dotted expression.


Example: Setting up m_omdb
--------------------------

All data calls to the OMDB go through the url ``http://www.omdbapi.com/?``, with query string appended. We can pass the movie id, title, and pass a type (movie/series/episode). OMDB offers more parameters but we don't need them now.


Template interface
^^^^^^^^^^^^^^^^^^

Let's define how will we use the data in templates.

To get all data for a particular ID::

    m.omdb["tt1135300"]

... so that we can get properties like the movie title::

    {{ m.omdb["tt1135300"].title }}

Find an item by title::

    {{ m.omdb["Alien"].year }}

Get all data from a movie::

    {% for k,v in m.omdb.movie["Alien"] %}{{ k }}: {{ v }}{% endfor %}

Get data from a series::

    {{ m.omdb.series[{query title="Dollhouse"}].plot }}

or from an episode::

    {{ m.omdb.episode[{query title="Dollhouse"}].plot }}


Model skeleton
^^^^^^^^^^^^^^

We will write our model in module ``models/m_omdb.erl``. Let's first get the mandatory elements out of the way::

    -module(m_omdb).
    -behaviour(zotonic_model).

    -export([
        m_get/3
    ]).

    -include_lib("zotonic_core/include/zotonic.hrl").

    % ... We will add our m_get functions here
    -spec m_get( list(), zotonic_model:opt_msg(), z:context() ) -> {ok, { term(), list() }} | {error, term()}.
    m_get([ _ | Rest ], _Msg, _Context) ->
        {ok, {undefined, Rest}};
    m_get(_, _Msg, _Context) ->
        {ok, {undefined, []}}.


Querying the API
^^^^^^^^^^^^^^^^

Before diving into the lookup functions, let's see what we want to achieve as result.

1. Using ``m_get`` we will generate a list of query parameters, for example ``[{type, "series"}, {title, "Dollhouse"}]``
2. And pass this list to a "fetch data" function
3. That creates a URL from the parameters,
4. loads JSON data from the URL,
5. and transforms the JSON into a property list

The ``fetch_data`` function::

    -spec fetch_data(Query) -> list() when
        Query:: list().
    fetch_data([]) ->
        [{error, "Params missing"}];
    fetch_data(Query) ->
        % Params title or id must be present
        case proplists:is_defined(title, Query) or proplists:is_defined(id, Query) of
            false -> [{error, "Param id or title missing"}];
            true ->
                % Translate query params id, title and type
                % into parameters that OMDB wants
                QueryParts = lists:map(fun(Q) ->
                    make_query_string(Q)
                end, Query),
                Url = ?API_URL ++ string:join(QueryParts, "&"),
                % Load JSON data
                case get_page_body(Url) of
                    {error, Error} ->
                        [{error, Error}];
                    Json ->
                        % Turn JSON into a property list
                        JsonData = z_json:decode(Json),
                        lists:map(fun(D) ->
                            convert_data_prop(D)
                        end, JsonData)
                end
        end.

It is important to know that we will pass a list, and get a list as result (for other template models this may be different).


Lookup functions
^^^^^^^^^^^^^^^^

To illustrate the simplest ``m_get`` function, we add one to get the API url::

    -define(API_URL, "http://www.omdbapi.com/?").

    % Syntax: m.omdb.api_url
    m_get([ <<"api_url">> | Rest ], _Msg, _Context) ->
        {ok, {?API_URL, Rest}};

The functions that will deliver our template interface are a bit more involved. From the template expressions we can discern 2 different patterns:

1. Expressions with 1 part:

  * ``m.omdb["Dollhouse"]``
  * ``m.omdb[{query title="Dollhouse"}]``

2. Expressions with 2 parts:

  * ``m.omdb.series["Dollhouse"]``
  * ``m.omdb.series[{query title="Dollhouse"}]``

When an expression is parsed from left to right, each parsed part needs to be passed on using our m record. For instance with ``m.omdb.series["Dollhouse"]`` we first tranform "series" to ``{type, "series"}``, and then "Dollhouse" to ``{title, "Dollhouse"}``, creating the full query ``[{type, "series"}, {title, "Dollhouse"}]``.

To parse the type, we add these functions to our module::

    % Syntax: m.omdb.movie[QueryString]
    m_get([ <<"movie">>, QueryString | Rest ], _Msg, Context) when is_binary(QueryString) ->
        Query = [ {type, movie}, {title, QueryString} ],
        {ok, {fetch_data(Query), []}};

    % Syntax: m.omdb.series[QueryString]
    m_get([ <<"series">>, QueryString | Rest ], _Msg, Context) when is_binary(QueryString) ->
        Query = [ {type, series}, {title, QueryString} ],
        {ok, {fetch_data(Query), []}};

    % Syntax: m.omdb.episode[QueryString]
    m_get([ <<"episode">>, QueryString | Rest ], _Msg, Context) when is_binary(QueryString) ->
        Query = [ {type, episode}, {title, QueryString} ],
        {ok, {fetch_data(Query), []}};


Notice the ``| Rest`` in the patterns. This is needed for expressions like::

    m.omdb.series["Dollhouse"].title

Which calls our ``m_get`` function as::

    m_get([ <<"series">>, <<"Dollhouse">>, <<"title">> ], _Msg, Context)


We can also pass:

1. The movie ID: ``m.omdb["tt1135300"]``
2. The title: ``m.omdb["Alien"]``
3. A search expression: ``m.omdb[{query title="Dollhouse"}]``

Luckily, the movie IDs all start with "tt", so we can use pattern matching to distinguish IDs from titles.

For the ID we recognize 2 situations - with or without a previously found value::

    % Syntax: m.omdb["tt1135300"]
    m_get([ <<"tt", _/binary>> = Id | Rest ], _Msg, Context) ->
        Query = [ {id, Id} ],
        {ok, {fetch_data(Query), []}};

    % Syntax: m.omdb.sometype["tt1135300"]
    m_get([ <<"sometype">>, <<"tt", _/binary>> = Id | Rest ], _Context) ->
        Query = [ {type, sometype}, {id, Id} ],
        {ok, {fetch_data(Query), []}}.

We need to place these two patterns above the title searches we already wrote

``fetch_data`` will return a property list, so we can write this to get all values::

    {% for k,v in m.omdb["tt1135300"] %}
        {{ k }}: {{ v }}
    {% endfor %}

Handling the title is similar to the ID. Title must be a string, otherwise it would be a property key (atom)::

    % Syntax: m.omdb["some title"]
    % If no atom is passed it must be a title (string)
    m_get([ Title | Rest ], _Context) when is_binary(Title) ->
        Query = [ {title, Title} ],
        {fetch_data(Query), []};

To parse the search expression, we can simply use the readymade property list::

    % Syntax: m.omdb[{query QueryParams}]
    % For m.omdb[{query title="Dollhouse"}], Query is: [{title,"Dollhouse"}]
    m_get([ {query, Query} | Rest ], _Context) ->
        {fetch_data(Query), []};

    % Syntax: m.omdb.sometype[{query QueryParams}]
    % For m.omdb.series[{query title="Dollhouse"}],
    % Query is: [{title,"Dollhouse"}] and Q is: [{type,"series"}]
    m_get([ <<"series">>, {query, Query} | Rest ], _Context) ->
        {fetch_data([{type, series} | Query), []};

If we want to fetch the year of the first result we use::

    m.omdb["Alien"].year

... we get called as::

    m_get([ <<"Alien">>, year ], _Msg, Context).

Which (after a search on the title "Alien") returns:

    {ok, {SomeSearchResultList, [ year ]}}.

The ``[ year ]`` will then be used to lookup the year property of the found result.

We won't do any validity checking on the parameter here, but for most modules it makes sense to limit the possibilities. See for instance how ``m_search:get_result`` is done.


Full source code
^^^^^^^^^^^^^^^^

The source code of the documentation so far can be found in this gist: `Zotonic 1.0 - Template model for the OMDB movie database - source code to accompany the documentation <https://gist.github.com/mworrell/08a9f2115c2df7a3f3068b500564314d>`_.


Possible enhancements
^^^^^^^^^^^^^^^^^^^^^

For a complete model for this API, I would expect:

* Data caching to speed up identical calls
* Support for all API parameters
* Better error handling (the service might be down or return wrong data)
