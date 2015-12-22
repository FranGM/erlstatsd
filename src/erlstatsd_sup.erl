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

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    ChildUDP = {erlstatsd_udp, {erlstatsd_udp, init, []},
            permanent, brutal_kill, worker, [erlstatsd_udp]},
    ChildFlusher = {erlstatsd_metric_flusher, {erlstatsd_metric_flusher, start_link, []},
                    permanent, brutal_kill, worker, [erlstatsd_metric_flusher]},
    ChildMetricSender = {metric_sender, {metric_sender, start_link, ["localhost", 2300]},
                         permanent, brutal_kill, worker, [metric_sender]},
    {ok, {{one_for_one, 0, 1}, [ChildUDP, ChildFlusher, ChildMetricSender]}}.

%%====================================================================
%% Internal functions
%%====================================================================
