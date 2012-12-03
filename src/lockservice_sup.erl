-module(lockservice_sup).
-behaviour(supervisor).

%% API
-export([
	 start_link/0
	]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).
-define(SUPFLAGS, {
	  one_for_one, % restart strategy
	  1000,        % max restarts
	  3600         % max seconds between restarts
	 }).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).


init([]) ->
    Master = {master, {master, start_link, []},
		     permanent, 2000, worker, [master]},
	
    
    AcceptorSup = {acceptor_sup, {acceptor_sup, start_link, []},
                permanent, infinity, supervisor, [acceptor_sup]},
    
    LockService = {lock, {lock, start_link, []},
                              permanent, 2000, worker, [lock]},

    % RSM
    RSM = {replica, {replica, start_link, [lock]},
           permanent, 2000, worker, [replica]},
    
    {ok, {?SUPFLAGS, [Master,LockService,AcceptorSup,RSM]}}.