%% Author: ziwei
%% Created: Nov 15, 2012
%% Description: TODO: Add description to client
-module(client).

%%
%% Include files
%%

%%
%% Exported Functions
%%

-export([start/2, request/4, stop/0]).

-define(CLIENT, 'client1@lakka-6.it.kth.se').
%-define(CLIENT, 'c@127.0.0.1').
%%
%% API Functions

%% Local Functions
%%
start(N,Server) ->
	register(client, self()),
	Mode = read_mode(),
	request(N, Server, client, Mode).

request(0,Server, Name, Mode) ->
 	ok;
request(N,Server, Name, Mode)->
	case Mode of
		1 ->
			lock:acquire(self(), Server),
			receive lock -> ok end,
			lock:release(self(), Server);
		2 ->
			%io:format("lock acquired ~n"),
    		ok = replica:request(acquire, Server, {erlang:now(), Name, ?CLIENT}, Mode);
		3 ->
			%io:format("lock acquired ~n"),
    		ok = replica:request(acquire, Server, {erlang:now(), Name, ?CLIENT}, Mode)
	end,
	
%% 	receive lock -> ok end,
%% 	ok = replica:request(release, {client1, ?CLIENT}, Server),
%% 	io:format("lock release"),
	%lock:get_queue(Server),
	%io:format("lock finished ~n"),
	request(N-1,Server, Name, Mode).

read_mode() ->
	Config = file:consult("../rel/mode.config"),
	{ok, Tuple} = Config,
	[{mode, Mode}] = Tuple,
	Mode.

stop() ->
	exit(whereis(?CLIENT), ok).

stop()->
	exit(whereis(?CLIENT), ok).

