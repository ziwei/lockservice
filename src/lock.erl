%% Author: ziwei
%% Created: Nov 15, 2012
%% Description: TODO: Add description to lock
-module(lock).

-behaviour(gen_server).
-export([acquire/1, acquire/2, release/1, release/2, get_queue/1]).
-export([start/0, start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
%%
%% Include files
%%
-include_lib("lock_state.hrl").
-define (SERVER, ?MODULE).
%%
%% Exported Functions
%%

%%
%% API Functions
%%
start() ->
	%io:format("enter start link"),
	gen_server:start({local, ?SERVER}, ?MODULE,[],[]).
start_link() ->
	%io:format("enter start link"),
	gen_server:start_link({local, ?SERVER}, ?MODULE,[],[]).
acquire (Client) ->
	%io:format("enter acq"), 	
    gen_server:call(?SERVER, {acquire, Client}).
acquire (Client, Server) ->
	%io:format("enter acq"), 	
    gen_server:call({?SERVER, Server}, {acquire, Client}).
release (Client) ->
    gen_server:call(?SERVER, {release, Client}).
release (Client, Server) ->
    gen_server:call({?SERVER, Server}, {release, Client}).
get_queue(Server) -> 
    gen_server:call({?SERVER, Server}, get_queue).
%%
%% Local Functions
%%7
init([])->
	%io:format("Lock init"),
	{ok, #state{
        queue = queue:new()
    }}.

handle_call(get_queue, _From, State) ->
	%io:format("Queue ~w", [State#state.queue]),
    {reply, State#state.queue, State};
handle_call({acquire, Client}, _From, State) ->
	%io:format("handle acq"),
    {reply, ok, handle_acquire_req(Client, State)};
handle_call({release, Client}, _From, State) -> 
    {reply, ok, handle_release_req(Client, State)}.
		  

%% add the client to the lock queue, and
%% give them the lock if nobody else was waiting
handle_acquire_req(Client, #state{queue=Queue}=State) ->
    NewQueue = queue:in(Client, Queue),
	NewState = State#state{queue=NewQueue},
	{_, RegName, ClientNode} = Client,
	Mode = read_lockmode(),
    % if the queue was empty we can send out the lock
    case queue:is_empty(Queue) of
        true -> comms(send_lock, {RegName, ClientNode}, State), NewState;
        false -> 
			case Mode of
				1 ->
					noop, NewState;
				2 ->
					%io:format("NewQueue ~w ~n", [NewQueue]),
					send_lock(NewQueue, State),
    				EmptyState = State#state{queue=queue:new()},
					EmptyState
			end
	end.
send_lock(Queue, State) -> 
	case queue:out(Queue) of
		{{value, Client}, RestQueue} ->
			%io:format("Client ~p ~n", [Client]),
			{_, RegName, ClientNode} = Client,
			comms(send_lock, {RegName, ClientNode}, State),
			send_lock(RestQueue, State);
		{empty, _} ->
			ok
	end.
%% give the current lock holder from the queue
%%  and give the lock to the next in queue (if any)
handle_release_req(_Client, State) ->
	%io:format("releasing ~n"),
    % release the lock, removing the queue head who held it
    case queue:out(State#state.queue) of
        % the lock was held
        {{value, _Releasing}, NewQueue} ->
            % is someone waiting in the queue?
            case queue:peek(NewQueue) of
                {value, NextLockHolder} -> 
                    % yes: send them the lock
					{_, RegName, ClientNode} = NextLockHolder,
					%io:format("Target ~w ~n", [{RegName, ClientNode}]),
                    comms(send_lock, {RegName, ClientNode}, State);
                empty -> 
                    % no: wait for the next request
                    ok
            end,
            State#state{queue=NewQueue};
        {empty, EmptyQueue} -> % no lock is held, do nothing
            State#state{queue=EmptyQueue}
    end.
comms(_, Args, _) -> 
	%io:format("Target pid ~w", [Args]),
     Args ! lock.

read_lockmode() ->
	Config = file:consult("lockmode.config"),
	{ok, Tuple} = Config,
	[{mode, Mode}] = Tuple,
	Mode.

%%%===================================================================
%%% Uninteresting gen_server boilerplate
%%%===================================================================
handle_cast(stop, State) -> 
    {stop, normal, State}.
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.
