-module(bubble_sort).
-author("zyh").

%% @doc （交换排序类）
%% 连续交换相邻两个元素,交换n轮
%% time:n^2    space:1
%% 效率不达标

%% API
-export([
    bubble_sort/1
]).
%%@spec bubble_sort/1
bubble_sort(L) -> bubble_sort(L, len(L)).
bubble_sort(L, 1) -> L;
bubble_sort([H | T], N) ->
    Result = bubble_once(H, T),
    bubble_sort(Result, N - 1).

bubble_once(H,[]) -> [H];
bubble_once(X, [H | T]) ->
    if X > H ->
        [H | bubble_once(X, T)];
        true ->
            [X | bubble_once(H, T)]
    end.

len([]) -> 0;
len([_H | T]) -> 1 + len(T).
