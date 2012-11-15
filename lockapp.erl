%% Author: ziwei
%% Created: Nov 15, 2012
%% Description: TODO: Add description to lockapp
-module(lockapp).

%%
%% Include files
%%

%%
%% Exported Functions
%%
-export([
         start/0
	]).



%%
%% API Functions
%%

start() ->
	lock:start_link().

%%
%% Local Functions
%%

