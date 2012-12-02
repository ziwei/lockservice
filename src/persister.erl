-module(persister).

-include_lib("persister.hrl").
-include_lib("acceptor_state.hrl").

%%% Log API
-export([
         remember_promise/2,
         remember_vote/3,
         load_saved_state/0,
		 load_saved_queue/0,
		 delete_election/1,
		 persist_queue/2
        ]).


%%% Internal API
-export([read_log_file/2, read_queue_file/2]).


%%% Log API
remember_promise(Election, Round) ->
	%io:format("promise logging"),
    ok = log_promise_to_file(Election, Round).

remember_vote(Election, Round, Value) ->
	io:format("remembering vote ~w ~w ~n", [Round, Value]),
	ok = log_vote_to_file(Election, Round, Value).
%% 	 case is_atom(Value) of
%% 		 true ->
%% 	%io:format("remembering vote").
%%     % currently only supports atoms for value
%%      ok = log_vote_to_file(Election, Round, Value);
%% 	 	false -> 
%% 			io:format("nooooooooooooooott suppppppport"),
%% 			ok
%% 	 end.

persist_queue(Slot, Command) ->
	append_to_queuefile(Slot, Command).

delete_election(Election) ->
	file:delete(?LOG(Election)).

load_saved_state() ->
    load_saved_state_from_file().

load_saved_queue() ->
    load_saved_queue_from_file().

%%% FILE LOG API
log_promise_to_file(Election, Round) ->
	%io:format("promise logging1"),
    %LogRecord = "{promised,"++integer_to_list(Round)++"}.\n",
    append_to_logfile(Election, {promised, Round}).

log_vote_to_file(Election, Round, Value) ->
%%     LogRecord = "{accepted,"++integer_to_list(Round)++
%%         ","++atom_to_list(Value)++"}.\n",
	io:format("Round : ~w, Value : ~w ~n", [Round, Value]),
    append_to_logfile(Election, {accepted, {Round, Value}}).

load_saved_state_from_file() ->
%%     error("unimplemented").
	io:format("log files recovery started ~n"),
 	case file:list_dir(?LOGDIRECTORY) of
  	   {ok, Files} ->
		  %io:format("log files located"),
   	      Elections = collect_elections(Files);
   	      %#state{elections=Elections}; %-- this has been removed
   	   {error, _} ->
		  Elections = [],
   	      io:format("log files corrupted ~n")
 	end,
	%io:format("recovered collections : ~w", [Elections]),
	Elections.

load_saved_queue_from_file() ->
%%     error("unimplemented").
	%io:format("log files recovery started"),
 	case file:list_dir(?QUEUEDIRECTORY) of
  	   {ok, Files} ->
		  io:format("log files located ~n"),
   	      SlotCommands = collect_slotcommands(Files),
		  io:format("log files collected ~n");
   	   {error, _} ->
		  SlotCommands = [],
   	      io:format("log files corrupted ~n")
 	end,
	%[SlotCommand|_] = SlotCommands,
	%io:format("recovered SlotCommands : ~s", [SlotCommands]),
	SlotCommands.

%%% Helper functions
 collect_elections(Files) ->
	 %io:format("log file collecting ~s", [Files]),
     Self = self(),
     Pids = lists:map(fun(File) ->
                              spawn(fun() ->
                                            read_log_file(Self, File)
                                    end) 
                      end, Files),
	 
     gather_elections(Pids).
 
 gather_elections([Pid|Tail]) ->
     receive 
         {Pid, {error, _}} -> % filter corrupt files, is this intended?
             gather_elections(Tail);
         {Pid, ReturnValue} ->
			 %io:format("return : ~w", [ReturnValue]),
             [ReturnValue|gather_elections(Tail)]
     end;
 gather_elections([]) ->
     [].

collect_slotcommands(Files) ->
	 io:format("log file collecting ~s  ~n", [Files]),
     Self = self(),
     Pids = lists:map(fun(File) ->
                              spawn(fun() ->
                                            read_queue_file(Self, File)
                                    end) 
                      end, Files),
	 
     gather_slotcommands(Pids).
 
 gather_slotcommands([Pid|Tail]) ->
     receive 
         {Pid, {error, _}} -> % filter corrupt files, is this intended?
             gather_slotcommands(Tail);
         {Pid, ReturnValue} ->
			 io:format("returnValue : ~w  ~n", [ReturnValue]),
             [ReturnValue|gather_slotcommands(Tail)]
     end;
 gather_slotcommands([]) ->
     [].

% returns an acceptor election record for specified logfile
read_log_file(Parent, File) ->
	%io:format("reading log file ~s", [File]),
    Result = 
        case file:consult(?LOGDIRECTORY++"/"++File) of
            {ok, [{election,ElectionId}|Data]} -> 
				%io:format("pro data1"),
				ReversedData = lists:reverse(Data),
				%io:format("pro data2"),
				{Promise, Accepted} = member(ReversedData, 0, {0,0}),
               %ReversedData = lists:reverse(Data),
				%io:format("data ~w ~w", [Promise, AccVal]),
                #election{id = ElectionId,
						   promised=Promise, 
                           accepted=Accepted}
                ;
            {error, {_,_,_}} ->
                % critical -> could not parse the logfile
                {error, parse_error}
        end,
	%io:format("result send back ~s", [Result]),
    Parent ! {self(), Result}.

read_queue_file(Parent, File) ->
	io:format("reading log file ~s", [File]),
     %io:format("consult ~w ", [file:consult(?QUEUEDIRECTORY++"/"++File)]),
    Result = 
        case file:consult(?QUEUEDIRECTORY++"/"++File) of
            {ok, Data} -> %
			%io:format("goooooood ~s", [Data]),
            Data;
            {error, {_,_,_}} ->
                % critical -> could not parse the logfile
                {error, parse_error}
        end,
	io:format("result send back ~w ~n", [Result]),
    Parent ! {self(), Result}.

member([], Promise, Accepted) -> {Promise, Accepted};
member(Data, Promise, Accepted) -> 
	[Item|DataRest] = Data,
	{Mark,Content} = Item,
	case Mark of
		promised -> member(DataRest, Content, Accepted);
		accepted -> member(DataRest, Promise, Content);
		error -> 
			ignore
	end.
	   

append_to_logfile(Election, Record) ->
    file:make_dir(?LOGDIRECTORY),
    case file:read_file_info(?LOG(Election)) of
        {ok, _} ->
            ignore;
        {error, _} ->
            file:write_file(?LOG(Election), "{election, "
                            ++integer_to_list(Election)++"}.\n", [append])
    end,
    file:write_file(?LOG(Election), io_lib:fwrite("~p.\n",[Record]), [append]).

append_to_queuefile(Slot, Record) ->
    file:make_dir(?QUEUEDIRECTORY),
    io:format("Command ~w ", [Record]),
	
 	{ComName, {ComId, RegName, Node}} = Record,
	%file:write_file(?QUEUE(Slot), integer_to_list(Slot)++";"++atom_to_list(P), [append]).

	file:write_file(?QUEUE(Slot),io_lib:fwrite("~p.\n",[{Slot, Record}])).
%% 	io:format("Command ~w ~w ~w", [ComName, Pid, Node]),
    %file:write_file(?QUEUE(Slot), "{slot, "++integer_to_list(Slot)++"}.\n{command, "++atom_to_list({P, R, {ComName, pid_to_list(Pid)}})++"}.\n", [append]).

% assumes list is reversed
%% find_last_promise([]) -> 0;
%% find_last_promise([{promised, Value}|_Tail]) -> Value;
%% find_last_promise([_|Tail]) -> find_last_promise(Tail).
%% 
%% find_last_accepted_value([]) -> no_value;
%% find_last_accepted_value([{accepted, Round, Value}|_Tail]) -> {Round, Value};
%% find_last_accepted_value([_|Tail]) -> find_last_accepted_value(Tail).
    
