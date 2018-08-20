-module(insert_sort).
-author("zyh").
%% @doc （插入排序类）
%% 每次从列表里取出一个值，插入到已排序的列表中
%% time: n^2    space: 1
%% 效率合格

%% API
-export([insert_sort/1]).
insert_sort(L) -> insert_sort([],L).
insert_sort(L,[]) -> L;
insert_sort(L,[H|T]) ->
    insert_sort(normal(H,L),T).

normal(X,[]) -> [X];
normal(X,[H|T]) ->
    if X > H ->
        [H|normal(X,T)];
        true ->
            [X|[H|T]]
    end.