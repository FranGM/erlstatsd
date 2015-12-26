-module(erlstatsd_metric).
-behaviour(gen_server).

-ifdef(EUNIT_TEST).
-compile(export_all).
-endif.

-include("erlstatsd_timervalues.hrl").

%% TODO: Allow for global prefixes
-record(state, {metricName::string(),
                flushInterval=30000::non_neg_integer(),
                percent=[0.9, 0.95]::[number()],
                counter=0::non_neg_integer(),
                gauge=0::number(),
                sets=sets:new()::sets:set(),
                timers=[]::[number()]}).

%% API
-export([start_link/1, gauge/2, flush/1, set/2, counter/2, timer/2]).

%% gen_server callbacks
-export([init/1, handle_info/2, handle_cast/2, handle_call/3, terminate/2, code_change/3]).

%% API

-spec start_link(MetricName::string()) -> {ok, pid()}.
start_link(MetricName) ->
    gen_server:start_link(?MODULE, [{metric, MetricName}], []).

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

-spec init([{metric, MetricName::string()}]) -> {ok, #state{}}.
init([{metric, MetricName}]) ->
    gproc:reg({n, l, MetricName}, self()),
    gproc:reg({p, l, metric}, self()),
    {ok, #state{metricName=MetricName}}.

-spec handle_cast({metric, c, Value::number()}, #state{}) -> {noreply, #state{}};
                 ({metric, ms, Value::number()}, #state{}) -> {noreply, #state{}};
                 ({metric, s, Value::number()}, #state{}) -> {noreply, #state{}};
                 ({metric, g, Value::number()}, #state{}) -> {noreply, #state{}};
                 ({metric, g, delta, Value::number()}, #state{}) -> {noreply, #state{}};
                 ({flush}, #state{}) -> {noreply, #state{}}.
handle_cast({metric, c, Value}, #state{counter=Counter}=State) ->
    %% Counters
    {noreply, State#state{counter=Counter + Value}};
handle_cast({metric, ms, Value}, #state{timers=Timers}=State) ->
    %% Timing
    {noreply, State#state{timers=[Value] ++ Timers}};
handle_cast({metric, s, Value}, #state{sets=Sets}=State) ->
    %% Sets
    {noreply, State#state{sets=sets:add_element(Value,Sets)}};
handle_cast({metric, g, Value}, State) ->
    %% Gauges
    {noreply, State#state{gauge=Value}};
handle_cast({metric, g, delta, Value}, #state{gauge=Gauge}=State) ->
    %% Gauges (With delta)
    {noreply, State#state{gauge=Gauge+Value}};
handle_cast({flush}, State) ->
    {ok, NewState} = flush_metrics(State),
    {noreply, NewState}.

-spec handle_info(_, #state{}) -> {noreply, #state{}}.
handle_info(Msg, State) ->
    io:format("---- ~p~n", [Msg]),
    {noreply, State}.

-spec handle_call(terminate, _, #state{}) -> {stop, normal, #state{}}.
handle_call(terminate, _From, State) ->
    {stop, normal, State}.

-spec terminate(normal, #state{}) -> ok.
terminate(normal, _State) ->
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
    {ok, #state{gauge=State#state.gauge, metricName=State#state.metricName}}.

-spec output_sets(#state{}) -> ok.
output_sets(State) ->
    metric_sender:send_metric(State#state.metricName, sets:size(State#state.sets)).

%% TODO: Allow this not to be sent/shown if there were no changes
-spec output_counters(#state{}) -> ok.
output_counters(State) ->
    metric_sender:send_metric("stats_counts."++State#state.metricName, State#state.counter),
    metric_sender:send_metric("stats."++State#state.metricName, State#state.counter / (State#state.flushInterval / 1000)).

%% TODO: Allow this not to be sent/shown if there were no changes
-spec output_gauges(#state{}) -> ok.
output_gauges(#state{gauge=Gauge}=State) ->
    metric_sender:send_metric("stats.gauges." ++ State#state.metricName, Gauge).

-spec output_timers(#state{}) -> ok.
output_timers(#state{timers=[]}) ->
    ok;
output_timers(State) ->
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
    %% TODO: Do this better, have a function that's output(type, State) and iterate over the known atoms
    output_sets(State),
    output_counters(State),
    output_timers(State),
    output_gauges(State),
    clear_state(State).
