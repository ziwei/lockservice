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
-export([start/0]).

%%
%% API Functions
%%



%%
%% Local Functions
%%
start() ->
lock:acquire(self()),
receive lock -> ok end,
lock:release(self()),
io:format("lock finished").
