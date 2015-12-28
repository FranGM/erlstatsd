-module(erlstatsd_config).

-behaviour(gen_server).

-record(state, {}).

-define(CONFIG_TABLE, ?MODULE).

%% API

-export([start_link/1,
         get_flush_interval/0,
         get_delete_config/0,
         get_backend_address/0,
         get_percentile_config/0,
         get_histogram_bins/1
        ]).

%% gen_server callbacks

-export([init/1, handle_info/2, handle_cast/2, handle_call/3, terminate/2, code_change/3]).

%% API

-spec start_link(Config::map()) -> {ok, pid()}.
start_link(Config) when is_map(Config) ->
    gen_server:start_link(?MODULE, [Config], []).

-spec get_backend_address() -> {inet:hostname() | inet:ip_address(), inet:port_number()}.
get_backend_address() ->
    Host = config_get(graphitehost),
    Port = config_get(graphiteport),
    {Host, Port}.

-spec get_flush_interval() -> non_neg_integer().
get_flush_interval() ->
    config_get(flushinterval).

-spec get_delete_config() -> map().
get_delete_config() ->
    config_get(delete_config).

-spec get_percentile_config() -> [number()].
get_percentile_config() ->
    config_get(percentiles).

%% TODO: Allow this to also work with a regex or a metric hierarchy (defining buckets for "foo" should also affect foo.bar, foo.lol, etc)
-spec get_histogram_bins(MetricName::string()) -> [number()].
get_histogram_bins(MetricName) ->
    Bins = config_get(histogram_bins),
    Metric = case is_binary(MetricName) of
        false -> MetricName;
        true -> binary_to_list(MetricName)
    end,
    case maps:find(Metric, Bins) of
        error -> [];
        {ok, Value} -> Value
    end.

%% gen_server callbacks

-spec init([Config::map()]) -> {ok, #state{}}.
init([Config]) when is_map(Config)->
    ets:new(?CONFIG_TABLE, [set, named_table]),
    FullConfig = maps:merge(default_config(), Config),
    lists:map(fun (X) ->
                      ets:insert(?CONFIG_TABLE, {X, maps:get(X, FullConfig)})
              end, maps:keys(FullConfig)),
    register(erlstatsd_config, self()),
    {ok, #state{}}.

-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
handle_info(_Msg, State) ->
    {noreply, State}.

-spec handle_call(terminate, _, #state{}) -> {stop, normal, #state{}}.
handle_call(terminate, _From, State) ->
    {stop, normal, State}.

-spec code_change(_, #state{}, _) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

-spec handle_cast({write_config, Key::atom(), Value::term()}, #state{}) -> {noreply, #state{}}.
handle_cast({write_config, Key, Value}, State) ->
    ets:insert(?CONFIG_TABLE, {Key, Value}),
    {noreply, State}.

-spec terminate(normal, #state{}) -> ok.
terminate(normal, #state{}) ->
    ok.

%% Private functions

%% TODO: Let this crash or return a not_found atom?
-spec config_get(Key::atom()) -> term().
config_get(Key) when is_atom(Key) ->
    [{Key, Val}] = ets:lookup(?CONFIG_TABLE, Key),
    Val.

-spec default_config() -> map().
default_config() ->
    #{graphitehost => "localhost",
      graphiteport => 2003,
      flushinterval => 10000,
      percentiles   => [0.90],
      histogram_bins => #{"foo.bar" => [50, 100, infinity]},
      delete_config => #{gauge => false,
                         counter => false,
                         timer => false,
                         set => false}}.
