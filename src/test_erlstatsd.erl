-module(test_erlstatsd).
-ifdef(EUNIT_TEST).

-include_lib("eunit/include/eunit.hrl").

-include("erlstatsd_timervalues.hrl").

-spec timer_stats_test_() -> [term()].
timer_stats_test_() ->
    [?_assert(#timerValues{lower=1, upper=10, sum=55, count=10, mean=5.5} =:= erlstatsd_metric:calculate_timer_stats([10,2,3,4,5,6,7,8,9,1])),
    ?_assert(#timerValues{} =:= erlstatsd_metric:calculate_timer_stats([]))].

-spec percentile_test_() -> [term()].
percentile_test_() ->
    [?_assert([1, 2, 3, 4, 5] =:= erlstatsd_metric:calculate_percentile([1, 2, 3, 4, 5], 1)),
    ?_assert([] =:= erlstatsd_metric:calculate_percentile([1, 2, 3, 4, 5], 0)),
    ?_assert([] =:= erlstatsd_metric:calculate_percentile([], 0.90)),
    ?_assert([43,54,56,61,62,66,68,69,69,70,71,72,77,78,79,85,87,88,89,93,95,96,98] =:= erlstatsd_metric:calculate_percentile([70,54,56,61,62,66,93,77,69,43,71,72,69,78,79,85,87,88,89,68,95,96,98,99,99], 0.90)),
    ?_assert([43,54,56,61,62,66,68,69,69,70,71,72,77] =:= erlstatsd_metric:calculate_percentile([70,54,56,61,62,66,93,77,69,43,71,72,69,78,79,85,87,88,89,68,95,96,98,99,99], 0.50))].

-endif.
