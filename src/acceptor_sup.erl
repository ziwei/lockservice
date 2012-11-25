%%% -------------------------------------------------------------------
%%% Author  : ziwei
%%% Description :
%%%
%%% Created : Nov 22, 2012
%%% -------------------------------------------------------------------
-module(acceptor_sup).

-behaviour(supervisor).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

%% --------------------------------------------------------------------
%% External exports
%% --------------------------------------------------------------------
-export([start_link/0]).

%% --------------------------------------------------------------------
%% Internal exports
%% --------------------------------------------------------------------
-export([
	 init/1
        ]).

%% --------------------------------------------------------------------
%% Macros
%% --------------------------------------------------------------------
-define(SERVER, ?MODULE).
-define(SIMPLE, simple_acceptor).
-define(FAST, fast_acceptor).

-define(SUPFLAGS, {
	  one_for_one, % restart strategy
	  1000,        % max restarts
	  3600         % max seconds between restarts
	 }).
%% --------------------------------------------------------------------
%% Records
%% --------------------------------------------------------------------

%% ====================================================================
%% External functions
%% ====================================================================
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).


%% ====================================================================
%% Server functions
%% ====================================================================
%% --------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok,  {SupFlags,  [ChildSpec]}} |
%%          ignore                          |
%%          {error, Reason}
%% --------------------------------------------------------------------
init([]) ->
    Acceptor = {acceptor ,{?SIMPLE, start_link,[]},
	      permanent, 2000, worker, [?SIMPLE]},
	
	io:format("Acceptor sup inited"),
	
    {ok, {?SUPFLAGS, [Acceptor]}}.

%% ====================================================================
%% Internal functions
%% ====================================================================

