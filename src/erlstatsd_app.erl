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
    Config = maps:from_list(application:get_all_env(erlstatsd)),
    'erlstatsd_metric_sup':start_link(),
    'erlstatsd_sup':start_link(Config).

%%--------------------------------------------------------------------
-spec stop(_) -> ok.
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
