-module(erlstatsd_metric_sender).
-behaviour(gen_server).

-record(state, {id::non_neg_integer(),
                graphite::{inet:hostname() | inet:ip_address(), inet:port_number()},
                prefix=""::string(),
                socket::port(),
                lines_sent = 0 :: non_neg_integer(),
                bytes_sent = 0 :: non_neg_integer()
               }).

%% Set a cap in the amount of time we're willing to backoff to reconnect to graphite.
-define(BACKOFF_LIMIT, 120000).

%% Initially wait 500ms for our backend to come back if we can't connect.
-define(INITIAL_BACKOFF, 500).

%% API
-export([start_link/1, send_metric/3, send_metric/2]).

%% gen_server callbacks
-export([init/1, handle_info/2, handle_cast/2, handle_call/3, terminate/2, code_change/3]).

%% API
-spec start_link({id, non_neg_integer()}) -> {ok, pid()}.
start_link({id, Id}) ->
    gen_server:start_link(?MODULE, {id, Id}, []).

-spec send_metric(MetricName::string(), Value::number()) -> ok.
send_metric(MetricName, Value) ->
    {MegaSeconds, Seconds, _} = os:timestamp(),
    Timestamp = MegaSeconds * 1000000 + Seconds,
    send_metric(MetricName, Value, Timestamp).

-spec send_metric(MetricName::string(), Value::number(), Timestamp::number()) -> ok.
send_metric(MetricName, Value, Timestamp) ->
    %% TODO: Detect when the list is empty and either wait for new processes to come up or just crash with a better error.
    Pids = gproc:lookup_pids({p, l, erlstatsd_metric_sender}),
    SenderPid = lists:nth(random:uniform(length(Pids)), Pids),
    gen_server:cast(SenderPid, {metric, MetricName, Value, Timestamp}).

%% gen_server callbacks

-spec connect_to_graphite({GraphiteServer::inet:hostname() | inet:ip_address(), GraphitePort::inet:port_number()}) ->
    {ok, port()}.
connect_to_graphite({GraphiteServer, GraphitePort}) ->
    connect_to_graphite({GraphiteServer, GraphitePort}, 0).

-spec graphite_backoff(Backoff::non_neg_integer()) -> ok.
graphite_backoff(Backoff) ->
    receive
    after Backoff -> ok
    end.

%% Increase our exponential backoff.
-spec increase_backoff(Backoff::non_neg_integer()) -> non_neg_integer().
increase_backoff(0) -> ?INITIAL_BACKOFF;
increase_backoff(Backoff) when Backoff*2 > ?BACKOFF_LIMIT -> ?BACKOFF_LIMIT;
increase_backoff(Backoff) -> Backoff*2.

-spec connect_to_graphite({GraphiteServer::inet:hostname() | inet:ip_address(), GraphitePort::inet:port_number()}, Backoff::non_neg_integer()) ->
    {ok, port()}.
connect_to_graphite({GraphiteServer, GraphitePort}, Backoff) ->
    graphite_backoff(Backoff),
    case gen_tcp:connect(GraphiteServer, GraphitePort, [binary]) of
        {ok, Socket} -> {ok, Socket};
        {error, Why} ->
            NewBackoff = increase_backoff(Backoff),
            lager:error("Connection to graphite backend failed: ~p. Will wait for ~w ms.", [Why, NewBackoff]),
            connect_to_graphite({GraphiteServer, GraphitePort}, NewBackoff)
    end.

-spec init({id, Id::non_neg_integer()}) ->
    {ok, #state{}}.
init({id, Id}) ->
    {GraphiteServer, GraphitePort} = erlstatsd_config:get_backend_address(),
    MetricPrefix = erlstatsd_config:get_prefix(),
    {ok, Socket} = connect_to_graphite({GraphiteServer, GraphitePort}),
    gproc:reg({p, l, erlstatsd_metric_sender}),
    {ok, #state{id=Id,
                graphite={GraphiteServer, GraphitePort},
                prefix=MetricPrefix,
                socket=Socket}
    }.


-spec handle_cast({metric, MetricName::binary(), Value::number(), Timestamp::number()}, #state{}) ->
    {noreply, #state{}}.
handle_cast({metric, MetricName, Value, Timestamp},
            #state{prefix=Prefix}=State) ->
    {ok, NewState} = send_line(format_line(MetricName, Value, Timestamp, Prefix), State), 
    lager:debug("Worker ~w just sent: ~p ~w ~w", [State#state.id, MetricName, Value, Timestamp]),
    lager:debug("Worker ~w has sent ~w lines with a total of ~w bytes.~n", [NewState#state.id, NewState#state.lines_sent, NewState#state.bytes_sent]),
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
send_line(Line, #state{socket=Socket,
                       lines_sent=LinesSent,
                       bytes_sent=BytesSent
                      }=State) ->
    case gen_tcp:send(Socket, Line) of
        ok -> {ok, State#state{lines_sent = LinesSent + 1,
                               bytes_sent = BytesSent + length(Line)}};
        %% TODO: Actually filter on the error we're getting to figure out if we want to try to resend or not
        {error, Reason} ->
            lager:error("Got an error sending line (~p). Will reconnect...", [Reason]),
            {ok, NewSocket} = connect_to_graphite(State#state.graphite),
            %% TODO: Do we really want to not retry after the first failure?
            send_line(noretry, Line, State#state{socket=NewSocket})
    end.

-spec send_line(noretry, Line::string(), #state{}) ->
    {ok, #state{}}.
send_line(noretry, Line, #state{socket=Socket}=State) ->
    case gen_tcp:send(Socket, Line) of
        {error, Reason} ->
            lager:error("Got an error sending line (~p). Not retrying...", [Reason]),
            error;
        ok -> {ok, State}
    end.

-spec format_line(MetricName::string(),
                  Value::number(),
                  Timestamp::non_neg_integer(),
                  string()
                 ) -> string().
format_line(MetricName, Value, Timestamp, <<"">>) ->
    io_lib:format("~s ~w ~w ~n", [MetricName, Value, Timestamp]);
format_line(MetricName, Value, Timestamp, Prefix) ->
    io_lib:format("~s.~s ~w ~w ~n", [Prefix, MetricName, Value, Timestamp]).
