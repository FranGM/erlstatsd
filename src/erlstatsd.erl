-module (erlstatsd).

-export([do_stuff/0]).

do_stuff() ->
    {ok, Pid} = erlstatsd_metric:start_link("foo.bar"),
    erlstatsd_metric:counter(Pid, 12),
    erlstatsd_metric:counter(Pid, 12),
    erlstatsd_metric:counter(Pid, 1),
    erlstatsd_metric:counter(Pid, 12),
    erlstatsd_metric:counter(Pid, 12),
    erlstatsd_metric:timer(Pid, 450),
    erlstatsd_metric:timer(Pid, 120),
    erlstatsd_metric:timer(Pid, 553),
    erlstatsd_metric:timer(Pid, 994),
    erlstatsd_metric:timer(Pid, 334),
    erlstatsd_metric:timer(Pid, 844),
    erlstatsd_metric:timer(Pid, 675),
    erlstatsd_metric:timer(Pid, 496),
    erlstatsd_metric:flush(Pid),
    erlstatsd_metric:counter(Pid, 12),
    erlstatsd_metric:timer(Pid, 120),
    erlstatsd_metric:timer(Pid, 334),
    erlstatsd_metric:timer(Pid, 450),
    erlstatsd_metric:timer(Pid, 496),
    erlstatsd_metric:timer(Pid, 553),
    erlstatsd_metric:timer(Pid, 675),
    erlstatsd_metric:timer(Pid, 844),
    erlstatsd_metric:timer(Pid, 994),
    erlstatsd_metric:flush(Pid),
    ok.
