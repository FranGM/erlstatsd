%%%-------------------------------------------------------------------
%% @doc erlstatsd top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module('erlstatsd_sup').

-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

-spec start_link(Config::map()) -> {ok, pid()}.
start_link(Config) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, [Config]).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
-spec init([any(),...]) ->
    {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}} | ignore.
init([Config]) ->
    ChildrenUDP = [{{udp_listener, X},  {erlstatsd_udp, init, [1]},
            permanent, brutal_kill, worker, [erlstatsd_udp]} || X <- lists:seq(1,10)],
    ChildFlusher = {erlstatsd_metric_flusher, {erlstatsd_metric_flusher, start_link, []},
                    permanent, brutal_kill, worker, [erlstatsd_metric_flusher]},
    ChildrenMetricSender = [{{metric_sender, X}, {metric_sender, start_link, [{id, X}]} , permanent, brutal_kill, worker, [metric_sender]} || X <- lists:seq(1,4)],
    ChildLineParser = {line_parser, {erlstatsd_lineparser, start_link, []},
                       permanent, brutal_kill, worker, [erlstatsd_lineparser]},
    ChildInternalStats = {internal_stats, {erlstatsd_internal_stats, start_link, []},
                          permanent, brutal_kill, worker, [erlstatsd_internal_stats]},
    ChildConfig = {erlstatsd_config, { erlstatsd_config, start_link, [Config]},
                   permanent, brutal_kill, worker, [erlstatsd_config]},
    {ok, {{one_for_one, 5, 5}, [ChildConfig] ++ ChildrenUDP ++ ChildrenMetricSender ++ [ChildFlusher, ChildLineParser, ChildInternalStats]}}.

%%====================================================================
%% Internal functions
%%====================================================================
