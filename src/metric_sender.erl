-module(metric_sender).
-behaviour(gen_server).

-record(state, {graphite, socket}).

%% API
-export([start_link/1, start_link/2, send_metric/3, send_metric/2]).

%% gen_server callbacks
-export([init/1, handle_info/2, handle_cast/2, handle_call/3, terminate/2, code_change/3]).

%% API

start_link(GraphiteServer) ->
    start_link(GraphiteServer, 2003).

start_link(GraphiteServer, GraphitePort) ->
    gen_server:start_link(?MODULE, [{GraphiteServer, GraphitePort}], []).


send_metric(MetricName, Value) ->
    {MegaSeconds, Seconds, _} = os:timestamp(),
    Timestamp = MegaSeconds * 1000000 + Seconds,
    send_metric(MetricName, Value, Timestamp).

send_metric(MetricName, Value, Timestamp) ->
    [Pid] = gproc:lookup_pids({n, l, metric_sender}),
    gen_server:cast(Pid, {metric, MetricName, Value, Timestamp}).

%% gen_server callbacks

init([{GraphiteServer, GraphitePort}]) ->
    {ok, Socket} = gen_tcp:connect(GraphiteServer, GraphitePort, [binary]),
    gproc:reg({n, l, metric_sender}),
    {ok, #state{graphite={GraphiteServer, GraphitePort}, socket=Socket}}.

handle_cast({metric, MetricName, Value, Timestamp}, #state{socket=Socket}=State) ->
    ok = gen_tcp:send(Socket, io_lib:format("~s ~w ~w~n", [MetricName, Value, Timestamp])),
    {noreply, State}.

handle_info(_Msg, State) ->
    {noreply, State}.

handle_call(terminate, _From, State) ->
    {stop, normal, State}.

terminate(normal, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
