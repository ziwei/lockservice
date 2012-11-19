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
-export([start/1]).

%%
%% API Functions
%%



%%
%% Local Functions
%%
start(Server) ->
lock:acquire(self(), Server),
receive lock -> ok end,
lock:release(self(), Server),
lock:get_queue(Server),
io:format("lock finished").