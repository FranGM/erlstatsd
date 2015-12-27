%%%-------------------------------------------------------------------
%% @doc erlstatsd top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module('erlstatsd_sup').

-behaviour(supervisor).

%% API
-export([start_link/3]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

-spec start_link(GraphiteHost::inet:hostname() | inet:ip_address(), GraphitePort::inet:port_number(), FlushInterval::non_neg_integer()) -> {ok, pid()}.
start_link(GraphiteHost, GraphitePort, FlushInterval) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, [GraphiteHost, GraphitePort, FlushInterval]).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
-spec init([any(),...]) ->
    {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}} | ignore.
init([GraphiteHost, GraphitePort, FlushInterval]) ->
    ChildrenUDP = [{{udp_listener, X},  {erlstatsd_udp, init, [1]},
            permanent, brutal_kill, worker, [erlstatsd_udp]} || X <- lists:seq(1,10)],
    ChildFlusher = {erlstatsd_metric_flusher, {erlstatsd_metric_flusher, start_link, [FlushInterval]},
                    permanent, brutal_kill, worker, [erlstatsd_metric_flusher]},
    ChildrenMetricSender = [{{metric_sender, X}, {metric_sender, start_link, [{id, X}, GraphiteHost, GraphitePort]} , permanent, brutal_kill, worker, [metric_sender]} || X <- lists:seq(1,4)],
    ChildLineParser = {line_parser, {erlstatsd_lineparser, start_link, [FlushInterval]},
                       permanent, brutal_kill, worker, [erlstatsd_lineparser]},
    {ok, {{one_for_one, 5, 5}, ChildrenUDP ++ ChildrenMetricSender ++ [ChildFlusher, ChildLineParser]}}.

%%====================================================================
%% Internal functions
%%====================================================================
