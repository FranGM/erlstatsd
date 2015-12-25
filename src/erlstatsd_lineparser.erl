-module(erlstatsd_lineparser).

-behaviour(gen_server).

-record(state, {}).

%% API
-export([start_link/0, parse/1]).

%% gen_server calbacks
-export([init/1, handle_info/2, handle_cast/2, handle_call/3, terminate/2, code_change/3]).

%% API

-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link(?MODULE, [], []).

-spec parse(Line::binary()) -> ok.
parse(Line) ->
    gen_server:cast(line_parser, {line, Line}).

%% gen_server callbacks

-spec init([]) -> {ok, #state{}}.
init([]) ->
    register(line_parser, self()),
    {ok, #state{}}.

-spec handle_cast({line, Line::binary()}, #state{}) -> {noreply, #state{}}.
handle_cast({line, Line}, State) ->
    parseLine(Line),
    {noreply, State}.

-spec handle_info(_, #state{}) -> {noreply, #state{}}.
handle_info(_Msg, State) ->
    {noreply, State}.

-spec handle_call(port(), _, #state{}) -> {noreply, #state{}}.
handle_call(_From, _Msg, State) ->
    {noreply, State}.

-spec code_change(_, #state{}, _) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

-spec terminate(_, #state{}) -> ok.
terminate(_Reason, _State) ->
    ok.

%% Private functions

%% Should try to follow this: https://github.com/b/statsd_spec
-spec parseLine(Line::binary()) -> ok.
parseLine(Line) ->
    try
        [MetricName, ValueType] = binary:split(Line, [<<$:>>], [trim]),
        [Value, Type] = binary:split(ValueType, [<<$|>>, <<"\n">>], [global, trim]),
        IntValue = list_to_integer(binary_to_list(Value)),
        case gproc:lookup_pids({n, l, MetricName}) of
            [] ->
                {ok, Pid} = supervisor:start_child(erlstatsd_metric_sup, [MetricName]),
                send_metric(binary_to_atom(Type, utf8), Pid, IntValue);
            [Pid] -> send_metric(binary_to_existing_atom(Type, utf8), Pid, IntValue)
        end
    catch
        _:Why -> io:format("Parse error: ~p~n", [Why])
    end.

-spec send_metric(ms, Pid::pid(), Value::number()) -> ok;
                 (c, Pid::pid(), Value::number()) -> ok;
                 (s, Pid::pid(), Value::number()) -> ok;
                 (g, Pid::pid(), Value::number()) -> ok.
send_metric(ms, Pid, Value) ->
    erlstatsd_metric:timer(Pid, Value);
send_metric(c, Pid, Value) ->
    erlstatsd_metric:counter(Pid, Value);
send_metric(s, Pid, Value) ->
    erlstatsd_metric:set(Pid, Value);
%% TODO: Support deltas for gauges
send_metric(g, Pid, Value) ->
    erlstatsd_metric:gauge(Pid, Value).

