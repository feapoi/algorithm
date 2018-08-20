%%%-------------------------------------------------------------------
%%% @author Thoe
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. 八月 2018 10:49
%%%-------------------------------------------------------------------
-module(mytc).
-author("Thoe").

%% API
-export([start/0, test/0]).
tc(M, F, A, N) when N > 0 ->     %%M是模块名， F是函数名， A是参数， N是执行次数
    L = test_loop(M, F, A, N, []),
    LSorted = lists:sort(L),
    Min = lists:min(LSorted),
    Max = lists:max(LSorted),
    Avg = round(lists:foldl(fun(X, Sum) ->
        X + Sum end,
        0,
        LSorted)/N),
    io:format(
        "Range:~b - ~b mics~n"
        "Average:~b mics ~n",
        [Min, Max, Avg]).
test_loop(_M, _F, _A, 0, List) ->
    List;
test_loop(M, F, A, N, List) ->
    {T, _R} = timer:tc(M, F, A),
    test_loop(M, F, A, N-1, [T|List]).
start() ->
    tc(mytc, test, [], 10).
test() ->
    TestList = shuffle(lists:seq(1,10000,1)),
%%    quick_sort:quick_sort(TestList).
%%    insert_sort:insert_sort(TestList).
%%    heap_sort:heap_sort(TestList).
%%    bubble_sort:bubble_sort(TestList).
    select_sort:select_sort(TestList).
shuffle(List) ->
    [B || {_A, B}<- lists:keysort(1, [{rand:uniform(1000000), Id} || Id <- List])].