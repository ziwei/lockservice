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
-export([start/2]).

%%
%% API Functions
%%



%%
%% Local Functions
%%
start(0,Server) ->
 	ok;
start(N,Server)->
	%lock:acquire(self(), Server),
	%receive lock -> ok end,
	%lock:release(self(), Server),
    ok = replica:request(acquire, Server),
	io:format("lock acquired"),
	receive lock -> ok end,
	ok = replica:request(release, Server),
	io:format("lock release"),
	lock:get_queue(Server),
	io:format("lock finished"),
	start(N-1,Server).

