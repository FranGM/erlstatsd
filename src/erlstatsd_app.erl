%%%-------------------------------------------------------------------
%% @doc erlstatsd public API
%% @end
%%%-------------------------------------------------------------------

-module('erlstatsd_app').

-behaviour(application).

%% Application callbacks
-export([start/2
        ,stop/1]).

%%====================================================================
%% API
%%====================================================================

-spec start(_,_) -> {error, _} | {ok, pid()}.
start(_StartType, _StartArgs) ->
    {ok, GraphiteHost} = application:get_env(erlstatsd, graphitehost),
    {ok, GraphitePort} = application:get_env(erlstatsd, graphiteport),
    {ok, FlushInterval} = application:get_env(erlstatsd, flushinterval),
    'erlstatsd_metric_sup':start_link(),
    'erlstatsd_sup':start_link(GraphiteHost, GraphitePort, FlushInterval).

%%--------------------------------------------------------------------
-spec stop(_) -> ok.
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
