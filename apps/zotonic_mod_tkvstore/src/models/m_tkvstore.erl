%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2010-2021 Marc Worrell
%% @doc Simple store for key/value pairs

%% Copyright 2010-2021 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(m_tkvstore).
-author("Marc Worrell <marc@worrell.nl").

-behaviour(zotonic_model).

%% interface functions
-export([
    m_get/3,

    get/3,
    put/4,
    delete/3,
    delete/2,
    init/1
]).


-include_lib("zotonic_core/include/zotonic.hrl").


%% @doc Fetch the value for the key from a model source
-spec m_get( list(), zotonic_model:opt_msg(), z:context() ) -> zotonic_model:return().
m_get([ Type, Key | Rest ], _Msg, Context) ->
    case z_acl:is_admin(Context) of
        true -> {ok, {get(Type, Key, Context), Rest}};
        false -> {error, eacces}
    end;
m_get(Vs, _Msg, _Context) ->
    ?LOG_INFO("Unknown ~p lookup: ~p", [?MODULE, Vs]),
    {error, unknown_path}.


%% @doc Fetch a value from the store
get(Type, Key, Context) ->
    z_db:q1("select props from tkvstore where type = $1 and key = $2", [Type, Key], Context).

%% @doc Put a value into the store
put(Type, Key, Data, Context) ->
    F = fun(Ctx) ->
        case z_db:q1("select count(*) from tkvstore where type = $1 and key = $2", [Type, Key], Ctx) of
            0 ->
                z_db:q("insert into tkvstore (type, key, props) values ($1, $2, $3)", [Type, Key, ?DB_PROPS(Data)], Ctx);
            1 ->
                z_db:q("update tkvstore set props = $3 where type = $1 and key = $2", [Type, Key, ?DB_PROPS(Data)], Ctx)
        end
    end,
    z_db:transaction(F, Context).

%% @doc Delete a value from the store
delete(Type, Key, Context) ->
    z_db:q("delete from tkvstore where type = $1 and key = $2", [Type, Key], Context),
    ok.

%% @doc Delete a value from the store
delete(Type, Context) ->
    z_db:q("delete from tkvstore where type = $1", [Type], Context),
    ok.


%% @doc Ensure that the persistent table is present
init(Context) ->
    case z_db:table_exists(tkvstore, Context) of
        true ->
            ok;
        false ->
            z_db:q("
                create table tkvstore (
                    type character varying(32) not null,
                    key character varying(64) not null,
                    props bytea,

                    constraint tkvstore_pkey primary key (type, key)
                )
                ", Context),
            z_db:flush(Context)
    end.
