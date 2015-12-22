-module(erlstatsd_udp).

-export([init/0]).


init() ->
    Pid = spawn_link(fun() ->
                             {ok, _} = gen_udp:open(8125, [binary]),
                             loop()
                     end),
    {ok, Pid}.

%% Should try to follow this: https://github.com/b/statsd_spec
%% This needs to go on a separate process as it's pretty crash-happy
parseLine(Line) ->
    [MetricName, ValueType] = binary:split(Line, [<<$:>>], [trim]),
    [Value, Type] = binary:split(ValueType, [<<$|>>, <<"\n">>], [global, trim]),
    IntValue = list_to_integer(binary_to_list(Value)),
    io:format("~p ~p ~p~n", [MetricName, IntValue, Type]),
    case gproc:lookup_pids({n, l, MetricName}) of
        [] ->
            {ok, Pid} = supervisor:start_child(erlstatsd_metric_sup, [MetricName]),
            send_metric(binary_to_atom(Type, utf8), Pid, IntValue);
        [Pid] -> send_metric(binary_to_atom(Type, utf8), Pid, IntValue)
    end.


send_metric(ms, Pid, Value) ->
    erlstatsd_metric:timer(Pid, Value);
send_metric(c, Pid, Value) ->
    erlstatsd_metric:counter(Pid, Value);
send_metric(s, Pid, Value) ->
    erlstatsd_metric:set(Pid, Value);
%% TODO: Support deltas for gauges
send_metric(g, Pid, Value) ->
    erlstatsd_metric:gauge(Pid, Value).

loop() ->
    receive
        {udp, _Socket, _From, _Port, Line} ->
            parseLine(Line);
        Msg ->
            io:format("Unknown message received: ~p~n", [Msg])
    end,
    loop().
