-module(metric_sender).
-behaviour(gen_server).

-record(state, {graphite, socket}).

%% API
-export([start_link/1, start_link/2, send_metric/3, send_metric/2]).

%% gen_server callbacks
-export([init/1, handle_info/2, handle_cast/2, handle_call/3, terminate/2, code_change/3]).

%% Types
-type host() :: atom() | string() | {byte(),byte(),byte(),byte()} | {char(),char(),char(),char(),char(),char(),char(),char()}.

%% API
-spec start_link(host()) -> {ok, pid()}.
start_link(GraphiteServer) ->
    start_link(GraphiteServer, 2003).

-spec start_link(GraphiteServer::host(), GraphitePort::non_neg_integer()) -> {ok, pid()}.
start_link(GraphiteServer, GraphitePort) ->
    gen_server:start_link(?MODULE, [{GraphiteServer, GraphitePort}], []).

-spec send_metric(MetricName::string(), Value::number()) -> ok.
send_metric(MetricName, Value) ->
    {MegaSeconds, Seconds, _} = os:timestamp(),
    Timestamp = MegaSeconds * 1000000 + Seconds,
    send_metric(MetricName, Value, Timestamp).

-spec send_metric(MetricName::string(), Value::number(), Timestamp::number()) -> ok.
send_metric(MetricName, Value, Timestamp) ->
    [Pid] = gproc:lookup_pids({n, l, metric_sender}),
    gen_server:cast(Pid, {metric, MetricName, Value, Timestamp}).

%% gen_server callbacks

-spec connect_to_graphite({GraphiteServer::host(), GraphitePort::non_neg_integer()}) ->
    {ok, port()}.
connect_to_graphite({GraphiteServer, GraphitePort}) ->
    connect_to_graphite({GraphiteServer, GraphitePort}, 0).

-spec connect_to_graphite({GraphiteServer::host(), GraphitePort::non_neg_integer()}, Backoff::non_neg_integer()) ->
    {ok, port()}.
connect_to_graphite({GraphiteServer, GraphitePort}, Backoff) ->
    receive
    after Backoff -> ok
    end,
    case gen_tcp:connect(GraphiteServer, GraphitePort, [binary]) of
        {ok, Socket} -> {ok, Socket};
        {error, Why} ->
            io:format("Connection to graphite backend failed: ~p~n", [Why]),
            connect_to_graphite({GraphiteServer, GraphitePort}, Backoff + 5000)
    end.

-spec init([{GraphiteServer::host(), GraphitePort::non_neg_integer()}]) -> {ok, #state{}}.
init([{GraphiteServer, GraphitePort}]) ->
    {ok, Socket} = connect_to_graphite({GraphiteServer, GraphitePort}),
    gproc:reg({n, l, metric_sender}),
    {ok, #state{graphite={GraphiteServer, GraphitePort}, socket=Socket}}.

-spec handle_cast({metric, MetricName::binary(), Value::number(), Timestamp::number()}, #state{}) ->
    {noreply, #state{}}.
handle_cast({metric, MetricName, Value, Timestamp}, #state{}=State) ->
    {ok, NewState} = send_line(io_lib:format("~s ~w ~w~n", [MetricName, Value, Timestamp]), State),
    {noreply, NewState}.

-spec handle_info(_, #state{}) -> {noreply, #state{}}.
handle_info(_Msg, State) ->
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

-spec send_line(Line::string(), #state{}) ->
    {ok, #state{}}.
send_line(Line, #state{socket=Socket}=State) ->
    case gen_tcp:send(Socket, Line) of
        ok -> {ok, State};
        {error, Reason} ->
            io:format("Got an error sending line (~p). Will reconnect...~n", [Reason]),
            {ok, NewSocket} = connect_to_graphite(State#state.graphite),
            send_line(noretry, Line, State#state{socket=NewSocket})
    end.

-spec send_line(noretry, Line::string(), #state{}) ->
    {ok, #state{}}.
send_line(noretry, Line, #state{socket=Socket}=State) ->
    ok = gen_tcp:send(Socket, Line),
    {ok, State}.
