-module(replica).
-export([request/3]).
-export([loop/1, start_link/1, stop/0]).

-record(replica, {slot_num = 1,
                  proposals = [],
                  decisions = [],
                  application = undefined,
				  leader = undefined
                  }).

-define (SERVER, ?MODULE).
-define (GC_INTERVAL, 60000).

%%% Client API
request(Operation,Server, Client) ->
	%io:format("Replica req1"),
    client_proxy(Operation, Server, Client),

    ok.

client_proxy(Operation, Server, Client) ->
    %ClientProxy = self(),
	%register(client, self()),
	io:format("applied "),
	%io:format("applied ~w ~w", [Client, ClientProxy]),
    %UniqueRef = make_ref(),
    %[{?SERVER, Node} ! {request, {ClientProxy, UniqueRef, {Operation, Client}}} || Node <- [node()|nodes()]],

	{?SERVER, Server} ! {client_request, {Operation, Client}},
	io:format("Replica: sending requests ~n"),

    %?SERVER ! {request, {ClientProxy, UniqueRef, {Operation, Client}}},
    receive
        {response, {_, Result}} ->
			io:format("applied "),
            {ok, Result}
    end.
    
%%% Replica 
start_link(LockApplication) ->
	Leader = leader_election(),
	io:format("replica inited nodes ~w ~n", [node()]),
    ReplicaState = #replica{application=LockApplication, leader=Leader},
	SlotCommands = persister:load_saved_queue(),
	io:format("start restoring ~n"),
	restore_slotcommands(SlotCommands, ReplicaState),
    Pid = spawn_link(fun() -> loop(ReplicaState) end),
    register(replica, Pid),
    %erlang:send_after(?GC_INTERVAL, replica, gc_trigger),

    {ok, Pid}.

stop() ->
    ?SERVER ! stop.

loop(State) ->
    receive
		{nodedown, _} ->
			Leader = leader_election(),
			NewState = #replica{leader=Leader},
			loop(NewState);
		{client_request, Command} ->
			io:format("client req~n"),
			{?SERVER, State#replica.leader} ! {server_request, Command},
			loop(State);
        {server_request, Command} ->
			io:format("server req~n"),
			io:format("Replica proposing~n"),


            NewState = propose(Command, State),
			io:format("Replica proposed~n"),
            loop(NewState);
        {decision, Slot, Command} ->

			io:format("Replica got decision~n"),

            NewState = handle_decision(Slot, Command, State),
			%persister:delete_election(Slot),
            loop(NewState);        
        gc_trigger ->
            NewState = gc_decisions(State),
            erlang:send_after(?GC_INTERVAL, replica, gc_trigger),
            loop(NewState);
        stop ->
            ok
    end.

%%% Internals
leader_election() ->
	io:format("Leader election start ~n"),
	Config = file:consult("gaoler.config"),
	{ok, [_, Nodes]} = Config,
	{nodes, NodeList} = Nodes,
	io:format("Leader election start 1 ~n"),
	Leader = gaoler:whois_leader(NodeList),
	io:format("Leader election start 2 ~n"),
	erlang:monitor_node(Leader, true),
	Leader.

gc_decisions(State) ->
    CleanUpto = State#replica.slot_num - 200,
    Pred = fun({Slot, _Op}) ->
        Slot >= CleanUpto
    end,
    CleanedDecisions = lists:filter(Pred, State#replica.decisions),
    State#replica{decisions = CleanedDecisions}.


%% Push the command into the replica command queue
%% Should check that it hasn't already been delivered (duplicate msg)
%% Side-effects: sends messages to total ordering layer
%% Returns: updated state, with the command added to proposals
propose(Command, State) ->
    case is_command_already_decided(Command, State) of 
        false ->
			io:format("New command proposed ~w  ~n", [Command]),
            Proposal = {slot_for_next_proposal(State), Command},
			io:format("Proposal ready:~w~n",[Proposal]),

            send_to_leaders(Proposal, State),
            add_proposal_to_state(Proposal, State);
        true ->
			io:format("Already proposed ~w  ~n", [Command]),
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
	persister:persist_queue(Slot, Command),

    NewStateA = add_decision_to_state({Slot, Command}, State),
    consume_decisions(NewStateA).

%% Performs as many decided (queued) commands as possible
%%   * Delivers contiguous commands from the holdback queue, 
%%      halting when reaching an empty slot
%%   * checks whether any proposals were pre-empted
%% returns: updated state, with changes to application, slot_number, and the command queues
consume_decisions(State) ->
    Slot = State#replica.slot_num,
	%io:format("consuming ~w", [Slot]),
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
    [acceptor:gc_this(Acceptor, node(), Slot) || 
        Acceptor <- gaoler:get_acceptors()];
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
	io:format("perform Command ~n"),
    case has_command_already_been_performed(Command, State) of
        true -> % don't apply repeat messages
			%io:format("already "),
            inc_slot_number(State);
        false -> % command not seen before, apply
            ResultFromFunction = (catch (State#replica.application):Operation(Client)),
			io:format("apply Client ~w ~n", [Client]),
            NewState = inc_slot_number(State),
			{_, Name, Node} = Client,
            {Name, Node} ! {response, {Operation, ResultFromFunction}},            
            NewState
    end.

%% predicate: if exists an S : S < slot_num and {slot, command} in decisions
has_command_already_been_performed(Command, State) ->
	io:format("is Command applied ? ~w ~n", [Command]),
    PastCmdMatcher = fun(
        {S, P}) -> 
            (P == Command) and (S < State#replica.slot_num)
    end,
    lists:any(PastCmdMatcher, State#replica.decisions).

inc_slot_number(State) ->
    State#replica{slot_num=State#replica.slot_num + 1}.

add_decision_to_state(SlotCommand, State) ->
	io:format(" Add dec to State SlotCommand ~w ~n", [SlotCommand]),
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
	io:format("Restore SlotCommand ~w ~n", [SlotCommand]),
	add_decision_to_state(SlotCommand, State),
	restore_slotcommands(RestSlotCommands, State).
