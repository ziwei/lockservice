-module(lockservice_app).

-behaviour(application).

%% Application callbacks
-export([start/0,start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start()->
	start(nil,nil).

start(_StartType, _StartArgs) ->
	io:format("*******Trying to start link*******"),
    lockservice_sup:start_link().

stop(_State) ->
    ok.
