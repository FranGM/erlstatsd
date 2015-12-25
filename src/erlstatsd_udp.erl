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
    Pid = spawn_link(fun() ->
                             {ok, Socket} = gen_udp:open(8125, [{reuseaddr, true} ,inet,  binary, {active, false}] ++ socket_opts() ),
                             loop(Socket, Id)
                     end),
    {ok, Pid}.


-spec loop(Socket::port(), Id::non_neg_integer()) -> no_return().
loop(Socket, Id) ->
    {ok, {_From, _Port, Line}} = gen_udp:recv(Socket, 0),
    erlstatsd_lineparser:parse(Line),
    loop(Socket, Id).
