-module(erlstatsd_metric_flusher).

-export([start_link/0, start_link/1]).

%% TODO: Make flush rate configurable
start_link() ->
    start_link(10000).

start_link(FlushInterval) ->
    Pid = spawn_link(fun () -> loop(FlushInterval) end),
    {ok, Pid}.

loop(FlushRate) ->
    receive
    after FlushRate ->
              Pids = gproc:lookup_pids({p, l, metric}),
              [erlstatsd_metric:flush(Pid) || Pid <- Pids]
    end,
    loop(FlushRate).
