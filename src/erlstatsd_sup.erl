%%%-------------------------------------------------------------------
%% @doc erlstatsd top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module('erlstatsd_sup').

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

-spec start_link() -> {ok, pid()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
-spec init(_Args::list()) ->
    {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}} | ignore.
init([]) ->
    ChildrenUDP = [{{udp_listener, X},  {erlstatsd_udp, init, [1]},
            permanent, brutal_kill, worker, [erlstatsd_udp]} || X <- lists:seq(1,10)],
    ChildFlusher = {erlstatsd_metric_flusher, {erlstatsd_metric_flusher, start_link, []},
                    permanent, brutal_kill, worker, [erlstatsd_metric_flusher]},
    ChildMetricSender = {metric_sender, {metric_sender, start_link, ["localhost", 2300]},
                         permanent, brutal_kill, worker, [metric_sender]},
    ChildLineParser = {line_parser, {erlstatsd_lineparser, start_link, []},
                       permanent, brutal_kill, worker, [erlstatsd_lineparser]},
    {ok, {{one_for_one, 5, 5}, ChildrenUDP ++ [ChildFlusher, ChildMetricSender, ChildLineParser]}}.

%%====================================================================
%% Internal functions
%%====================================================================
