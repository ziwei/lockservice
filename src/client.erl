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
-export([start/2, service/2]).

-define(CLIENT, 'ziwei@127.0.0.1').

%%
%% API Functions
%%
start(N,Server) ->
register(client1, self()),
service(N,Server),
ok.
%%
%% Local Functions
%%
service(0,Server) ->
 	ok;
service(N,Server)->
	%lock:acquire(self(), Server),
	%receive lock -> ok end,
	%lock:release(self(), Server),
    ok = replica:request(acquire, {client1, ?CLIENT}, Server),
	io:format("lock acquired ~w", [{client1, ?CLIENT}]),
	receive lock -> ok end,
	ok = replica:request(release, {client1, ?CLIENT}, Server),
	io:format("lock release"),
	lock:get_queue(Server),
	io:format("lock finished"),
	service(N-1,Server).

