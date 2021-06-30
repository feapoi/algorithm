-module(quick_sort).
-author("zyh").

%% @doc （交换排序类）
%% time: n log2 (n)     space: n log2 (n)
%% 效率合格
%% API

-export([start/0,
        quick_sort/1]).
start() ->
    SortList = get_rand_list(1, 100, 10),
    quick_sort(SortList).
quick_sort([]) ->
    [];
quick_sort([A | List]) ->
    quick_sort([Min || Min <- List, Min < A ]) ++ [A] ++ quick_sort([Max || Max <- List, Max > A ]).

get_rand_list(Min, Max, Num) ->
    get_rand_list(Min, Max, Num, []).
get_rand_list(_Min, _Max, 0, ResultList) ->
    ResultList;
get_rand_list(Min, Max, Num, ResultList) ->
    get_rand_list(Min, Max, Num - 1, [Min + rand:uniform(Max - Min + 1) - 1 | ResultList]).

