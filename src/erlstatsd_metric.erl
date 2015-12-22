-module(erlstatsd_metric).
-behaviour(gen_server).

-record(timerValues, {count,
                      lower,
                      upper,
                      sum,
                      mean
                     }).

%% TODO: Allow for global prefixes
-record(state, {metricName,
                flushInterval=30000,
                percent=[0.9, 0.95],
                counter=0,
                gauge=0,
                sets=sets:new(),
                timers=[]}).

%% API
-export([start_link/1, gauge/2, flush/1, set/2, counter/2, timer/2]).

%% gen_server callbacks
-export([init/1, handle_info/2, handle_cast/2, handle_call/3, terminate/2, code_change/3]).

%% API

start_link(MetricName) ->
    gen_server:start_link(?MODULE, [{metric, MetricName}], []).

gauge(Pid, {delta, Value}) ->
    gen_server:cast(Pid, {metric, g, delta, Value});
gauge(Pid, Value) ->
    gen_server:cast(Pid, {metric, g, Value}).

set(Pid, Value) ->
    gen_server:cast(Pid, {metric, s, Value}).

counter(Pid, Value) ->
    gen_server:cast(Pid, {metric, c, Value}).

timer(Pid, Value) ->
    gen_server:cast(Pid, {metric, ms, Value}).

flush(Pid) ->
    gen_server:cast(Pid, {flush}).

%% gen_server callbacks

init([{metric, MetricName}]) ->
    gproc:reg({n, l, MetricName}, self()),
    gproc:reg({p, l, metric}, self()),
    {ok, #state{metricName=MetricName}}.

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

handle_info(Msg, State) ->
    io:format("---- ~p~n", [Msg]),
    {noreply, State}.

handle_call(terminate, _From, State) ->
    {stop, normal, State}.

terminate(normal, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Private functions

percentileStats(L, Pct) ->
    {PctList, _} = lists:split(round(length(L) * Pct), lists:sort(L)),
    calculate_timer_stats(PctList).

clear_state(State) ->
    {ok, #state{gauge=State#state.gauge, metricName=State#state.metricName}}.

output_sets(State) ->
    metric_sender:send_metric(State#state.metricName, sets:size(State#state.sets)).

%% TODO: Allow this not to be sent/shown
output_counters(State) ->
    metric_sender:send_metric("stats_counts."++State#state.metricName, State#state.counter),
    metric_sender:send_metric("stats."++State#state.metricName, State#state.counter / (State#state.flushInterval / 1000)).

%% TODO: Allow this not to be sent/shown
output_gauges(#state{gauge=Gauge}=State) ->
    metric_sender:send_metric("stats.gauges." ++ State#state.metricName, Gauge).

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

calculate_timer_pct_stats(Timers, PctList) ->
    [{pct, Pct, percentileStats(Timers, Pct)} || Pct <- PctList ].

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

flush_metrics(State) ->
    output_sets(State),
    output_counters(State),
    output_timers(State),
    output_gauges(State),
    clear_state(State).
