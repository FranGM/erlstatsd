-module(erlstatsd_metric_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

-spec start_link() -> {ok, pid()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% TODO: Figure out the right restart strategy/timeout values
-spec init(_Args::list()) ->
    {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}} | ignore.
init(_Args) ->
    RestartStrategy = {simple_one_for_one, 3, 60},
    ChildSpec = {erlstatsd_metric,
                 {erlstatsd_metric, start_link, []},
                 temporary, 5000, worker, [erlstatsd_metric]},
    {ok, {RestartStrategy, [ChildSpec]}}.
