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

connect_to_graphite({GraphiteServer, GraphitePort}) ->
    connect_to_graphite({GraphiteServer, GraphitePort}, 0).

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

init([{GraphiteServer, GraphitePort}]) ->
    {ok, Socket} = connect_to_graphite({GraphiteServer, GraphitePort}),
    gproc:reg({n, l, metric_sender}),
    {ok, #state{graphite={GraphiteServer, GraphitePort}, socket=Socket}}.

handle_cast({metric, MetricName, Value, Timestamp}, #state{}=State) ->
    {ok, NewState} = send_line(io_lib:format("~s ~w ~w~n", [MetricName, Value, Timestamp]), State),
    {noreply, NewState}.

handle_info(_Msg, State) ->
    {noreply, State}.

handle_call(terminate, _From, State) ->
    {stop, normal, State}.

terminate(normal, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Private functions

send_line(Line, #state{socket=Socket}=State) ->
    case gen_tcp:send(Socket, Line) of
        ok -> {ok, State};
        {error, Reason} ->
            io:format("Got an error sending line (~p). Will reconnect...~n", [Reason]),
            {ok, NewSocket} = connect_to_graphite(State#state.graphite),
            send_line(noretry, Line, State#state{socket=NewSocket})
    end.

send_line(noretry, Line, #state{socket=Socket}=State) ->
    ok = gen_tcp:send(Socket, Line),
    {ok, State}.
