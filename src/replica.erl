-module(replica).
-export([request/4]).
-export([loop/1, start_link/1, stop/0]).

-record(replica, {slot_num = 1,
                  proposals = [],
                  decisions = [],
                  application = undefined,
				  leader = undefined
                  }).

-define (SERVER, ?MODULE).
-define (GC_INTERVAL, 20000).
-define (REPLICAS, 3).

%%% Client API
request(Operation,Server, Client, Mode) ->
	%io:format("Replica req1"),
    client_proxy(Operation, Server, Client, Mode),
	ok.

client_proxy(Operation, Server, Client, Mode) ->
    %ClientProxy = self(),
	%register(client, self()),
	%io:format("applied "),
	%io:format("applied ~w ~w", [Client, ClientProxy]),
    %UniqueRef = make_ref(),
    %[{?SERVER, Node} ! {request, {ClientProxy, UniqueRef, {Operation, Client}}} || Node <- [node()|nodes()]],
	case Mode of
		2 -> 
			{?SERVER, Server} ! {server_request, {Operation, Client}};
		3 ->
			{?SERVER, Server} ! {client_request, {Operation, Client}}
	end,
	%io:format("Replica: sending requests to ~w ~n", [{?SERVER, Server}]),

    %?SERVER ! {request, {ClientProxy, UniqueRef, {Operation, Client}}},
    receive
        {response, {_, Result}} ->
			%io:format("applied "),
            {ok, Result}
    end.
    
%%% Replica 
start_link(LockApplication) ->
	%timer:sleep(2000),
	Leader = default_leader(),%leader_election(),

	%io:format("Leader is ~w ~n", [Leader]),
    ReplicaState = #replica{application=LockApplication, leader=Leader},
	%SlotCommands = persister:load_saved_queue(),
	%io:format("start restoring SlotCommands ~w ~n", [SlotCommands]),
	%restore_slotcommands(SlotCommands, ReplicaState),
    Pid = spawn_link(fun() -> loop(ReplicaState) end),
    register(?SERVER, Pid),
    erlang:send_after(?GC_INTERVAL, replica, gc_trigger),

    {ok, Pid}.

stop() ->
    ?SERVER ! stop.

loop(State) ->
	%io:format("start looping ~n"),
    receive
		{nodedown, _} ->
			%io:format("New leader election ~n"),
			Leader = leader_election(),
			NewState = #replica{leader=Leader},
			loop(NewState);
		gc_trigger ->
			io:format("~n********start garbage collection********~n"),
            NewState = gc_decisions(State),
            erlang:send_after(?GC_INTERVAL, replica, gc_trigger),
            loop(NewState);
		{client_request, Command} ->
			%io:format("client req~n"),
			{?SERVER, State#replica.leader} ! {server_request, Command},
			loop(State);
        {server_request, Command} -> %From, 
			%io:format("server req~n"),
			%io:format("Replica proposing~n"),

            NewState = propose(Command, State),
			%io:format("Replica proposed~n"),
            loop(NewState);
        {decision, Slot, Command} ->
			%io:format("Decision ~w",[Slot]),
            NewState = handle_decision(Slot, Command, State),
			%persister:delete_election(Slot),
            loop(NewState);        
        stop ->
            ok
    end.
	%io:format("end looping ~n").

%%% Internals
default_leader() ->
	Config = file:consult("lockservice.config"),
	{ok, [_, Nodes]} = Config,
	%io:format("Nodes are ~w ~n", [Nodes]),
	{nodes, NodeList} = Nodes,
	[Leader|_] = NodeList,
	Leader.

leader_election() ->
	%io:format("Leader election start ~n"),
	Config = file:consult("lockservice.config"),
	{ok, [_, Nodes]} = Config,
	%io:format("Nodes are ~w ~n", [Nodes]),
	{nodes, NodeList} = Nodes,
	%io:format("Leader election start 1 ~n"),
	Leader = master:whois_leader(NodeList),
	%io:format("Leader is ~w ~n",[Leader]),
	erlang:monitor_node(Leader, true),
	Leader.

gc_decisions(State) ->
	%GetSlot = fun(Replica) -> Replica ! {gc_req, self()} end,
	%lists:foreach(GetSlot,master:get_replicas()),
	[spawn(fun() -> 
        Replica ! {gc_req, self()} 
    end) || Replica <- master:get_replicas()],
	CleanUpto = get_min_slot_num(?REPLICAS, State#replica.slot_num) -100,
    %CleanUpto = State#replica.slot_num - 200,
    Pred = fun({Slot, _Op}) ->
        Slot >= CleanUpto
    end,
    CleanedDecisions = lists:filter(Pred, State#replica.decisions),
	io:format("clean up to ~w ",[CleanUpto]),
    State#replica{decisions = CleanedDecisions}.

get_min_slot_num(0, Num) ->
	Num;
get_min_slot_num(R, Num) ->
	receive
		{slot_num, NewNum} ->
			io:format("****Receive slot number****: ~w ~n",[NewNum]),
			get_min_slot_num(R-1, min(Num, NewNum));
		{gc_req, From} ->
			From ! {slot_num, Num},
			io:format("Receive gc_req ~n"),
			get_min_slot_num(R, Num)
	after 
		100 ->
			io:format("****timeout!****~n"),
			get_min_slot_num(0, Num)
	end.



%% Push the command into the replica command queue
%% Should check that it hasn't already been delivered (duplicate msg)
%% Side-effects: sends messages to total ordering layer
%% Returns: updated state, with the command added to proposals
propose(Command, State) ->
    case is_command_already_decided(Command, State) of 
        false ->
			%io:format("New command proposed ~w  ~n", [Command]),
            Proposal = {slot_for_next_proposal(State), Command},
			%io:format("Proposal ready:~w~n",[Proposal]),

            send_to_leaders(Proposal, State),
            add_proposal_to_state(Proposal, State);
        true ->
			%io:format("Already proposed ~w  ~n", [Command]),
            State
    end.

%% returns the next available command sequence slot, using the local replica's state
slot_for_next_proposal(#replica{proposals=Proposals, decisions=Decisions}) ->
    MaxSlotFn = fun({Slot, _Command}, Highest) -> max(Slot, Highest) end,
    MaxPropSlot = lists:foldl(MaxSlotFn, 0, Proposals),
    HighSlot = lists:foldl(MaxSlotFn, MaxPropSlot, Decisions),
	1 + HighSlot.

%% predicate returning true/false 
%% whether the command has already been decided and applied to the replica state
is_command_already_decided(Command, State) ->
    lists:any(
        fun({_S, DecidedCommand}) -> 
            Command == DecidedCommand 
        end, 
        State#replica.decisions
    ).

handle_decision(Slot, Command, State) ->
	%persister:persist_queue(Slot, Command),

    NewStateA = add_decision_to_state({Slot, Command}, State),
	%{_, {Suffix}} = Command,
	%{_, Id, Client} = Suffix,
	%{Id, Client} ! req_inqueue,
    consume_decisions(NewStateA).

%% Performs as many decided (queued) commands as possible
%%   * Delivers contiguous commands from the holdback queue, 
%%      halting when reaching an empty slot
%%   * checks whether any proposals were pre-empted
%% returns: updated state, with changes to application, slot_number, and the command queues
consume_decisions(State) ->
    Slot = State#replica.slot_num,
	%o:format("consuming ~w", [Slot]),
    case lists:keyfind(Slot, 1, State#replica.decisions) of
        false ->
			%io:format("not here "),
			
            State;
        {Slot, DecidedCommand} ->
            StateAfterProposalGC = handle_received_decision(Slot, DecidedCommand, State),
            StateAfterPerform = perform(DecidedCommand, StateAfterProposalGC),
            % multicast slot to acceptors for gc every nth decision
            check_gc_acceptor(Slot),
            consume_decisions(StateAfterPerform)
    end.

check_gc_acceptor(Slot) when Slot rem 300 == 0 ->
    [simple_acceptor:gc_this(Acceptor, node(), Slot) || 
        Acceptor <- master:get_acceptors()];
check_gc_acceptor(_) ->
    noop.

%% Garbage-collects the proposal for the given slot
%% When the command does not match the decided command
%% it will be re-proposed for another slot
handle_received_decision(Slot, DecidedCommand, State) ->
    % do we have a proposal for the same slot?
    case lists:keyfind(Slot, 1, State#replica.proposals) of 
        false -> % no match, noop
            State;
        {Slot, DecidedCommand} -> % we proposed this decision, gc it
            remove_proposal_from_state(Slot, State);
        {Slot, ConflictingCommand} -> 
            % we proposed a different command in this slot, repropose it in another slot
            CleanedState = remove_proposal_from_state(Slot, State),
            propose(ConflictingCommand, CleanedState)
    end.

%% carries out Command, unless it's already been performed by a previous decision
perform({Operation, Client}=Command, State) ->
	%io:format("perform Command ~n"),
    case has_command_already_been_performed(Command, State) of
        true -> % don't apply repeat messages
			%io:format("already "),
            inc_slot_number(State);
        false -> % command not seen before, apply
			case is_command_self_proposed(Command, State) of
				true ->
            		ResultFromFunction = (catch (State#replica.application):Operation(Client))
			end,
			%io:format("apply Client ~w ~p ~n", [Client, State]),
            NewState = inc_slot_number(State),
			%io:format("State updated ~n"),
			%{_, Name, Node} = Client,
            %{Name, Node} ! {response, {Operation, ResultFromFunction}},
			%io:format("Response sent out ~n"),
            NewState
    end.

%% predicate: if exists an S : S < slot_num and {slot, command} in decisions
is_command_self_proposed(Command, State) ->
	%io:format("is Command applied ? ~w ~n", [Command]),
    ProCmdMatcher = fun(
        {_, P}) -> 
            (P == Command)
    end,
    lists:any(ProCmdMatcher, State#replica.proposals).

has_command_already_been_performed(Command, State) ->
	%io:format("is Command applied ? ~w ~n", [Command]),
    PastCmdMatcher = fun(
        {S, P}) -> 
            (P == Command) and (S < State#replica.slot_num)
    end,
    lists:any(PastCmdMatcher, State#replica.decisions).

inc_slot_number(State) ->
    State#replica{slot_num=State#replica.slot_num + 1}.

add_decision_to_state(SlotCommand, State) ->
	%io:format(" Add dec to State SlotCommand ~w ~n", [SlotCommand]),
    State#replica{ decisions = [SlotCommand | State#replica.decisions] }.

add_proposal_to_state(Proposal, State) ->
    State#replica{ proposals = [Proposal | State#replica.proposals] }.

remove_proposal_from_state(SlotNumber, State) ->
    State#replica{proposals = lists:keydelete(SlotNumber, 1, State#replica.proposals)}.

send_to_leaders(Proposal, _State) ->
%    self() ! {decision, Slot, Proposal}.
    simple_proposer:propose(Proposal).

restore_slotcommands([], _) -> ok;
restore_slotcommands(SlotCommands, State) ->
	[SlotCommand|RestSlotCommands] = SlotCommands,
	%io:format("Restore SlotCommand ~w ~n", [SlotCommand]),
	add_decision_to_state(SlotCommand, State),
	restore_slotcommands(RestSlotCommands, State).

read_mode() ->
	Config = file:consult("mode.config"),
	{ok, Tuple} = Config,
	[{mode, Mode}] = Tuple,
	Mode.
