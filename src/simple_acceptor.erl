%%% -------------------------------------------------------------------
%%% Author  : ziwei
%%% Description :
%%%
%%% Created : Nov 22, 2012
%%% -------------------------------------------------------------------
-module(simple_acceptor).

-behaviour(gen_server).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------
-include_lib("acceptor_state.hrl").
%% --------------------------------------------------------------------
%% External exports
-export([]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, 
        terminate/2, code_change/3]).

-export([
	 start_link/0, 
	 stop/0, 
	 stop/1,
	 prepare/2, 
	 accept/3
	]).


%% ====================================================================
%% External functions
%% ====================================================================
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:cast(?MODULE, stop).
stop(Name) ->
    gen_server:cast(Name, stop).

prepare(Acceptor, {Election,Round}) ->
  gen_server:call(Acceptor, {prepare, {Election, Round}}).

accept(Acceptor, {Election,Round}, Value) ->
  gen_server:call(Acceptor, {accept, {Election, Round}, Value}).


%% ====================================================================
%% Server functions
%% ====================================================================

%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------
init([]) ->
	acceptor_statestore:init(),
    StartState = #state{},
	io:format("Acceptor inited~n"),
	
	Elections = persister:load_saved_state(),
	io:format("Acceptor inited ~w", [Elections]),
	restore_elections(Elections),
	io:format("Restoration finished"),
    {ok, StartState}.

handle_call({prepare, {ElectionId, Round}}, _From, State) ->
    handle_prepare({ElectionId, Round}, State);
handle_call({accept, {ElectionId, Round}, Value}, _From, State) ->
    handle_accept({ElectionId, Round}, Value, State).

handle_cast(stop, State) -> {stop, normal, State}.

handle_info(Info, State) ->
    {noreply, State}.
%%%===================================================================
%%% Prepare requests
%%%=================================================================== 
handle_prepare({ElectionId, Round}, State) ->
    case acceptor_statestore:find(ElectionId) of
        {ElectionId, FoundElection} ->
            handle_prepare_for_existing_election(ElectionId, Round, FoundElection, State);
        false ->
            create_new_election_from_prepare_request(ElectionId, Round, State)
    end.    

handle_prepare_for_existing_election(_ElectionId, Round, FoundElection, State) ->
	%io:format("id:~w round:~w found election:~w State:~w", [_ElectionId, Round, FoundElection, State]),
    HighestPromise = max(Round, FoundElection#election.promised),
    NewElection = FoundElection#election{promised = HighestPromise},
    update_election(NewElection),
    Reply = {promised, HighestPromise, NewElection#election.accepted},
    persister:remember_promise(_ElectionId, NewElection#election.promised),
    {reply, Reply, State}.

create_new_election_from_prepare_request(ElectionId, Round, State) ->
	%io:format("id:~w round:~w State:~w", [ElectionId, Round, State]),
    NewElection = #election{id = ElectionId, promised = Round},
    add_new_election(NewElection),

	io:format("promise replied~n"),

    persister:remember_promise(ElectionId, Round),

    {reply, {promised, Round, NewElection#election.accepted}, State}.

	

%%%===================================================================
%%% Accept requests
%%%=================================================================== 
handle_accept({ElectionId, Round}, Value, State) ->
    {Reply, NextState} = 
        case acceptor_statestore:find(ElectionId) of
            {ElectionId, _ElectionRecord}=Election ->
                handle_accept_for_election(Round, Value, Election, State);
            false ->
                create_new_election_from_accept_request(ElectionId, Round, Value, State)
        end,
    {reply, Reply, NextState}.

handle_accept_for_election(Round, Value, {ElectionId, Election}, State) 
  when Round >= Election#election.promised ->
    NewElection = Election#election{id = ElectionId, 
                                    promised = Round, 
                                    accepted = {Round, Value}},
    update_election(NewElection),
    persister:remember_vote(ElectionId, Round, Value),
    {{accepted, Round, Value}, State};
handle_accept_for_election(Round, _Value, _Election, State) ->
    {{reject, Round}, State}.

create_new_election_from_accept_request(ElectionId, Round, Value, State) ->
    NewElection = #election{id = ElectionId, 
                            promised = Round,
                            accepted = {Round, Value}},
    add_new_election(NewElection),
    persister:remember_vote(ElectionId, Round, Value),
    {{accepted, Round, Value}, State}.


%%%===================================================================
%%% Internal functions
%%%=================================================================== 
add_new_election(NewElection) ->
    acceptor_statestore:add(NewElection).

update_election(NewElection) ->
    acceptor_statestore:replace(NewElection).

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(Reason, State) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(OldVsn, State, Extra) ->
    {ok, State}.

%% --------------------------------------------------------------------
%%% Internal functions
%% --------------------------------------------------------------------

restore_elections([]) -> ok;
restore_elections(Elections) ->
	[Election|RestElections] = Elections,
	%io:format("Elec ~w", [Election]),
	{_, ElectionId, Promise, Accepted} = Election,
	%io:format("ooogidoooogi ~w ~w ~w", [ElectionId, Promise, Accepted]),
	add_new_election(#election{id = ElectionId, 
                            promised = Promise,
                            accepted = Accepted}),
	restore_elections(RestElections).
