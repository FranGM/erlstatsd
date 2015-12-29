-module(erlstatsd_internal_stats).

-behaviour(gen_server).

%% TODO: Implement the metrics
-record(state, {
          metrics_received=0::non_neg_integer(),
          calculation_time=0::non_neg_integer(),
          processing_time=0::non_neg_integer(),
          last_exception=0::non_neg_integer(),
          last_flush=0::non_neg_integer(),
          flush_time=0::non_neg_integer(),
          flush_length=0::non_neg_integer()
         }).

%% API
-export([start_link/0,
         bad_line/0,
         metric_received/0,
         flush/0,
         last_flush/1]).

%% gen_server callbacks
-export([init/1, handle_info/2, handle_cast/2, handle_call/3, terminate/2, code_change/3]).

%% API

-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link(?MODULE, [], []).

-spec last_flush(Timestamp::non_neg_integer()) -> ok.
last_flush(Timestamp) ->
    gen_server:cast(erlstatsd_internal_stats, {last_flush, Timestamp}).

-spec metric_received() -> ok.
metric_received() ->
    erlstatsd_metric:counter("metrics_received", 1).

-spec bad_line() -> ok.
bad_line() ->
    erlstatsd_metric:counter("bad_lines_seen", 1).

-spec flush() -> ok.
flush() ->
    gen_server:cast(erlstatsd_internal_stats, flush).

%% gen_server callbacks

-spec init([]) -> {ok, #state{}}.
init([]) ->
    register(erlstatsd_internal_stats, self()),
    {ok, #state{}}.

-spec handle_info(_, #state{}) -> {noreply, #state{}}.
handle_info(_Msg, State) ->
    {noreply, State}.

-spec terminate(normal, #state{}) -> ok.
terminate(normal, #state{}) ->
    ok.

-spec handle_call(terminate, _, #state{}) -> {stop, normal, #state{}}.
handle_call(terminate, _From, State) ->
    {stop, normal, State};
handle_call({metric,  MetricName}, _From, #state{}=State) ->
    Pid = case gproc:where({n, l, {metric, MetricName}}) of
        undefined ->
            {ok, MetricPid} = supervisor:start_child(erlstatsd_metric_sup, [MetricName]),
            MetricPid;
        MetricPid -> MetricPid
          end,
    {reply, Pid, State}.

-spec handle_cast(flush, #state{}) -> {noreply, #state{}};
                 ({last_flush, Timestamp::non_neg_integer()}, #state{}) -> {noreply, #state{}}.
handle_cast(flush, #state{}=State) ->
    {noreply, State};
handle_cast({last_flush, Timestamp}, #state{}=State) ->
    {noreply, State#state{last_flush=Timestamp}}.

-spec code_change(_, #state{}, _) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal functions

