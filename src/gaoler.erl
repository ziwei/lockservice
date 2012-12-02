-module(gaoler).
-behaviour(gen_server).

-include_lib("gaoler_state.hrl").

%% API
-export([
	 start_link/0, 
	 get_acceptors/0,
         majority/0,
         replicas/0,
	 whois_leader/1,
	% join/0,
	 stop/0
	]).

%% gen_server callbacks
-export([
	 init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3
	]).

-define(SERVER, ?MODULE). 
-define(DEFAULT_MAJORITY, 1).
-define(DEFAULT_REPLICAS, 1).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

majority() ->
    gen_server:call(?SERVER, majority).

replicas() ->
    gen_server:call(?SERVER, replicas).

%join() ->
    %gen_server:abcast(?SERVER, {join, node()}). 

get_acceptors() ->
    gen_server:call(?SERVER, get_acceptors).

stop() ->
    gen_server:cast(?SERVER, stop).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    process_flag(trap_exit, true),
    
    % read config
    Configuration = 
        case file:consult("gaoler.config") of
            {ok, ReadConfig} ->
                ReadConfig;
            {error, _} ->
                [{majority, ?DEFAULT_MAJORITY}, 
                 {replicas, ?DEFAULT_REPLICAS},
                 {nodes, []}]
        end,
    InitialState = #state{configuration = Configuration},

    % ping nodes from configuration
    Nodes = proplists:get_value(nodes, InitialState#state.configuration, []),
    [spawn(fun() -> net_adm:ping(Node) end) || Node <- Nodes],
	
	%io:format("Gaoler inited"),
	
    {ok, InitialState}.

handle_call(replicas, _From, State) ->
    {reply, proplists:get_value(replicas, State#state.configuration), State};
handle_call(majority, _From, State) ->
    {reply, proplists:get_value(majority, State#state.configuration), State};
handle_call(get_acceptors, _From, State) ->
	%%Modified!
	%Reply = [{simple_acceptor, Node} || Node <- [node()|nodes()]],
	%io:format("Acceptors: ~w",[proplists:get_value(nodes, State#state.configuration)]),
    Reply = [{simple_acceptor, Node} || Node <- [node()|proplists:get_value(nodes, State#state.configuration)]],
	%io:format("Acceptors:~w~n",[Reply]),
    {reply, Reply, State}.

%handle_cast({join, Node}, State) ->
    %erlang:monitor_node(Node, true),
    %{noreply, State};
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({nodedown, Node}, State) ->
    io:format("Lost node: ~p~n", [Node]),
    case length(gaoler:get_acceptors()) < gaoler:majority() of 
	true ->
	    io:format("FATAL: Insufficient majority.~n", []);
	false ->
	    ok
    end,
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

whois_leader([]) ->
	ok;
whois_leader(Nodes) ->
	io:format("Node ~w ~n" ,[Nodes]),
	[Node|OtherNodes] = Nodes,
	%io:format("Node ~w ~n" ,[Node]),
	case net_adm:ping(Node) of
		pang ->
			whois_leader(OtherNodes);
		pong ->
			io:format(" Leader Node ~w ~n" ,[Node]),
			Node
	end.

%%%===================================================================
%%% Internal functions
%%%===================================================================
