-module(erlstatsd_metric_flusher).

-export([start_link/0]).

-spec start_link() -> {ok, pid()}.
start_link() ->
    FlushInterval = erlstatsd_config:get_flush_interval(),
    Pid = spawn_link(fun () -> loop(FlushInterval) end),
    {ok, Pid}.

-spec loop(FlushRate::non_neg_integer()) -> no_return().
loop(FlushRate) ->
    receive
    after FlushRate ->
              Pids = gproc:lookup_pids({p, l, metric}),
              [erlstatsd_metric:flush(Pid) || Pid <- Pids],
              erlstatsd_internal_stats:flush()
    end,
    loop(FlushRate).
