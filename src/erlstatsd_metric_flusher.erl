-module(erlstatsd_metric_flusher).

-export([start_link/0, start_link/1]).

%% TODO: Make flush rate configurable

-spec start_link() -> {ok, pid()}.
start_link() ->
    start_link(10000).

-spec start_link(FlushInterval::non_neg_integer()) -> {ok, pid()}.
start_link(FlushInterval) ->
    Pid = spawn_link(fun () -> loop(FlushInterval) end),
    {ok, Pid}.

-spec loop(FlushRate::non_neg_integer()) -> no_return().
loop(FlushRate) ->
    receive
    after FlushRate ->
              Pids = gproc:lookup_pids({p, l, metric}),
              [erlstatsd_metric:flush(Pid) || Pid <- Pids]
    end,
    loop(FlushRate).
