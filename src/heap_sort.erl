-module(heap_sort).
%% @doc (选择排序类)
%%
%% time: n log2 (n)     space: 1
%% 效率不达标

-export([heap_sort/1]).
%% 堆调整
heap_adjust(List, Start, End) when Start > End/2 -> List;
heap_adjust(List, Start, End) ->
    heap_adjust_helper(List, Start, End).

heap_adjust_helper(List, Start, End) ->
    Left = Start * 2,
    Right = Start * 2 + 1,
%% 找出节点Left, Max, Start中对应值为最小的节点
    Max = Start,
    MaxAfLeft = get_max_index(Left, Max, End, List),
    MaxAfRight = get_max_index(Right, MaxAfLeft, End, List),
    case MaxAfRight /= Max of
        true ->
            NewList = swap(List, Start, MaxAfRight),
            heap_adjust(NewList, MaxAfRight, End);
        false ->
            List
    end.

%% 获得最大值的节点
get_max_index(T1, T2, End, _List) when T1 > End -> T2;
get_max_index(T1, T2, _End, List) ->
    case lists:nth(T1, List) > lists:nth(T2, List) of
        true -> T1;
        false -> T2
    end.

%% 初始化堆
build_heap(List) ->
    Len = length(List),
    I = trunc(Len / 2),
    build_heap_helper(List, I, Len).

build_heap_helper(List, 0, _Len) -> List;
build_heap_helper(List, I, Len) ->
    NewList = heap_adjust(List, I, Len),
    build_heap_helper(NewList, I-1, Len).

%% 堆排
heap_sort(List) ->
    Len = length(List),
    NewList = build_heap(List),
    heap_sort_helper(NewList, Len).

heap_sort_helper(List, 0) -> List;
heap_sort_helper(List, Len) ->
% io:format("~n M:~p L:~p List:~p ~n", [?MODULE, ?LINE, List]),
    NewList1 = swap(List, 1, Len),
    NewList2 = heap_adjust(NewList1, 1, Len - 1),
    heap_sort_helper(NewList2, Len - 1).

%% 替换
swap(List, I, J) ->
    VI = lists:nth(I, List),
    VJ = lists:nth(J, List),
    Tuple = list_to_tuple(List),
    NewTuple1 = setelement(I, Tuple, VJ),
    NewTuple2 = setelement(J, NewTuple1, VI),
    NewList = tuple_to_list(NewTuple2),
    NewList.

%% 测试代码
test() ->
    List = random_number(20, 1000, 10, []),
    heap_sort(List).

random_number( 0, _, _, L) -> L;
random_number(Size, Max, Min, L) ->
    Num = rand:uniform(Max-Min) + Min,
    random_number(Size-1, Max, Min, [Num|L]).
