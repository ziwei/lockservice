-module(acceptor_statestore).

-export([
         init/0,
         find/1,
         replace/1,
         add/1
        ]).

-include_lib("stdlib/include/ms_transform.hrl").
-include_lib("acceptor_state.hrl").

-define (TABLE, acceptor_statestore).

init() -> %TODO: make this private; it is public for delete in test cleanup 
    ets:new(?TABLE, [set, named_table, public]). 

find(ElectionId) ->
    case ets:lookup(?TABLE, ElectionId) of
        [] ->
            false;
        [{_ElectionId, _Election}=Found] ->
            Found
    end.

replace(NewElection) ->
    add(NewElection).

add(Election) ->
    ets:insert(?TABLE, {Election#election.id, Election}).
