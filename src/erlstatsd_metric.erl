-module(erlstatsd_metric).
-behaviour(gen_server).

-ifdef(EUNIT_TEST).
-compile(export_all).
-endif.

-include("erlstatsd_timervalues.hrl").

-type metric_type() :: counter | timer | gauge | set.

%% FIXME: These should not be defines, but config options
-define(DELETE_COUNTERS, false).
-define(DELETE_TIMERS, true).
-define(DELETE_GAUGES, false).
-define(DELETE_SETS, true).

%% TODO: Allow for global prefixes
-record(state, {metricName::string(),
                flushInterval=10000::non_neg_integer(),
                percent=[0.9, 0.95]::[number()],
                counter=0::non_neg_integer(),
                gauge=0::number(),
                sets=sets:new()::sets:set(),
                timers=[]::[number()],
                last_received_data=maps:new()::map(),
                last_flushed=0::non_neg_integer(),
                delete_metrics::map()
               }).

%% API
-export([start_link/2, gauge/2, flush/1, set/2, counter/2, timer/2]).

%% gen_server callbacks
-export([init/1, handle_info/2, handle_cast/2, handle_call/3, terminate/2, code_change/3]).

%% API

-spec start_link(MetricName::string(), FlushInterval::non_neg_integer()) -> {ok, pid()}.
start_link(MetricName, FlushInterval) ->
    gen_server:start_link(?MODULE, {{metric, MetricName}, FlushInterval}, []).

-spec gauge(Pid::pid(), {delta, Value::number()}) -> ok;
           (Pid::pid(), Value::number()) -> ok.
gauge(Pid, {delta, Value}) ->
    gen_server:cast(Pid, {metric, g, delta, Value});
gauge(Pid, Value) ->
    gen_server:cast(Pid, {metric, g, Value}).

-spec set(Pid::pid(), Value::number()) -> ok.
set(Pid, Value) ->
    gen_server:cast(Pid, {metric, s, Value}).

-spec counter(Pid::pid(), Value::number()) -> ok.
counter(Pid, Value) ->
    gen_server:cast(Pid, {metric, c, Value}).

-spec timer(Pid::pid(), Value::number()) -> ok.
timer(Pid, Value) ->
    gen_server:cast(Pid, {metric, ms, Value}).

-spec flush(Pid::pid()) ->ok.
flush(Pid) ->
    gen_server:cast(Pid, {flush}).

%% gen_server callbacks

-spec init({{metric, MetricName::string()}, FlushInterval::non_neg_integer()}) -> {ok, #state{}}.
init({{metric, MetricName}, FlushInterval}) ->
    gproc:reg({n, l, MetricName}, self()),
    gproc:reg({p, l, metric}, self()),
    ConfigDelete = #{counter => ?DELETE_COUNTERS,
                     timer => ?DELETE_TIMERS,
                     gauge => ?DELETE_GAUGES,
                     set => ?DELETE_SETS},
    {ok, #state{metricName=MetricName, flushInterval=FlushInterval, delete_metrics=ConfigDelete}}.

-spec handle_cast({metric, c, Value::number()}, #state{}) -> {noreply, #state{}};
                 ({metric, ms, Value::number()}, #state{}) -> {noreply, #state{}};
                 ({metric, s, Value::number()}, #state{}) -> {noreply, #state{}};
                 ({metric, g, Value::number()}, #state{}) -> {noreply, #state{}};
                 ({metric, g, delta, Value::number()}, #state{}) -> {noreply, #state{}};
                 ({flush}, #state{}) -> {noreply, #state{}}.
handle_cast({metric, c, Value}, #state{counter=Counter, last_received_data=Last_updated}=State) ->
    %% Counters
    New_Last_Updated = Last_updated#{counter => now_timestamp()},
    {noreply, State#state{counter=Counter + Value, last_received_data=New_Last_Updated}};
handle_cast({metric, ms, Value}, #state{timers=Timers, last_received_data=Last_updated}=State) ->
    %% Timing
    New_Last_Updated = Last_updated#{timer => now_timestamp()},
    {noreply, State#state{timers=[Value] ++ Timers, last_received_data=New_Last_Updated}};
handle_cast({metric, s, Value}, #state{sets=Sets, last_received_data=Last_updated}=State) ->
    %% Sets
    New_Last_Updated = Last_updated#{set => now_timestamp()},
    {noreply, State#state{sets=sets:add_element(Value,Sets), last_received_data=New_Last_Updated}};
handle_cast({metric, g, Value}, #state{last_received_data=Last_updated}=State) ->
    %% Gauges
    New_Last_Updated = Last_updated#{gauge => now_timestamp()},
    {noreply, State#state{gauge=Value, last_received_data=New_Last_Updated}};
handle_cast({metric, g, delta, Value}, #state{gauge=Gauge, last_received_data=Last_updated}=State) ->
    %% Gauges (With delta)
    New_Last_Updated = Last_updated#{gauge => now_timestamp()},
    {noreply, State#state{gauge=Gauge+Value, last_received_data=New_Last_Updated}};
handle_cast({flush}, State) ->
    case should_send_something(State) of
        true ->
            {ok, NewState} = flush_metrics(State),
            {noreply, NewState};
        false -> {stop, normal, State}
    end.

-spec handle_info(_, #state{}) -> {noreply, #state{}}.
handle_info(Msg, State) ->
    io:format("---- ~p~n", [Msg]),
    {noreply, State}.

-spec handle_call(terminate, _, #state{}) -> {stop, normal, #state{}}.
handle_call(terminate, _From, State) ->
    lager:error("Terminating worker for metric ~w", [State#state.metricName]),
    {stop, normal, State}.

-spec terminate(normal, #state{}) -> ok.
terminate(normal=Reason, #state{metricName=Metric}) ->
    lager:debug("Terminating process for metric ~w with reason ~w", [Metric, Reason]),
    ok.

-spec code_change(_, #state{}, _) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Private functions

-spec calculate_percentile(L::[number()], Pct::number()) -> [number()].
calculate_percentile(L, Pct) ->
    {PctList, _} = lists:split(round(length(L) * Pct), lists:sort(L)),
    PctList.

-spec percentileStats(L::[number(),...], Pct::number()) -> #timerValues{}.
percentileStats(L, Pct) ->
    PctList = calculate_percentile(L, Pct),
    calculate_timer_stats(PctList).

-spec clear_state(#state{}) -> {ok, #state{}}.
clear_state(State) ->
    {ok, State#state{counter=0,
                     timers=[],
                     sets=sets:new(),
                     last_flushed=now_timestamp()}}.

-spec output_metric(metric_type(), #state{}) -> ok.
output_metric(set, #state{}=State) ->
    metric_sender:send_metric(State#state.metricName, sets:size(State#state.sets));
output_metric(counter, State) ->
    metric_sender:send_metric("stats_counts."++State#state.metricName, State#state.counter),
    metric_sender:send_metric("stats."++State#state.metricName, State#state.counter / (State#state.flushInterval / 1000));
output_metric(gauge, #state{gauge=Gauge}=State) ->
    metric_sender:send_metric("stats.gauges." ++ State#state.metricName, Gauge);
output_metric(timer, #state{timers=[]}) ->
    ok;
output_metric(timer, State) ->
    TimerVals = calculate_timer_stats(State#state.timers),
    PctTimerVals = calculate_timer_pct_stats(State#state.timers, State#state.percent),
    lists:foreach(fun({pct, Pct, TV}) ->
                          PctRepr = round(Pct*100),
                          metric_sender:send_metric(io_lib:format("stats.timers.~s.upper_~w", [State#state.metricName, PctRepr]), TV#timerValues.upper),
                          metric_sender:send_metric(io_lib:format("stats.timers.~s.sum_~w", [State#state.metricName, PctRepr]), TV#timerValues.sum),
                          metric_sender:send_metric(io_lib:format("stats.timers.~s.mean_~w", [State#state.metricName, PctRepr]), TV#timerValues.mean)
                  end, PctTimerVals),
    metric_sender:send_metric(io_lib:format("stats.timers.~s.lower", [State#state.metricName]), TimerVals#timerValues.lower),
    metric_sender:send_metric(io_lib:format("stats.timers.~s.upper", [State#state.metricName]), TimerVals#timerValues.upper),
    metric_sender:send_metric(io_lib:format("stats.timers.~s.sum", [State#state.metricName]), TimerVals#timerValues.sum),
    metric_sender:send_metric(io_lib:format("stats.timers.~s.count", [State#state.metricName]), TimerVals#timerValues.count),
    metric_sender:send_metric(io_lib:format("stats.timers.~s.mean", [State#state.metricName]), TimerVals#timerValues.mean).

-spec calculate_timer_pct_stats(Timers::[number(),...], PctList::[number(),...]) -> [{pct, number(), #timerValues{}},...].
calculate_timer_pct_stats(Timers, PctList) ->
    [{pct, Pct, percentileStats(Timers, Pct)} || Pct <- PctList ].

-spec calculate_timer_stats(Timers::[number()]) -> #timerValues{}.
%% TODO: Maybe an empty list should just ben an error?
calculate_timer_stats([]) ->
    #timerValues{};
calculate_timer_stats(Timers) ->
    Count = length(Timers),
    SortedList = lists:sort(Timers),
    Min = hd(SortedList),
    Max = lists:last(SortedList),
    Sum = lists:sum(SortedList),
    Mean = Sum / Count,
    #timerValues{lower=Min,
                 upper=Max,
                 sum=Sum,
                 count=Count,
                 mean=Mean}.

-spec flush_metrics(#state{}) -> {ok, #state{}}.
flush_metrics(State) ->
    MetricTypes = [counter, set, timer, gauge],
    MetricsToSend = lists:filtermap(fun (Type) -> should_send_metric(Type, State) end, MetricTypes),
    lists:map(fun (Type) -> output_metric(Type, State) end, MetricsToSend),
    clear_state(State).

-spec now_timestamp() -> non_neg_integer().
now_timestamp() ->
    timestamp_to_seconds(os:timestamp()).

-spec timestamp_to_seconds({MegaSeconds::non_neg_integer(), Seconds::non_neg_integer(), any()}) -> non_neg_integer().
timestamp_to_seconds({MegaSeconds, Seconds, _}) ->
    MegaSeconds * 1000000 + Seconds.

-spec updated_since_last_flush(Type::metric_type(), #state{}) -> true | false.
updated_since_last_flush(Type, #state{last_received_data=Last_updated,
                                      last_flushed=Last_flushed}) ->
    case maps:find(Type, Last_updated) of
        {ok, _} -> maps:get(Type, Last_updated) > Last_flushed;
        error -> false
    end.

-spec updated_at_least_once(Type::metric_type(), #state{}) -> boolean().
updated_at_least_once(Type, #state{last_received_data=Last_updated}) ->
    case maps:find(Type, Last_updated) of
        {ok, _} -> true;
        error -> false
    end.

-spec should_send_metric(Type::metric_type(), #state{}) -> boolean().
should_send_metric(Type, #state{delete_metrics=DeleteMetrics}=State) ->
    updated_at_least_once(Type, State) andalso (updated_since_last_flush(Type, State) orelse not maps:get(Type, DeleteMetrics)).

-spec should_send_something(#state{}) -> boolean().
should_send_something(#state{}=State) ->
    lists:any(fun (Type) -> should_send_metric(Type, State) end, [set, timer, gauge, counter]).
