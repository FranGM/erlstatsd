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
    ChildrenUDP = udp_listener_spec(4),
    ChildFlusher = flusher_worker_spec(),
    ChildrenMetricSender = metric_sender_worker_spec(4),
    ChildrenLineParser = lineparser_worker_spec(4),
    ChildInternalStats = internal_stats_worker_spec(),
    ChildConfig = config_worker_spec(Config),
    {ok,
     {{one_for_one, 5, 5}, [ChildConfig] ++ ChildrenUDP ++ ChildrenMetricSender ++ ChildrenLineParser ++ [ChildFlusher, ChildInternalStats]}}.

%%====================================================================
%% Internal functions
%%====================================================================

-spec udp_listener_spec(NumWorkers::non_neg_integer()) -> [supervisor:child_spec()].
udp_listener_spec(NumWorkers) ->
    [{{udp_listener, X},  {erlstatsd_udp, init, [X]},
      permanent, brutal_kill, worker, [erlstatsd_udp]} || X <- lists:seq(1,NumWorkers)].

-spec flusher_worker_spec() -> supervisor:child_spec().
flusher_worker_spec() ->
    {erlstatsd_metric_flusher, {erlstatsd_metric_flusher, start_link, []},
     permanent, brutal_kill, worker, [erlstatsd_metric_flusher]}.

-spec metric_sender_worker_spec(NumWorkers::non_neg_integer) -> [supervisor:child_spec()].
metric_sender_worker_spec(NumWorkers) ->
    [{{erlstatsd_metric_sender, X}, {erlstatsd_metric_sender, start_link, [{id, X}]},
      permanent, brutal_kill, worker, [erlstatsd_metric_sender]} || X <- lists:seq(1, NumWorkers)].

-spec lineparser_worker_spec(NumWorkers::non_neg_integer()) -> [supervisor:child_spec()].
lineparser_worker_spec(NumWorkers) ->
    [{{line_parser, X}, {erlstatsd_lineparser, start_link, []},
      permanent, brutal_kill, worker, [erlstatsd_lineparser]} || X <- lists:seq(1, NumWorkers)].

-spec internal_stats_worker_spec() -> supervisor:child_spec().
internal_stats_worker_spec() ->
    {internal_stats, {erlstatsd_internal_stats, start_link, []},
     permanent, brutal_kill, worker, [erlstatsd_internal_stats]}.

-spec config_worker_spec(Config::map()) -> supervisor:child_spec().
config_worker_spec(Config) ->
    {erlstatsd_config, { erlstatsd_config, start_link, [Config]},
     permanent, brutal_kill, worker, [erlstatsd_config]}.
