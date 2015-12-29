-module(erlstatsd_lineparser).


-behaviour(gen_server).

-record(state, {flushInterval::non_neg_integer()}).

%% API
-export([start_link/0, parse/1]).

%% gen_server calbacks
-export([init/1, handle_info/2, handle_cast/2, handle_call/3, terminate/2, code_change/3]).

-define(DEFAULT_SAMPLE_RATE, 1.0).

%% API

-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link(?MODULE, [], []).

-spec parse(Packet::binary()) -> ok.
parse(Packet) ->
    Pids = gproc:lookup_pids({p, l, line_parser}),
    ParserPid = lists:nth(random:uniform(length(Pids)), Pids),
    gen_server:cast(ParserPid, {packet, Packet}).

%% gen_server callbacks

-spec init([]) -> {ok, #state{}}.
init([]) ->
    FlushInterval = erlstatsd_config:get_flush_interval(),
    gproc:reg({p, l, line_parser}),
    {ok, #state{flushInterval=FlushInterval}}.

-spec handle_cast({packet, Packet::binary()}, #state{}) -> {noreply, #state{}}.
handle_cast({packet, Packet}, State) ->
    %% The last element from the split is either an empty binary or a line that doesn't
    %%     end with a newline
    [Extra | Lines] = lists:reverse(binary:split(Packet, [<<$\n>>], [global])),
    case Extra of
        <<"">> -> ok;
        _ -> erlstatsd_internal_stats:bad_line()
    end,
    lists:map(fun (Line) ->
                  parseLine(Line, State)
              end, Lines),
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

-spec parseLine(Line::binary(), #state{}) -> ok.
parseLine(Line, #state{}) ->
    lager:debug("Parsing line: '~p'", [Line]),
    try
        [MetricName, ValueType] = binary:split(Line, [<<$:>>]),
        [Value, Type, SampleRate] = case binary:split(ValueType, [<<$|>>], [global]) of
            [V, T, <<$@, S/binary>>] ->
                                             [list_to_integer(binary_to_list(V)),
                                  binary_to_existing_atom(T, utf8),
                                  list_to_float(binary:bin_to_list(S))];
            [V, T] ->
                                            [list_to_integer(binary_to_list(V)),
                       binary_to_existing_atom(T, utf8),
                      ?DEFAULT_SAMPLE_RATE]
        end,
        Delta = case ValueType of
                    << $-, _/binary >> -> true;
                    << $+, _/binary >> -> true;
                    _ -> false
                end,
        SanitizedMetricName = sanitize_metric_name(MetricName),
        Pid = erlstatsd_metric:metric_worker_pid(SanitizedMetricName),
        case {Delta, Type} of
            {true, g} -> send_metric(Type, Pid, {delta, Value}, SampleRate);
            _ -> send_metric(Type, Pid, Value, SampleRate)
        end,
        erlstatsd_internal_stats:metric_received()
    catch
        _:Why ->
            erlstatsd_internal_stats:bad_line(),
            lager:error("Parse error: ~p", [Why])
    end.

-spec send_metric(ms | c | s | g, Pid::pid(), Value::number(), SampleRate::float()) -> ok;
                 (g, Pid::pid(), {delta, Value::number()}, SampleRate::float()) -> ok.
send_metric(ms, Pid, Value, SampleRate) ->
    erlstatsd_metric:timer(Pid, Value, SampleRate);
send_metric(c, Pid, Value, SampleRate) ->
    erlstatsd_metric:counter(Pid, Value, SampleRate);
send_metric(s, Pid, Value, _SampleRate) ->
    erlstatsd_metric:set(Pid, Value);
send_metric(g, Pid, {delta, Value}, _SampleRate) ->
    erlstatsd_metric:gauge(Pid, {delta, Value});
send_metric(g, Pid, Value, _SampleRate) ->
    erlstatsd_metric:gauge(Pid, Value).

-spec sanitize_metric_name(MetricName::binary()) -> binary().
sanitize_metric_name(MetricName) when is_binary(MetricName) ->
    %% TODO: This regexes should at least be compiled beforehand
    StripSpaces = re:replace(MetricName, "\s+", "_", [global, {return, binary}]),
    StripSlashes = re:replace(StripSpaces, "\/", "-", [global, {return, binary}]),
    re:replace(StripSlashes, "[^a-zA-Z\.\-_0-9]", "", [global, {return, binary}]).

%% Tests

-ifdef(EUNIT_TEST).

-include_lib("eunit/include/eunit.hrl").

sanitize_metric_name_test_() ->
    [?_assert(<<"foo">> =:= sanitize_metric_name(<<"fo/o">>)),
     ?_assert(<<"b_ar">> =:= sanitize_metric_name(<<"b ar">>)),
     ?_assert(<<"foobar">> =:= sanitize_metric_name(<<"foo+bar">>))].

-endif.
