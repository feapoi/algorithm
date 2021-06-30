%%%-------------------------------------------------------------------
%%% @author Thoe
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 31. 八月 2018 17:28
%%%-------------------------------------------------------------------
-module(merge_sort).
-author("Thoe").

%% API
-export([merge_sort/1]).
merge_sort([]) -> [];
merge_sort([A]) ->[A];
merge_sort(List) ->
    Middle = length(List) div 2,
    {L, R} = lists:split(Middle, List),
    L1 = merge_sort(L),
    R1 = merge_sort(R),
    do_merge_sort(L1, R1).

do_merge_sort(L, R) ->
    do_merge_sort(L, R, []).

do_merge_sort([], [], Result) ->
    Result;
do_merge_sort([L1 | L], [], Result) ->
    do_merge_sort(L, [], Result ++ [L1]);
do_merge_sort([], [R1 | R], Result) ->
    do_merge_sort([], R, Result ++ [R1]);
do_merge_sort([L1 | L], [R1 | R], Result) when L1 < R1 ->
    do_merge_sort([L1 | L], R, Result ++ [R1]);
do_merge_sort([L1 | L], [R1 | R], Result) ->
    do_merge_sort(L, [R1 | R], Result ++ [L1]).


