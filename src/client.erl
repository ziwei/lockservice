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

-export([start/2, request/3]).

-define(CLIENT, 'client@lakka-6.it.kth.se').
%%-define(CLIENT, 'c@127.0.0.1').
%%
%% API Functions

%% Local Functions
%%
start(N,Server) ->
	register(client, self()),
	request(N, Server, client).

request(0,Server, Name) ->
 	ok;
request(N,Server, Name)->
	%lock:acquire(self(), Server),
	%receive lock -> ok end,
	%lock:release(self(), Server),

	io:format("lock acquired ~n"),
    ok = replica:request(acquire, Server, {erlang:now(), Name, ?CLIENT}),
	
%% 	receive lock -> ok end,
%% 	ok = replica:request(release, {client1, ?CLIENT}, Server),
%% 	io:format("lock release"),
	%lock:get_queue(Server),
	io:format("lock finished ~n"),
	request(N-1,Server, Name).

