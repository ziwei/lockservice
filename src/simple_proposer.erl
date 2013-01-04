%% @author ziwei
%% @doc @todo Add description to simple_proposer.


-module(simple_proposer).
-behaviour(gen_fsm).
-include_lib("proposer_state.hrl").
-include_lib("accepted_record.hrl").

%% API
-export([
    start_link/3,
    deliver_promise/2,
    deliver_accept/2,
    propose/1
    ]).

%% gen_fsm callbacks
-export([init/1, 
	 awaiting_promises/2,
	 awaiting_accepts/2,
	 accepted/2
	]).


-export([handle_event/3,
	 handle_sync_event/4, 
	 handle_info/3, 
	 terminate/3, 
	 code_change/4]).


-define(SERVER, ?MODULE).
-define(MAJORITY, 1).


%%%===================================================================
%%% API
%%%===================================================================

%% begins an election where the proposer will seek
%% concensus on a value, proposing Proposal if no
%% other value has already been accepted by a majority
propose({Slot, Proposal}) ->
    ?MODULE:start_link(Slot, Proposal, self()).

start_link(Election, Proposal, ReplyPid) ->
    gen_fsm:start_link(?MODULE, [Election, Proposal, ReplyPid], []).

deliver_promise(Proposer, AcceptorReply) ->
    gen_fsm:send_event(Proposer, AcceptorReply).

deliver_accept(Proposer, AcceptorReply) ->
    gen_fsm:send_event(Proposer, AcceptorReply).

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

init([Election, Proposal, ReplyPid]) ->
    Round = 1,
	send_promise_requests(self(), {Election,Round}),
    {ok, awaiting_promises, #state{
           election = Election,
           round = Round, 
           value=#proposal{value = Proposal},
           reply_to = ReplyPid
    }}.

send_promise_requests(ReplyToProposer, Round) ->
    [spawn(fun() -> 
        send_promise_request(ReplyToProposer, Acceptor, Round) 
    end) || Acceptor <- master:get_acceptors()],
    ok.

send_promise_request(Proposer, Acceptor, Round) ->    
	%io:format("Acceptor prepared ~w~n", [Acceptor]),

    Reply = simple_acceptor:prepare(Acceptor, Round),
    deliver_promise(Proposer, Reply).

send_accept_requests(Proposer, Round, Value) ->
    [spawn(fun() -> 
        send_accept_request(Acceptor, Proposer, Round, Value) 
    end) || Acceptor <- master:get_acceptors() ],
    ok.

send_accept_request(Acceptor, Proposer, Round, Value) ->
    Reply = simple_acceptor:accept(Acceptor, Round, Value),
    deliver_accept(Proposer, Reply).
% on discovering a higher round has been promised
awaiting_promises({promised, PromisedRound, _}, State) 
    when PromisedRound > State#state.round -> % restart with Round+1 

    %io:format("promise received1~n"),

    NextRound = PromisedRound + 1, 
    NewState = State#state{round = NextRound, promises = 0},
    timer:sleep(NextRound*10), % lazy version of exponential backoff
    send_promise_requests(self(), {NewState#state.election,
                                             NextRound}),
    {next_state, awaiting_promises, NewState};
        
% on receiving a promise without past-vote data
awaiting_promises({promised, PromisedRound, no_value}, #state{round = PromisedRound}=State) ->
	%io:format("promise received2~n"),

    loop_until_promise_quorum(State#state{promises = State#state.promises + 1});

% on receiving a promise with accompanying previous-vote data
awaiting_promises({promised, PromisedRound, {AcceptedRound, AcceptedValue}}, 
    #state{round=PromisedRound}=State) -> 

	%io:format("promise received3~n"),

    NewState = State#state{ 
        value = case AcceptedRound > State#state.value#proposal.accepted_in_round of
            true -> #proposal{accepted_in_round = AcceptedRound, value=AcceptedValue} ;
            false -> State#state.value
        end,
        promises = State#state.promises + 1
    },
    loop_until_promise_quorum(NewState);

% on receiving unknown message
awaiting_promises(_, State) ->

	%io:format("promise received4~n"),
    {next_state, awaiting_promises, State}.

loop_until_promise_quorum(State) ->

    case State#state.promises >= master:majority() of
        true -> % majority reached
            Proposal = State#state.value#proposal.value,
            send_accept_requests(self(), 
                                           {State#state.election, 
                                            State#state.round}, 
                                           Proposal),
            {next_state, awaiting_accepts, State};
        false ->  % keep waiting
            {next_state, awaiting_promises, State}
    end.



awaiting_accepts({rejected, Round}, #state{round = Round, rejects = 2}=State) ->
    RetryRound = Round + 2,
    send_promise_requests(self(), {State#state.election, RetryRound}),
    {next_state, awaiting_promises, State#state{round = RetryRound, promises = 0}};

awaiting_accepts({rejected, Round}, #state{round=Round}=State) ->
    {next_state, awaiting_accepts, State#state{rejects = State#state.rejects + 1}};

awaiting_accepts({accepted, Round, _Value}, #state{round=Round}=State) ->
    NewState = State#state{accepts = State#state.accepts + 1},
    case NewState#state.accepts >= master:majority() of
        false ->
            {next_state, awaiting_accepts, NewState};
        true -> % deliver result to coordinator (its replica module)           
            %NewState#state.reply_to ! {decision, 
                                       %State#state.election, 
                                       %State#state.value#proposal.value},
			[spawn(fun() -> Replica ! {decision, 
                                       State#state.election, 
                                       State#state.value#proposal.value} 
    end) || Replica <- master:get_replicas()],
            {stop, normal, NewState}
    end;

awaiting_accepts(_, State) ->
    {next_state, awaiting_accepts, State}.


%% OTP Boilerplate
accepted(_, State) -> {next_state, accepted, State}.
handle_event(_Event, StateName, State) -> {next_state, StateName, State}.
handle_sync_event(_Event, _From, StateName, State) ->
    {reply, ok, StateName, State}.
handle_info(_Info, StateName, State) -> {next_state, StateName, State}.
terminate(_Reason, _StateName, _State) -> ok.
code_change(_OldVsn, StateName, State, _Extra) -> {ok, StateName, State}.


