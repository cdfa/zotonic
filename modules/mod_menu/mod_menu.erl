%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2009 Marc Worrell
%% @date 2009-07-12
%% @doc Menu module.  Supports menus in Zotonic. Adds admin interface to define the menu.

%% Copyright 2009 Marc Worrell
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

-module(mod_menu).
-author("Marc Worrell <marc@worrell.nl>").

-mod_title("Menus").
-mod_description("Menus in Zotonic, adds amdin interface to define the menu.").

-include("zotonic.hrl").

%% interface functions
-export([
    init/1,
    datamodel/1,
    get_menu/1,
    get_menu/2,
    set_menu/3,
    observe_menu_get_rsc_ids/2,
    test/0,
    menu_flat/1,
    convert_symbolic_names/1
]).

%% @doc The datamodel for the menu routines.
datamodel(Context) ->
    [
     {categories,
      [
       {menu, categorization,
        [{title, <<"Page menu">>}]
       }
      ]
     },
     {resources,
      [
       {main_menu,
        menu,
        [{title, <<"Main menu">>},
         {menu, z_install_defaultdata:default_menu(m_site:get(skeleton, Context))}
        ]
       }
      ]}
    ].

%% @doc Initializes the module (after the datamodel is installed).
init(Context) ->
    z_pivot_rsc:insert_task(?MODULE, convert_symbolic_names, Context),
    case m_config:get(menu, menu_default, Context) of
        undefined -> ok;
        Props -> 
            %% upgrade from previous menu
            OldMenu = proplists:get_value(menu, Props, []),
            ?zInfo("Upgrading old menu structure", Context),
            set_menu(OldMenu, Context),
            m_config:delete(menu, menu_default, Context)
    end.



%% @doc Notifier handler to get all menu ids for the default menu.
observe_menu_get_rsc_ids(menu_get_rsc_ids, Context) ->
    Menu = get_menu(Context),
    {ok, menu_ids(Menu, [])}.

    menu_ids([], Acc) ->
        Acc;
    menu_ids([{Id,SubMenu}|T], Acc) ->
        Acc1 = menu_ids(SubMenu, [Id|Acc]),
        menu_ids(T, Acc1);
    menu_ids([H|T], Acc) ->
        menu_ids(T, [H|Acc]).


%% @doc Fetch the default menu. Performs validation/visibility checking on the menu items.
%% @spec get_menu(Context) -> list()
get_menu(Context) ->
    get_menu(m_rsc:rid(main_menu, Context), Context).

%% @doc Fetch a menu structure from a rsc. Performs validation/visibility checking on the menu items.
%% @spec get_menu(Id, Context) -> list()
get_menu(Id, Context) ->
    case m_rsc:p(Id, menu, Context) of
        undefined -> [];
        <<>> -> [];
        Menu -> remove_invisible(validate(Menu, []), [], Context)
    end.

	validate([], Acc) ->
		lists:reverse(Acc);
	validate([{_M,_L} = M|Ms], Acc) ->
		validate(Ms, [M|Acc]);
	validate([M|Ms], Acc) ->
		validate(Ms, [{M,[]}|Acc]).


%% Remove invisible menu items
remove_invisible([], Acc, _Context) ->
    lists:reverse(Acc);
remove_invisible([{Id,Sub}|Rest], Acc, Context) ->
    case m_rsc:is_visible(Id, Context) of
        true ->  remove_invisible(Rest, [{Id,remove_invisible(Sub, [], Context)} | Acc], Context);
        false -> remove_invisible(Rest, Acc, Context)
    end;
remove_invisible([Id|Rest], Acc, Context) ->
    case m_rsc:is_visible(Id, Context) of
        true ->  remove_invisible(Rest, [Id | Acc], Context);
        false -> remove_invisible(Rest, Acc, Context)
    end.


%% @doc Save the default menu.
set_menu(Menu, Context) ->
    Id = m_rsc:rid(main_menu, Context),
    set_menu(Id, Menu, Context).


%% @doc Save the current menu.
set_menu(Id, Menu, Context) ->
    m_rsc:update(Id, [{menu, Menu}], Context).



menu_flat(undefined) ->
    [];
menu_flat(<<>>) ->
    [];
menu_flat(X) ->
    menu_flat(X, [1], []).

menu_flat([], _Path, Acc) ->
    lists:reverse(Acc);
menu_flat([ {MenuId, []} | Rest], [Idx|PR], Acc ) ->

    [ {MenuId, [Idx|PR], undefined} ] 
        ++ menu_flat(Rest, [Idx+1|PR], [])
        ++  Acc;
menu_flat([ {MenuId, Children} | Rest], [Idx|PR], Acc ) ->

    [ {MenuId, [Idx|PR], down} ] 
        ++ menu_flat(Children, [1,Idx|PR], []) 
        ++ [{undefined, undefined, up}]
        ++ menu_flat(Rest, [Idx+1|PR], [])
        ++  Acc.


%% @doc Convert the menu structure as installed (which can contain
%%      resource names) to a menu which only contains numeric
%%      ids. This is needed for the menu trail to correctly function.
convert_symbolic_names(Ctx) ->
    Context = z_acl:sudo(Ctx),
    Menu = get_menu(Context),
    Menu2 = menu_names_to_ids(Menu, Context),
    set_menu(Menu2, Context),
    ok.

menu_names_to_ids(Menu, Ctx) ->
    menu_names_to_ids(Menu, Ctx, []).

menu_names_to_ids([], _Ctx, Acc) ->
    lists:reverse(Acc);
menu_names_to_ids([{Item, Childs}|Rest], Context, Acc) ->
    Id = case Item of
             X when is_integer(X) -> X;
             N -> m_rsc:rid(N, Context)
         end,
    [{Id, menu_names_to_ids(Childs, Context, [])} | menu_names_to_ids(Rest, Context, Acc)].
    

%% @doc test function
%%  111  [1]
%%  - 44   [1,1]
%%  - - 555  [1,1,1]
%%  - - 666  [1,1,2]
%%  222  [2]
%%  - 333  [2,1]
test() ->

    [
     {111, [1], down },
     {444, [1,1], down},
     {555, [1,1,1], undefined},
     {666, [2,1,1], undefined},
     {undefined, undefined, up},
     {undefined, undefined, up},
     {222, [2], down},
     {333, [1,2], undefined},
     {undefined, undefined, up}
    ]
        = menu_flat([{111, [{444, [{555, []}, {666, []} ]}]}, {222, [{333, []}]}]).
