-module(select_sort).
-author("zyh").
%% @doc （选择排序类）
%% 每次都从剩余的列表中取出最大/小值
%% time: n^2        space: 1
%% 效率不合格
%% API
-export([select_sort/1]).
select_sort([]) -> [];
select_sort(List) ->
    do_select_sort([], List).

do_select_sort(List, []) -> List;
do_select_sort(FinishList, WaitList) ->
    Min = get_min([], WaitList),
    do_select_sort([Min | FinishList], lists:delete(Min, WaitList)).

get_min([], [A | WaitList]) ->
    get_min([A], WaitList);
get_min([Min], []) -> Min;
get_min([Min], [A | WaitList]) when Min < A ->
    get_min([Min], WaitList);
get_min([_Min], [A | WaitList]) ->
    get_min([A], WaitList).

