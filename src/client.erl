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

	io:format("lock acquired "),
    ok = replica:request(acquire, Server, {N, Name, ?CLIENT}),
	
%% 	receive lock -> ok end,
%% 	ok = replica:request(release, {client1, ?CLIENT}, Server),
%% 	io:format("lock release"),
	%lock:get_queue(Server),
	io:format("lock finished"),
	request(N-1,Server, Name).

