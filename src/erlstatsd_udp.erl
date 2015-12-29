-module(erlstatsd_udp).

-export([init/1]).

-spec socket_opts() -> [{raw, non_neg_integer(), non_neg_integer(), binary()}].
socket_opts() ->
    case os:type() of
        {unix, linux} -> [{raw, 1, 15, <<1:32/native>>}];
        {unix, darwin} -> [{raw, 16#ffff, 16#0200, <<1:32/native>>}];
        _ -> []
  end.

-spec init(Id::non_neg_integer()) -> {ok, pid()}.
init(Id) ->
    SocketIsActive = false,
    Pid = spawn_link(fun() ->
                             {ok, Socket} = gen_udp:open(8125, [
                                                                inet,
                                                                binary,
                                                                {active, SocketIsActive}] ++ socket_opts() ),
                             loop(Socket, Id, {active, SocketIsActive})
                     end),
    {ok, Pid}.


%% TODO: Should wait until rest of processes are ready before starting to accept traffic (gproc:await in init should do it)
-spec loop(Socket::gen_udp:socket(), Id::non_neg_integer(), {active, boolean()}) -> no_return().
loop(Socket, Id, {active, false}) ->
    {ok, {_From, _Port, Line}} = gen_udp:recv(Socket, 0),
    erlstatsd_lineparser:parse(Line),
    erlstatsd_metric:counter("packets_received", 1),
    loop(Socket, Id, {active, false});
loop(Socket, Id, {active, true}) ->
    receive
        {udp, _Socket, _From, _Port, Line} ->
            erlstatsd_lineparser:parse(Line),
            erlstatsd_metric:counter("packets_received", 1)
    end,
    loop(Socket, Id, {active, true}).
