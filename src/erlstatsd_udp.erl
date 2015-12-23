-module(erlstatsd_udp).

-export([init/1]).

socket_opts() ->
    case os:type() of
        {unix, linux} -> [{raw, 1, 15, <<1:32/native>>}];
        {unix, darwin} -> [{raw, 16#ffff, 16#0200, <<1:32/native>>}];
        _ -> []
  end.

init(Id) ->
    Pid = spawn_link(fun() ->
                             {ok, Socket} = gen_udp:open(8125, [{reuseaddr, true} ,inet,  binary, {active, false}] ++ socket_opts() ),
                             loop(Socket, Id)
                     end),
    {ok, Pid}.


loop(Socket, Id) ->
    {ok, {_From, _Port, Line}} = gen_udp:recv(Socket, 0),
    erlstatsd_lineparser:parse(Line),
    loop(Socket, Id).
